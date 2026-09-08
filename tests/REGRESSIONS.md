# Architecture and household regressions

Run these suites through `run_regressions.py` on Linux. The runner copies the explicit `regression_inputs.json` resources and test scripts into a new project, removes editor tooling, and sets private XDG and `JUSTLIFE_DATA_DIR` paths before launching Godot. The source project and player saves are not run or modified. Each group retains logs, source hashes, saves and JSON receipts in its reported output directory.

Examples, from the project root:

```sh
python tests/run_regressions.py --group architecture --group build --group protection
python tests/run_regressions.py --group stair-save --movement-case cancel_later
python tests/run_regressions.py --group build-food --food-case partial_later
python tests/run_regressions.py --group adoption
```

Use `TMPDIR` to select a filesystem with sufficient space, or `--output /absolute/new-directory` outside the source project. Every run starts in a new directory. `--timeout` limits each owned process; timeout terminates that process and records a failed run. Producer and consumer phases run in separate processes with the same group's private saves. A consumer requires its producer's receipt and named slot.

| Group | Coverage |
| --- | --- |
| `duration` | Saved action-duration compatibility and rejection cases |
| `architecture` | Building records, levels, legacy ingress, supported decorations, roofs and meal floors |
| `build` | Shared-wallet construction transactions, undo and roof edits |
| `protection` | Actors, routes, furnishings and food protected during construction |
| `controller` | Straight and rotated stair routing |
| `stair-save` | Same-process restore, fresh-process journeys, cancellation and rejected loads |
| `food` | Cooked dishes and partial servings carried through stair saves |
| `leftover`, `food-clear` | Leftover restoration and blocked food setdown |
| `build-food` | Construction while a saved stair journey holds food |
| `adoption` | Adoption arrivals and custody during fresh-process restoration |
| `waiting` | Autonomy while household members wait for shared resources |
| `motion` | Reconstructed stair poses, shoe clearance and rendered movement |

Movement cases are `walk_up`, `walk_down`, `cancel_empty` and `cancel_later`. Food cases are `serving_empty`, `serving_later`, `partial_empty` and `partial_later`. Omitting the case option runs every case for the selected group. The motion group requires `--render`; coordinate access to the display before running it.

These are controlled API and simulation regressions. Some fixtures construct architecture, set needs or advance simulation time directly. Passing them does not establish pointer usability, visual quality, a full public playthrough or export qualification. Use the rendered public-flow runners for those separate checks. Warnings are recorded even when a suite passes; inspect them before claiming a clean run.

`python tests/run_public_twofloor.py` separately opens a private rendered game,
creates two Lifelets through the creator, chooses A Fresh Canvas, purchases an
upper floor and staircase through viewport clicks, places an upstairs bookcase
and plant, and physically reads upstairs. It saves through the public picker,
travels to the library and back, then loads that untouched upstairs activity in
a second process and finishes it before another car departure. Architecture,
actors, funds, needs and time are not injected. Autonomy is disabled to keep this
finite interaction sequence deterministic; camera framing is controlled. Button
signals exercise the production callbacks, while construction, furnishing and
interaction clicks use actual viewport input. This is a functional bare upper
floor example, not a furnished house design or a whole-game quality score.

The construction and furnishing protection fixtures preload the actual main scene before their dynamic setup. An unchanged-runtime comparison showed that late loading could retain 23 script objects and 15 resources at shutdown despite passing assertions. The maintained preload change preserves all assertions and passes **49 + 52 checks, zero failures or engine warnings**, at `dist/test-work/justlife-regression-8cn_in2o`. Historical warning logs remain in the wood-material evidence; this test dependency change does not alter production teardown or hide warnings.
