import AllSetCore
import AppKit
import AVFoundation
import SwiftUI

/// Pick and preview the live wallpaper.
struct LiveWallpaperPage: View {
    let services: AppServices

    enum Tab: String, CaseIterable, Identifiable {
        case aerials, art, videos

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aerials: "Aerial Videos"
            case .art: "Art"
            case .videos: "My Videos"
            }
        }
    }

    @State private var tab: Tab

    init(services: AppServices, tab: Tab = .aerials) {
        self.services = services
        _tab = State(initialValue: tab)
    }

    var body: some View {
        let setWallpaper = LibraryContext(action: .init(title: "Set as Wallpaper", symbol: "photo.artframe") { source in
            if case .art(let piece) = source {
                services.pickWallpaper(.art(piece))
            } else {
                services.pickWallpaper(.photo(source))
            }
        })

        VStack(spacing: 0) {
            WallpaperHero(services: services)
                .padding([.horizontal, .top], 24)
                .padding(.bottom, 16)
            if services.ui.desktopUndo != nil {
                DesktopUndoBanner(services: services)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            Picker("Source", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
            Divider().padding(.top, 8)

            Group {
                switch tab {
                case .aerials: AerialsPage(services: services)
                case .art: ArtLibraryPage(services: services, context: setWallpaper)
                case .videos: VideosPage(services: services)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The current wallpaper, playing, with the main switch.
private struct WallpaperHero: View {
    let services: AppServices
    /// Plays for a moment when the page opens, then whenever the pointer is on it.
    @State private var isIntroPlaying = true
    @State private var isHovering = false

    var body: some View {
        let store = services.wallpaper
        let config = store.config
        HStack(alignment: .center, spacing: 22) {
            // A small preview needn't run at the desktop's frame rate, nor all
            // the time: animating it costs as much as the wallpaper itself.
            WallpaperView(config: { var preview = config; preview.frameRate = min(config.frameRate, 24); return preview }(),
                          services: services)
                .environment(\.widgetIsVisible, isIntroPlaying || isHovering)
                .frame(width: 300, height: 188)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .overlay(alignment: .top) {
                    // A hint of the menu bar and notch, so it reads as a screen.
                    Capsule().fill(.black).frame(width: 44, height: 7).padding(.top, 3)
                }
                .onHover { isHovering = $0 }
                .task {
                    try? await Task.sleep(for: .seconds(6))
                    isIntroPlaying = false
                }
                .help("Point at the preview to see it move")

            VStack(alignment: .leading, spacing: 10) {
                Text("Live Wallpaper").font(.largeTitle.bold())
                Text(description(of: config.source))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Toggle(isOn: Binding(get: { store.config.isEnabled }, set: { store.config.isEnabled = $0 })) {
                    Text(config.isEnabled ? "On: playing on your desktop" : "Off")
                        .font(.headline)
                }
                .toggleStyle(.switch)
                .controlSize(.large)
                HStack(spacing: 10) {
                    Button("Options…") { services.openWindow(.wallpaperOptions) }
                    if config.isEnabled, !services.ui.wallpaperPlaying {
                        Label("Paused to save energy", systemImage: "pause.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func description(of source: WallpaperSource) -> String {
        switch source {
        case .art(let piece): "\(piece.title), animated"
        case .photo(.web(let photo)): "Photo by \(photo.author)"
        case .photo(.file): "Your photo, with gentle motion"
        case .photo(.art(let piece)): piece.title
        case .video(let name):
            if let aerial = services.aerials.aerials.first(where: { name.hasPrefix("aerial-\($0.id)") }) {
                "\(aerial.name), an Apple aerial"
            } else {
                "Your video, looping silently"
            }
        case .library(let id):
            if let video = services.wallpaper.libraryVideo(id) {
                "\(video.title), from your library"
            } else {
                "A video from your library"
            }
        }
    }
}

/// Imported videos, for video wallpapers.
private struct VideosPage: View {
    let services: AppServices
    @State private var isDropTarget = false
    @State private var detailVideo: LibraryVideo?
    /// Owned tiles only offload on delete; everywhere else, permanent +
    /// admin-gated. Lifted here (not just in LibrarySection) so the detail
    /// sheet, which overlays the whole page, agrees with the grid.
    @State private var ownedOnly = false

    var body: some View {
        let store = services.wallpaper
        ZStack(alignment: .bottom) {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Videos").font(.largeTitle.bold())
                        Text("Any MP4 or MOV loops silently behind your desktop. Drop files here or import them.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        importVideos()
                    } label: {
                        Label("Import Videos…", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.large)
                }
                let videos = store.videos.filter { !$0.hasPrefix("aerial-") }
                if videos.isEmpty, !store.library.isEmpty {
                    // The header already says how to add some; the library follows.
                    EmptyView()
                } else if videos.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Drop videos here").font(.headline)
                        Text("Screen-sized loops look best. Videos are copied into All Set.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundStyle(.quaternary))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(videos, id: \.self) { name in
                            VideoTile(url: store.videoURL(name), isCurrent: store.config.source == .video(name)) {
                                services.pickWallpaper(.video(name))
                            } onDelete: {
                                store.deleteVideo(name)
                            }
                        }
                    }
                }
                LibrarySection(services: services, detailVideo: $detailVideo, ownedOnly: $ownedOnly)
            }
            .padding(28)
        }
        // Picks up a fresh import without restarting.
        .onAppear { store.reloadLibrary() }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, lineWidth: 3).padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            !store.importVideos(from: urls).isEmpty
        } isTargeted: { isDropTarget = $0 }
        if let video = detailVideo {
            // Dims the grid behind the preview; a click anywhere on it goes back.
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { withMotion(Motion.standard) { detailVideo = nil } }
                .transition(.opacity)
                .accessibilityHidden(true)
            LibraryDetailSheet(video: video, store: store, images: services.images, deleteKind: deleteKind(for: video)) {
                services.pickWallpaper(.library(video.id))
                detailVideo = nil
            } onClose: {
                withMotion(Motion.standard) { detailVideo = nil }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        }
    }

    /// Owned tiles only offload; everywhere else, permanent + admin-gated.
    private func deleteKind(for video: LibraryVideo) -> LibraryTile.DeleteKind {
        ownedOnly ? .offloadOnly { await services.wallpaper.offloadAll(only: [video.id]) }
                  : .permanent { await services.wallpaper.deleteEverywhere(video.id) }
    }

    private func importVideos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie]
        panel.prompt = "Import"
        if panel.runModal() == .OK {
            services.wallpaper.importVideos(from: panel.urls)
        }
    }
}

private struct VideoTile: View {
    let url: URL
    let isCurrent: Bool
    let onUse: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if isHovering {
                LoopingVideo(url: url, isPlaying: true)
            } else if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .aspectRatio(16 / 10, contentMode: .fill)
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isCurrent ? 3 : 0)
        }
        .overlay(alignment: .bottom) {
            if isHovering {
                HStack {
                    Button(action: onUse) {
                        Label(isCurrent ? "Current" : "Set as Wallpaper", systemImage: "photo.artframe")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCurrent)
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                }
                .controlSize(.small)
                .padding(8)
            }
        }
        .onHover { isHovering = $0 }
        .task(id: url) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            if let (image, _) = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)) {
                thumbnail = NSImage(cgImage: image, size: .zero)
            }
        }
    }
}

