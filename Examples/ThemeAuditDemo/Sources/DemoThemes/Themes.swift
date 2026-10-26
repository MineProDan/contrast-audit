import ContrastCore

// Two invented themes. Neither comes from a real product.

/// Passes WCAG 2.1 AA in both variants, including a translucent `glass`
/// surface measured over each variant's `wallpaper`.
public enum Orchard {
    /// Every pair is checked in every variant.
    public static let pairs = [
        ColorPair("text", on: "surface", role: .bodyText),
        ColorPair("muted", on: "surface", role: .bodyText),
        ColorPair("link", on: "card", role: .bodyText),
        ColorPair("border", on: "surface", role: .uiComponent),
        ColorPair("caption", on: "glass", role: .bodyText, backdrop: "wallpaper"),
    ]

    /// The theme with its light and dark palettes.
    public static let theme = Theme("Orchard", pairs: pairs, variants: [
        Variant("light", hex: [
            "text": "#14303A", "muted": "#4A6670", "surface": "#F7FBFC", "card": "#E8F1F3",
            "link": "#0B6470", "border": "#6F8A93", "glass": "#FFFFFFCC", "wallpaper": "#2F7F8C",
            "caption": "#12313B",
        ]),
        Variant("dark", hex: [
            "text": "#E6F2F4", "muted": "#9DB5BC", "surface": "#0D1D22", "card": "#16292F",
            "link": "#5CC6D0", "border": "#5F7C85", "glass": "#0D1D22B3", "wallpaper": "#2F7F8C",
            "caption": "#E6F2F4",
        ]),
    ])
}

/// Fails AA on purpose: dark `subtitle` is too faint for body text and
/// light `toggle-track` is too faint for a UI component. Light `brand-mark`
/// also fails, but it is a logotype and has a waiver. The translucent `frost`
/// surface passes over each variant's `wallpaper`.
public enum Ember {
    /// Every pair is checked in every variant.
    public static let pairs = [
        ColorPair("title", on: "surface", role: .bodyText),
        ColorPair("subtitle", on: "surface", role: .bodyText),
        ColorPair("link", on: "card", role: .bodyText),
        ColorPair("toggle-track", on: "surface", role: .uiComponent),
        ColorPair("caption", on: "frost", role: .bodyText, backdrop: "wallpaper"),
        ColorPair("brand-mark", on: "banner", role: .largeText, note: "Logotype"),
    ]

    /// The theme with its light and dark palettes.
    public static let theme = Theme("Ember", pairs: pairs, variants: [
        Variant("light", hex: [
            "title": "#2B1A12", "subtitle": "#6E5649", "surface": "#FFF8F3", "card": "#F6E9DF",
            "link": "#A13D12", "toggle-track": "#D9B8A3", "frost": "#FFFFFFBF", "wallpaper": "#B4532A",
            "caption": "#3A2418", "banner": "#F39A62", "brand-mark": "#FFFFFF",
        ]),
        Variant("dark", hex: [
            "title": "#F7E9DF", "subtitle": "#8A6F60", "surface": "#1E140F", "card": "#2A1D16",
            "link": "#F29A6B", "toggle-track": "#8E6C59", "frost": "#1E140FA6", "wallpaper": "#B4532A",
            "caption": "#F7E9DF", "banner": "#C2561F", "brand-mark": "#FFFFFF",
        ]),
    ])

    /// Reviewed exceptions for this theme.
    public static let waivers = [
        Waiver("brand-mark", on: "banner", variant: "light",
               reason: "Logotype, exempt under SC 1.4.3",
               expiryNote: "Revisit with the next banner color change"),
    ]
}
