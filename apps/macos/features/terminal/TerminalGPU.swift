import Metal

/// What every terminal shares on the GPU: one command queue and one
/// pipeline per device, and one glyph atlas per font and display scale.
/// Each terminal used to make its own: a 16 MB atlas, a queue and the
/// shaders compiled again, ~34 MB for each tab past the first (make perf,
/// 2026-10-21). An atlas lives while a terminal uses it, so a font no
/// terminal uses any more is let go.
@MainActor
enum TerminalGPU {
    private final class Held {
        weak var atlas: GlyphAtlas?
        init(_ atlas: GlyphAtlas) { self.atlas = atlas }
    }

    private static var queues: [ObjectIdentifier: MTLCommandQueue] = [:]
    private static var pipelines: [String: MTLRenderPipelineState] = [:]
    private static var atlases: [String: Held] = [:]

    static func queue(_ device: MTLDevice) -> MTLCommandQueue? {
        if let queue = queues[ObjectIdentifier(device)] { return queue }
        let queue = device.makeCommandQueue()
        queues[ObjectIdentifier(device)] = queue
        return queue
    }

    static func pipeline(_ device: MTLDevice, pixelFormat: MTLPixelFormat,
                         make: (MTLDevice, MTLPixelFormat) -> MTLRenderPipelineState?) -> MTLRenderPipelineState? {
        let key = "\(ObjectIdentifier(device)) \(pixelFormat.rawValue)"
        if let pipeline = pipelines[key] { return pipeline }
        let pipeline = make(device, pixelFormat)
        pipelines[key] = pipeline
        return pipeline
    }

    /// The atlas for `key` (the font's settings and the scale), made with
    /// `font` the first time; terminals with the same font share it.
    static func atlas(_ device: MTLDevice, key: String, font: () -> TerminalFont) -> GlyphAtlas? {
        let key = "\(ObjectIdentifier(device)) \(key)"
        if let atlas = atlases[key]?.atlas { return atlas }
        atlases = atlases.filter { $0.value.atlas != nil }
        guard let atlas = GlyphAtlas(device: device, font: font()) else { return nil }
        atlases[key] = Held(atlas)
        return atlas
    }
}
