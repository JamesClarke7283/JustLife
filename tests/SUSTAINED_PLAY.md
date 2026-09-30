# Continuous 180-day play

Run `python3 tests/run_sustained_play.py --segment-days 1 --render --rendering-method gl_compatibility` for the first
rendered day. Continue the same household with
`python3 tests/run_sustained_play.py --resume --segment-days 30 --render --rendering-method gl_compatibility`.
The default goal is 180 full elapsed game days, measured from the initial game
clock rather than just the displayed day number. Use `--render` on later
segments to inspect the actual scene as well.
Use `--render --rendering-method gl_compatibility` for Godot's regular OpenGL
renderer; omitting the method uses the project's configured renderer.

The maintained run uses a regular renderer after a saved day reproduced a null
material RID error in Godot 4.7.2's dummy renderer during the 17:00 work return.
The same saved day completed in Forward+ without that error. Retaining speech
text did not fix the dummy replay, so no speculative speech change was applied.
Headless mode remains available for diagnostics; renderer errors remain fatal
and are not filtered out of the recorded evidence.

The runner keeps a separate project and save under
`dist/test-work/justlife-playthrough-sustained`. It refuses to overwrite an
existing run. Each invocation copies the current production scripts and records
their hashes, allowing a confirmed bug to be fixed before play continues from
the same saved clock. It also refuses to start while that playthrough's recorded
engine is still running. Logs and source manifests live in `sessions/`.
To end a running segment at a saved checkpoint, create `checkpoint.request` in
the isolated project directory. This leaves the full 180-day target intact.

The household is created through the normal UI with two young adults, a furnished
cottage, and a purchased dog. The standard Long lifespan setting keeps the
household playable throughout the run, with automatic birthdays enabled. No
money, needs, positions, clocks, action phases or completion results are injected.
The harness pays bills and requests pet care through the same UI callbacks used
by players; ordinary autonomy manages other daily activities.

Godot runs complete engine frames at a fixed 1/15-second delta with the supported
8× game speed. Headless segments omit rendering but keep the scene, physics,
timers, movement and simulation. There are no manual `_process` or household
`tick` calls. Daily paused saves provide restart points; each restart verifies
the saved clock, money, membership, needs, skills, career and lifecycle, plus
every furnishing, placement and construction record (rotations modulo a turn).
New checkpoints also verify street positions, directions and presence, plus
resident positions, routines and visits.
Each checkpoint archives the exact save bytes with a SHA256 digest. A newer
rolling autosave is retained separately before restoring the archive paired
with the journal; a failed verification stops before gameplay or new saves.
The same checkpoint archives observations and watchdog state. Recovery restores
those counters with the matching save, preserving any uncommitted observations
separately so replayed activity is not counted twice. Checkpoint archives never
overwrite an earlier branch when a failed restart is replayed.

Pet requests record availability, acceptance into the activity queue, and the
matching completion signal. An accepted request that disappears or exceeds its
queue time and six-hour allowance stops the run for inspection. The requested
activity rotates between attempts so work schedules do not exclude one activity
throughout the run.

The journal in the isolated `userdata` directory retains daily state, action
completion counts and recent quarter-hour observations. Persistent motion stalls,
critical hunger or an unexpectedly stopped clock halt the run for investigation;
engine errors are captured through Godot's logger and halt at the next frame.
Walking residents are observed each engine frame; three game hours without
movement stops the run. Conversations, invited visits, doorbell waits and absent
residents are excluded from that walking check. Their positions are included in
the quarter-hour observations, and the watchdog survives paired save restarts.
These failures are not bypassed to reach the target. A successful segment is only partial
progress. Completion requires the journal's target clock and a verified final
restart, with any observed issues resolved or explicitly explained.

Add `--library-excursion` to a later `--resume` invocation to opt into one paused
home → library → home round trip. From day 48 onward, it waits for daytime on a
non-work day, healthy available party members, and completion of every accepted
pet-care request. Work, school, stair/door crossings, meals, sleep, paid actions,
and player instructions are protected. New harness pet requests wait during a
due daytime off-duty admission window; accepted care and ordinary autonomy
continue. The normal Travel button may end a free
autonomous pastime. It uses Explore, the destination pin, Choose who goes, and
Travel, advancing only actual engine frames. No clocks, needs, poses, activity
completion or autonomy settings are injected.

The outing archives an immutable paired home checkpoint before departure. Each
leg must progress within 90 seconds and finish within 180 seconds. Each Lifelet
must physically reach the boarding endpoint; production boarding/car-entry
timeout fallbacks fail qualification. After thirty
natural game minutes it verifies the exact home furnishings, property/land,
household and pet identities, and the camera's documented arrival defaults.
Success is committed in the paired observation journal, so another opted-in
resume cannot repeat the outing. Generic commands and checkpoints wait until
home. A refused or stalled trip halts with its observations and preserves the
prior home checkpoint; an away save is never committed as a harness checkpoint.
The original 180-day target remains unchanged.

`test_sustained_library_excursion.gd` qualifies this addition in a separate
plugin-free `justlife-playthrough-*` project with private userdata copied from
an immutable paired day-48/49 home checkpoint. Set `JUSTLIFE_SUSTAINED_RESUME=1`
and `JUSTLIFE_LIBRARY_EXCURSION=1`; it uses the same full sustained loop and requests
a normal segment stop after the completed home checkpoint. A second fresh process
with `-- --verify-excursion-resume` verifies that success survives restart without
repeating the trip. The optional `-- --fail-at-library` control halts after a real
outbound trip, to verify that the previous paired home checkpoint is retained;
that controlled failure is expected to exit nonzero. `-- --interrupt-at-library`
exercises an external checkpoint request after arrival: the harness promptly
flushes interruption evidence and halts without an away checkpoint, within the
runner's existing stop grace period. Never run these diagnostic
controls in the maintained playthrough directory.

Pet-care commands prioritize the visible **Bathe the dog** option when the dog's
hygiene is below 35, then **Train Social Skills** while social need is below 45.
Both overrides preserve the paired normal-care cursor. Accepted requests keep
the regular six-hour cadence; if urgent care cannot be attempted because no
caregiver is available or its UI option is unavailable/refused, the harness
rechecks in one game hour without canceling any activity. The household's food
bowl autonomy continues to handle ordinary pet hunger.

Quarter-hour samples include all pet needs, mood and skills. Daily checkpoints
record each need's first/last value, range and mean, plus mood counts. A full
observed day below 15 social or 10 hygiene halts play with evidence; both timers
survive paired restarts. Historical loneliness and dirty-coat observations
remain in the journal.

`test_sustained_social_care.gd` qualifies one full natural day from an isolated
paired home checkpoint, with the excursion option disabled.
`test_sustained_hygiene_priority.gd` uses a dirty-dog home checkpoint and the same
real-frame loop. It stops through the normal checkpoint-request channel only
after an urgent bath materially restores hygiene and a later social lesson
completes. Set the private segment limit to two days; the fixture verifies the
normal cursor and saved hygiene watchdog. Neither fixture changes game state
to manufacture a need or completion.
