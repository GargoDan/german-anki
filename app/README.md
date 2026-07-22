# GermanAnki iOS app

SwiftUI iPhone app (iOS 17+) that studies the deck built by `pipeline/`.
Three swipeable pages: progress & session picker · card learning (opens here) ·
settings & stats. SM-2 scheduling (Anki defaults), all state on-device.

## Build

```sh
# 1. Build the app artifacts (from repo root)
python3 pipeline/10_convert_audio.py          # media/*.mp3 -> data/app/audio/*.m4a
python3 pipeline/09_build_app_db.py --verify-audio   # -> data/app/content.sqlite

# 2. Generate the Xcode project (brew install xcodegen once)
cd app && xcodegen generate

# 3. Build / test / run
xcodebuild -project GermanAnki.xcodeproj -scheme GermanAnki \
  -destination 'platform=iOS Simulator,name=iPhone 16' build   # or: test
open GermanAnki.xcodeproj                                      # run on your phone from Xcode
```

`GermanAnki.xcodeproj` is generated (don't edit it; edit `project.yml`).
The ~280 MB `data/app/audio/` folder ships in the bundle as a folder reference.

## Layout

- `GermanAnki/Models` — `Word`, `Sentence`, `Topic`, `CardState` (SRS state), enums.
- `GermanAnki/Data` — read-only bundled `content.sqlite` + mutable
  `progress.sqlite` in Application Support (survives app reinstalls of content),
  both via GRDB. `AppSettings` = UserDefaults keys.
- `GermanAnki/SRS` — `Scheduler` (pure SM-2, params in `SchedulerConfig`),
  `SessionQueue` (goal/custom queue building), `ProgressMetrics` (learned = review
  interval ≥ 21 d).
- `GermanAnki/Views` — Study (front/reveal/grade bar), Progress (level bars,
  custom session sheet), Settings (defaults + stats).
- `GermanAnkiTests` — scheduler/queue/metrics unit tests.
  `GermanAnkiUITests` — end-to-end study flow + screenshot capture.

Debug launch args (screenshot automation): `-page progress|settings`, `-reveal`.
