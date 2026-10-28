import SwiftUI

/// The evaluation bar beside the game board: White's share of the bar is its winning
/// chance, with White's part at whichever end White sits on the board.
struct EvalBar: View {
    /// The analyzer's result for the position on screen, or nil while it's analysing.
    let evaluation: Evaluation?
    /// The side at the bottom of the board.
    let orientation: Side
    /// The last result shown, so the fill holds still until the next position's first result.
    @State private var last: Evaluation?

    static let width: CGFloat = 16
    static let gap: CGFloat = 6
    /// Depth from which the label is shown at full strength.
    static let firmDepth = 12
    static let whitePart = Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF4 / 255)
    static let blackPart = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)

    var body: some View {
        let shown = evaluation ?? last
        let white = Self.whiteShare(shown)
        let leader = Self.leader(shown)
        GeometryReader { geometry in
            ZStack(alignment: orientation == .white ? .bottom : .top) {
                Self.blackPart
                Self.whitePart.frame(height: geometry.size.height * white)
            }
            .overlay(alignment: leader == orientation ? .bottom : .top) {
                Text(evaluation.map(Self.label) ?? "…")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(leader == .white ? Self.blackPart : Self.whitePart)
                    .opacity(evaluation.map { $0.final || $0.depth >= Self.firmDepth } == true ? 1 : 0.5)
                    .padding(.vertical, 3)
            }
        }
        .frame(width: Self.width)
        .clipShape(.rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator), lineWidth: 0.5) }
        .animation(.smooth(duration: 0.35), value: white)
        .onChange(of: evaluation, initial: true) { _, next in if let next { last = next } }
        .accessibilityElement()
        .accessibilityLabel("Evaluation")
        .accessibilityValue(Self.spoken(evaluation))
        .accessibilityIdentifier("eval-bar")
    }

    /// White's part of the bar, 0–1: Lichess's win-chance curve, kept off the ends so
    /// the losing side stays visible. Only a mate fills it.
    static func whiteShare(_ evaluation: Evaluation?) -> Double {
        guard let evaluation else { return 0.5 }
        switch evaluation.score {
        case .mate: return evaluation.winner == .white ? 1 : 0
        case .cp(let cp):
            let percent = 50 + 50 * (2 / (1 + exp(-0.00368208 * Double(cp))) - 1)
            return min(max(percent, 2), 98) / 100
        }
    }

    /// The side ahead; White when level.
    static func leader(_ evaluation: Evaluation?) -> Side {
        guard let evaluation else { return .white }
        if let winner = evaluation.winner { return winner }
        if case .cp(let cp) = evaluation.score, cp < 0 { return .black }
        return .white
    }

    /// `0.6` / `M3`, without a sign: the end it sits at shows who's ahead.
    static func label(_ evaluation: Evaluation) -> String {
        switch evaluation.score {
        case .cp(let cp): return pawns(cp)
        case .mate(let moves): return "M\(abs(moves))"
        }
    }

    static func spoken(_ evaluation: Evaluation?) -> String {
        guard let evaluation else { return "Analysing" }
        let side = leader(evaluation) == .white ? "White" : "Black"
        switch evaluation.score {
        case .mate(0): return "\(side) has checkmated"
        case .mate(let moves): return "\(side) mates in \(abs(moves))"
        case .cp(let cp):
            let size = pawns(cp)
            return size == "0.0" ? "Equal" : "\(side) is better by \(size), depth \(evaluation.depth)"
        }
    }

    private static func pawns(_ cp: Int) -> String { String(format: "%.1f", Double(abs(cp)) / 100) }
}
