import AppKit
import SwiftUI

struct LivePreviewView: View {
    @ObservedObject var previewController: PreviewCaptureController
    private let maximumPreviewSize = CGSize(width: 640, height: 400)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.88))

            if let image = previewController.image {
                PreviewImageLayerView(image: image)
                    .padding(8)
                    .accessibilityLabel("Live preview")
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
        .frame(width: lockedPreviewSize.width, height: lockedPreviewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var lockedPreviewSize: CGSize {
        let aspectRatio: CGFloat
        if let image = previewController.image, image.height > 0 {
            aspectRatio = CGFloat(image.width) / CGFloat(image.height)
        } else {
            aspectRatio = 16 / 10
        }

        guard aspectRatio > 0 else {
            return maximumPreviewSize
        }

        let size: CGSize
        if aspectRatio >= maximumPreviewSize.width / maximumPreviewSize.height {
            size = CGSize(width: maximumPreviewSize.width, height: maximumPreviewSize.width / aspectRatio)
        } else {
            size = CGSize(width: maximumPreviewSize.height * aspectRatio, height: maximumPreviewSize.height)
        }

        return CGSize(width: size.width.rounded(), height: size.height.rounded())
    }
}

private struct PreviewImageLayerView: NSViewRepresentable {
    let image: CGImage

    func makeNSView(context: Context) -> LayerBackedPreviewView {
        LayerBackedPreviewView()
    }

    func updateNSView(_ nsView: LayerBackedPreviewView, context: Context) {
        nsView.image = image
    }
}

final class LayerBackedPreviewView: NSView {
    var image: CGImage? {
        didSet {
            updateLayerContents()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerContents()
    }

    private func configureLayer() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.minificationFilter = .linear
        layer?.magnificationFilter = .linear
        layer?.drawsAsynchronously = true
        updateLayerContents()
    }

    private func updateLayerContents() {
        guard let layer else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.commit()
    }
}
