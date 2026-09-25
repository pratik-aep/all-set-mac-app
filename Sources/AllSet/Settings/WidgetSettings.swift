import AllSetCore
import SwiftUI

struct WidgetSettings: View {
    @Bindable var settings: AppSettings
    let services: AppServices

    var body: some View {
        Section {
            Toggle("Show widgets on the desktop", isOn: $settings.showWidgets)
            LabeledContent("Layout") {
                Button(services.ui.isArrangingWidgets ? "Done Arranging" : "Arrange Widgets") {
                    services.ui.isArrangingWidgets.toggle()
                }
            }
            .disabled(!settings.showWidgets)
        } footer: {
            Text("While arranging, widgets float above your windows so you can drag them anywhere. They snap into line when you let go.")
        }

        Section {
            Picker("Font", selection: $settings.widgetFont) {
                ForEach(WidgetFont.allCases) { font in
                    Text(font.title).tag(font)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent("Corner roundness") {
                Slider(value: $settings.widgetCornerRadius, in: 8...32, step: 1)
                    .frame(width: 200)
            }
        } header: {
            Text("All widgets")
        } footer: {
            Text("Weather by Open-Meteo.com. Photos by Unsplash photographers, via Picsum.")
        }
    }
}
