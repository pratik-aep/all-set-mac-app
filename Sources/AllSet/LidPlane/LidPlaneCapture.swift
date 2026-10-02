// Copyright (c) 2026 Jhey
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ScreenCaptureKit

final class LidPlaneCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var cancelled = false
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var frames = 0

    /// `excludingWindowID` is the overlay: only that window is left out, because
    /// the wallpaper and widgets this app draws are part of the desktop being shown.
    @MainActor
    func start(displayID: CGDirectDisplayID, excludingWindowID: CGWindowID) async throws {
        // The overlay is ordered out at rest, so ask for offscreen windows too.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        // A clamshell/display transition can cancel us while discovery is awaiting.
        guard !cancelled else { throw CancellationError() }
        // Without the overlay found, capturing would feed the effect to itself.
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              let overlay = content.windows.first(where: { $0.windowID == excludingWindowID }) else {
            throw NSError(domain: "LidPlane", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find this display or exclude the overlay from capture."])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [overlay])
        let config = SCStreamConfiguration()
        // Keep a Retina source at native resolution where practical, capped at 2560px.
        let width = CGDisplayPixelsWide(displayID)
        let height = CGDisplayPixelsHigh(displayID)
        let scale = min(1, 2560.0 / Double(max(width, height)))
        config.width = max(2, Int(Double(width) * scale))
        config.height = max(2, Int(Double(height) * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.colorSpaceName = CGColorSpace.sRGB
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        self.stream = stream
        try await stream.startCapture()
        if cancelled {
            // stop() may have run while startCapture() was still in flight.
            try? await stream.stopCapture()
            throw CancellationError()
        }
        NSLog("Desktop capture started, %d x %d; overlay excluded", config.width, config.height)
    }

    @MainActor
    func stop() async {
        cancelled = true
        let current = stream
        stream = nil
        try? await current?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard self.stream === stream, type == .screen, sampleBuffer.isValid,
              let metadata = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = metadata.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        frames += 1
        if frames == 1 { NSLog("Desktop capture received first complete frame") }
        onFrame?(pixelBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // SCStream calls this on its own queue; the controller wants main.
        nonisolated(unsafe) let stopped = stream
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stopped else { return }
            self.onError?(error)
        }
    }
}
