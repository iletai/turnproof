import SwiftUI
import UIKit

/// Draws freehand strokes and exports them as a 600×200 transparent PNG.
struct SignatureCanvas: View {
    var onChange: (Data?) -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []

    private static let exportSize = CGSize(width: 600, height: 200)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        GeometryReader { proxy in
            Canvas { context, size in
                for stroke in strokes + (current.isEmpty ? [] : [current]) {
                    context.stroke(path(stroke, in: size), with: .color(TPColor.textPrimary),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            .background(TPColor.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TPColor.separator)
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .overlay {
                if strokes.isEmpty && current.isEmpty {
                    Label("Sign here", systemImage: "signature")
                        .font(.footnote)
                        .foregroundStyle(TPColor.textSecondary)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        current.append(normalized(value.location, in: proxy.size))
                    }
                    .onEnded { _ in
                        guard !current.isEmpty else { return }
                        strokes.append(current)
                        current = []
                        onChange(renderPNG())
                    }
            )
        }
        .frame(height: 160)
        .clipShape(shape)
        .overlay(shape.stroke(TPColor.separator, lineWidth: 1))
    }

    func clear() {
        strokes = []
        current = []
        onChange(nil)
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x / max(size.width, 1), 0), 1),
                y: min(max(point.y / max(size.height, 1), 0), 1))
    }

    private func path(_ stroke: [CGPoint], in size: CGSize) -> Path {
        var path = Path()
        guard let first = stroke.first else { return path }
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in stroke.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        return path
    }

    private func renderPNG() -> Data? {
        guard !strokes.isEmpty else { return nil }
        let size = Self.exportSize
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(3)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                cg.beginPath()
                cg.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                for point in stroke.dropFirst() {
                    cg.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                cg.strokePath()
            }
        }
        return image.pngData()
    }
}
