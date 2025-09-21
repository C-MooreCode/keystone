import SwiftUI

struct DesignSystem {
    let colors = ColorPalette()

    struct ColorPalette {
        let primary = Color.accentColor
        let background = Color(uiColor: .systemBackground)
    }
}
