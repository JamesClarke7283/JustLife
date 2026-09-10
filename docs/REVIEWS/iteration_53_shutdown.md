# Iteration 53 — normal game shutdown

Main-menu Quit and the window's close request now share a guarded shutdown helper. It queues the game scene for deletion and lets a SceneTree-owned 0.2-second timer end the process. The existing audio stop/detach cleanup is unchanged. Repeated close requests use the same pending shutdown.

The exported `093e0f4d` startup previously left an AudioStreamWAV and AudioStreamPlaybackWAV reference when the engine was forcibly ended after twenty frames. A second verbose run reproduced it. Those logs remain failed qualifications. Engine-forced `--quit-after` bypasses the normal window-close path; this change does not claim to fix that forced path or prove an application reference cycle.

The isolated source probe runs twenty actual startup frames with menu ambience playing through the Dummy audio driver, then exercises the real Quit button callback or a window-close notification. Each process passes eight assertions with no verbose shutdown diagnostics. App/audio weak references are released before the game's quit timer fires, observed after 51 milliseconds for menu Quit and 44 milliseconds for window close. Repeated close notifications are also checked. The window case uses the actual notification handler, not an operating-system mouse click.

The first import attempt used verbose asset-import logging and hit its 120-second cap before either shutdown case ran. Its 8,491 diagnostic lines and timeout are retained. The corrected run removes verbosity only from import, matching the established import convention; both shutdown cases retain verbose output and identical runtime/test expectations. Import then completes in 26.47 seconds. This does not establish why the original import timed out or resolve its asset-import diagnostics.

Evidence remains in `dist/test-work/normal-audio-shutdown-b3pnhmpq`. Corrected terminal receipt: `runs/normal-close-m1jlf0dv/RECEIPT.json`, SHA-256 `b23ff017bddabdfc9f72d41ebc8349d09caec09775b12729cd66b8617c4ebfab`. All 239 private source inputs remain exact; only main/menu behavior and private plugin removal differ from `093e0f4d`.

The opt-in packaged release probe separately excludes GUI input, all four Node input channels and direct camera polling, with a focused offscreen control. Nine capture checks verify those exclusions. Its existing 58 control/asset/save/travel assertions remain intact. It still uses an isolated data directory and directed public callbacks; it is not an unscripted full-game review or a forced-shutdown test.
