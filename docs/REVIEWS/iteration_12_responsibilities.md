# School, work and household responsibility review

8 September 2026. Integrated source follows the reviewed candidate based on `89acee9`; all 27 integration files match its frozen SHA-256 manifest. This is a bounded implementation acceptance. The full-game quality score remains **7.2/10**, and the requested 10/10 target is open.

## Resulting behavior

Lifelets walk to the neighborhood exit for weekday school or ordinary work, disappear while away, and follow a real route home. Away members cannot be picked or targeted for social activities. The player can control other household members, save an absence or return walk, and bring someone home early. School attendance, learning and career pay are earned once; early return earns neither attendance nor pay. Work income reflects actual time away, and lateness or missed weekdays affect performance. Online classes and home shifts remain explicit alternatives using the same daily attendance marker.

Autonomy prepares for scheduled departures, completes daily homework, protects short need recovery from repeated cancellation, and varies social activities and partners. Explicit player queues and cooperative homework retain priority. Saved state includes away progress, career attendance and autonomy history, with validation before restoration.

## Verification

| Evidence | Result |
|---|---|
| Final rendered seven-day household run and fresh-process resume | 127 + 210 checks passed; no runtime or I/O errors |
| Final-source public career flow and fresh-process resume | 69 + 38 passed; exact payment, selected child play during adult absence, physical return and early cancellation |
| Public school flow on the preceding core | 63 + 42 passed; same controller/world, with current school persistence also exercised by the final week |
| Final focused career, school, autonomy, simulation, education and lifecycle suites | 791 checks passed |
| Real return endpoints, saved arrival boundaries and blocked-route recovery | 44 passed; same-process headless coverage, with two ObjectDB teardown leaks retained in the log |
| Integrated Linux export and packaged menu/save/family/travel probe | Export passed; 32 checks passed with no warnings or errors; packaged production hashes match the reviewed candidate |

The final week recorded 505 useful completions across 665 samples. All eight members completed five due weekday absences; the maximum useful-completion gap was 13.41 hours, final household funds were ℒ16,474, and the final need floor was 32.50. There were no settled waiting overlaps. Social activity included 23 friendly chats, 13 jokes and 7 heartfelt conversations across eight distinct partners.

## Remaining limits

Attendance is not uniformly punctual. Taylor's final school departure was 10:49, 109.87 minutes late; Morgan's final work departure was 11:11, 71.47 minutes late. Over the week, Parker accumulated 10.64 sampled hours below 10 fun, 4.85 hours below 10 hygiene and 2.55 hours below 10 hunger. Taylor and Parker completed four and three homework assignments respectively. No sampled collapse of all six needs or day-long useful-completion stall occurred, but these results still leave autonomy and daily pacing to improve.

The endpoint harness is not fresh-process UI proof, and its teardown leaks are not claimed fixed. The final rendered week and career runs exited cleanly. There are no playable campuses or workplaces, per-career schedules or away activity choices. Wider school/career content, animations and overall presentation remain limited; passing these checks does not establish commercial-game depth. Meal and hair candidates remain separate from production.

Local raw evidence, per-member daily results, rejected runs, the exact patch and file hashes are preserved under `art/screenshots/responsibility_iteration_11/final_integration/`. Generated screenshots, traces and build artifacts are excluded from Git. Maintained regression tests are in `tests/`, including `test_autonomy_policy.gd`, school/career policy adversaries, and the `offlot_school` / `offlot_career` rendered suites in `run_playthrough.py`.
