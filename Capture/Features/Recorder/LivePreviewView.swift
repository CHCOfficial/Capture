import SwiftUI

struct LivePreviewView: View {
    @ObservedObject var previewController: PreviewCaptureController

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.88))

            if let image = previewController.image {
                Image(image, scale: 1, orientation: .up, label: Text("Live preview"))
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(previewController.stateText == "Loading preview..." ? 1 : 0)
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(previewController.stateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
