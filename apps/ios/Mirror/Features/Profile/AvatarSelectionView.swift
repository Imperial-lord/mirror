import SwiftUI
import PhotosUI
import ImageIO

// Avatar thumbnails are extracted from the user's Behance design reference.
struct AvatarSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var photo: PhotosPickerItem?
    var hasPhoto: Bool
    var onSelect: (UIImage) -> Void
    var onRemove: () -> Void
    @State private var isTakingPhoto = false
    @State private var isCameraUnavailable = false
    private let categories = ["Games of Thrones", "Superheroes", "Avatar", "Dune"]
    private let names = ["Tyrion", "Daenerys", "Jon Snow", "Jaime", "Batman", "Deadpool", "Catwoman", "Iron Man", "Jake", "Neytiri", "Lo'ak", "Tsireya", "Paul", "Chani", "Baron Harkonnen", "Duncan"]

    var body: some View {
        VStack(spacing: 0) {
            ProfileScreenHeader(title: "Select an Avatar") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) { isTakingPhoto = true }
                            else { isCameraUnavailable = true }
                        } label: { sourceTile("Take a photo", icon: .camera) }
                        PhotosPicker(selection: $photo, matching: .images) {
                            sourceTile("Choose from gallery", icon: .photo)
                        }
                    }
                    ForEach(categories.indices, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(categories[section]).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.mirrorInk)
                            HStack(spacing: 12) {
                                ForEach(0..<4) { offset in
                                    let index = section * 4 + offset
                                    Button {
                                        if let image = UIImage(named: "AvatarPreset\(index)") {
                                            onSelect(image)
                                            dismiss()
                                        }
                                    } label: {
                                        Image("AvatarPreset\(index)").resizable().scaledToFill()
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .clipShape(Circle())
                                    }
                                    .accessibilityLabel("Select \(names[index]) avatar")
                                }
                            }
                        }
                    }
                    if hasPhoto {
                        Button("Remove photo", role: .destructive) { onRemove(); dismiss() }
                            .font(.system(size: 13)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
                .padding(16)
                .padding(.top, 16)
            }
        }
        .background(Color.mirrorBackground.ignoresSafeArea())
        .tint(.mirrorAccent)

        .onChange(of: photo) { _, value in if value != nil { dismiss() } }
        .alert("Camera unavailable", isPresented: $isCameraUnavailable) {
            Button("OK", role: .cancel) {}
        } message: { Text("Choose a photo from your gallery or select an avatar instead.") }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            AvatarCameraView { image in
                isTakingPhoto = false
                if let image { onSelect(image); dismiss() }
            }
            .ignoresSafeArea()
        }
    }

    private func sourceTile(_ title: String, icon: PhosphorIcon) -> some View {
        VStack(spacing: 12) {
            PhosphorView(icon, size: 28)
            Text(title).font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.mirrorTextTertiary)
        .frame(maxWidth: .infinity).frame(height: 116)
        .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct AvatarCameraView: UIViewControllerRepresentable {
    var onResult: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (UIImage?) -> Void
        init(onResult: @escaping (UIImage?) -> Void) { self.onResult = onResult }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onResult(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onResult(info[.originalImage] as? UIImage)
        }
    }
}

enum AvatarPhotoEncoder {
    static func encode(_ image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else { throw ProfileError.invalidImage }
        return try encode(data)
    }
    static func encode(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 384
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.7),
              jpeg.count <= 200_000 else { throw ProfileError.invalidImage }
        return jpeg.base64EncodedString()
    }
}
