# External validation corpus

ResizeLint 1.0 was validated against 11 public iOS repositories at exact
commits. The corpus spans UIKit, SwiftUI, mixed, scene-based, legacy, game,
media, and modular codebases. Repositories were shallow-cloned into a temporary
directory, analyzed without building, checked for a clean worktree before and
after analysis, and then removed. No third-party source is part of ResizeLint.

## Corpus

| Repository | Commit | Coverage | Swift files | Findings |
| --- | --- | --- | ---: | ---: |
| [appcoda/QRCodeReader](https://github.com/appcoda/QRCodeReader) | `a06e21dae61c5beab4f09100efc492228fb10aa5` | UIKit, legacy | 3 | 1 |
| [apple/sample-backyard-birds](https://github.com/apple/sample-backyard-birds) | `1843d5655bf884b501e2889ad9862ec58978fdbe` | SwiftUI, scenes | 114 | 0 |
| [apple/sample-food-truck](https://github.com/apple/sample-food-truck) | `3954a769e99f3cc53297d94f2b960ceb2665b3d6` | SwiftUI, scenes | 82 | 0 |
| [cardoso/ReduxMovieDB](https://github.com/cardoso/ReduxMovieDB) | `744248cc8bf95c9940cfc9c8597877f722279c27` | UIKit, media | 81 | 1 |
| [insidegui/NoteTaker](https://github.com/insidegui/NoteTaker) | `db7e5f1fe60c18b4f27209d7a0889b1f199a383b` | UIKit, legacy | 17 | 3 |
| [kudoleh/iOS-Modular-Architecture](https://github.com/kudoleh/iOS-Modular-Architecture) | `02b207642a714495fe5b647b8b6562b184f5a897` | UIKit, modular | 128 | 4 |
| [merlos/iOS-Open-GPX-Tracker](https://github.com/merlos/iOS-Open-GPX-Tracker) | `cd0954ffcd5ae688b76f8b796607c98ea5c6a0eb` | UIKit, legacy | 51 | 3 |
| [mhdhejazi/CoronaTracker](https://github.com/mhdhejazi/CoronaTracker) | `9add7608522b498dc5bfa617867ceab9722bf946` | Mixed, scenes | 69 | 2 |
| [mouredev/Pokemon-SwiftUI](https://github.com/mouredev/Pokemon-SwiftUI) | `87a28481659f207be42828756c884f4b1b9942a0` | SwiftUI | 5 | 0 |
| [pencilresearch/OpenScanner](https://github.com/pencilresearch/OpenScanner) | `6336c2cba1cac759f3f14bc306b4569ac6bfe494` | SwiftUI, mixed | 37 | 10 |
| [pointfreeco/isowords](https://github.com/pointfreeco/isowords) | `c727d3a7c49cf0c98f2fa4f24c562f81e30165f7` | Game, mixed, modular | 388 | 9 |

The corpus contains 975 Swift files. Every checkout stayed clean. All 22 lint
processes from two complete passes exited with the documented code 0 or 1,
produced no stderr, and emitted byte-identical JSON between passes.

## Finding classification

Every diagnostic was inspected in source context. Rows with multiple locations
list every occurrence and count each occurrence independently.

| Repository | Rule | Locations | Count | Classification | Reason |
| --- | --- | --- | ---: | --- | --- |
| QRCodeReader | RL008 | `QRCodeReader/AppDelegate.swift:14` | 1 | True positive | The app delegate owns the only window without scene lifecycle. |
| ReduxMovieDB | RL008 | `ReduxMovieDB/AppDelegate.swift:14` | 1 | True positive | The app delegate owns the only window without scene lifecycle. |
| NoteTaker | RL008 | `MobileNoteTaker/AppDelegate.swift:18` | 1 | True positive | The app delegate owns and constructs the window without scene lifecycle. |
| NoteTaker | RL001 | `MobileNoteTaker/AppDelegate.swift:36:60`, `:36:96` | 2 | True positive | Both window dimensions come from global screen bounds. |
| iOS-Modular-Architecture | RL002 | `CGSize+ScaledSize.swift:13:30`, `:13:68` | 2 | True positive | Pixel conversion uses the main screen scale instead of local display traits. |
| iOS-Modular-Architecture | RL004 | `LoadingView.swift:17` | 1 | True positive | A process-global key window receives the loading overlay. |
| iOS-Modular-Architecture | RL001 | `LoadingView.swift:18` | 1 | True positive | The overlay frame uses global screen bounds instead of its window. |
| iOS-Open-GPX-Tracker | RL008 | `OpenGpxTracker/AppDelegate.swift:17` | 1 | True positive | The app delegate owns the window without scene lifecycle. |
| iOS-Open-GPX-Tracker | RL004 | `MapViewDelegate.swift:110`, `Toast.swift:139` | 2 | True positive | Presentation and toast placement select a process-global key window. |
| CoronaTracker | RL006 | `MapController.swift:321` | 1 | True positive | Panel layout is selected from pad idiom rather than available size. |
| CoronaTracker | RL006 | `ShareManager.swift:27` | 1 | True positive | Modal presentation behavior is selected from device idiom. |
| OpenScanner | RL004 | `CaptureSummary.swift:128`, `:134`; `LiveCaptureSummary.swift:82`, `:88`; `LiveScanSummary.swift:256`, `:412`, `:419`, `:426`; `PageScan.swift:39`; `PageScanSummary.swift:127` | 10 | True positive | Each presentation selects the first process-global window rather than the initiating scene. |
| isowords | RL004 | `ComposableGameCenter/CrossPlatformSupport.swift:8`; `ComposableStoreKit/LiveKey.swift:41`; `UIApplicationClient/LiveKey.swift:15` | 3 | True positive | Each dependency selects the first connected window scene from global application state. |
| isowords | RL001 | `CubeSceneView.swift:253`, `:254`, `:258`, `:259` | 4 | True positive | Scene-view positioning uses physical screen bounds instead of the view bounds. |
| isowords | RL001 | `GameOverView.swift:805`; `Styleguide/AdaptiveSize.swift:33` | 2 | True positive | SwiftUI width and adaptive-size defaults derive from global screen width. |

## Precision

| Severity | True positive | False positive | Ambiguous | Precision | Release threshold |
| --- | ---: | ---: | ---: | ---: | ---: |
| Error | 29 | 0 | 0 | 100% | 95% |
| Warning | 4 | 0 | 0 | 100% | 85% |
| Total | 33 | 0 | 0 | 100% | — |

No repeated false-positive category was found, so no corpus-driven exclusion
was added. The validation did expose a nondeterministic runtime field in JSON;
a regression test now requires byte-for-byte equality across different run
durations, and machine-readable JSON no longer contains runtime timing.
