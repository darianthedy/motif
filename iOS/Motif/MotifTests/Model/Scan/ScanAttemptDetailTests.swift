import XCTest
@testable import Motif

final class ScanAttemptDetailTests: XCTestCase {
    func testStoresThePlanShape() throws {
        let detail = ScanAttemptDetail(
            steps: ScanSteps(quickScan: ScanMarkStep(ms: 7400, limitMs: nil, missed: ["c6"], extra: []),
                             move: ScanMoveStep(ms: 3100, limitMs: nil, played: Uci.parse("c4f7"), lossCp: 12)),
            softMisses: [.quickScanMissed], failReason: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(detail)) as? [String: Any])
        let steps = try XCTUnwrap(json["steps"] as? [String: Any])
        let move = try XCTUnwrap(steps["move"] as? [String: Any])
        XCTAssertEqual(move["played"] as? String, "c4f7"); XCTAssertEqual(move["lossCp"] as? Int, 12)
        XCTAssertEqual(json["softMisses"] as? [String], ["quickScanMissed"])
        XCTAssertEqual(try JSONDecoder().decode(ScanAttemptDetail.self, from: JSONEncoder().encode(detail)), detail)
    }

    func testANewerAppsWordsAreLeftOutNotFatal() throws {
        let text = #"{"steps":{"quickScan":{"ms":1,"missed":[],"extra":[]}},"softMisses":["quickScanSlow","someday"],"failReason":"someday"}"#
        let detail = try JSONDecoder().decode(ScanAttemptDetail.self, from: Data(text.utf8))
        XCTAssertEqual(detail.softMisses, [.quickScanSlow]); XCTAssertNil(detail.failReason)
        XCTAssertEqual(detail.steps.quickScan?.ms, 1)
        XCTAssertEqual(try JSONDecoder().decode(ScanAttemptDetail.self, from: Data("{}".utf8)), ScanAttemptDetail())
    }
}
