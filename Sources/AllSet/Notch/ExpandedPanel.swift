import AllSetCore
import SwiftUI

/// The open notch: tabs and controls flank the camera housing, content below.
struct ExpandedPanel: View {
    let model: NotchViewModel
    let services: AppServices
    let openSettings: @MainActor () -> Void
    @Namespace private var tabHighlight

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    tabButton(.home, symbol: "house.fill", help: "Home")
                    tabButton(.tray, symbol: "tray.full.fill", help: "Shelf & Clipboard")
                    tabButton(.mixer, symbol: "slider.vertical.3", help: "Sound")
                    tabButton(.notes, symbol: "note.text", help: "Notes")
                    tabButton(.system, symbol: "gauge.with.dots.needle.50percent", help: "System")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: model.geometry.notchRect.width)

                HStack(spacing: 12) {
                    Button {
                        Task { await ScreenshotStudioController.shared.capture(services: services) }
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchIconButtonStyle())
                    .help("Screenshot with AI")
                    if let battery = services.monitor.snapshot.battery {
                        BatteryBadge(battery: battery)
                    }
                    Button(action: openSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchIconButtonStyle())
                    .help("Settings")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: model.geometry.notchRect.height)

            // Each tab lays out at its final width, so nothing reflows while the
            // shape animates between sizes; the shape's edge clips it instead.
            ZStack(alignment: .top) {
                switch model.tab {
                case .home:
                    HomeTab(services: services)
                        .frame(width: Self.bodyWidth(for: .home))
                        .transition(.reveal(in: .smooth(duration: 0.28).delay(0.1), out: .easeIn(duration: 0.12)))
                case .tray:
                    TrayTab(services: services)
                        .frame(width: Self.bodyWidth(for: .tray))
                        .transition(.reveal(in: .smooth(duration: 0.28).delay(0.1), out: .easeIn(duration: 0.12)))
                case .mixer:
                    MixerTab(services: services)
                        .frame(width: Self.bodyWidth(for: .mixer))
                        .transition(.reveal(in: .smooth(duration: 0.28).delay(0.1), out: .easeIn(duration: 0.12)))
                case .notes:
                    NotesTab(notes: services.notes, model: model, openNotes: { services.openWindow(.notes) })
                        .frame(width: Self.bodyWidth(for: .notes))
                        .transition(.reveal(in: .smooth(duration: 0.28).delay(0.1), out: .easeIn(duration: 0.12)))
                case .system:
                    SystemTab(services: services)
                        .frame(width: Self.bodyWidth(for: .system))
                        .transition(.reveal(in: .smooth(duration: 0.28).delay(0.1), out: .easeIn(duration: 0.12)))
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(.white)
    }

    private static func bodyWidth(for tab: NotchViewModel.Tab) -> CGFloat {
        NotchViewModel.expandedSize(for: tab).width - 44
    }

    private func tabButton(_ tab: NotchViewModel.Tab, symbol: String, help: String) -> some View {
        NotchTabButton(symbol: symbol, isSelected: model.tab == tab, highlight: tabHighlight) {
            withAnimation(NotchAnimation.tab) { model.tab = tab }
        }
        .help(help)
    }
}

/// A tab icon: brightens under the pointer, and the highlight glides over to
/// whichever one is chosen.
private struct NotchTabButton: View {
    let symbol: String
    let isSelected: Bool
    let highlight: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected ? 1 : isHovered ? 0.8 : 0.45))
                .symbolEffect(.bounce, value: isSelected)
                .frame(width: 32, height: 22)
                .background {
                    if isSelected {
                        Capsule().fill(.white.opacity(0.14))
                            .matchedGeometryEffect(id: "tab", in: highlight)
                    } else if isHovered {
                        Capsule().fill(.white.opacity(0.06))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withMotion(Motion.quick) { isHovered = hovering }
        }
    }
}

private struct BatteryBadge: View {
    let battery: BatteryInfo

    var body: some View {
        HStack(spacing: 4) {
            Text("\(battery.percent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            Image(systemName: battery.isCharging ? "battery.100percent.bolt" : CollapsedActivityView.batterySymbol(percent: battery.percent))
                .font(.system(size: 13))
                .foregroundStyle(Theme.battery(percent: battery.percent, charging: battery.isCharging), .white.opacity(0.9))
        }
        .foregroundStyle(.white.opacity(0.8))
    }
}
