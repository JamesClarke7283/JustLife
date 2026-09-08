# Packaged release verification

8 September 2026. Current artifact: `dist/JustLife/JustLife.x86_64`, speech/v20 build with embedded project data. The character meshes remain the reviewed v18 production assets; the v19 hair experiment is not included.

## Packaged checks

The new executable passed **32 packaged checks, zero failures and zero engine/script errors**, using actual Forward+ rendering on the available NVIDIA RTX 5090. Private data: `/tmp/justlife-release-check-speech-v20-s92gkn2z/data`. Seven screenshots, runtime log and the exact build manifest are archived locally in `art/screenshots/release_speech_v20/initial_shutdown_warning/`. The first run reported two ObjectDB instances remaining at shutdown. A verbose repeat of the identical executable in `/tmp/justlife-release-check-speech-verbose-eg2_ae4t/data` passed the same checks without that warning; it recorded four hardware RGB8-to-RGBA8 conversion warnings. The intermittent exit warning is retained, not claimed fixed.

The probe checks startup/main menu, all five creator age choices, face controls, imported wordless voice/ambience/click resources, original cake/booster resources, child/adult move-in, directed genealogy, school enrollment, named save/load, Keep save, confirmed exact-save deletion and library travel. It does not measure perceived audio, sustained simulation or general hardware compatibility.

Frozen input: `/tmp/justlife-speech-source-t0sm4kk1`; exporter snapshot: `/tmp/justlife-release-u6ywt6oa`. Executable SHA-256: `22050b4a58910301964623257bccf9828a7efa20a57aa29713bc8391a4b8e102`.

## Connected gameplay evidence

The source repairs unfair resource access and blocked autonomous choices. Arrived waiters keep priority, wait at distinct reachable positions and reconsider urgent needs; an occupied resource remains reserved while its owner re-establishes physical arrival after loading. A typed-array runtime error found during the rejected candidate week is also corrected.

The final repeated seven-day, eight-member fixture passed **127 first-process and 129 fresh-process checks**, with no runtime errors. Every Lifelet finished 59–72 activities, the largest gap between completions was 12.38 game hours, and no critical needs or overlapping settled wait positions were observed in the samples. A separate public seven-waiter save/restart passed **154 + 25 checks**, verifying the current occupant resumes first and the oldest waiter follows after cancellation. These are fixture-specific observations, not a promise that every possible house has adequate capacity. Raw traces, rejected candidates and exact source hashes are in `art/screenshots/autonomy_iteration_10/`; independent findings are in `REVIEWS/iteration_10_autonomy.md`.

Cooperative homework now routes both participants, supports cancellation from either, preserves shared progress through a named restart, and awards learning/Parenting/relationship benefits exactly once. The HUD identifies the partner and displays skill progress. The helper raises an open explaining hand while the learner periodically looks toward them. The accepted directed child/adult run passed **72 + 23 checks** with no runtime errors; raw evidence is in `art/screenshots/cooperative_homework_iteration_10/accepted/`. Other ages/body extremes and smaller windows are not implied by that focused visual acceptance. See `REVIEWS/iteration_10_homework.md`.

The speech update repeats the connected homework flow, then checks readable named cards at three zoom levels, an actual 960×600 window, pause/modal restoration, offscreen removal and controlled simultaneous messages (**72 + 93 checks**). A separate **16-check** real-frame presentation probe verifies natural expiry after play resumes. These overlap the earlier homework checks and do not add new simulation breadth. The selected speaker is prioritized; excess crowd cards can be omitted. Source, images, exact hashes and limits are in `art/screenshots/speech_iteration_11/` and `REVIEWS/iteration_11_speech.md`. The package probe loads the new script but does not repeat those speech-specific scenarios.

The independent full-request score is **7.2/10**, with the 10/10 goal still open. Healthy pupils still need player direction for school/homework, adults need direction for work, and autonomous social choice is strongly repetitive. Character acting/art, household depth and the wardrobe/build catalogue remain substantially short of the requested breadth. The current evidence does not establish feature parity with The Sims 4. See `REVIEWS/iteration_10_final.md`.

## Delivery and history

The original JustLife icon and wordmark splash remain configured with a matching cream background, preserved aspect ratio and 900ms minimum display time. The probe begins after scene initialization; it does not record the earlier native splash. Wordless character sounds remain original game assets and do not depend on GladeCore.

`tools/export_linux.py` strips development MCP services from the isolated export. Font and engine/component notices accompany the artifact. Staged candidate models and downloaded references are excluded. The adjacent `build_manifest.json` records exact runtime/asset and executable hashes.

The superseded care/v19 build is preserved locally at `dist/archive/JustLife-care-v19/`, with its original evidence in `art/screenshots/release_care_v19/`. The superseded family/v18 build is preserved locally at `dist/archive/JustLife-family-v18/`; its original evidence remains in `art/screenshots/release_family_v18/`. Its later 6.7/10 starvation finding is retained in `REVIEWS/iteration_09_autonomy.md`. Successful earlier focused tests did not establish a dependable household week.
