# Transport, dog training and assigned beds

28 September 2026. Source checks used Godot 4.7.2 and private game-data folders.

## Delivered behavior

- The school bus has white body panels, green stripes, three-leaf shamrocks,
  tinted passenger glass, a split windshield, grille, bumper and four emissive
  rear brake lamps. Named components and curb-side door/exit markers drive the
  real boarding and drop-off routes.
- Selecting a dog and clicking the floor interrupts its activity. The Lifelet
  tool offers Point & Move and Move Out of the Way. Clever Tricks, Social Skills
  and Logic Skills progress to level 10, with animated tricks, chosen-toy fetch,
  visible agility weaving, calmer responses and navigation recovery.
- Workers walk to their car, open its door, enter, close it and drive away.
  Returning workers park, exit, close the door and walk around to the rear
  entrance. The starter home now has a usable rear doorway. Vehicle collision
  footprints follow the authored car axes. A car and its occupied garage are
  reserved during the commute, including against Build storage and undo.
- Work and school preserve at least 80 energy through the return home.
- Double beds offer Assign bed sides and Go to Bed. Two adults retain their
  chosen halves, approach the correct sides and sleep together regardless of
  arrival order. Assignments persist, reject duplicate claims and require clear
  bedside access.

## Focused evidence

| Check | Result |
| --- | --- |
| Bus components, materials, brake phases and rendered views | 43 checks passed |
| Bus/street routing | 16 checks passed |
| Dog commands, HUD clicks, training, fetch and rendered slalom | 39 checks passed |
| Existing pet behavior, stairs and pet-care-only suites | 37, 18 and 34 checks passed |
| Assigned bed UI, movement, poses and save validation | 23 checks passed |
| Existing shared-bed and child-bed routing | 8 and 9 checks passed |
| Canonical work commute, actual Build refusal and rear arrival | 200 checks passed |
| Rendered commute with all seven physical save/load reconstructions | 228 checks passed |
| Adversarial commute save validation | 10 checks passed |
| Work/school energy reserve | 61 checks passed |
| School day and career day | 116 and 89 checks passed |
| Autonomy responsibility policy | 170 checks passed |
| Commute car/garage reservations | 31 checks passed |
| Existing Build transactions | 57 checks passed |
| Existing vehicle-drive and garage fixtures | 7 and 3 checks passed |
| Existing household and lot exits | 22 and 15 checks passed |

Rendered bus, pet menus/slalom, shared sleepers, car boarding/exit and rear-entry
views were inspected. Logs were also checked for script errors rather than
relying solely on assertion totals. The editor import completed without parser
errors. Commands and capture flags are listed in [the test guide](../../tests/README.md).

Two older test assumptions were corrected: the pet-care fixture buys a cat and
must exclude dog-only lessons, and the room-paint fixture costs 42 rather than
40. The latter price was independently reproduced with the unchanged HEAD
building policy; no paint-price behavior was changed.

These are focused source fixtures. No packaged release was built for this task.
Custom homes need a clear rear entrance and accessible parking; blocked geometry
is refused instead of moving a Lifelet through it.

The existing `test_trip_party.gd` fixture still reports two arrival assertions
failing out of 23. An isolated unchanged HEAD run reproduces both failures
exactly; the shared-party trip issue is retained and was not changed in this task.
