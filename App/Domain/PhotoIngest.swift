import Foundation
import ImageIO
import UIKit

struct IngestedPhoto: Sendable {
    let jpeg: Data
    let exifTakenAt: Date?
}

enum PhotoIngestError: Error, Equatable {
    case undecodable
    case tooLargeAfterDownscale
}

/// Normalises any picked/captured image into a bounded JPEG so a report packet stays small.
struct PhotoIngest: Sendable {
    static let maxEdge: CGFloat = 1600
    static let maxBytes = 600_000

    func ingest(_ raw: Data) throws -> IngestedPhoto {
        guard let source = CGImageSourceCreateWithData(raw as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw PhotoIngestError.undecodable }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxEdge,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoIngestError.undecodable
        }

        let size = CGSize(width: thumbnail.width, height: thumbnail.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let flattened = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: thumbnail).draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = flattened.jpegData(compressionQuality: 0.75) else {
            throw PhotoIngestError.undecodable
        }
        guard jpeg.count <= Self.maxBytes else { throw PhotoIngestError.tooLargeAfterDownscale }
        return IngestedPhoto(jpeg: jpeg, exifTakenAt: Self.exifDate(from: properties))
    }

    static func exifDate(from properties: [CFString: Any]) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let string = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = string[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        return formatter.date(from: raw)
    }
}

enum PhotoSourceError: Error {
    case cancelled
}

/// Swapped for a fixture source when the app runs with `-UITestMode`.
protocol PhotoSource: Sendable {
    func capturePhoto() async throws -> Data
    func pickFromLibrary() async throws -> Data
}
