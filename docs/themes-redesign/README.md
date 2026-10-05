# Themes redesign package

Everything an AI agent needs to rebuild the Themes page to match the reference.

**To start:** open this repo in your IDE (on your own working branch, e.g. `perf-audit`), make sure these files are present locally (`git fetch origin claude/inspiring-fermat-5bibd1` then `git checkout origin/claude/inspiring-fermat-5bibd1 -- docs/themes-redesign`), and paste this to your IDE AI:

> Read `docs/themes-redesign/PROMPT.md` completely and execute it now, exactly as written. Run Phases 0–6 back to back without asking me anything. Open the reference images and compare your screenshots against them; if they don't match, loop Phase 6 until they do. Stop and ask me only before Phase 7.

| Path | Contents |
|---|---|
| `PROMPT.md` | The phased master prompt |
| `UI-SPEC.md` | Full UI specification (numbers for everything) |
| `CONTENT.md` | App content inventory |
| `APP-README.md` | App README (architecture, commands) |
| `reference/reference-B-themes-page-rows.png` | Primary target |
| `reference/reference-A-cinematic-carousel.png` | Secondary style reference |
| `reference/current-ui-screen-recording.mov` | Current UI, 14 s |
| `reference/current-ui-frame-t*.png` | Frames from the recording |
