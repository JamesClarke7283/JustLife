# Residents and visits

Maya Chen and Leo Morgan retain their existing relationship IDs, `maya` and `leo`. Each has a permanent home destination (`maya_home` and `leo_home`). New towns show Maya walking past the front sidewalk, with Leo at home until his next walk. Residents leave the street between walks, and their hidden actors are excluded from social targets. Pausing and Build mode stop resident motion.

Only a current social approach or active conversation holds a walking resident in place. A later queued conversation does not stop their walk; its destination is refreshed when that action actually starts. Completion and cancellation release the resident. If the resident has already left when a deferred conversation reaches the front, that conversation is canceled without rewards; later instructions keep their own routes. Existing wordless Lifelet voices and social animations are used.

A household can arrange a home visit after any member reaches 20 friendship with its resident. The People panel's **All relationships** list provides **Visit home**, and both addresses appear in **Explore**. Clicking an absent resident's name opens their address rather than targeting an invisible actor. Visitors can use furnishings and talk to the resident; Build & buy remains restricted to the player's own home.

Maya's smaller cottage and Leo's wide bungalow have distinct room arrangements, floors, furniture, landscaping and entrances. Both use the same transparent window system as the player's house. Background houses also use two different exterior configurations.

## Travel

The map states that travel takes the household together and clears current activities. A trip checks everyone is available and a sidewalk route exists before canceling activities. It then walks each household member to the curb, shows an original Blender-authored shared car driving away, changes destinations, and shows the car arriving. The household appears at the destination curb. The simulation advances exactly 15 game minutes per completed journey and restores the chosen speed, including pause.

The temporary `travel` mode keeps saving and other gameplay controls unavailable until arrival. A persistent journey caption explains the current step; Escape does not remove it. This version presents boarding and exiting by hiding/showing Lifelets at the curb. It does not yet animate car doors, seat passengers, or support driving controls.

## Persistence

`world_state.residents` is a version-1 dictionary maintained by `LifeResidents`:

- `locations`: destination IDs mapped to `maya`/`leo` route records.
- Each record: numeric XYZ `position`, `rotation`, integer `direction` (-1 or 1), integer `waypoint` (0–2), nonnegative finite `wait`, and `phase` (`walking`, `home`, or `visiting`, constrained by location).
- Stable profiles and ownership come from `LifeResidents.PEOPLE`, never from save-supplied identities.

The selected household member's shared world state also retains the existing `home_layout` and `venue_layouts`. Saving while visiting therefore preserves the player's own furnished house and all resident locations. Older saves lacking resident records receive compatible defaults; their existing friendships are retained. Malformed resident records are ignored safely, with fresh defaults on attachment.

Resident locations away from the currently displayed lot are retained, not simulated in the background. Only Maya and Leo are currently implemented; richer resident schedules and additional households remain future game work.

## Verification

Run `python3 tests/run_neighborhood_checks.py`. It creates a private project snapshot with editor services disabled, sets `JUSTLIFE_DATA_DIR` and `XDG_DATA_HOME` to isolated directories, imports it, and runs validation, producer, fresh-process save consumer, queued-absence producer and fresh continuation, existing neighborhood regression checks, and an eight-member paused/fast-speed round trip with named save restoration. The producer's `user://resident_expected.json` is consumed by the immediately following fresh process. Logs, input hashes and results remain under `dist/test-work/resident-checks-*/evidence`.

The eight-member control checks exact decoded construction records and unchanged rendered wall/floor geometry separately from JSON conversion. Furniture positions are exact; orientation reconstruction from the saved Euler angle permits only float32 component precision. The named-save writer requests full JSON precision, but Godot’s native JSON parser is not assumed to preserve every double bit for bit.
