# Iteration 15 — clear places for standing diners

8 September 2026. The independent critic accepts this bounded repair for production. The full-game score remains **7.2/10**; the 10/10 goal is open.

## Behavior

When no chair is available, a Lifelet carrying a serving reserves a reachable standing position within three metres. Positions use the actual navigation grid and clear furnishings, visible people, floor dishes and other reserved activity destinations. Standing diners use their own plate as the activity resource. Later activities wait if their arrival or displayed position would intrude on a reserved dining place.

An obstructed arrival causes the diner to walk to another clear position before eating. Building over an occupied dining position similarly reroutes the same paid partial serving. Named saves retain the standing destination, ownership, consumed food and later instructions; older saves acquire the new route metadata while retaining their meal state.

If no acceptable position exists, cancellation releases the serving. A guard after meal resolution prevents the canceled action's callback from overwriting the route of the next player instruction, which can start synchronously during cancellation.

## Evidence

| Check | Result |
| --- | --- |
| Public four-adult cooking, standing dining, furniture obstruction, cancellation and named restart | **96 + 35 passed**, clean logs |
| Fresh-process replay of the authentic eight-member crowded-dinner save | **482 passed**, clean logs |
| Final exported-source standing reservations and save validation | **31 passed**, clean log |
| Final exported-source admission of a later nap | **11 passed**; one shutdown warning reports two remaining ObjectDB instances |
| Final exported-source cancellation and next-instruction route | **11 passed**, clean log |
| Linux package startup, creator, saves, deletion and travel | **39 passed**, clean log |

The public run is `dist/test-work/justlife-playthrough-zot3hop_`. It creates four adults through the creator, disables autonomy for deterministic instructions, sells chairs through Build, cooks dinner and runs an actual nap alongside standing diners. Moving a lamp over a paid dining position triggers real rerouting. Cancellation and recollection preserve the same partial plate; a paused fresh restart preserves actor locations, destinations, progress and subsequent instructions. All four servings and the later reading instruction finish. Two active diners are 1.0m apart in the initial capture; the nap is 3.29m away, so this image is not a tight crowd test. Object interactions use public click signals and buttons; furniture placement uses actual mouse input.

The separate legacy replay is `dist/test-work/justlife-playthrough-8ku4mcoj`. It loads the authentic earlier named save without changing actor locations, queues, clock, needs or autonomy, and runs from 23:15 to 23:59. Eighteen samples show minimum active eater/eater separation of 1.0m and eater/nap separation of 1.25m. The original partial plate and an already-owned zero-progress plate finish. Newly claimed portions remain partial when the replay stops. This is a focused continuation, not a new multiday household qualification.

The critic verified the frozen public and legacy manifests. Final runtime differs from those runs by one line in `main.gd`: the current-action identity guard after meal resolution. Its focused regression first reproduced two failures in ten checks, then passed eleven checks after repair. All three component suites subsequently passed on the final exporter snapshot, `dist/build_snapshots/justlife-release-ls3pmwuf`. Runtime hashes are recorded in the packaged build manifest; all 46 production GLBs remain unchanged.

Local evidence is archived under `art/screenshots/standing_iteration_15/`. The original no-space failures remain in `dist/test-work/standing-cancel-probe-d2hj__i_`; the corrected private run is `standing-cancel-fixed-teucb83l`. Earlier admission and malformed-save failures remain preserved with the handoff review. Successful isolated runs do not erase the intermittent ObjectDB shutdown warning seen in controlled tests.

## Scope and limits

Ordinary reserved spacing is 0.85m, increasing to 1.15m around nap/sleep activities. These checks and sampled actor positions do not prove continuous mesh collision avoidance; walking paths can still cross. A three-metre search can cancel when no clear place exists. Instantaneous dish setdown, slow cleanup in crowded households, lateness and prolonged low needs remain. Character artwork, natural oven handling and the wider game catalogue still need work; private hair and oven studies are excluded from this integration.

The maintained public scenario is available as `python tests/run_playthrough.py --suite standing_dining`. Like the other rendered suites, it uses an isolated project and private userdata. The three controlled tests are `test_standing_dining.gd`, `test_standing_admission.gd` and `test_standing_cancel_route.gd`. The historical legacy replay depends on its authentic diagnostic save and is deliberately excluded from the portable test set.
