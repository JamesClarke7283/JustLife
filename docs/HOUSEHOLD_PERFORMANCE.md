# Household genealogy performance

An eight-Lifelet household with six parent links repeatedly traversed the unchanged family graph for all 56 directed pairs during each social-context synchronization. A live household tick performed two such synchronizations before rendering or navigation work.

Measured in isolated Godot 4.7.2 headless processes, with no editor/MCP autoload, 50 synchronization warmups, and three batches of 1,000 calls per measurement. Each live tick advances 1/60 second; autonomy is disabled. The same fixture and engine were used before and after the change. These are local CPU timings, not an end-to-end frame-rate claim.

| Operation | Before, milliseconds per call | After, milliseconds per call |
| --- | --- | --- |
| Social-context synchronization | 1.493 / 1.491 / 2.144 | 0.228 / 0.222 / 0.219 |
| Paused household tick | 3.765 / 3.351 / 3.151 | 0.459 / 0.457 / 0.453 |
| Live household tick | 3.338 / 3.443 / 3.381 | 0.588 / 0.594 / 0.594 |

The mean live tick cost fell from 3.387ms to 0.592ms, about 83%. The retained work synchronizes changing friendship, romance, age eligibility and partnership data. Only derived genealogy roles are cached.

The private role table is rebuilt after member addition, successful family configuration and successful restore, and cleared for a new household. Invalid setup/restore operations leave the live graph and role table intact. Birthdays do not alter established genealogy. The table is not saved; restoration rebuilds it from the validated graph. Callers change family data through the public household APIs, rather than mutating its owned `family_graph` dictionary.

`tests/benchmark_household.gd` reproduces the measurement in an isolated project. `tests/test_family_context.gd` adds 46 behavioral checks for creator replacement/removal, failed setup/restore, successful JSON restore, new members, birthdays, pause, unknown IDs, new households, legacy saves and live romance eligibility. Existing genealogy, family, household, relationship, save, familiar-conversation and lifecycle regressions also pass (291 checks).
