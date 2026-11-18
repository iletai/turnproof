import SwiftUI
import ImageIO
import UIKit

/// Thin wrapper over the system camera; the app never asks for photo-library access here.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.95) {
                parent.onImage(Self.keepingExif(info[.mediaMetadata] as? [String: Any], in: data))
            }
            parent.dismiss()
        }

        /// `jpegData` drops metadata, but the capture time is evidence; copy the EXIF block back without re-encoding.
        private static func keepingExif(_ metadata: [String: Any]?, in data: Data) -> Data {
            guard let exif = metadata?[kCGImagePropertyExifDictionary as String],
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source) else { return data }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return data }
            CGImageDestinationAddImageFromSource(destination, source, 0,
                                                 [kCGImagePropertyExifDictionary: exif] as CFDictionary)
            return CGImageDestinationFinalize(destination) ? output as Data : data
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
