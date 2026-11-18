import Foundation
import ImageIO
import Testing
import UIKit
@testable import Turnproof

struct PhotoIngestTests {
    private let ingest = PhotoIngest()

    private func render(size: CGSize, alpha: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = !alpha
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if alpha {
                context.cgContext.clear(CGRect(origin: .zero, size: size))
            }
            UIColor(red: 0.4, green: 0.45, blue: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            UIColor(red: 0.75, green: 0.7, blue: 0.6, alpha: 1).setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
    }

    private func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private func hasAlpha(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return true }
        return properties[kCGImagePropertyHasAlpha] as? Bool ?? false
    }

    @Test func largeCameraPhotoIsDownscaledAndRecompressed() throws {
        let raw = try #require(render(size: CGSize(width: 4032, height: 3024), alpha: false)
            .jpegData(compressionQuality: 0.92))
        let result = try ingest.ingest(raw)

        #expect(result.jpeg.count <= PhotoIngest.maxBytes)
        let size = try #require(pixelSize(of: result.jpeg))
        #expect(max(size.width, size.height) <= PhotoIngest.maxEdge)
        #expect(!hasAlpha(result.jpeg))
    }

    @Test func transparentPNGIsFlattenedToOpaqueJPEG() throws {
        let raw = try #require(render(size: CGSize(width: 900, height: 600), alpha: true).pngData())
        let result = try ingest.ingest(raw)

        #expect(!hasAlpha(result.jpeg))
        #expect(result.jpeg.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func corruptDataIsRejected() {
        #expect(throws: PhotoIngestError.undecodable) {
            try ingest.ingest(Data(repeating: 0x00, count: 12))
        }
    }

    @Test func emptyDataIsRejected() {
        #expect(throws: PhotoIngestError.undecodable) {
            try ingest.ingest(Data())
        }
    }

    @Test func exifOriginalDateIsRead() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:18 09:41:07"]
        ]
        #expect(PhotoIngest.exifDate(from: properties) == formatter.date(from: "2026:11:18 09:41:07"))
        #expect(PhotoIngest.exifDate(from: [:]) == nil)
    }
}
