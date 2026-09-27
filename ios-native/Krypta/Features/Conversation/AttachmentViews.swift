import AVKit
import CoreTransferable
import ImageIO
import KryptaMessenger
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Was man im Chat anhängen kann; `nil` im Composer heißt: hier nicht.
struct AttachmentActions {
    let photo: () -> Void
    let camera: () -> Void
    let file: () -> Void
    let voice: () -> Void
}

/// Ein Anhang, bereit zum Senden, mit Kennung fürs Blatt.
struct PendingAttachment: Identifiable {
    let id = UUID()
    let out: OutgoingAttachment
}

/// Ein Video aus der Mediathek, als Datei kopiert (PhotosPicker).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = try AttachmentPreparer.temporaryURL(ext: received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

// MARK: - In der Blase

/// Foto, Video, Sprachnachricht oder Datei in der Blase.
struct AttachmentBubbleContent: View {
    @Environment(MessengerEngine.self) private var engine
    let message: Message
    let attachment: Attachment
    let mine: Bool

    @State private var image: UIImage?
    @State private var player = VoicePlayer()

    var body: some View {
        switch attachment.kind {
        case .image, .video: visual
        case .audio: voice
        case .file: file
        }
    }

    // Foto und Video: das Bild, bis es da ist die unscharfe Vorschau.
    private var visual: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let thumb = attachment.thumbnail.flatMap(UIImage.init(data:)) {
                Image(uiImage: thumb).resizable().scaledToFill().blur(radius: 8)
            } else {
                Rectangle().fill(.quaternary)
            }
            if attachment.kind == .video && attachment.state == .ready {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
            }
            stateOverlay
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if attachment.kind == .video, let d = attachment.duration {
                Text(Self.clock(d))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(6)
            }
        }
        .task(id: "\(attachment.id)|\(attachment.state.rawValue)") { await loadImage() }
        .accessibilityLabel(attachment.kind == .image ? Text("Foto") : Text("Video"))
    }

    /// Nicht größer als nötig, im Seitenverhältnis des Bildes.
    private var size: CGSize {
        let maxW: CGFloat = 230, maxH: CGFloat = 300
        guard let w = attachment.width, let h = attachment.height, w > 0, h > 0 else { return CGSize(width: maxW, height: maxW * 0.75) }
        let ratio = CGFloat(h) / CGFloat(w)
        var width = maxW, height = maxW * ratio
        if height > maxH { height = maxH; width = maxH / ratio }
        return CGSize(width: max(width, 120), height: max(height, 90))
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch attachment.state {
        case .transferring:
            ProgressView().tint(.white).padding(10).background(.black.opacity(0.35), in: Circle())
        case .failed:
            Group {
                if mine {
                    Label("Nicht gesendet", systemImage: "exclamationmark.circle")
                } else {
                    Label("Tippen, um es erneut zu laden", systemImage: "arrow.clockwise")
                }
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.5), in: Capsule())
        case .ready, .gone:
            EmptyView()
        }
    }

    private func loadImage() async {
        guard attachment.state == .ready, image == nil else { return }
        // Fotos in Vorschaugröße; Videos zeigen ihr Vorschaubild scharf nur, wenn geladen.
        guard attachment.kind == .image, let data = engine.attachmentData(message) else { return }
        let side = 600
        image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: side,
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }

    // Sprachnachricht: Abspielen direkt in der Blase.
    private var voice: some View {
        HStack(spacing: 10) {
            Button {
                guard let data = engine.attachmentData(message) else {
                    if attachment.state == .failed && !mine { engine.retryAttachment(chatId: message.chatId, messageId: message.id) }
                    return
                }
                player.toggle(data)
            } label: {
                Group {
                    if attachment.state == .transferring {
                        ProgressView()
                    } else {
                        Image(systemName: attachment.state == .failed ? "arrow.clockwise.circle.fill" : (player.isPlaying ? "pause.circle.fill" : "play.circle.fill"))
                            .font(.system(size: 32))
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? Text("Pause") : Text("Abspielen"))
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: player.progress)
                    .tint(mine ? .white : .accentColor)
                    .frame(width: 130)
                Text(Self.clock(attachment.duration ?? 0))
                    .font(.caption2.monospacedDigit())
                    .opacity(0.8)
            }
        }
        .onDisappear { player.stop() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Sprachnachricht, \(Self.clock(attachment.duration ?? 0))"))
    }

    // Datei: Symbol, Name, Größe.
    private var file: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.state == .failed ? "exclamationmark.arrow.circlepath" : "doc.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name ?? String(localized: "Datei"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                    .font(.caption)
                    .opacity(0.8)
            }
            if attachment.state == .transferring { ProgressView() }
        }
        .frame(maxWidth: 230, alignment: .leading)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Ansehen

/// Vollbild: Foto zum Zoomen, Video zum Abspielen, Datei in der Vorschau.
/// Liegt im Screenshot-Schutz (ShieldedSheet).
struct AttachmentViewer: View {
    @Environment(\.closeSheet) private var closeSheet
    @Environment(\.dismiss) private var dismiss
    let data: Data
    let attachment: Attachment
    /// Einmal ansehen: danach ist es weg.
    var once = false

