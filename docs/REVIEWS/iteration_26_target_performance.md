# Reusing unchanged furniture approach positions

The simulation no longer repeats expensive furniture standing-position searches twice per frame. The cache retains the exact original answer while the furnishing and navigation remain unchanged. Actor targets stay live; movement, collisions, search ordering and saved state are unchanged.

Profiling an edited starter home found approximately 383.5 ms of a 384.6 ms controller step in two target publications. Eleven furnishings repeatedly scanned and sorted 729 candidate grid points because their first approach point was blocked. The fix is confined to `world.gd`: memoization uses node identity, exact global transform, size, floor, kind and transient flags, and is invalidated by navigation identity/generation or a rebuild. Removed nodes are pruned, and returned records remain separate from cache contents.

## Evidence

The private handoff is `dist/test-work/canonical-target-cache-v1-6ykiiimd/HANDOFF.md`, SHA-256 `559fdab3adf6f54b18201e2838a7d3deec8c5223992b0407a3805b19c2399c94`. Its frozen manifest `2bacfc3dec72d848f6090edbb4bb848fc33b4701099a660c4c1e7577f8cfb1da` pins 93 artifacts. Root reviewed the runtime diff and invalidation cases, verified every pin and promoted four exact files. `dist/game-work/target_cache_promotion_receipt.json` records that integration.

Two uninstrumented processes ran the same fixed authored layout and 20 controller steps of 0.05 simulation seconds, at normal speed with two household members. Autonomy, aging and bills were disabled. All recorded targets, household state, queues, geometry, physical snapshots and resident state matched exactly after every step.

| Controller CPU time | Original | Revised |
| --- | ---: | ---: |
| Mean | 386.02 ms | 1.35 ms |
| Median | 387.94 ms | 1.35 ms |
| Range | 374.31–400.33 ms | 1.14–1.62 ms |

These are headless CPU-step measurements on the available machine, not rendered FPS. The first target fill after a rebuild still took 192.91 ms; the first controller step after another rebuild took 197.91 ms, followed by a 1.28 ms average over 20 warm steps. Graph reconstruction itself remains unchanged and is outside those cold-fill timings.

Validation passed with terminal exit zero, clean engine logs and unchanged pinned inputs:

- **58 cache assertions:** exact uncached output and read-only state after furnishing movement, rotation, resizing, floor/parent changes, transient food/puddle changes, removed/reused IDs, moving/absent actors, successful/rejected rebuilds and replacement navigation ownership.
- **43 existing Build transaction assertions.**
- **41 existing edited-home Invite lifecycle assertions**, including paid Welcome, six named save/load phases and physical departure.

The first comparison failed because independently constructed starter homes generated different wall IDs from timestamps. Its 720 repeated ID-field differences and both traces remain retained. The qualified comparison supplies one identical authored layout to both processes; it does not ignore fields or enlarge a numerical tolerance.

The maintained profile/control scripts inherit `test_home_visit.gd` and require an isolated project with private XDG/save directories and `-- --canonical-fixture`. The profile also reads `tests/canonical_target_fixture.json`. Complete reproduction drivers and exact commands remain in the handoff. No profiling instrumentation, benchmark saves or generated reports are shipped.

This fixes repeated target-publication work. It does not resolve all performance cases or change the independently assessed full-game quality score.
