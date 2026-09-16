import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PlaylistView: View {
    @Binding var urls: [String]
    let currentIndex: Int?
    let onPlay: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newURL = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playlist").font(.system(size: 24, weight: .semibold))
                    Text("Your next watch, lined up.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(urls.count) \(urls.count == 1 ? "video" : "videos")")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                TextField("YouTube, playlist, MP4 or WebM URL", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addURL)
                Button("Add", action: addURL)
                    .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Add Files…", action: addFiles)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            if urls.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                    Text("Your playlist is empty").font(.headline)
                    Text("Add video links or MP4/WebM files to play them in order.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        playlistRow(index: index, url: url)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Divider()
            HStack {
                Button("Clear Playlist") { urls.removeAll() }
                    .disabled(urls.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
    }

    private func playlistRow(index: Int, url: String) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
            Button {
                onPlay(index)
            } label: {
                Image(systemName: currentIndex == index ? "speaker.wave.2.fill" : "play.fill")
            }
            .help("Play item \(index + 1)")
            .accessibilityLabel("Play item \(index + 1)")
            VStack(alignment: .leading, spacing: 4) {
                Text(StreamingProviderRegistry.shared.resolve(url)?.defaultTitle ?? "Video")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(url)
            Spacer()
            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
                .help("Move up")
                .accessibilityLabel("Move item \(index + 1) up")
            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index == urls.count - 1)
                .help("Move down")
                .accessibilityLabel("Move item \(index + 1) down")
            Button {
                guard urls.indices.contains(index) else { return }
                urls.remove(at: index)
            } label: { Image(systemName: "minus.circle") }
                .help("Remove from playlist")
                .accessibilityLabel("Remove item \(index + 1)")
        }
        .buttonStyle(.borderless)
        .padding(12)
        .background(currentIndex == index ? Color.accentColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard urls.indices.contains(index), urls.indices.contains(destination) else { return }
        urls.swapAt(index, destination)
    }

    private func addURL() {
        let input = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        guard StreamingProviderRegistry.shared.resolve(input) != nil else {
            errorMessage = "Enter a supported video or playlist URL, or choose an MP4 or WebM file."
            return
        }
        urls.append(input)
        newURL = ""
        errorMessage = nil
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie] + [UTType(filenameExtension: "webm")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add to Playlist"
        guard panel.runModal() == .OK else { return }
        urls.append(contentsOf: panel.urls.map(\.absoluteString))
        errorMessage = nil
    }
}
