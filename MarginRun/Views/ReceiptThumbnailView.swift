import SwiftUI
import UIKit

struct ReceiptThumbnailView: View {
    let fileName: String
    var size: CGFloat = 58

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.text.image")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
        }
        .accessibilityLabel(image == nil ? "Receipt image unavailable" : "Receipt photo")
        .task(id: fileName) {
            image = ReceiptStorage.image(fileName: fileName)
        }
    }
}
