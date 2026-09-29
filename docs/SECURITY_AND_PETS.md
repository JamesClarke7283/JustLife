# Police, home security, and pet control

Implemented and verified in Godot 4.7.2 on 27 September 2026.

## Playing the features

- A burglary has a 1% base chance at the daily overnight check while the household is home. A striped burglar physically approaches and enters the home, with an audio warning and an on-screen police-call button. The cell phone and the Buy/Build home telephone also offer the call, including for children and young adults.
- The response uses a siren-equipped patrol car and two officers. They leave the car, approach the burglar indoors, scuffle, cuff, escort, load the rear seat, and drive to custody. The police station is a travel destination with a reception desk and a closed jail area; its services open careers, the selected Lifelet's shift record, and custody status.
- Police Officer day duty is 09:00–17:00 for ℒ100; night duty is 17:00–09:00 for ℒ150. Investigator earns ℒ200 and Sergeant ℒ300 for either pattern. Select the pattern in the career record. Shift selection, departure, and completion produce shift-change events; overnight attendance belongs to the day the shift starts.
- The wall keypad costs ℒ300 in Buy/Build and, like the home telephone, hangs on any wall a person can point at, on either floor, whatever stands against it below. Home insurance includes one and costs ℒ200 when bought, then ℒ200 on the displayed weekly payment day. The alarm sounds and calls authorities on attempted entry. Missed payment dates do not cause retrospective deductions, and there is no three-day debit.
- An arrest restores the stolen furnishings and cash and adds ℒ200 once. Household members receive a Shaken moodlet lasting two game days. An unresolved case blocks remodeling and moving away so its physical actors and stolen-property journal remain valid.
- Select a cat or dog through its portrait or body to open its personal needs and behavior panel. Commands are species-specific; selection survives closing the panel, and clicking reachable ground directs that pet. Clicking a Lifelet portrait returns to human control.
- Pets autonomously use beds, doghouses, cat trees, and toy boxes. Commands use the same physical routes and interactions. Doghouse rests last at most two game hours; toys are retrieved before floor play and squeaking. Stop Squeaking mutes that play session; Stop Playing exits the activity. Connected stairs support direct movement and upstairs furniture.

## Ownership and persistence

`crime_response.gd` owns the case state, physical sequence, stolen-property journal, and one-time recovery. `crime_visuals.gd` builds the costumes, police car details, audio, and custody furnishings. `safety.gd` connects those to household time, phones, insurance, and venue presentation. Active cases are validated and saved in household extras; loading a case restores its stage without charging or paying twice.

`pet_behavior.gd` owns autonomous choices and commands; `pet_actor.gd` supplies movement poses and squeaks. The existing pet records retain their save format. `main.gd` owns the species menus, needs panel, active selection, and pointer routing.

Insurance dates are saved with each property. Older policies without dates acquire a next weekly date without an immediate extra charge. Existing police careers migrate to the new role and shift definitions.

## Verification

| Test | Passing checks |
| --- | ---: |
| `test_crime_response.gd` | 82 |
| `test_police_station.gd` (rendered) | 27 |
| `test_police_careers.gd` | 99 |
| `test_police_calendar.gd` | 14 |
| `test_security_insurance.gd` | 21 |
| `test_pet_behavior.gd` | 37 |
| `test_pet_stairs.gd` | 18 |
| `test_safety_pet_integration.gd` (rendered) | 36 |
| `probe_funds_leak.gd` | 353 |
| Existing career-day regression | 89 |
| Existing adversarial career-policy regression | 115 |
| Existing calendar regression | 19 |
| `test_progression.gd` | 173 |

These suites passed 1,083 checks in total. The combined integration test exercises the real main scene, species-specific panels, switching portraits, physical floor-click movement, buying insurance through the phone, alarm installation and placement preview, police shift selection, active case save validation and restoration, police dispatch, and unresolved-case travel/build guards. The station test verifies navigation, physical and screen-space picking, service routing, restored custody, and cleanup when changing venues. Police career tests also validate 141 saved callback snapshots. The full progression suite confirms fresh household/save-load behavior, the nightly burglary signal, insurance, and existing book/skill progression. The final crime suite additionally covers custom wall-item heights through theft, recovery, a subsequent ordinary household save, validation, and fresh home reconstruction.

Run focused tests from the project root, for example:

```sh
godot --headless --path . --script res://tests/test_crime_response.gd
godot --headless --path . --script res://tests/test_pet_stairs.gd
godot --path . --audio-driver Dummy --script res://tests/test_safety_pet_integration.gd -- --capture
```

Rendered evidence is retained locally in `evidence/security-pets/` (ignored by Git). The rendered combined test exits successfully with no script errors; Godot reports seven leaked texture RIDs during renderer shutdown. A packaged export and a long unattended soak were not run in this pass.