/// Videos from a wallpaper library outside All Set (a folder or a drive,
/// imported with `scripts/wallpaper_library.py`). They play from where they
/// live, through the same player and the same pausing rules as any video;
/// cards show a picture made at import, never the video itself until you
/// rest the pointer on one.
private struct LibrarySection: View {
    let services: AppServices
    /// Both owned by `VideosPage`: its bottom detail sheet overlays the
    /// whole page (this section alone scrolls with the grid), and needs to
    /// agree with the grid on which delete behaviour applies.
    @Binding var detailVideo: LibraryVideo?
    @Binding var ownedOnly: Bool

    @State private var query = ""
    @State private var category: Aerial.Category?
    @State private var sort = LibrarySort.title
    @State private var show = Show.all

    /// Moving videos, or stills taken from Wallpaper Engine scenes.
    enum Show: String, CaseIterable, Identifiable {
        case all, live, stills
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .live: "Live"
            case .stills: "Stills"
            }
        }
    }

    var body: some View {
        let store = services.wallpaper
        let all = store.library
        if !all.isEmpty {
            let kinds = Aerial.Category.allCases.filter { kind in all.contains { $0.category == kind } }
            let shown = sort.sorted(all.filter { video in
                (category == nil || video.category == category) && video.matches(query)
                    && (show == .all || (show == .live) == (video.kind == .video))
                    && (!ownedOnly || store.canPlay(video))
            })
            let stills = all.filter { $0.kind == .image }.count
            // Not on this Mac, but the personal server has a copy to fetch.
            let hasServer = store.config.libraryServerURL != nil
            let onServer = all.filter { !store.canPlay($0) && hasServer && ($0.playback != nil || $0.still != nil) }
            // Only the wallpapers with no copy anywhere else need the folder
            // they came from. Once everything has a copy here or on the
            // server, an unplugged drive changes nothing.
            let waiting = all.filter { !store.canPlay($0) && !(hasServer && ($0.playback != nil || $0.still != nil)) }
            let offline = store.libraryRoots.values
                .filter { root in waiting.contains { $0.root == root.id } }
            VStack(alignment: .leading, spacing: 14) {
                Divider().padding(.vertical, 6)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library").font(.title.bold())
                        Text("\(all.count - stills) live, \(stills) stills, "
                             + (!waiting.isEmpty
                                ? "from \(store.libraryRoots.values.compactMap(\.label).sorted().joined(separator: ", "))"
                                : onServer.isEmpty
                                ? "kept on this Mac"
                                : "\(all.count - onServer.count) on this Mac, \(onServer.count) on your server"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Show", selection: $show) {
                        ForEach(Show.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    Picker("Sort", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 210)
                }
                Label("For your own desktop: these came from Steam Workshop with no author or license. Scene wallpapers are rebuilt here, as a loop made from their own layers or as their artwork held still. Never shared.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !offline.isEmpty {
                    Label("\(offline.compactMap(\.label).joined(separator: ", ")) isn't connected. Connect it to preview or play these.",
                          systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if hasServer, store.serverReachable == false, !onServer.isEmpty {
                    Label("Personal server isn't reachable right now. \(onServer.count) wallpaper\(onServer.count == 1 ? "" : "s") that rely on it won't play until it is.",
                          systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                }
                if hasServer {
                    FreeUpSpaceRow(store: store)
                }
                HStack(spacing: 8) {
                    TextField("Search your library", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    chip(nil, title: "All", symbol: "sparkles")
                    ForEach(kinds) { chip($0, title: $0.title, symbol: $0.symbol) }
                    if hasServer {
                        Divider().frame(height: 16)
                        ownedChip
                    }
                }
                if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(shown) { video in
                            LibraryTile(video: video, store: store, images: services.images,
                                        isCurrent: store.config.source == .library(video.id), deleteKind: deleteKind(for: video)) {
                                services.pickWallpaper(.library(video.id))
                            } onShowDetails: {
                                detailVideo = video
                            }
                        }
                    }
                }
            }
            .task { store.checkServerReachable() }
        }
    }

    /// Owned tiles only offload; everywhere else, permanent + admin-gated.
    private func deleteKind(for video: LibraryVideo) -> LibraryTile.DeleteKind {
        ownedOnly ? .offloadOnly { await services.wallpaper.offloadAll(only: [video.id]) }
                  : .permanent { await services.wallpaper.deleteEverywhere(video.id) }
    }

    private var ownedChip: some View {
        Button {
            withMotion(Motion.quick) { ownedOnly.toggle() }
        } label: {
            Label("Owned", systemImage: ownedOnly ? "checkmark.circle.fill" : "internaldrive")
                .font(.callout.weight(.medium))
                .foregroundStyle(ownedOnly ? Color.white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(ownedOnly ? Color.accentColor : Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help("Only wallpapers stored on this Mac right now — delete here removes just this Mac's copy, not the wallpaper.")
    }

    private func chip(_ value: Aerial.Category?, title: String, symbol: String) -> some View {
        let selected = category == value
        return Button {
            withMotion(Motion.quick) { category = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(selected ? Color.white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Deletes this Mac's copy of every wallpaper the personal server is
/// confirmed to hold; each comes back the next time it's played.
private struct FreeUpSpaceRow: View {
    let store: WallpaperStore

    @State private var estimate: (files: Int, bytes: Int64) = (0, 0)
    @State private var confirming = false
    @State private var result: WallpaperStore.OffloadResult?

    var body: some View {
        HStack(spacing: 10) {
            if let progress = store.offloadProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: 160)
                Text("Checking your server: \(progress.done) of \(progress.total)")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task {
                        estimate = await store.offloadableSpace()
                        confirming = true
                    }
                } label: {
                    Label("Free Up Space…", systemImage: "internaldrive")
                }
                .disabled(store.serverReachable == false)
                Text(result.map(Self.summary)
                     ?? "Wallpapers stay in your library and download again from your server when you use them.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .confirmationDialog(estimate.files == 0 ? "Nothing to free up" : "Free up \(Self.size(estimate.bytes))?",
                            isPresented: $confirming, titleVisibility: .visible) {
            if estimate.files > 0 {
                Button("Free Up \(Self.size(estimate.bytes))", role: .destructive) {
                    Task { result = await store.offloadAll() }
                }
            }
            Button(estimate.files == 0 ? "OK" : "Cancel", role: .cancel) {}
        } message: {
            Text(estimate.files == 0
                 ? "Every wallpaper already plays from your server."
                 : "Each of the \(estimate.files) files is checked on your server first; anything it can't confirm stays on this Mac. Thumbnails stay, so browsing is still instant.")
        }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func summary(_ result: WallpaperStore.OffloadResult) -> String {
        let kept = result.kept.isEmpty ? "" : " \(result.kept.count) kept here: your server couldn't confirm them."
        return "Freed \(size(result.freedBytes)) (\(result.freedFiles) files).\(kept)"
    }
}

private struct LibraryTile: View {
    /// What the trash button does here, decided by the caller (the Owned
    /// filter vs. the main grid), not by the tile itself.
    enum DeleteKind {
        /// This Mac's copy only — the wallpaper stays in the library and on
        /// the server, and comes back the next time it's played.
        case offloadOnly(@Sendable () async -> WallpaperStore.OffloadResult)
        /// Gone everywhere: this Mac, the server's file, the database row.
        /// Gated by Touch ID/the Mac password before it runs at all.
        case permanent(@Sendable () async -> WallpaperStore.DeleteEverywhereOutcome?)
    }

    let video: LibraryVideo
    let store: WallpaperStore
    let images: ImageLibrary
    let isCurrent: Bool
    let deleteKind: DeleteKind
    let onUse: () -> Void
    let onShowDetails: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    /// The video starts after a moment's rest, not as the pointer passes over.
    @State private var isPreviewing = false
    @State private var confirmingDelete = false
    @State private var downloadProgress: Double?
    @State private var deleteProblem: String?

    private static let thumbnailPixels = 512

    var body: some View {
        let playable = store.canPlay(video)
        // Not local and no drive for it, but the personal server might still
        // have it: worth trying rather than calling it unplayable outright.
        let onServer = !playable && store.config.libraryServerURL != nil
            && (video.playback != nil || video.still != nil) && store.serverReachable != false
        // Set from the store's own count-of-callers state, not a fetch this
        // tile starts itself: whichever wallpaper is actually downloading (set
        // as active, or another tile's own hover-preview) shows its progress
        // here too, since it's the same shared download either way.
        let isFetching = store.isFetching(video.id)
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    }
                    // Resolved only when previewing: finding the file costs a
                    // disk check, too much to do for every card as it scrolls by.
                    // Stills have nothing more to show than their card.
                    if isPreviewing, video.kind == .video {
                        if let url = store.libraryURL(video.id) {
                            LoopingVideo(url: url, isPlaying: true).transition(.opacity)
                        } else {
                            // Not on this Mac: a hover never downloads on its
                            // own (every scroll-by would trigger one) — tap
                            // opens the detail sheet, which does fetch.
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle").font(.title2)
                                Text("Tap to preview").font(.caption2)
                            }
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                            .transition(.opacity)
                        }
                    }
                }
                .scaleEffect(isHovering ? 1.03 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isCurrent ? 3 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if isHovering || confirmingDelete {
                    Button {
                        confirmingDelete = true
                    } label: {
                        Image(systemName: isOffloadDelete ? "internaldrive" : "trash.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.55), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.opacity)
                    .help(isOffloadDelete ? "Remove from this Mac only — stays on your server"
                          : "Delete this wallpaper permanently, everywhere (admin)")
                }
            }
            // On the tile, not the hover-only button: moving the pointer to the
            // dialog ends the hover, and a dialog on a view that disappears
            // closes with it.
            .confirmationDialog(isOffloadDelete ? "Remove “\(video.title)” from this Mac?" : "Delete “\(video.title)” for good?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button(isOffloadDelete ? "Remove From This Mac" : "Delete Permanently", role: .destructive) { runDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isOffloadDelete
                     ? "Stays in your library and on your server. Downloads again the next time you play it."
                     : "Removes it everywhere: this Mac, your server's copy, and the database. Asks to confirm it's you first, and can't be undone.")
            }
            .alert("Couldn't finish deleting “\(video.title)”", isPresented: .init(get: { deleteProblem != nil }, set: { if !$0 { deleteProblem = nil } })) {
                Button("OK") {}
            } message: {
                Text((deleteProblem ?? "") + " It's already gone from this Mac; try again once that's fixed to finish removing it from the server.")
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: video.category.symbol)
                        Text(video.title).lineLimit(1)
                        if video.kind == .image {
                            Image(systemName: "photo")
                                .foregroundStyle(.white.opacity(0.75))
                                .help("A still from the scene: its animation isn't included")
                        }
                        Spacer(minLength: 4)
                        Text(video.resolutionLabel).foregroundStyle(.white.opacity(0.75))
                        if let size = video.size {
                            Text("·").foregroundStyle(.white.opacity(0.5))
                            Text(Self.size(size)).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .font(.caption.weight(.semibold))
                    if isFetching {
                        ProgressView(value: downloadProgress ?? 0)
                            .tint(.white)
                        Text(downloadProgress.map { "Downloading… \(Int($0 * 100))%" } ?? "Downloading…")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                    } else if isHovering {
                        Button(action: onUse) {
                            Label(isCurrent ? "Current" : playable ? "Set as Wallpaper"
                                  : onServer ? "Fetch from Server" : "Drive Not Connected",
                                  systemImage: "photo.artframe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isCurrent || !(playable || onServer))
                    }
                }
                .foregroundStyle(.white)
                .padding(8)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: onShowDetails)
            .onHover { hovering in
                withMotion(Motion.quick) { isHovering = hovering }
                if !hovering { isPreviewing = false }
            }
            .task(id: isHovering) {
                guard isHovering else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, isHovering else { return }
                withMotion(Motion.standard) { isPreviewing = true }
            }
            .task(id: video.id) {
                guard let file = store.libraryThumbnailURL(video) else { return }
                if let cached = images.cachedThumbnail(at: file, maxPixels: Self.thumbnailPixels) {
                    thumbnail = cached
                    return
                }
                // Not on this Mac: bring it back from the personal server
                // first. Only tiles actually on screen get here (the grid
                // is lazy), so this never asks for all of them at once.
                if store.config.libraryServerURL != nil, !FileManager.default.fileExists(atPath: file.path) {
                    _ = try? await store.fetchThumbnail(video.id)
                }
                thumbnail = await images.thumbnail(at: file, maxPixels: Self.thumbnailPixels)
            }
            // A local timer, not Observation: `fetches` ticks 4 times a
            // second, and only this one tile — not every tile watching
            // `isFetching` — should redraw that often.
            .task(id: isFetching) {
                guard isFetching else { downloadProgress = nil; return }
                while !Task.isCancelled {
                    downloadProgress = store.fetchProgress(for: video.id)
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            .help(video.statusReason.map { "\(video.title): personal use (\($0))" } ?? video.title)
    }

    private var isOffloadDelete: Bool { if case .offloadOnly = deleteKind { true } else { false } }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func runDelete() {
        switch deleteKind {
        case .offloadOnly(let offload):
            Task { _ = await offload() }
        case .permanent(let delete):
            Task {
                guard await AdminGate.authorize(reason: "delete “\(video.title)” everywhere") else { return }
                switch await delete() {
                case .success, nil: break
                case .localOnly(let reason): deleteProblem = reason
                }
            }
        }
    }
}

/// A bigger look at one wallpaper, sliding up over the grid: a real
/// preview (fetching it if it isn't local — tapping is deliberate, unlike
/// a hover) plus every detail the tile's small footer has no room for.
private struct LibraryDetailSheet: View {
    let video: LibraryVideo
    let store: WallpaperStore
    let images: ImageLibrary
    let deleteKind: LibraryTile.DeleteKind
    let onUse: () -> Void
    let onClose: () -> Void

    @State private var thumbnail: NSImage?
    /// A local still, decoded off the main thread at a size the sheet can
    /// use: the original is 3840 px, and drawing it straight from the file
    /// decoded all of it on the main thread as the sheet slid in.
    @State private var still: NSImage?
    @State private var confirmingDelete = false
    @State private var deleteProblem: String?

    var body: some View {
        let isFetching = store.isFetching(video.id)
        let url = store.libraryURL(video.id)
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let thumbnail { Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill) }
                if let url {
                    if video.kind == .image {
                        if let still { Image(nsImage: still).resizable().aspectRatio(contentMode: .fill) }
                    } else {
                        LoopingVideo(url: url, isPlaying: true)
                    }
                } else if isFetching {
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            .frame(height: 320)
            .clipped()
            .overlay(alignment: .topTrailing) {
                // Always in view, over the preview, and Esc does the same.
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close the preview (Esc)")
                .accessibilityLabel("Close preview")
                .padding(12)
            }
            .task(id: url) {
                guard video.kind == .image, let url else { return }
                still = images.cachedThumbnail(at: url, maxPixels: 1600)
                if still == nil { still = await images.thumbnail(at: url, maxPixels: 1600) }
            }
            .task(id: video.id) {
                guard url == nil, let file = store.libraryThumbnailURL(video) else { return }
                if let cached = images.cachedThumbnail(at: file, maxPixels: 1024) {
                    thumbnail = cached
                } else {
                    thumbnail = await images.thumbnail(at: file, maxPixels: 1024)
                }
            }
            .task(id: video.id) {
                guard url == nil, store.config.libraryServerURL != nil else { return }
                await store.fetchLibraryVideoRetrying(video.id, delays: [.seconds(2)])
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title).font(.title2.bold())
                        Text(video.category.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 8) {
                    detail("Resolution", video.resolutionLabel)
                    if let size = video.size { detail("Size", Self.size(size)) }
                    if let duration = video.duration { detail("Length", String(format: "%.0fs", duration)) }
                    if let fps = video.fps { detail("Frame rate", String(format: "%.0f fps", fps)) }
                    detail("Kind", video.kind == .image ? "Still" : "Live")
                }
                if let reason = video.statusReason {
                    Label(reason, systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(action: onUse) {
                        Label(store.config.source == .library(video.id) ? "Current" : "Set as Wallpaper", systemImage: "photo.artframe")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.config.source == .library(video.id))
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label(isOffloadDelete ? "Remove From This Mac" : "Delete Permanently", systemImage: "trash")
                    }
                    Spacer()
                }
            }
            .padding(20)
        }
        .frame(maxWidth: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.separator))
        .shadow(radius: 24, y: 8)
        .padding(24)
        .confirmationDialog(isOffloadDelete ? "Remove “\(video.title)” from this Mac?" : "Delete “\(video.title)” for good?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(isOffloadDelete ? "Remove From This Mac" : "Delete Permanently", role: .destructive) { runDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isOffloadDelete
                 ? "Stays in your library and on your server. Downloads again the next time you play it."
                 : "Removes it everywhere: this Mac, your server's copy, and the database. Asks to confirm it's you first, and can't be undone.")
        }
        .alert("Couldn't finish deleting “\(video.title)”", isPresented: .init(get: { deleteProblem != nil }, set: { if !$0 { deleteProblem = nil } })) {
            Button("OK") {}
        } message: {
            Text((deleteProblem ?? "") + " It's already gone from this Mac.")
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium))
        }
    }

    private var isOffloadDelete: Bool { if case .offloadOnly = deleteKind { true } else { false } }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func runDelete() {
        switch deleteKind {
        case .offloadOnly(let offload):
            Task { _ = await offload(); onClose() }
        case .permanent(let delete):
            Task {
                guard await AdminGate.authorize(reason: "delete “\(video.title)” everywhere") else { return }
                switch await delete() {
                case .success, nil: onClose()
                case .localOnly(let reason): deleteProblem = reason
                }
            }
        }
    }
}

/// Apple's aerial videos: pick one and it downloads once, then loops offline.
private struct AerialsPage: View {
    let services: AppServices

    @State private var category: Aerial.Category?
    @AppStorage("aerials.quality") private var quality = Aerial.Quality.uhd
    @State private var problem: String?

    var body: some View {
        let catalog = services.aerials
        let store = services.wallpaper
        let downloaded = Set(store.videos.filter { $0.hasPrefix("aerial-") })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aerial Videos").font(.largeTitle.bold())
                        Text("Apple's own drone and space footage, from the Apple TV screen savers. Rest the pointer on one to preview it; choosing it downloads it once, then it loops offline.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Quality", selection: $quality) {
                        ForEach(Aerial.Quality.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 230)
                }

                HStack(spacing: 8) {
                    categoryChip(nil, title: "All", symbol: "sparkles")
                    // Only the kinds Apple's list has (the library adds others).
                    ForEach(Aerial.Category.allCases.filter { kind in catalog.aerials.contains { $0.category == kind } }) {
                        categoryChip($0, title: $0.title, symbol: $0.symbol)
                    }
                    Spacer()
                    if !downloaded.isEmpty {
                        Menu("\(downloaded.count) downloaded") {
                            Button("Delete Downloads Not in Use", role: .destructive) {
                                for name in downloaded where store.config.source != .video(name) {
                                    store.deleteVideo(name)
                                }
                            }
                        }
                        .fixedSize()
                    }
                }

                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if catalog.aerials.isEmpty {
                    VStack(spacing: 12) {
                        if let error = catalog.errorMessage {
                            Text(error).foregroundStyle(.secondary)
                            Button("Try Again") { Task { await catalog.retry() } }
                        } else {
                            ProgressView()
                            Text("Getting Apple's aerial list…").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        ForEach(catalog.aerials.filter { category == nil || $0.category == category }) { aerial in
                            let file = aerial.fileName(quality)
                            AerialTile(aerial: aerial, catalog: catalog,
                                       isDownloaded: downloaded.contains(file),
                                       isCurrent: store.config.source == .video(file)) {
                                use(aerial)
                            }
                        }
                    }
                    .motion(Motion.standard, value: category)
                }
            }
            .padding(28)
        }
        .task { await catalog.load() }
    }

    private func categoryChip(_ value: Aerial.Category?, title: String, symbol: String) -> some View {
        let selected = category == value
        return Button {
            withMotion(Motion.quick) { category = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(selected ? Color.white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private func use(_ aerial: Aerial) {
        problem = nil
        let store = services.wallpaper
        let quality = quality
        Task {
            do {
                let name = try await services.aerials.download(aerial, quality: quality, into: store.videosFolder)
                store.reloadVideos()
                services.pickWallpaper(.video(name))
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                problem = "\(aerial.name) couldn't be downloaded: \(error.localizedDescription)"
            }
        }
    }
}

private struct AerialTile: View {
    let aerial: Aerial
    let catalog: AerialCatalog
    let isDownloaded: Bool
    let isCurrent: Bool
    let onUse: () -> Void

    @State private var preview: CGImage?
    @State private var isHovering = false
    /// Streaming starts after a moment's rest, not as the pointer passes over.
    @State private var isPreviewing = false

    var body: some View {
        let progress = catalog.downloads[aerial.id]
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let preview {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    }
                    if isPreviewing {
                        LoopingVideo(url: aerial.hdURL, isPlaying: true)
                            .transition(.opacity)
                    }
                }
                .scaleEffect(isHovering ? 1.03 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isCurrent ? 3 : 0)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    Image(systemName: aerial.category.symbol)
                    Text(aerial.name).lineLimit(1)
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.white.opacity(0.8))
                            .help("Downloaded")
                    }
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
            }
            .overlay {
                if let progress {
                    ZStack {
                        Color.black.opacity(0.45)
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                                Circle().trim(from: 0, to: progress)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .motion(Motion.standard, value: progress)
                                Text("\(Int(progress * 100))%")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 46, height: 46)
                            Button("Cancel") { catalog.cancelDownload(aerial) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if isHovering {
                    Button(action: onUse) {
                        Label(isCurrent ? "Current Wallpaper" : isDownloaded ? "Set as Wallpaper" : "Download & Set",
                              systemImage: isCurrent ? "checkmark" : isDownloaded ? "photo.artframe" : "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCurrent)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .shadow(color: .black.opacity(isHovering ? 0.3 : 0.1), radius: isHovering ? 14 : 4, y: isHovering ? 6 : 2)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onHover { hovering in
                withMotion(Motion.responsive) { isHovering = hovering }
                if !hovering { withMotion(Motion.quick) { isPreviewing = false } }
            }
            .task(id: isHovering) {
                guard isHovering else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, isHovering else { return }
                withMotion(Motion.standard) { isPreviewing = true }
            }
            .task(id: aerial.id) {
                let image = await catalog.preview(for: aerial)
                withMotion(Motion.standard) { preview = image }
            }
    }
}

/// Look, motion and energy settings for the live wallpaper.
struct WallpaperOptionsPage: View {
    let services: AppServices

    var body: some View {
        let store = services.wallpaper
        Form {
            Section {
                Toggle("Live wallpaper", isOn: binding(\.isEnabled))
                LabeledContent("Dim") {
                    Slider(value: binding(\.dim), in: 0...0.6)
                        .frame(width: 220)
                }
            } footer: {
                Text("Dimming helps desktop icons and widgets stand out.")
            }

            Section("Art") {
                LabeledContent("Speed") {
                    Slider(value: binding(\.speed), in: 0.25...3)
                        .frame(width: 220)
                }
                Picker("Quality", selection: binding(\.sharpArt)) {
                    Text("Balanced: soft styles look the same, much less work").tag(false)
                    Text("Sharp: full resolution").tag(true)
                }
                Picker("Frame rate", selection: binding(\.frameRate)) {
                    Text("15 fps: calm, least energy").tag(15)
                    Text("30 fps: smooth").tag(30)
                    Text("60 fps: silky").tag(60)
                }
            }

            Section("Photos") {
                Picker("Motion", selection: binding(\.motion)) {
                    ForEach(WallpaperMotion.allCases) { motion in
                        Text(motion.title).tag(motion)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Pause while windows cover the desktop", isOn: binding(\.pauseWhenCovered))
                Toggle("Pause on battery power", isOn: binding(\.pauseOnBattery))
            } header: {
                Text("Energy")
            } footer: {
                Text("The wallpaper also pauses when the screen is locked or asleep, and in Low Power Mode.")
            }

            Section {
                Toggle("Match the system wallpaper", isOn: binding(\.matchSystemWallpaper))
            } footer: {
                Text("Sets a still of your live wallpaper as the macOS wallpaper, so Mission Control, Spaces and the lock screen match. Your previous wallpaper comes back when you turn the live wallpaper off.")
            }

            Section {
                Button("Choose a Wallpaper…") { services.openWindow(.wallpaper) }
            }
        }
        .formStyle(.grouped)
        .motion(Motion.standard, value: store.config)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WallpaperConfig, Value>) -> Binding<Value> {
        Binding(get: { services.wallpaper.config[keyPath: keyPath] },
                set: { services.wallpaper.config[keyPath: keyPath] = $0 })
    }
}
