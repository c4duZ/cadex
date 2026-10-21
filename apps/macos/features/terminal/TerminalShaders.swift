/// Metal source for the terminal, compiled at launch with
/// MTLDevice.makeLibrary(source:). The offline Metal compiler ships only with
/// Xcode, and day-to-day development does not need Xcode (ADR 0007).
///
/// Everything is an instanced quad: a solid rectangle (cell background,
/// cursor, underline) or a glyph from the atlas. Layout of `Instance` must
/// match `QuadInstance` in TerminalRenderer.swift.
enum TerminalShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Instance {
        float2 origin;   // top-left, device pixels
        float2 size;     // device pixels
        float4 uv;       // atlas rect: x0, y0, x1, y1 (normalized)
        float4 color;    // straight RGBA
        uint kind;       // 0 solid, 1 tinted glyph mask, 2 color glyph
        uint background; // a glyph's cell background, 0xRRGGBB
        uint pad1;
        uint pad2;
    };

    struct Uniforms {
        float2 viewport; // drawable size, device pixels
        float minimumContrast; // WCAG ratio; 1 is off
        float pad;
    };

    float luminance(float3 c) {
        float3 l = select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
        return dot(l, float3(0.2126, 0.7152, 0.0722));
    }

    float ratio(float a, float b) {
        return (max(a, b) + 0.05) / (min(a, b) + 0.05);
    }

    // Text below the minimum contrast moves toward white or black, whichever
    // reads better on its background, just far enough (8 halvings).
    float3 contrasted(float3 fg, float3 bg, float minimum) {
        float lb = luminance(bg);
        if (ratio(luminance(fg), lb) >= minimum) return fg;
        float3 target = ratio(1.0, lb) >= ratio(0.0, lb) ? float3(1.0) : float3(0.0);
        float lo = 0.0, hi = 1.0;
        for (int i = 0; i < 8; i++) {
            float mid = (lo + hi) * 0.5;
            if (ratio(luminance(mix(fg, target, mid)), lb) >= minimum) hi = mid; else lo = mid;
        }
        return mix(fg, target, hi);
    }

    struct Fragment {
        float4 position [[position]];
        float2 uv;
        float4 color;
        uint kind [[flat]];
    };

    vertex Fragment terminal_vertex(uint vid [[vertex_id]],
                                    uint iid [[instance_id]],
                                    constant Instance *instances [[buffer(0)]],
                                    constant Uniforms &uniforms [[buffer(1)]]) {
        Instance quad = instances[iid];
        float2 corner = float2(vid & 1, vid >> 1);  // triangle strip of 4
        float2 pixel = quad.origin + corner * quad.size;
        Fragment out;
        out.position = float4(pixel.x / uniforms.viewport.x * 2.0 - 1.0,
                              1.0 - pixel.y / uniforms.viewport.y * 2.0, 0.0, 1.0);
        out.uv = mix(quad.uv.xy, quad.uv.zw, corner);
        out.color = quad.color;
        if (quad.kind == 1 && uniforms.minimumContrast > 1.0) {
            float3 bg = float3((quad.background >> 16) & 0xFF, (quad.background >> 8) & 0xFF, quad.background & 0xFF) / 255.0;
            out.color.rgb = contrasted(quad.color.rgb, bg, uniforms.minimumContrast);
        }
        out.kind = quad.kind;
        return out;
    }

    // Output is premultiplied alpha (blend: one, one-minus-source-alpha).
    fragment float4 terminal_fragment(Fragment in [[stage_in]],
                                      texture2d<float> atlas [[texture(0)]]) {
        // Nearest: glyphs are rasterized at the drawn size, sampling is 1:1.
        constexpr sampler pixelExact(filter::nearest, address::clamp_to_edge);
        if (in.kind == 0) {
            return float4(in.color.rgb * in.color.a, in.color.a);
        }
        float4 texel = atlas.sample(pixelExact, in.uv);
        if (in.kind == 1) {
            float coverage = texel.a * in.color.a;
            return float4(in.color.rgb * coverage, coverage);
        }
        return texel * in.color.a;
    }
    """
}
