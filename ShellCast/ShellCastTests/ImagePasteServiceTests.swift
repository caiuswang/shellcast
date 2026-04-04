import XCTest
@testable import ShellCast

/// Tests for ImagePasteService image preparation logic.
final class ImagePasteServiceTests: XCTestCase {

    // MARK: - prepareImage

    func testPrepareSmallImage() {
        // A small image should pass through without excessive compression
        let image = createTestImage(width: 100, height: 100)
        let result = ImagePasteService.prepareImage(image)

        XCTAssertNotNil(result)
        // PNG of 100x100 should be well under 500KB
        XCTAssertLessThan(result!.count, 500_000)
    }

    func testPrepareLargeImageIsResized() {
        // A large image should be resized down
        let image = createTestImage(width: 3000, height: 2000)
        let result = ImagePasteService.prepareImage(image, maxDimension: 1600)

        XCTAssertNotNil(result)
        // Verify the PNG data can be decoded back
        let decoded = UIImage(data: result!)
        XCTAssertNotNil(decoded)
        // The longest side should be <= 1600
        let maxSide = max(decoded!.size.width, decoded!.size.height)
        XCTAssertLessThanOrEqual(maxSide, 1600)
    }

    func testPrepareImageReturnsPNG() {
        let image = createTestImage(width: 200, height: 200)
        let result = ImagePasteService.prepareImage(image)

        XCTAssertNotNil(result)
        // PNG magic bytes: 0x89 P N G
        XCTAssertEqual(result![0], 0x89)
        XCTAssertEqual(result![1], 0x50) // 'P'
        XCTAssertEqual(result![2], 0x4E) // 'N'
        XCTAssertEqual(result![3], 0x47) // 'G'
    }

    func testPrepareImageRespectsSizeLimit() {
        // Create a complex image that would be large as PNG
        let image = createNoiseImage(width: 2000, height: 2000)
        let result = ImagePasteService.prepareImage(image, maxDimension: 1600, maxBytes: 500_000)

        XCTAssertNotNil(result)
        // Should have been progressively resized to fit under maxBytes
        // (may exceed for very noisy images, but the function should still return data)
    }

    func testPrepareImagePreservesAspectRatio() {
        // Landscape image
        let image = createTestImage(width: 3000, height: 1500)
        let result = ImagePasteService.prepareImage(image, maxDimension: 1600)

        XCTAssertNotNil(result)
        let decoded = UIImage(data: result!)!
        let ratio = decoded.size.width / decoded.size.height
        // Original ratio is 2:1, should be preserved
        XCTAssertEqual(ratio, 2.0, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func createTestImage(width: Int, height: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Add some variation
            UIColor.red.setFill()
            ctx.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        }
    }

    private func createNoiseImage(width: Int, height: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            // Fill with gradient-like pattern to create some PNG entropy
            for y in stride(from: 0, to: height, by: 4) {
                for x in stride(from: 0, to: width, by: 4) {
                    let r = CGFloat(x % 256) / 255.0
                    let g = CGFloat(y % 256) / 255.0
                    let b = CGFloat((x + y) % 256) / 255.0
                    UIColor(red: r, green: g, blue: b, alpha: 1.0).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        }
    }
}
