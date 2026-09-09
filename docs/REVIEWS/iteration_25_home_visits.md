# Invited neighbors

Known neighbors can now visit the player's home through **People → Invite over → Welcome in**. They walk to the welcome point, enter only after the selected household member completes the identified friendly conversation, and leave physically after **Say goodbye** or the visit deadline. The guest card shows remaining welcome/stay time. One neighbor visits at a time; Build and travel wait for departure. Guests retain their own homes and do not join the household.

Named saves preserve each visit phase, route progress, clocks and the actual queued/paid conversation owner. Invalid guest records are checked against a detached world before replacing the current household. The starter layout uses its existing navigation view. Edited homes use a one-metre social offset so grid snapping does not put the host's destination inside the guest's route clearance. Paused guest conversations preserve host facing.

## Evidence and limits

The private handoff is `dist/test-work/home-visit-source-ix10gmjk/HANDOFF.md`, SHA-256 `00e6e22be2ce43b305c7c2137093e8eab1f5c43c169c82da568c86f0fc0e947a`. Its frozen manifest `4fc2acec6d701d9ee70ae82eff202a9b17d7cd4c7457ef23dd88c8bcd814d8b7` pins 259 source, test, save and evidence artifacts. Root verified all pins and copied the 18-file promotion set; the receipt is `dist/game-work/home_visit_promotion_receipt.json`.

| Qualified check | Assertions / failures |
| --- | --- |
| Starter lifecycle and six named save/load phases | 41 / 0 |
| Fresh engine reopening all six starter phases | 38 / 0 |
| Conversation ownership, cancellation, deadlines and invalid-save rejection | 29 / 0 |
| Concurrent paid cooking and unrelated queue preservation | 10 / 0 |
| Fresh paid-Welcome departure | 7 / 0 |
| Actual Forward+ UI, including 960×600 waiting view | 15 / 0; eight images |
| Edited-house lifecycle and six named save/load phases | 41 / 0 |
| Final fresh edited-house greeting, pause, entry and exit | 7 / 0 |

These are bounded assertions from successive source revisions, not hundreds of independent sessions. Each listed run ended with exit zero, clean Godot diagnostics and unchanged pinned inputs. The final edited-house tests cover the later spacing correction; the final fresh test covers the pause correction. Earlier starter/UI checks use the unchanged branch. Root also inspected the final Welcome, inside and 960×600 captures.

Root independently ran the existing resident-record validation against the final four runtime scripts: **26/0**, exit zero and clean diagnostics. Its exact input hashes and isolated environment are in `dist/test-work/resident-validation-home-n51a73qb/receipt.json`.

The critic inspected all eight final UI images and rated this interface increment **8/10**. The full-game score remains the earlier **7.2/10**, with the 10/10 goal open. The independent final UI report is `dist/test-work/crop-invite-critic-v26-kwf3f_lr/FINAL_INVITE_UI.md`, SHA-256 `7d5e8345238a60d66ba23384fd3263d54eaed27178f82ca7e158784fd367716b`.

Earlier failures remain in the handoff: missing starter navigation access, callback clock ownership, active-Welcome departure metadata, resident-envelope validation, typed-container comparison, suppressed automatic rendering, edited-house social clearance and paused host yaw. Legacy JSON-to-world reconstruction retains its pre-existing approximately 1e-16 coordinate differences. The qualified checks compare exact immediately restored layout values; no epsilon was enlarged to hide an invitation change.

A separate headless timing study measured 20 controller steps per state in an edited home: mean **385.60 ms without a guest**, **374.15 ms arriving**, and **382.61 ms waiting**. This reveals an existing controller performance problem; it is not rendered FPS or evidence that the game meets a performance target. The study is `dist/test-work/home-visit-perf-458p9n0x/PERFORMANCE.md`, SHA-256 `f99c806f6db5f217672e6a83d33cdd27d0cffe452daa5d88a9718c493fc5daab`. Performance improvement remains separate work.

Guest dining, parties, overnight stays and additional resident households remain unimplemented. A completely body-blocked route can require moving another Lifelet in Live mode.

## Reproduction

`python tests/run_home_visits.py --source /absolute/path/to/JustLife` creates an isolated snapshot, private XDG directories and private save data, then runs the maintained cases. Add `--capture` for the actual UI sequence. The component commands were executed in the handoff; the wrapper was syntax checked. Root added the required project icon to its copy list during integration. The opt-in packaged release probe also now disables native viewport input and forces a draw before capture, addressing hidden-window capture suspension without changing ordinary game input.
