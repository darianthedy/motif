import XCTest
@testable import Motif

/// Expected values come only from export-ios-fixtures.ts and the live TS API.
final class BoardParityTests: XCTestCase {
    private struct Fixture: Decodable {
        let version: Int
        let defaultPosition: String
        let squares: [String]
        let uci: [UciCase]
        let invalid: [InvalidCase]
        let positions: [PositionCase]
        let mating: [MatingCase]
    }

    private struct UciCase: Decodable {
        let text: String
        let parsed: Uci?
        let from: String?
        let to: String?
        let promotion: PromotionPiece?
        let stripped: Uci?
    }

    private struct InvalidCase: Decodable {
        let fen: String
        let valid: Bool
        let validation: Board.FenValidation
        let checkmate: Bool
        let targets: [String: Board.Target]
        let piece: Board.Piece?
        let empty: [String]
    }

    private struct PositionCase: Decodable {
        let name: String
        let fen: String
        let valid: Bool
        let validation: Board.FenValidation
        let turn: Side
        let checkmate: Bool
        let targets: [TargetCase]
        let moves: [MoveCase]
        let sans: [SanCase]
        let pieces: [PieceCase]
        let empty: [String]
        let placements: [PlacementCase]
        let line: [Uci]
        let replay: [Board.ReplayStep]
        let solutions: [[Uci]]
        let firstIllegal: Board.IllegalMove?
    }

    private struct TargetCase: Decodable {
        let from: String
        let destinations: [String: Board.Target]
    }
    private struct MoveCase: Decodable {
        let uci: Uci
        let legal: Bool
        let san: String?
        let fenAfter: String?
    }
    private struct SanCase: Decodable {
        let text: String
        let played: Board.PlayedSan?
    }
    private struct PieceCase: Decodable {
        let square: String
        let piece: Board.Piece?
    }
    private struct PlacementCase: Decodable {
        let placement: Placement
        let fenAfter: String?
    }
    private struct MatingCase: Decodable {
        let fen: String
        let color: Side
        let placements: [Placement]
    }

    private func fixture() throws -> Fixture {
        let bundle = Bundle(for: BoardParityTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "board", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "board", withExtension: "json"),
            "Generated board.json must be included in MotifTests resources"
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testGeometryAndUciNormalizationMatchTheWeb() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture.version, 1)
        XCTAssertEqual(Board.defaultPosition, fixture.defaultPosition)
        XCTAssertEqual(Board.squares, fixture.squares)
        for item in fixture.uci {
            let parsed = parseUci(item.text)
            XCTAssertEqual(parsed, item.parsed, item.text)
            XCTAssertEqual(parsed.map(moveFrom), item.from, item.text)
            XCTAssertEqual(parsed.map(moveTo), item.to, item.text)
            XCTAssertEqual(parsed.flatMap(movePromotion), item.promotion, item.text)
            XCTAssertEqual(parsed.flatMap(stripQueenPromotion), item.stripped, item.text)
        }
    }

    func testFENValidationAndCheckmateMatchTheWeb() throws {
        let fixture = try fixture()
        for item in fixture.invalid {
            XCTAssertEqual(Board.validateFen(item.fen), item.validation, item.fen)
            XCTAssertEqual(Board.isValidFen(item.fen), item.valid, item.fen)
            XCTAssertEqual(Board.isCheckmate(item.fen), item.checkmate, item.fen)
            XCTAssertEqual(Board.targetsFrom(item.fen, "e1"), item.targets, item.fen)
            XCTAssertEqual(Board.pieceAt(item.fen, "e1"), item.piece, item.fen)
            XCTAssertEqual(Board.emptySquares(item.fen), item.empty, item.fen)
            XCTAssertNil(Board.applyUci(item.fen, try uci("e1e2")))
            XCTAssertNil(Board.sanFor(item.fen, try uci("e1e2")))
            XCTAssertNil(Board.playSan(item.fen, "Ke2"))
            XCTAssertNil(Board.withPiece(item.fen, .init(color: .white, type: .knight, square: "d4")))
        }
        for item in fixture.positions {
            XCTAssertEqual(Board.validateFen(item.fen), item.validation, item.name)
            XCTAssertEqual(Board.isValidFen(item.fen), item.valid, item.name)
            XCTAssertEqual(Board.turnOf(item.fen), item.turn, item.name)
            XCTAssertEqual(Board.isCheckmate(item.fen), item.checkmate, item.name)
        }
    }

    func testEveryDestinationAndPromotionFlagMatchesTheWeb() throws {
        for item in try fixture().positions {
            for query in item.targets {
                XCTAssertEqual(Board.targetsFrom(item.fen, query.from), query.destinations,
                               "\(item.name): \(query.from)")
                for (to, target) in query.destinations {
                    XCTAssertEqual(Board.needsPromotion(item.fen, query.from, to), target.promotion,
                                   "\(item.name): \(query.from)-\(to)")
                }
            }
        }
    }

    func testEveryUciMoveSANAndWrittenFENMatchesTheWeb() throws {
        for item in try fixture().positions {
            for move in item.moves {
                let label = "\(item.name): \(move.uci.text)"
                XCTAssertEqual(Board.isLegal(item.fen, move.uci), move.legal, label)
                XCTAssertEqual(Board.applyUci(item.fen, move.uci), move.fenAfter, label)
                XCTAssertEqual(Board.sanFor(item.fen, move.uci), move.san, label)
            }
        }
    }

    func testCanonicalAndLooseSANMatchTheWeb() throws {
        for item in try fixture().positions {
            for move in item.sans {
                XCTAssertEqual(Board.playSan(item.fen, move.text), move.played,
                               "\(item.name): \(move.text)")
            }
        }
    }

    func testPieceLookupAndEmptySquareOrderMatchTheWeb() throws {
        for item in try fixture().positions {
            XCTAssertEqual(Board.emptySquares(item.fen), item.empty, item.name)
            for query in item.pieces {
                XCTAssertEqual(Board.pieceAt(item.fen, query.square), query.piece,
                               "\(item.name): \(query.square)")
            }
        }
    }

    func testMissingPiecePlacementsAndMetadataMatchTheWeb() throws {
        for item in try fixture().positions {
            for query in item.placements {
                XCTAssertEqual(Board.withPiece(item.fen, query.placement), query.fenAfter,
                               "\(item.name): \(query.placement)")
            }
        }
    }

    func testReplayAndFirstIllegalMoveMatchTheWeb() throws {
        for item in try fixture().positions {
            XCTAssertEqual(Board.replayLine(item.fen, item.line), item.replay, item.name)
            XCTAssertEqual(Board.firstIllegalMove(item.fen, item.solutions), item.firstIllegal, item.name)
        }
    }

    func testMatingPlacementAuditMatchesTheWeb() throws {
        for item in try fixture().mating {
            XCTAssertEqual(Board.matingPlacements(item.fen, item.color), item.placements, item.fen)
        }
    }
}
