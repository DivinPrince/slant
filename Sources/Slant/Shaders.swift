/// Metal shaders for the bend. Compiled at launch so the app needs no resource bundle.
///
/// The screen is a quad hinged on its bottom edge. The vertex stage rotates it away
/// from the viewer and projects it with a fixed camera distance, so the top narrows
/// and drops as the tilt grows. The fragment stage samples the desktop through its
/// mip chain with a level that rises toward the top (the progressive blur), darkens
/// the upper corners (the shade), optionally veils the top in white (Frost), and
/// feathers the top edge so the silhouette softens with the pixels.
let bendShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float tilt;          // radians the lid has rotated away from the viewer
    float distance;      // camera distance; the quad is 2 units tall
    float blur;          // 0..1 blur strength, already scaled by progress
    float shade;         // 0..1 shade strength, already scaled by progress
    float feather;       // fraction of the height feathered along the top edge
    float frost;         // 0..1 white veil, already scaled by progress
    float aspect;        // view width / height
    float cornerRadius;  // top corner radius, in units of view height
    float maxLod;        // highest mip level of the source
    float texelHeight;   // 1 / source height
    float sourceAspect;  // source width / height (matches aspect for the live screen)
    float pad;
};

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

vertex Varyings bend_vertex(uint vid [[vertex_id]], constant Uniforms& u [[buffer(0)]]) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    float2 c = corners[vid];
    float rise = c.y + 1.0;
    float y = -1.0 + rise * cos(u.tilt);
    float z = -rise * sin(u.tilt);
    float w = u.distance - z;
    Varyings out;
    out.position = float4(c.x * u.distance, y * u.distance, 0.0, w);
    out.uv = float2((c.x + 1.0) * 0.5, 1.0 - (c.y + 1.0) * 0.5);
    return out;
}

static float band(float v, float solid, float gone) {
    return 1.0 - smoothstep(solid, gone, v);
}

fragment float4 bend_fragment(Varyings in [[stage_in]],
                              constant Uniforms& u [[buffer(0)]],
                              texture2d<float> source [[texture(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear, mip_filter::linear);
    float2 uv = in.uv;
    float v = uv.y;

    // Three blur bands, widest and strongest at the top, summed into one radius.
    float profile = (6.0 * band(v, 0.30, 0.75) + 16.0 * band(v, 0.15, 0.52) + 36.0 * band(v, 0.06, 0.34)) / 58.0;
    float radius = profile * u.blur * 0.075 / u.texelHeight;
    float lod = clamp(log2(max(radius, 1.0)), 0.0, u.maxLod);
    float2 step = float2(u.texelHeight / u.sourceAspect, u.texelHeight) * exp2(lod) * 0.4;
    float4 color = source.sample(smp, uv, level(lod)) * 0.36
                 + source.sample(smp, uv + float2( step.x,  step.y), level(lod)) * 0.16
                 + source.sample(smp, uv + float2(-step.x,  step.y), level(lod)) * 0.16
                 + source.sample(smp, uv + float2( step.x, -step.y), level(lod)) * 0.16
                 + source.sample(smp, uv + float2(-step.x, -step.y), level(lod)) * 0.16;

    // Shade: two radial pools in the top corners and a linear wash from the top.
    float k = min(u.shade * 1.6, 1.6);
    float left  = 0.55 * (1.0 - saturate(length(float2(uv.x / 1.2, v / 0.6)) / 0.6));
    float right = 0.55 * (1.0 - saturate(length(float2((1.0 - uv.x) / 1.2, v / 0.6)) / 0.6));
    float top   = 0.35 * (1.0 - saturate(v / 0.45));
    color.rgb *= (1.0 - left * k) * (1.0 - right * k) * (1.0 - top * k);

    // Frost: a white veil that thickens toward the top.
    float veil = u.frost * (1.0 - smoothstep(0.0, 0.7, v)) * 0.45;
    color.rgb = mix(color.rgb, float3(1.0), veil);

    // Feather the top edge so the outline softens with the bend.
    float alpha = 1.0;
    if (u.feather > 0.0) {
        float s = v / u.feather;
        alpha = s < 0.25 ? s / 0.25 * 0.25
              : s < 0.55 ? mix(0.25, 0.65, (s - 0.25) / 0.30)
              : s < 1.0  ? mix(0.65, 1.0, (s - 0.55) / 0.45)
              : 1.0;
    }

    // Round the top corners.
    float r = u.cornerRadius;
    if (r > 0.0) {
        float2 p = float2(uv.x * u.aspect, v);
        float px = min(p.x, u.aspect - p.x);
        if (px < r && p.y < r) {
            float d = length(float2(px, p.y) - float2(r, r));
            alpha *= 1.0 - smoothstep(r - 1.5 * u.texelHeight, r + 1.5 * u.texelHeight, d);
        }
    }

    return float4(color.rgb * alpha, 1.0);
}
"""
