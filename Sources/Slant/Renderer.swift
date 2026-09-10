import Foundation
import Metal
import MetalKit
import CoreVideo

struct Uniforms {
    var tilt: Float = 0
    var distance: Float = 4.9
    var blur: Float = 0
    var shade: Float = 0
    var feather: Float = 0
    var frost: Float = 0
    var aspect: Float = 1
    var cornerRadius: Float = 0
    var maxLod: Float = 0
    var texelHeight: Float = 1
    var sourceAspect: Float = 1
    var pad: Float = 0
}

/// How far the picture is bent. All values are already scaled by the lid progress.
struct BendParams {
    var progress: Double
    var perspective: Double
    var blur: Double
    var shadow: Double
    var frost: Double

    /// Combines the current settings with a progress value.
    init(progress: Double, settings: AppSettings) {
        self.progress = progress
        perspective = settings.perspective
        blur = settings.blur
        shadow = settings.shadow
        frost = settings.style.frost
    }

    init(progress: Double, style: Style) {
        self.progress = progress
        perspective = style.perspective
        blur = style.blur
        shadow = style.shadow
        frost = style.frost
    }

    /// Fully open lids show at most this much rotation, matching the web demo.
    static let maxTiltDegrees = 72.0
}

/// One Metal device, queue and pipeline shared by the overlay and every preview.
final class Renderer {
    static let shared = Renderer()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm
    static let sampleCount = 4
    private var textureCache: CVMetalTextureCache?

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let library = try! device.makeLibrary(source: bendShaderSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "bend_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bend_fragment")
        descriptor.colorAttachments[0].pixelFormat = Renderer.pixelFormat
        descriptor.rasterSampleCount = Renderer.sampleCount
        pipeline = try! device.makeRenderPipelineState(descriptor: descriptor)
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    func configure(_ view: MTKView) {
        view.device = device
        view.colorPixelFormat = Renderer.pixelFormat
        view.sampleCount = Renderer.sampleCount
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.framebufferOnly = true
    }

    /// Wraps a captured frame as a texture. The returned CVMetalTexture must outlive the
    /// command buffer that reads it.
    func wrap(_ pixelBuffer: CVPixelBuffer) -> (MTLTexture, CVMetalTexture)? {
        guard let textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil,
                                                               Renderer.pixelFormat, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return (texture, cvTexture)
    }

    func makeMipTexture(width: Int, height: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }

    func makeMipTexture(from image: CGImage) -> MTLTexture? {
        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(cgImage: image, options: [
            .generateMipmaps: true,
            .SRGB: false,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
        ])
    }

    /// Copies `frame` into `mip` level 0 and rebuilds its mip chain.
    func encodeUpload(of frame: MTLTexture, into mip: MTLTexture, using commandBuffer: MTLCommandBuffer) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: frame, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: frame.width, height: frame.height, depth: 1),
                  to: mip, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.generateMipmaps(for: mip)
        blit.endEncoding()
    }

    func encodeDraw(source: MTLTexture, params: BendParams, in view: MTKView, using commandBuffer: MTLCommandBuffer) {
        guard let descriptor = view.currentRenderPassDescriptor else { return }
        encodeDraw(source: source, params: params, pass: descriptor, size: view.drawableSize, using: commandBuffer)
    }

    func encodeDraw(source: MTLTexture, params: BendParams, pass descriptor: MTLRenderPassDescriptor, size: CGSize, using commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        var uniforms = Uniforms()
        let p = Float(params.progress)
        uniforms.tilt = Float(params.perspective * BendParams.maxTiltDegrees * .pi / 180) * p
        uniforms.blur = Float(params.blur) * p
        uniforms.shade = Float(params.shadow) * p
        uniforms.frost = Float(params.frost) * p
        uniforms.feather = 0.22 * p
        uniforms.aspect = Float(size.width / max(size.height, 1))
        uniforms.cornerRadius = 0.012
        uniforms.maxLod = Float(source.mipmapLevelCount - 1)
        uniforms.texelHeight = 1 / Float(source.height)
        uniforms.sourceAspect = Float(source.width) / Float(source.height)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
}
