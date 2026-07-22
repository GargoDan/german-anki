import SwiftUI

/// Playful per-topic styling: an SF Symbol and a color for each topic slug.
/// Falls back to a stable hash-picked color and a generic icon for any slug
/// not in the curated map, so new pipeline topics still look intentional.
enum TopicStyle {

    /// SF Symbol name for a topic slug.
    static func icon(_ slug: String) -> String {
        iconMap[slug] ?? "square.grid.2x2"
    }

    /// A pleasant, deterministic tint for a topic slug.
    static func color(_ slug: String) -> Color {
        if let explicit = colorMap[slug] { return explicit }
        // Stable pick from the palette for uncurated slugs.
        let index = abs(slug.hashValueStable) % palette.count
        return palette[index]
    }

    private static let palette: [Color] = [
        .blue, .green, .orange, .pink, .purple, .teal, .indigo, .mint, .cyan, .brown,
    ]

    private static let iconMap: [String: String] = [
        "alltag": "sun.max",
        "arbeit": "briefcase",
        "arbeit-beruf": "briefcase.fill",
        "beziehungen": "heart",
        "bildung": "graduationcap",
        "bildung-lernen": "graduationcap.fill",
        "dienstleistungen": "building.columns",
        "einkaufen": "cart",
        "einkaufen-konsum": "cart.fill",
        "essen-trinken": "fork.knife",
        "freizeit-hobby": "gamecontroller",
        "gefuehle-beziehungen": "heart.fill",
        "gesellschaft": "person.3",
        "gesellschaft-politik": "building.columns.fill",
        "gesundheit": "cross.case",
        "gesundheit-ernaehrung": "heart.text.square",
        "grundwortschatz": "star",
        "kleidung": "tshirt",
        "koerper-gesundheit": "figure.walk",
        "kultur": "theatermasks",
        "kultur-medien": "theatermasks.fill",
        "lernen-schule": "book",
        "medien-internet": "wifi",
        "medien-technologie": "tv",
        "person-familie": "person.2",
        "redemittel": "bubble.left.and.bubble.right",
        "reisen-mobilitaet": "airplane",
        "reisen-verkehr": "car",
        "technik": "gearshape.2",
        "termine": "calendar",
        "umwelt": "leaf",
        "umwelt-nachhaltigkeit": "leaf.arrow.triangle.circlepath",
        "umwelt-wetter": "cloud.sun",
        "wirtschaft-konsum": "eurosign.circle",
        "wissenschaft-technik": "atom",
        "wohnen": "house",
    ]

    private static let colorMap: [String: Color] = [
        "person-familie": .pink,
        "gefuehle-beziehungen": .pink,
        "beziehungen": .pink,
        "wohnen": .orange,
        "essen-trinken": .red,
        "gesundheit": .mint,
        "gesundheit-ernaehrung": .mint,
        "koerper-gesundheit": .mint,
        "umwelt": .green,
        "umwelt-wetter": .green,
        "umwelt-nachhaltigkeit": .green,
        "reisen-verkehr": .blue,
        "reisen-mobilitaet": .blue,
        "arbeit": .brown,
        "arbeit-beruf": .brown,
        "bildung": .indigo,
        "bildung-lernen": .indigo,
        "lernen-schule": .indigo,
        "einkaufen": .purple,
        "einkaufen-konsum": .purple,
        "wissenschaft-technik": .teal,
        "technik": .teal,
        "medien-technologie": .teal,
        "medien-internet": .cyan,
        "kultur": .purple,
        "kultur-medien": .purple,
    ]
}

private extension String {
    /// A stable hash that doesn't vary between launches (unlike `hashValue`).
    var hashValueStable: Int {
        var hash = 5381
        for byte in utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return hash
    }
}
