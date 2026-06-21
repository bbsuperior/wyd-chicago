import SwiftUI

// MARK: - Typography (canon §2)
//
// Display / headings: Space Grotesk (weights 500/600/700)
// Body / UI:          Inter (weights 400/500/600)
//
// On iOS we bundle the TTFs (see README) and reference them by their PostScript
// names. If the fonts aren't bundled yet, we gracefully fall back to SF Pro
// Rounded so the app still renders cleanly. The helpers below pick the custom
// font when available and otherwise return a rounded system font of the same size.

enum WYDFont {

    // PostScript names of the bundled fonts. Update if your TTFs differ.
    private enum Name {
        static let display      = "SpaceGrotesk-Medium"   // 500
        static let displaySemi  = "SpaceGrotesk-SemiBold"  // 600
        static let displayBold  = "SpaceGrotesk-Bold"      // 700
        static let body         = "Inter-Regular"          // 400
        static let bodyMedium   = "Inter-Medium"           // 500
        static let bodySemi     = "Inter-SemiBold"         // 600
    }

    private static func custom(_ name: String, size: CGFloat, fallbackWeight: Font.Weight) -> Font {
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: fallbackWeight, design: .rounded)
    }

    // Display / headings — Space Grotesk
    static func display(_ size: CGFloat) -> Font {
        custom(Name.display, size: size, fallbackWeight: .medium)
    }
    static func displaySemibold(_ size: CGFloat) -> Font {
        custom(Name.displaySemi, size: size, fallbackWeight: .semibold)
    }
    static func displayBold(_ size: CGFloat) -> Font {
        custom(Name.displayBold, size: size, fallbackWeight: .bold)
    }

    // Body / UI — Inter
    static func body(_ size: CGFloat) -> Font {
        custom(Name.body, size: size, fallbackWeight: .regular)
    }
    static func bodyMedium(_ size: CGFloat) -> Font {
        custom(Name.bodyMedium, size: size, fallbackWeight: .medium)
    }
    static func bodySemibold(_ size: CGFloat) -> Font {
        custom(Name.bodySemi, size: size, fallbackWeight: .semibold)
    }
}

// MARK: - Convenient text styles

extension Font {
    /// Big hero / wordmark.
    static let wydHero      = WYDFont.displayBold(34)
    /// Screen title.
    static let wydTitle     = WYDFont.displayBold(26)
    /// Card / section headline.
    static let wydHeadline  = WYDFont.displaySemibold(20)
    /// Standard body copy.
    static let wydBody      = WYDFont.body(16)
    /// Emphasised body.
    static let wydBodyMedium = WYDFont.bodyMedium(16)
    /// Captions, meta, chips.
    static let wydCaption   = WYDFont.bodyMedium(13)
    /// Tiny labels.
    static let wydTiny      = WYDFont.bodyMedium(11)
}