    @State private var fileURL: URL?
    @State private var player: AVPlayer?
    @State private var voice = VoicePlayer()
    @State private var zoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { if let closeSheet { closeSheet() } else { dismiss() } }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top) {
                    if once {
                        Label("Verschwindet, sobald du es schließt.", systemImage: "eye")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
        }
        .onAppear(perform: prepare)
        .onDisappear(perform: cleanUp)
    }

    @ViewBuilder
    private var content: some View {
        switch attachment.kind {
        case .image:
            if let ui = UIImage(data: data) {
                GeometryReader { geo in
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(MagnifyGesture().onChanged { zoom = min(max($0.magnification, 1), 5) }.onEnded { _ in
                            withAnimation(.smooth) { zoom = 1 }
                        })
                }
                .background(Color.black)
                .accessibilityLabel(Text("Foto"))
            }
        case .video:
            if let player {
                VideoPlayer(player: player).background(Color.black)
            } else {
                ProgressView()
            }
        case .audio:
            VStack(spacing: 20) {
                Button { voice.toggle(data) } label: {
                    Image(systemName: voice.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
                }
                ProgressView(value: voice.progress).padding(.horizontal, 40)
            }
        case .file:
            if let fileURL {
                QuickLookPreview(url: fileURL)
            } else {
                ProgressView()
            }
        }
    }

    private func prepare() {
        switch attachment.kind {
        case .video:
            if let url = try? AttachmentPreparer.temporaryFile(data, attachment: attachment) {
                fileURL = url
                player = AVPlayer(url: url)
            }
        case .file:
            fileURL = try? AttachmentPreparer.temporaryFile(data, attachment: attachment)
        case .image, .audio:
            break
        }
    }

    /// Die entschlüsselte Kopie gleich wieder löschen.
    private func cleanUp() {
        player?.pause()
        player = nil
        voice.stop()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }
}

/// QuickLook für Dateien (PDF, Bilder, Office …).
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

// MARK: - Aufnehmen

/// Die Kamera von iOS, ohne dass etwas in der Mediathek landet: das Foto
/// oder Video geht nur an Krypta.
struct CameraPicker: UIViewControllerRepresentable {
    enum Result {
        case photo(UIImage)
        case movie(URL)
    }

    let done: (Result?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = 120
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (Result?) -> Void
        init(done: @escaping (Result?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                done(.movie(url))
            } else if let image = info[.originalImage] as? UIImage {
                done(.photo(image))
            } else {
                done(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

/// Sprachnachricht aufnehmen: Aufnahme läuft, Stopp schickt, Verwerfen löscht.
struct VoiceRecorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let send: (URL, TimeInterval) -> Void
    @State private var recorder = VoiceRecorder()

    var body: some View {
        VStack(spacing: 18) {
            Group {
                if recorder.isRecording {
                    Text("Aufnahme läuft")
                } else if recorder.denied {
                    Text("Kein Zugriff aufs Mikrofon")
                } else {
                    Text("Sprachnachricht")
                }
            }
            .font(.headline)
            Text(AttachmentBubbleContent.clock(recorder.elapsed))
                .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(recorder.isRecording ? .red : .secondary)
            if recorder.denied {
                Text("Erlaube das Mikrofon in den iOS-Einstellungen unter Krypta.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 40) {
                Button(role: .destructive) {
                    recorder.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "trash.circle.fill").font(.system(size: 52))
                }
                .accessibilityLabel(Text("Verwerfen"))
                Button {
                    if let result = recorder.stop() {
                        Haptics.confirm()
                        send(result.url, result.duration)
                    }
                    dismiss()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 52))
                }
                .disabled(!recorder.isRecording)
                .accessibilityLabel(Text("Senden"))
            }
            Text("Höchstens fünf Minuten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .presentationDetents([.height(320)])
        .task { await recorder.start() }
        .onDisappear { if recorder.isRecording { recorder.cancel() } }
    }
}

/// Vor dem Senden: Vorschau, Bildunterschrift, einmal ansehen.
struct AttachmentComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pending: PendingAttachment
    let send: (OutgoingAttachment, String, Bool) -> Void
    @State private var caption = ""
    @State private var once = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Bildunterschrift", text: $caption, axis: .vertical)
                        .lineLimit(1...4)
                    if pending.out.kind == .image || pending.out.kind == .video {
                        Toggle(isOn: $once) { Label("Einmal ansehen", systemImage: "eye") }
                    }
                } footer: {
                    if pending.out.kind == .image {
                        Text("Das Foto wird neu gespeichert, ohne Ort, Kamera und Aufnahmezeit.")
                    } else if pending.out.kind == .video {
                        Text("Das Video wird neu gespeichert, ohne Ort und ohne persönliche Metadaten.")
                    } else {
                        Text("Dateien gehen so, wie sie sind. Was in der Datei steht, bleibt drin.")
                    }
                }
            }
            .navigationTitle("Senden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") {
                        send(pending.out, caption.trimmingCharacters(in: .whitespacesAndNewlines), once)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch pending.out.kind {
        case .image:
            if let ui = UIImage(data: pending.out.data) {
                Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .video:
            ZStack {
                if let thumb = pending.out.thumbnail.flatMap(UIImage.init(data:)) {
                    Image(uiImage: thumb).resizable().scaledToFit().frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Image(systemName: "play.circle.fill").font(.system(size: 48)).foregroundStyle(.white)
            }
        case .audio, .file:
            Label(pending.out.name ?? String(localized: "Datei"), systemImage: pending.out.kind == .audio ? "waveform" : "doc.fill")
                .font(.headline)
        }
        Text(ByteCountFormatter.string(fromByteCount: Int64(pending.out.data.count), countStyle: .file))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
