import AllSetCore
import SwiftUI

/// Everything about the Dynamic Island: a live miniature to play with, buttons
/// that run each animation on the real notch, and its settings.
struct IslandPage: View {
    let services: AppServices
    @State private var preview = NotchViewModel(geometry: IslandPage.previewGeometry)
    @State private var previewState: PreviewState = .home

    enum PreviewState: String, CaseIterable, Identifiable {
        case closed, nowPlaying, volume, home, system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .closed: "Closed"
            case .nowPlaying: "Now Playing"
            case .volume: "Volume"
            case .home: "Open: Home"
            case .system: "Open: System"
            }
        }
    }

    /// A pretend 940-point-wide screen with a MacBook-sized notch.
    static let previewGeometry = NotchGeometry(
        screenFrame: CGRect(origin: .zero, size: NotchViewModel.windowSize),
        safeAreaTop: 32,
        topLeftArea: CGRect(x: 0, y: 0, width: (NotchViewModel.windowSize.width - 180) / 2, height: 32),
        topRightArea: CGRect(x: 0, y: 0, width: (NotchViewModel.windowSize.width - 180) / 2, height: 32),
        menuBarHeight: 32
    )

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section {
                VStack(spacing: 14) {
                    IslandStage(model: preview, services: services)
                    Picker("Preview", selection: $previewState) {
                        ForEach(PreviewState.allCases) { state in
                            Text(state.title).tag(state)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .listRowInsets(EdgeInsets())
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    tryButton("Open the panel", symbol: "rectangle.expand.vertical", demo: .open)
                    tryButton("Now Playing", symbol: "music.note", demo: .nowPlaying)
                    tryButton("Volume", symbol: "speaker.wave.2.fill", demo: .volume)
                    tryButton("Charging", symbol: "bolt.fill", demo: .charging)
                    tryButton("Low battery", symbol: "battery.25percent", demo: .lowBattery)
                    tryButton("Audio device", symbol: "airpods", demo: .audioDevice)
                }
                .padding(.vertical, 4)
                .disabled(!settings.notchEnabled)
            } header: {
                Text("Try it on your notch")
            } footer: {
                Text("Each button plays that animation on your Mac's real notch.")
            }

            Section {
                Toggle(isOn: $settings.notchEnabled) {
                    Text("Dynamic Island")
                    Text("Turn the notch into a live panel with activities around it.")
                }
            }

            Section("Opening") {
                Toggle("Open when the pointer rests on the notch", isOn: $settings.expandOnHover)
                LabeledContent("Delay") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: 0...0.6, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int((settings.hoverDelay * 1000).rounded())) ms")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                .disabled(!settings.expandOnHover)
                Picker("Open to", selection: $settings.notchStartTab) {
                    ForEach(NotchStartTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                Toggle("Haptic feedback when opening", isOn: $settings.hapticFeedback)
            }
            .disabled(!settings.notchEnabled)

            Section {
                Picker("Show on", selection: $settings.notchDisplay) {
                    ForEach(NotchDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                }
            } header: {
                Text("Placement")
            } footer: {
                Text("Screens without a notch get a virtual one in the middle of the menu bar. Clicking the notch always opens it.")
            }
            .disabled(!settings.notchEnabled)
        }
        .dsFormStyle()
        .onChange(of: previewState, initial: true) { _, state in apply(state) }
        // A preview: numbers every couple of seconds are plenty.
        .onAppear { services.monitor.setViewer("window", visible: true, interval: 2) }
        .onDisappear { services.monitor.setViewer("window", visible: false) }
    }

    private func tryButton(_ title: String, symbol: String, demo: NotchDemo) -> some View {
        Button {
            services.notch?.demo(demo)
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    private func apply(_ state: PreviewState) {
        let opening = state == .home || state == .system
        withAnimation(opening ? NotchAnimation.open : NotchAnimation.close) {
            preview.isExpanded = opening
            preview.tab = state == .system ? .system : .home
            preview.transientActivity = switch state {
            case .nowPlaying: .nowPlaying
            case .volume: .volume(level: max(services.volume.volume, 0.5), muted: false)
            default: nil
            }
        }
    }
}

/// The miniature: the notch hanging from the top of a pretend screen, scaled to fit.
private struct IslandStage: View {
    let model: NotchViewModel
    let services: AppServices

    var body: some View {
        GeometryReader { geometry in
            let size = NotchViewModel.windowSize
            let scale = min(1, geometry.size.width / size.width)
            ZStack(alignment: .top) {
                StudioBackdrop(piece: ArtPiece(style: .aurora, palette: .midnight))
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .frame(height: 32 * scale)
                IslandRepresentable(model: model, services: services)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .top)
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        // Tall enough for whatever the island shows, plus some screen below it.
        .frame(height: max(model.shapeSize.height * 0.78 + 70, 150))
        .animation(model.isExpanded ? NotchAnimation.open : NotchAnimation.close, value: model.shapeSize)
        .clipped()
    }
}

/// The notch's System tab, larger, plus the monitor's settings.
struct MonitorPage: View {
    let services: AppServices

    var body: some View {
        Form {
            Section {
                GeometryReader { geometry in
                    let width: CGFloat = 816
                    let scale = min(1, (geometry.size.width - 32) / width)
                    SystemTab(services: services)
                        .frame(width: width, height: 244)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: width * scale, height: 244 * scale, alignment: .topLeading)
                        .padding(16)
                        .environment(\.colorScheme, .dark)
                        .foregroundStyle(.white)
                }
                .frame(height: 290)
                .background(RoundedRectangle(cornerRadius: 12).fill(.black))
                .listRowInsets(EdgeInsets())
            }
            MonitorSettings(settings: services.settings)
        }
        .dsFormStyle()
        .onAppear { services.monitor.setViewer("window", visible: true) }
        .onDisappear { services.monitor.setViewer("window", visible: false) }
    }
}
