import SwiftUI

/// The ways to browse the library as one compact strip. The bright pill
/// slides to whichever is chosen (fades there with Reduce Motion); the strip
/// scrolls when the window is too narrow for all of them.
struct CategoryRail: View {
    /// A `ThemeDiscovery` raw value, as the page stores it.
    @Binding var selection: String
    /// Reduce Motion is on.
    var reduced = false

    @Namespace private var namespace

    var body: some View {
        let chosen = ThemeDiscovery(rawValue: selection) ?? .all
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(ThemeDiscovery.allCases) { item in
                        let selected = item == chosen
                        Button {
                            selection = item.rawValue
                            withAnimation(reduced ? nil : .easeInOut(duration: 0.15)) { scroller.scrollTo(item.id) }
                        } label: {
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selected ? Color.black.opacity(0.85) : DS.Ink.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background { if selected { pill } }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(3)
                // Only the strip animates. The page below changes at once:
                // a dozen rails sliding to new places is motion nobody asked for.
                .animation(reduced ? Motion.reduced : .easeInOut(duration: 0.15), value: chosen)
            }
        }
        // A plain dark fill, not a material: the strip scrolls with the
        // page, and a material re-blurs what moves behind it.
        .background(Color.black.opacity(0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Surface.hairline))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var pill: some View {
        if reduced {
            Capsule().fill(DS.Ink.primary).transition(.opacity)
        } else {
            Capsule().fill(DS.Ink.primary).matchedGeometryEffect(id: "pill", in: namespace)
        }
    }
}
