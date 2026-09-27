import AVFoundation
import Foundation
import ImageIO
import KryptaCore
import KryptaMessenger
import UIKit
import UniformTypeIdentifiers

/// Macht aus Fotos, Videos, Aufnahmen und Dateien etwas zum Verschicken —
/// ohne das, was niemanden etwas angeht.
///
/// - Fotos werden neu kodiert (JPEG, höchstens 2048 Pixel): kein EXIF, kein
///   GPS, kein Kameramodell, keine Aufnahmezeit. Die Drehung wird vorher
///   eingerechnet.
/// - Videos werden neu exportiert (MP4, mittlere Qualität) mit dem Filter
///   von AVFoundation fürs Teilen, der Ort und persönliche Metadaten entfernt.
/// - Dateien gehen so, wie sie sind: was in einem PDF steht, gehört zur Datei.
enum AttachmentPreparer {
    enum Failure: LocalizedError {
        case unreadable
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "Die Datei lässt sich nicht lesen.")
            case .tooLarge: String(localized: "Die Datei ist zu groß. Höchstens 25 MB gehen.")
            }
        }
    }

    static let maxImageSide = 2048
    static let thumbnailSide = 64

    // MARK: - Fotos

    static func image(from data: Data) throws -> OutgoingAttachment {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw Failure.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImageSide,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failure.unreadable }
        return try image(cg)
    }

    /// Aus der Kamera: das Bild trägt dort keinen Ort, wird aber trotzdem
    /// neu gezeichnet (Drehung eingerechnet, Größe begrenzt).
    static func image(from ui: UIImage) throws -> OutgoingAttachment {
        let scale = min(1, CGFloat(maxImageSide) / max(ui.size.width, ui.size.height))
        let size = CGSize(width: (ui.size.width * scale).rounded(), height: (ui.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        guard let cg = drawn.cgImage else { throw Failure.unreadable }
        return try image(cg)
    }

    private static func image(_ cg: CGImage) throws -> OutgoingAttachment {
        let jpeg = try encodeJPEG(cg, quality: 0.8)
        guard jpeg.count <= AttachmentCrypto.maxSize else { throw Failure.tooLarge }
        return OutgoingAttachment(data: jpeg, kind: .image, mime: "image/jpeg", width: cg.width, height: cg.height, thumbnail: thumbnail(cg))
    }

    /// JPEG ohne jede Metadaten: nur das Bild und die Kompression.
    static func encodeJPEG(_ cg: CGImage, quality: CGFloat) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.unreadable
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.unreadable }
        return out as Data
    }

    /// Winzige Vorschau, reist verschlüsselt in der Nachricht mit.
    static func thumbnail(_ cg: CGImage) -> Data? {
        let scale = CGFloat(thumbnailSide) / CGFloat(max(cg.width, cg.height))
        let w = max(1, Int(CGFloat(cg.width) * min(1, scale)))
        let h = max(1, Int(CGFloat(cg.height) * min(1, scale)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage(), let data = try? encodeJPEG(small, quality: 0.5),
              data.count <= AttachmentPolicy.maxThumbnail else { return nil }
        return data
    }

    // MARK: - Videos

    static func video(at url: URL) async throws -> OutgoingAttachment {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else { throw Failure.unreadable }
        let out = try temporaryURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        export.metadata = []
        export.metadataItemFilter = .forSharing()
        await export.export()
        guard export.status == .completed else { throw Failure.unreadable }
        let data = try Data(contentsOf: out)
        guard data.count <= AttachmentCrypto.maxSize else { throw Failure.tooLarge }

        let duration = (try? await asset.load(.duration).seconds) ?? 0
        var width: Int?, height: Int?
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) {
            let size = natural.applying(transform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        let poster = try? await generator.image(at: .zero).image
        return OutgoingAttachment(data: data, kind: .video, mime: "video/mp4", width: width, height: height,
                                  duration: duration.isFinite ? duration : nil, thumbnail: poster.flatMap(thumbnail))
    }

    // MARK: - Sprachnachrichten und Dateien

    static func audio(at url: URL, duration: TimeInterval) throws -> OutgoingAttachment {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw Failure.unreadable }
        guard data.count <= AttachmentCrypto.maxSize else { throw Failure.tooLarge }
        return OutgoingAttachment(data: data, kind: .audio, mime: "audio/mp4", duration: duration)
    }

    static func file(at url: URL) throws -> OutgoingAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= AttachmentCrypto.maxSize else { throw Failure.tooLarge }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw Failure.unreadable }
        guard data.count <= AttachmentCrypto.maxSize else { throw Failure.tooLarge }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return OutgoingAttachment(data: data, kind: .file, mime: mime, name: url.lastPathComponent)
    }

    // MARK: - Zum Ansehen

    /// Ordner für entschlüsselte Kopien, die ein Abspieler oder die Vorschau
    /// als Datei braucht. Nur solange sie offen sind; beim Sperren weg.
    private static var viewDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("krypta-view", isDirectory: true)
    }

    static func temporaryURL(ext: String) throws -> URL {
        let dir = viewDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        return dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    /// Eine entschlüsselte Kopie für AVPlayer oder QuickLook.
    static func temporaryFile(_ data: Data, attachment: Attachment) throws -> URL {
        let url: URL
        if let name = attachment.name, !name.isEmpty {
            // Den Namen behalten, damit die Vorschau ihn zeigt; eigener Ordner je Datei.
            let dir = try temporaryURL(ext: "d")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            url = dir.appendingPathComponent((name as NSString).lastPathComponent)
        } else {
            url = try temporaryURL(ext: fileExtension(for: attachment))
        }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func fileExtension(for a: Attachment) -> String {
        if let ext = UTType(mimeType: a.mime)?.preferredFilenameExtension { return ext }
        switch a.kind {
        case .image: return "jpg"
        case .video: return "mp4"
        case .audio: return "m4a"
        case .file: return "bin"
        }
    }

    static func clearTemporaryFiles() {
        try? FileManager.default.removeItem(at: viewDirectory)
    }
}
