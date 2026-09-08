# JustLife independent review — neighborhood checkpoint

Review date: 8 September 2026. This is the frozen pre-menu, pre-rig checkpoint at `/tmp/justlife-playthrough-wr8aejl2`, not the later shared project. Source hashes, thirty actual renderer PNGs, both state reports and full logs are preserved in `art/screenshots/neighborhood_iteration_03_initial/`. Later fixes are reported as pending verification rather than silently included in this score.

## Full-request score: 6.3 / 10

| Dimension | Score | Evidence and limit |
|---|---:|---|
| Visual and character quality | 6.5 | The park, library and studio are distinct furnished spaces with a consistent original palette. The rendered characters still use the older segmented assets; ceiling beams obscure active characters in close views. |
| Usability and flow | 6.0 | The illustrated map, daily decisions and persistent speed selection work. Eight-person chips overlap in both creator and live mode; description text overflows the map and clips in Stories. |
| Simulation and interaction depth | 6.5 | Real routed public-lot actions improve needs/skills; travel consumes time; a daily choice changes the shared wallet, individual needs, skill XP and friendship without replacing the player's queue. Much activity presentation still looks like a standing timed pose. |
| Creative breadth and sustained play | 6.0 | Eight individually created playable Lifelets, four locations including home, persistent remodeling, daily choices and aspirations broaden the loop. Family/aging, substantial identity/furnishing variety and deeper careers/social outcomes remain major limits. |
| Reliability and delivery | 6.5 | All away-save and exact household-position comparisons pass after a fresh process restart. Measured frame pacing in this run was slow and needs a controlled follow-up. Three UI-fit assertions fail. |

The weighted mean is 6.3. This is meaningful progress beyond the single-house loop, but the full requested experience remains incomplete. A subsequently staged character render is not evidence that those assets work in this executable checkpoint.

## Rendered verification

Godot 4.7.2 used the actual Forward+ renderer at 1440 × 900. The isolated project contains no editor addons, autoload or registry connection, and writes only to private temporary userdata. Gameplay proceeds through real frames; the harness does not teleport Lifelets, call simulation tick directly or fake action arrival. Public button signals exercise production callbacks, while furnishing and room placement use actual mouse input. This does not certify physical hit testing for every button.

The run made **304 assertions: 301 passed and 3 failed**. The three failures were the same confirmed household-chip overlap in creator, live mode and returned-home mode. Their intentional `push_error` messages are the only error lines in the two runtime logs; there were no independent script exceptions or engine failures.

- Created eight distinct named Lifelets through the public creator, selected hair/body/color variations, confirmed the ninth-member control is disabled, moved into Willow Cottage, and selected each household member individually. Three true outfit silhouettes were not exercised in this frozen run.
- All four speed controls applied the correct household-wide rate and had a persistent selected state. Most evidence captures deliberately pause the simulation for legibility; the four speed-state assertions inspect the selection before that pause. The next harness version preserves speed for those four images.
- Purchased a plant with a valid mouse placement, rejected an overlap without charging, drew a four-wall room/floor and doorway, rejected overlapping construction, and changed the finish. The complete serialized remodel became the home-restoration checkpoint.
- Queued an activity at home, then used Explore to travel to Juniper Gardens. Travel cleared prior orders exactly as the map describes, advanced fifteen game minutes, applied need decay, charged no hidden fare, and brought all eight household members. The bench activity completed after real walking.
- Travelled to The Reading Room, verified town build mode is refused, and completed reading after real routing. Logic progress persisted. Travelled to Common Ground Studio, selected the eighth Lifelet and inspected the map at an actual 1120 × 700 window.
- Allowed actual accelerated simulation to reach Day 2. The first daily event appeared in Stories. Choosing “Bring a homemade dish” charged §24, restored Hunger/Social by the displayed values, added 20 Cooking XP and 14 Maya friendship, consumed the event once and recorded its choice history. Opening/choosing the story preserved the pending painting action and did not advance the paused clock.
- Walked to the studio easel and began painting, paying §20 on arrival. Queued reading afterward and saved while away. A fresh process resumed in the actual studio with the eighth Lifelet selected, preserving all eight identities, needs, skills, relationships and actual positions, the active action's progress/payment and the following action. Resuming did not charge painting materials again.
- Travelled home after restart. Every saved furnishing, wall, floor and doorway plus the selected finish matched the original remodel. The consumed daily story remained consumed and its recorded choice survived.

The eight-person test disables autonomy to make selection, travel and persistence comparisons deterministic. It does not establish eight-person autonomous crowd behavior. The earlier two-person review separately verified overnight autonomy.

## Required next changes

### P1 — Confirm UI bounds after minimum-size fixes

All eight chips are individually discoverable but their themed minimum width exceeds their assigned spacing, causing overlap. Map descriptions run through the right-hand card and beyond the window; the story description is cut off by its scroll region. These are directly observed defects, not just screenshot preferences. Parent reports fixes that reapply chip size after compact styling and set wrapping before assigning text. Rerun the same bounds checks and inspect creator/map/Stories at both window sizes before closing these findings.

### P1 — Expose the activity through the cutaway view

In `05_library_reading.png` a structural ceiling beam crosses directly in front of the reading Lifelet; in `10_studio_painting_before_away_save.png` it blocks the painter's head, arm and part of the easel. The interaction needs to remain visible while using the normal focus camera. Fade or cut away obstructing ceiling structure as is already done for foreground trees. Current queue cards also use dark text over translucent dark backgrounds; raise their text/background contrast and keep the separate cancel symbol readable.

### P1 — Integrate and assess the character rig through real activities

The old body joints are still conspicuous. Library reading appears to be standing at a bookshelf with a repeated gesture; the early bench capture is only partly seated. The latter is not yet classified as a confirmed anchor bug because it was captured early in its transition. The next run captures later in activity progress and must use the new rig for sit, sleep, read, paint, cooking and conversation. Assess face proportions, clothing deformation and visible hand/object contact in the actual game, not only a studio render.

### P2 — Measure a quiet eight-person session

After twenty warm-up frames, sixty idle frames averaged **58.7 ms** with **80.2 ms at the 95th percentile** (about 17 frames/s by the mean) on the available RTX 5090 machine. Other agents were concurrently rendering and the old character assets were active, so this is not a controlled hardware benchmark or a diagnosis. Repeat after LOD/rig promotion without competing renders, then profile CPU/GPU work if the slowdown remains. An eight-person cap should be supported by acceptable observed pacing.

## Limits and decision

This verifies one home, three public venues, one daily choice, one away-save cycle and eight-player selection. It does not verify every story branch, multi-day progression/economy, all careers/relationships, family/aging, all construction combinations, audio, release packaging, every UI hit target or stable performance on other devices. The map's smaller-window screenshot confirms the same fixed composition scales to 1120 × 700; it does not establish that all resulting small text is comfortable to read.

The next checkpoint adds the requested main menu and named-save picker with delete confirmation. Those screens were absent from this frozen run and require their own lifecycle checks. **Neighborhood milestone accepted with material UI, presentation and performance limits; continue iteration.**
