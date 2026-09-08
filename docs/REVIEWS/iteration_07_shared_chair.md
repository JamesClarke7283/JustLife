# Independent review — desk and supporting-chair occupancy

8 September 2026. **Correction accepted: 72 actual rendered-flow checks pass, zero runtime errors. Full-request score remains 7.2/10.**

The critic-owned `tests/test_shared_chair.gd` runs via `tests/run_playthrough.py --suite chair`. It creates a child/adult household through public controls, uses actual normal-speed routing and action processing, and never calls arrival or action-completion directly. The test selects the actual nearest chair used by the desk's anchor, then queues Relax through that exact chair's public interaction menu.

The pre-fix source `/tmp/justlife-desk-source-ign6rf9v` reproduced four failures in `/tmp/justlife-playthrough-7kv9feoh`: child school and adult relaxation could both become active on the same desk/chair pair, and neither direction caused the requester to wait. This confirms a gameplay resource-sharing defect independently of the developer's component checks.

The corrected source `/tmp/justlife-chair-source-jhdaxg52`, run separately in `/tmp/justlife-playthrough-a0qxkt7y`, passes the same 72 checks:

- While the child studies, an adult reaching the supporting chair waits with the chair action preserved. The HUD explicitly displays the waiting state.
- Canceling the child's class releases the adult's waiting chair action, which starts through real frame processing.
- The reverse order works: an adult already relaxing in the chair makes a newly arriving child desk action wait.
- Canceling that waiting desk action leaves the actual chair occupant unchanged.
- Requeuing the class, then canceling the adult's chair activity, releases the preserved class.
- A different chair remains usable by the adult while the child studies. The resource reservation does not block unrelated seats.

Baseline/fixed screenshots, source/model hashes, logs and reports are preserved in `art/screenshots/shared_chair_iteration_07/`. This is a bounded default-lot routing/occupancy review; it does not independently test every rearranged desk/chair layout, multiple desks sharing one chair, or saving during contention. The parent's broader resource component checks remain supporting evidence rather than additional rendered coverage claimed here.


## Paused cancellation follow-up

The subsequent `world.begin_activity_frame(paused)` correction was independently checked using the extended `--suite desk` harness. Source `/tmp/justlife-paused-booster-source-t4d1065k`, run `/tmp/justlife-playthrough-i0s9sgp3`, passed **45 rendered checks with zero runtime errors**. Public cancel while paused clears the class and grants no attendance, while preserving the booster under the frozen seated body. Public resume releases the booster as the child leaves that pose. Both states are captured in `art/screenshots/paused_booster_iteration_08/`. The full current score has since been revised to 7.0 because of the separately discovered profile-art defect in `iteration_08_profile.md`.
