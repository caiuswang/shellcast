import UIKit

/// Handles transferring images from the iOS clipboard to a remote Mac's clipboard via SSH,
/// enabling native Ctrl+V image paste in Claude Code.
enum ImagePasteService {

    enum ImagePasteError: Error, LocalizedError {
        case compressionFailed
        case transferFailed(String)
        case clipboardSetFailed(String)

        var errorDescription: String? {
            switch self {
            case .compressionFailed: return "Failed to compress image"
            case .transferFailed(let reason): return "Image transfer failed: \(reason)"
            case .clipboardSetFailed(let reason): return "Failed to set remote clipboard: \(reason)"
            }
        }
    }

    /// Resize image so the longest side is at most `maxDimension`, then encode as PNG.
    /// Progressively reduces size if the result exceeds `maxBytes`.
    static func prepareImage(_ image: UIImage, maxDimension: CGFloat? = nil, maxBytes: Int? = nil) -> Data? {
        let quality = TerminalSettings.shared.imagePasteQuality
        let maxDimension = maxDimension ?? quality.maxDimension
        let maxBytes = maxBytes ?? quality.maxBytes
        let resized = resize(image, maxDimension: maxDimension)
        if let data = resized.pngData(), data.count <= maxBytes {
            return data
        }
        // PNG too large — use JPEG for better compression while keeping quality
        for quality in [0.85, 0.7, 0.5] as [CGFloat] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        // Last resort: reduce dimensions
        let smaller = resize(image, maxDimension: 1200)
        return smaller.jpegData(compressionQuality: 0.7)
    }

    /// Transfer image to remote Mac and set it in the macOS clipboard.
    /// After this call, pressing Ctrl+V in Claude Code will paste the image as `[image1]`.
    static func transferAndSetClipboard(image: UIImage, session: SSHSession) async throws {
        guard let pngData = prepareImage(image) else {
            throw ImagePasteError.compressionFailed
        }

        let uuid = UUID().uuidString.prefix(8).lowercased()
        let remotePath = "/tmp/shellcast-img-\(uuid).png"

        // Clean up old images first (fire and forget)
        async let _ = cleanupOldImages(session: session)

        // Transfer image via base64 in chunks to avoid SSH exec size limits
        let base64 = pngData.base64EncodedString()
        // Write base64 in chunks to avoid SSH exec size limits, then decode
        let chunkSize = 50_000
        let b64Path = remotePath + ".b64"
        var offset = 0
        var chunkIndex = 0

        while offset < base64.count {
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: min(chunkSize, base64.count - offset))
            let chunk = String(base64[start..<end])
            let op = chunkIndex == 0 ? ">" : ">>"
            _ = try await session.exec("printf '%s' '\(chunk)' \(op) \(b64Path)")
            offset += chunkSize
            chunkIndex += 1
        }

        _ = try await session.exec("base64 -d < \(b64Path) > \(remotePath) && rm -f \(b64Path)")

        // Verify file was written
        let checkCmd = "test -f \(remotePath) && echo ok || echo fail"
        let checkResult = try await session.exec(checkCmd)
        guard checkResult.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
            throw ImagePasteError.transferFailed("File not written to \(remotePath)")
        }

        // Set the remote Mac's clipboard to the image
        // Using AppleScript's «class PNGf» to set PNG data in clipboard
        let clipboardCmd = """
        osascript -e 'set the clipboard to (read POSIX file "\(remotePath)" as «class PNGf»)'
        """
        let clipResult = try await session.exec(clipboardCmd)
        debugLog("[IMAGE] Clipboard set result: \(clipResult)")

        // Verify clipboard was set (optional, best-effort)
        let verifyCmd = "osascript -e 'clipboard info' 2>/dev/null | grep -q PNGf && echo ok || echo fail"
        let verifyResult = try await session.exec(verifyCmd)
        if verifyResult.trimmingCharacters(in: .whitespacesAndNewlines) != "ok" {
            debugLog("[IMAGE] Warning: clipboard verification failed, but continuing")
        }

        debugLog("[IMAGE] Image ready at \(remotePath), clipboard set")
    }

    /// Remove ShellCast temp images older than 60 minutes.
    static func cleanupOldImages(session: SSHSession) async {
        _ = try? await session.exec("find /tmp -name 'shellcast-img-*' -mmin +60 -delete 2>/dev/null")
    }

    // MARK: - Private

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        // Use pixel dimensions (not points) to ensure consistent output regardless of device scale
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension else { return image }

        let ratio = maxDimension / longest
        let newSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
        // Use scale 1.0 so the output image has 1:1 point-to-pixel mapping
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
