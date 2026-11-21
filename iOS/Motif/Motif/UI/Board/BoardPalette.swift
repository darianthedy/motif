import SwiftUI

/// The board's colours in one place. Mark colours are asset-catalog colours with dark and
/// increased-contrast variants (Scan plan §4); none is the only signal, every mark has a shape.
enum BoardPalette {
    static let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.71)
    static let darkSquare = Color(red: 0.71, green: 0.53, blue: 0.39)
    static let markRed = Color("BoardMarkRed")
    static let markOrange = Color("BoardMarkOrange")
    static let markDot = Color("BoardMarkDot")
    static let ringCorrect = Color("BoardRingCorrect")
    static let ringMissed = Color("BoardRingMissed")
    static let ringExtra = Color("BoardRingExtra")
    static let arrowOwn = Color("BoardArrowOwn")
    static let arrowTheirs = Color("BoardArrowTheirs")
}
