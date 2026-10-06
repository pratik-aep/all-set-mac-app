import CoreGraphics
import Foundation
import Testing
@testable import AllSetCore

/// Review R2: an AI answer belongs to the picture it was asked about. One that
/// arrives after New Screenshot or Open must not change the new document.
@Suite @MainActor struct ScreenshotStudioTests {
    private func picture(width: Int, height: Int = 64) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Answers Claude after `delay`, with one crop to half the width (so the
    /// result shows which picture it was drawn on).
    private func slowClaude(delay: Duration, fails: Bool = false) -> ScreenshotAI {
        ScreenshotAI(
            key: { _ in "test-key" },
            claude: { _, session, _ in
                try await Task.sleep(for: delay)
                if fails { throw AIEditError("the server said no") }
                let plan = EditPlan(reply: "Cropped.", edits: [ScreenshotEdit(kind: .crop, x: 0, y: 0, width: 32, height: 64)])
                return (session, ClaudeReply(plan: plan, answer: "", usage: TokenUsage()))
            },
            openAI: { image, _, _ in image }
        )
    }

    private func settle(_ task: Task<Void, Never>) async { await task.value }

    @Test func anAnswerForThePreviousPictureLeavesTheNewOneAlone() async {
        let studio = ScreenshotStudio(ai: slowClaude(delay: .milliseconds(150)))
        studio.provider = .claude
        studio.load(picture(width: 64))
        let request = Task { await studio.ask("crop it") }
        try? await Task.sleep(for: .milliseconds(30))
        studio.load(picture(width: 128))          // New Screenshot while it's thinking
        await settle(request)

        #expect(studio.image?.width == 128)
        #expect(studio.versionCount == 1)
        #expect(studio.messages.isEmpty)
        #expect(!studio.isWorking)
    }

    @Test func aFailureForThePreviousPictureIsNotShownOnTheNewOne() async {
        let studio = ScreenshotStudio(ai: slowClaude(delay: .milliseconds(150), fails: true))
        studio.provider = .claude
        studio.load(picture(width: 64))
        let request = Task { await studio.ask("crop it") }
        try? await Task.sleep(for: .milliseconds(30))
        studio.load(picture(width: 128))
        await settle(request)
        #expect(studio.messages.isEmpty)
    }

    @Test func anAnswerForTheOpenPictureIsApplied() async {
        let studio = ScreenshotStudio(ai: slowClaude(delay: .milliseconds(10)))
        studio.provider = .claude
        studio.load(picture(width: 64))
        await studio.ask("crop it")
        #expect(studio.image?.width == 32)
        #expect(studio.versionCount == 2)
        #expect(studio.messages.map(\.role) == [.user, .assistant])
    }

    /// Review P2: undo history is bounded by bytes, not only by count; the original stays.
    @Test func undoHistoryStaysWithinItsByteBudget() async {
        let ai = ScreenshotAI(key: { _ in "k" }, claude: { _, s, _ in throw AIEditError("unused") },
                              openAI: { image, _, _ in
                                  let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                                  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                                  return context.makeImage()!
                              })
        let original = picture(width: 256, height: 256)   // 256 KB of pixels
        let studio = ScreenshotStudio(ai: ai, historyBudget: 4 * 256 * 256 * 4)
        studio.provider = .openAI
        studio.load(original)
        for _ in 0..<10 { await studio.ask("redraw it") }
        #expect(studio.historyBytes <= 4 * 256 * 256 * 4)
        #expect(studio.versionCount >= 2)
        // The original is never the one dropped: undoing all the way gets back to it.
        while studio.versionCount > 1 { studio.undo() }
        #expect(studio.image === original)
    }
}
