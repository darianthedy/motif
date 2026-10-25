import XCTest
@testable import Motif

final class AppConfigTests: XCTestCase {
    func testMissingURLUsesMemoryBackend() {
        XCTAssertNil(AppConfig.neonBaseURL(in: [:]))
    }

    func testEmptyURLUsesMemoryBackend() {
        XCTAssertNil(AppConfig.neonBaseURL(in: ["NeonBaseURL": ""]))
    }

    func testWhitespaceURLUsesMemoryBackend() {
        XCTAssertNil(AppConfig.neonBaseURL(in: ["NeonBaseURL": " \n\t "]))
    }

    func testUnexpandedBuildSettingUsesMemoryBackend() {
        XCTAssertNil(AppConfig.neonBaseURL(in: ["NeonBaseURL": "$(NEON_BASE_URL)"]))
    }

    func testNonStringURLUsesMemoryBackend() {
        XCTAssertNil(AppConfig.neonBaseURL(in: ["NeonBaseURL": 42]))
    }

    func testRelativeURLUsesMemoryBackend() {
        XCTAssertNil(AppConfig.neonBaseURL(in: ["NeonBaseURL": "neondb"]))
    }

    func testConfiguredURLPreservesEndpointAndTrimsWhitespace() {
        let text = "https://example.neon.tech/neondb"
        XCTAssertEqual(
            AppConfig.neonBaseURL(in: ["NeonBaseURL": " \(text)\n"])?.absoluteString,
            text
        )
    }
}
