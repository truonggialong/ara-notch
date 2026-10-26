import AppKit
import ClipboardCore
import NotchShell
import SwiftUI

/// A large preview of one clip, as shown beside the panel's list and in the Library's inspector.
struct ClipPreviewView: View {
    let item: ClipItem
    @ObservedObject var model: ClipboardViewModel

    @ViewBuilder
    var body: some View {
        switch item.kind {
        case .link where item.linkTitle != nil || item.linkImageBlobName != nil:
            VStack(alignment: .leading, spacing: 8) {
                if let image = model.linkImage?(item) {
                    Color.clear
                        .overlay {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if let title = item.linkTitle {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(3)
                }
                Text(item.snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.6))
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        case .text, .link:
            ScrollView {
                // Very long clips are cut for layout; the full text is what gets pasted.
                Group {
                    if CodeRecognition.isCode(item) {
                        Text(CodeHighlighter.attributed(item.text, fontSize: 12))
                    } else {
                        Text(String(item.text.prefix(CodeHighlighter.maxLength)))
                            .font(.system(size: 12))
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .color:
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.swatch)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AraPalette.hairline, lineWidth: 1))
                    .frame(height: 140)
                Text(item.snippet)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
        case .image:
            if let image = model.previewImage?(item) ?? model.thumbnail?(item) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The text read from the picture, so it can be checked and selected.
                    if let text = item.recognizedText, !text.isEmpty {
                        ScrollView {
                            Text(text)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary.opacity(0.7))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 64)
                    }
                }
            } else {
                Label(L10n.string("clipboard.image.missing"), systemImage: "photo.badge.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.55))
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.filePaths, id: \.self) { path in
                        Label(path, systemImage: "doc")
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
