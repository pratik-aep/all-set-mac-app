import AllSetCore
import SwiftUI

/// Draws the notch shape and whatever it currently holds. Size changes animate
/// through the `NotchAnimation` the controller wraps each change in.
struct NotchRootView: View {
    let model: NotchViewModel
    let services: AppServices
    let expand: @MainActor () -> Void
    let openSettings: @MainActor () -> Void

    var body: some View {
        let size = model.shapeSize
        let shape = NotchShape(topCornerRadius: model.topCornerRadius, bottomCornerRadius: model.bottomCornerRadius)

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .shadow(color: .black.opacity(model.isExpanded ? 0.5 : 0), radius: 16, y: 8)
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if model.isExpanded {
            ExpandedPanel(model: model, services: services, openSettings: openSettings)
                .transition(.reveal())
        } else if let activity = model.activity {
            CollapsedActivityView(activity: activity, media: services.media,
                                  notchSize: model.geometry.notchRect.size, earInset: model.topCornerRadius)
                .id(activity.kind)
                .contentShape(Rectangle())
                .onTapGesture(perform: expand)
                .transition(.reveal(in: .smooth(duration: 0.25).delay(0.05), out: .easeIn(duration: 0.12)))
        } else {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: expand)
        }
    }
}
