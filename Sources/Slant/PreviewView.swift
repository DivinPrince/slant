import SwiftUI
import MetalKit

/// Renders the sample desktop through the same bend shader the overlay uses.
final class PreviewMetalView: MTKView, MTKViewDelegate {
    private static let art: MTLTexture? = PreviewArt.image().flatMap { Renderer.shared.makeMipTexture(from: $0) }

    var params = BendParams(progress: 0, style: .silk)
    /// Eases toward `params.progress` when true; thumbnails jump straight there.
    var animates = true
    private var shown: Double = 0
    private let renderer = Renderer.shared

    init() {
        super.init(frame: .zero, device: renderer.device)
        renderer.configure(self)
        preferredFramesPerSecond = 60
        delegate = self
    }

    required init(coder: NSCoder) { fatalError() }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let art = PreviewMetalView.art, let commandBuffer = renderer.queue.makeCommandBuffer(), let drawable = currentDrawable else { return }
        if animates {
            shown += (params.progress - shown) * 0.14
            if abs(params.progress - shown) < 0.001 { shown = params.progress }
        } else {
            shown = params.progress
        }
        var frame = params
        frame.progress = shown
        renderer.encodeDraw(source: art, params: frame, in: view, using: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
        if !animates || shown == params.progress { isPaused = true }
    }

    func update(_ newParams: BendParams) {
        params = newParams
        isPaused = false
    }
}

struct BendPreview: NSViewRepresentable {
    var params: BendParams
    var animates = true

    func makeNSView(context: Context) -> PreviewMetalView {
        let view = PreviewMetalView()
        view.animates = animates
        view.update(params)
        return view
    }

    func updateNSView(_ view: PreviewMetalView, context: Context) {
        view.animates = animates
        view.update(params)
    }
}

/// A MacBook drawn in SwiftUI with a live bend on its screen. Proportions come from the
/// landing page's figure so the preview matches the marketing art.
struct MacBookPreview: View {
    var params: BendParams
    var animates = true

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let unit = w / 100
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 4.83 * unit, topTrailingRadius: 4.83 * unit)
                        .fill(Color(white: 0.07))
                    BendPreview(params: params, animates: animates)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3.4 * unit, topTrailingRadius: 3.4 * unit))
                        .padding(.horizontal, 1.5 * unit)
                        .padding(.top, 1.5 * unit)
                        .padding(.bottom, 2.2 * unit)
                    Notch()
                        .fill(Color(white: 0.07))
                        .frame(width: 22.06 * unit, height: 22.06 * unit * 9 / 64)
                        .padding(.top, 1.5 * unit)
                }
                .aspectRatio(1.54, contentMode: .fit)
                .padding(.horizontal, 3.81 * unit)
                UnevenRoundedRectangle(bottomLeadingRadius: 1.03 * unit, bottomTrailingRadius: 1.03 * unit)
                    .fill(Color(white: 0.52))
                    .frame(height: 3.1 * unit)
                    .overlay(alignment: .top) {
                        Capsule().fill(Color(white: 0.42)).frame(width: 16 * unit, height: 0.9 * unit)
                    }
            }
        }
        .aspectRatio(100 / ((100 - 2 * 3.81) / 1.54 + 3.1), contentMode: .fit)
    }
}

private struct Notch: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 64, sy = rect.height / 9
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: 2 * sx, y: 2 * sy), control: CGPoint(x: 2 * sx, y: 0))
        p.addLine(to: CGPoint(x: 2 * sx, y: 5 * sy))
        p.addQuadCurve(to: CGPoint(x: 6 * sx, y: 9 * sy), control: CGPoint(x: 2 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 58 * sx, y: 9 * sy))
        p.addQuadCurve(to: CGPoint(x: 62 * sx, y: 5 * sy), control: CGPoint(x: 62 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 62 * sx, y: 2 * sy))
        p.addQuadCurve(to: CGPoint(x: 64 * sx, y: 0), control: CGPoint(x: 62 * sx, y: 0))
        p.closeSubpath()
        return p
    }
}
