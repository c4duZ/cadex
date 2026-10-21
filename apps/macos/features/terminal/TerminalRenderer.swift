import CCadex
import Metal
import QuartzCore
import simd

/// One quad for the GPU. Layout matches `Instance` in TerminalShaders.
struct QuadInstance {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var uv: SIMD4<Float>
    var color: SIMD4<Float>
    var kind: UInt32
    /// A glyph's cell background, 0xRRGGBB, for the minimum contrast.
    var background: UInt32 = 0
    // Scalars, not SIMD3: SIMD3<UInt32> is 16 bytes and made the
    // stride 80 instead of the shader.s 64, scrambling every glyph after the
    // first (found 2026-10-19, first run of the app).
    var pad1: UInt32 = 0
    var pad2: UInt32 = 0

    /// Must equal sizeof(Instance) in TerminalShaders.
    static let shaderStride = 64

    static let solid: UInt32 = 0
    static let maskGlyph: UInt32 = 1
    static let colorGlyph: UInt32 = 2
}

/// Draws a cadex_terminal_frame with Metal: one instanced draw call.
@MainActor
final class TerminalRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private(set) var atlas: GlyphAtlas
    private var font: TerminalFont
    private var builder = QuadBuilder()
    /// The theme's selection color; nil tints with the text color.
    var selectionColor: UInt32?
    /// The default background's opacity (TerminalAppearance.backgroundAlpha).
    var backgroundAlpha: Double = 1
    /// The WCAG ratio text keeps against its cell (terminal.minimumContrast);
    /// 1 leaves the colors alone. Applied in the vertex shader, once per glyph.
    var minimumContrast: Float = 1

    /// Several frames can be in flight; each writes its own buffer.
    private static let buffersInFlight = 3
    private var buffers: [MTLBuffer?] = Array(repeating: nil, count: buffersInFlight)
    private var bufferIndex = 0
    private let inFlight = DispatchSemaphore(value: buffersInFlight)

    /// The queue and the pipeline are the app's, the atlas is shared by the
    /// terminals with the same font (TerminalGPU.swift).
    init?(device: MTLDevice, atlas: GlyphAtlas, pixelFormat: MTLPixelFormat) {
        guard let queue = TerminalGPU.queue(device),
              let pipeline = TerminalGPU.pipeline(device, pixelFormat: pixelFormat, make: Self.makePipeline)
        else { return nil }
        self.device = device
        self.queue = queue
        self.atlas = atlas
        self.font = atlas.font
        self.pipeline = pipeline
    }

    var metrics: CellMetrics { font.metrics }

    /// The display scale or font changed: the atlas for the new one.
    func setAtlas(_ newAtlas: GlyphAtlas) {
        font = newAtlas.font
        atlas = newAtlas
    }

    func draw(_ frame: cadex_terminal_frame, padding: SIMD2<Float>, in drawable: CAMetalDrawable, size: CGSize,
              overlay: DrawOverlay = DrawOverlay(), synchronously: Bool = false) {
        let quads = builder.build(frame: frame, atlas: atlas, metrics: font.metrics, padding: padding,
                                  viewSize: SIMD2(Float(size.width), Float(size.height)), overlay: overlay,
                                  selection: selectionColor)

        inFlight.wait()
        bufferIndex = (bufferIndex + 1) % Self.buffersInFlight
        guard let buffer = buffer(for: quads), let commands = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let semaphore = inFlight
        commands.addCompletedHandler { _ in semaphore.signal() }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = Self.clearColor(frame.background, alpha: backgroundAlpha)

        if let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
            var uniforms = SIMD4<Float>(Float(size.width), Float(size.height), minimumContrast, 0)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            if !quads.isEmpty {
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: quads.count)
            }
            encoder.endEncoding()
        }
        // With the layer's transaction (a new surface's first frame), the
        // drawable is shown once the work is scheduled, with the frame.
        if synchronously {
            commands.commit()
            commands.waitUntilScheduled()
            drawable.present()
        } else {
            commands.present(drawable)
            commands.commit()
        }
    }

    private func buffer(for quads: [QuadInstance]) -> MTLBuffer? {
        let length = max(1, quads.count) * MemoryLayout<QuadInstance>.stride
        if let existing = buffers[bufferIndex], existing.length >= length {
            quads.withUnsafeBytes { existing.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            return existing
        }
        // Grow with headroom so a busy screen does not reallocate every frame.
        let created = device.makeBuffer(length: length * 2, options: .storageModeShared)
        quads.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { created?.contents().copyMemory(from: base, byteCount: bytes.count) }
        }
        buffers[bufferIndex] = created
        return created
    }

    private static func makePipeline(_ device: MTLDevice, _ pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: TerminalShaders.source, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "terminal_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "terminal_fragment")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = pixelFormat
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Premultiplied, like everything the pipeline blends.
    private static func clearColor(_ rgb: UInt32, alpha: Double) -> MTLClearColor {
        let c = rgba(rgb)
        return MTLClearColor(red: Double(c.x) * alpha, green: Double(c.y) * alpha, blue: Double(c.z) * alpha, alpha: alpha)
    }
}

func rgba(_ rgb: UInt32, alpha: Float = 1) -> SIMD4<Float> {
    SIMD4(Float((rgb >> 16) & 0xFF) / 255, Float((rgb >> 8) & 0xFF) / 255, Float(rgb & 0xFF) / 255, alpha)
}
