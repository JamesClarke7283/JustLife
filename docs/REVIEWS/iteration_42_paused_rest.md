# Iteration 42 — sleeping after a paused save loads

Loading a paused household now places an actively sleeping Lifelet on the existing bed or seat anchor, with closed eyes. Previously the saved Sleep activity was intact, but the Lifelet could appear standing beside the bed until animation resumed. The correction covers household members regardless of which Lifelet is selected.

The two existing load-preparation paths reconstruct only active Sleep/Nap presentation for paused members who are at home. The actor requires a finite, matching bed or seat anchor. The controller restores its previous member binding afterward. Physical bodies, needs, paid actions, later queues, route ownership, simulation speed and animation, blink and voice clocks do not advance. Ordinary paused animation keeps its existing freeze behavior.

## Maintained checks and rendered evidence

`python tests/run_rest_pose.py` runs in an isolated project with separate save, data, config, cache and temporary directories for each phase. It reuses the committed genuine stair checkpoint. A public household selection and named save create the nonselected-sleeper case; the next process loads those actual bytes.

The complete proposed runner passed **62/0** for the selected fixture and component controls, **37/0** for the public save producer, and **49/0** for its fresh nonselected restart: **148 assertions across three gameplay processes**, plus a clean import. Source and copied inputs, reports, terminal counts and unchanged fixture bytes were verified. These are overlapping assertions, not 148 independent gameplay scenarios.

Four separate 1440×900 Forward+ images compare the original and corrected selected and nonselected loads. Both actual sleepers retain their saved activity and body state; the corrected images show supported lying contact and closed eyes. Root and the independent critic inspected all four. The capture freezes before the first ordinary process call, so it retains the world's initial lighting; it does not demonstrate normal nighttime lighting or continuous sleep animation. No lighting or camera changes ship with this correction. Seat Nap is a component check, not a separately saved seat fixture. The legacy load seam is source-reviewed; actual fresh-process fixtures use the existing journey format.

## Retained failed attempts

An initial component check failed exact idempotence because full-weight interpolation changed a scaled teen seat offset by about 0.00000003 units. Reconstruction now assigns that offset directly; ordinary animation interpolation remains unchanged. Earlier nonselected comparisons exposed only a known absent-to-empty traversal cache fill. Final expectations guard the exact original absence and lack of a route before projecting that single derived entry; all authoritative state remains exact. Two private typed-array harness errors timed out and remain failed attempts. Initial visual comparisons also failed because they included the deliberately changed camera or used the wrong packed camera representation. Their corrected comparisons preserve every other recorded fact; no simulation state was adjusted to pass them.

## Review and integration

The independent source and four-image review is `7f55d1a496d6908cf69d2a10e73e7eeafb255bcdea4a817ed4bb393677d545c0`. The separate maintained-runner review is `96ff49a21911b758ec14db4b0be24abd78988e80aabac0bad332e974ee16887a`; root verified all 530 pins in its freeze. The accepted five-file manifest is `7f3bf90055a6b800c523b320ef85ee3cec1a16718811c2617b2e7f0fc63343cc`. Integration copies only the two reviewed runtime files, test, UID and runner, plus this documentation. Exact accepted inputs were already executed; integration does not claim another engine run.

This resolves the presentation defect recorded in [iteration 41](iteration_41_clearing_walks.md). Its failed sustained-play result and other crowding limitations remain. Packaged release is still held, and the latest whole-game rating remains 7.2/10.
