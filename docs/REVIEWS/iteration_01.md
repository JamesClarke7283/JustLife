# JustLife independent review — iteration 01

Date: 7 September 2026. Evidence: actual Godot 1440 × 900 captures at art/screenshots/creator.png, live.png and build.png; current main.gd, world.gd, catalog.gd and life_sim.gd source; simulation API documentation. The simulation agent reports 45 stateful assertions passing. This critic has **not yet personally played the integration**, measured frame pacing or performed a close/reopen save test.

## Scores against the full user objective

| Dimension | Score | Evidence and limitation |
|---|---:|---|
| Visual and character quality | 6.5/10 | Cohesive original cream/teal palette, readable furnished house, real object thumbnails, good broad proportions. Close-up Lifelet still has visible assembled joints, protruding eye-corner rims, trouser seams and largely neutral face. Motion unverified. |
| Usability and flow | 6/10 provisional | Clear three-stage creation/home/live progression, strong selected-state styling, legible primary actions, recognizable mode tabs, contextual interactions and queue implementation. Small secondary text, semantic problems in home selection and potential long-queue overflow remain. Actual interaction behavior unverified. |
| Simulation and depth | 4/10 provisional | Source implements gradual needs, spatial approach, actions/queue, five skills, traits affecting rates, two persistent relationship records, wants, bills and career advancement. Main world provides pathing and procedural activity poses. Only one controlled person, limited combined interactions and no hands-on concurrency/contact proof. |
| Breadth and sustained play | 3/10 | One house structure, two materially identical furnished home selections, twenty furnishing types, limited creation with recolors, two static-location neighbors, one career track. No household creation/switching, wall drawing, broad family progression or travel. |
| Reliability and delivery | Unverified; 5/10 working estimate | Actual runtime screenshots and reported model/simulation validation establish basic execution, not reliable user flow. Save serialization is present; integration close/reopen, renderer errors, placement recovery and sustained play still need independent verification. |

**Final overall score: unverified. Evidence-limited working estimate: 4.7/10**, using 6.5 / 6 / 4 / 3 / 5 with the rubric's weights. This estimate is not a certified overall score. The absence of an independently verified save/resume also imposes the rubric's maximum of 5 until tested. A good-looking starter-house milestone does not satisfy the requested full Sims-like breadth.

## What works

The game is recognizable as a life simulation, with an original identity. The house includes coherent room zones, cutaway walls/windows, furnished bedroom/bathroom/kitchen/living room and a garden context. Build catalog cards show the actual art, price and category. The active appearance is consistent between the creator and portrait. Creator primary controls have useful visual hierarchy and preview prominence.

The underlying engine is more than decorative meters: actions have durations and partial effects, queue/approach/active phases, ingredient cost, trait modifiers, skills and persistent social progression. Build placement/move/sale/undo and save APIs exist in source. These are concrete foundations, although still unverified through the final UI.

## Required next changes

### P1 — Fix home-selection meaning and make choices real

Observed in source: the move-in card says “ℒ2,500 to make it yours,” but starting the household leaves ℒ2,500 available. Fresh Canvas displays ℒ4,500 and leaves ℒ4,500. Those amounts are spending money, not purchase prices. Also Willow Cottage and Sage House both call the same furnished starter_layout; only lot 2 differs.

Impact: players cannot reason about affordability and are offered a home choice with no visible consequence.

Acceptance: show an unambiguous post-move household balance (or explicit starting funds, price and balance); give the second furnished option a genuinely distinct layout/style. Capture all choices and verify the shown balance matches live funds.

### P1 — Verify and correct grounded activity before adding breadth

Only idle live/build frames are available. The source uses a shared approach point and rotates toward object centers; sitting and lying alignment are known approximate. Empty paths cancel actions, and build changes can alter a queued target.

Impact: the core “click an object and see a person use it” promise fails if actors float, clip, face away, walk through furniture, or remain indefinitely in approach.

Acceptance: capture and play cooking, eating, sleeping, showering, toilet, TV/sofa, reading, painting, desk work and conversation. For each, check arrival, orientation, hand/body contact, gradual benefits and exit. Move/sell a queued target and surround one with blocking furniture; the action must fail clearly or recover. Test pause and every speed during both travel and activity.

### P1 — Provide bounded queue and persistent speed feedback

Source creates one unbounded HBox of up to eight label buttons in an 830-pixel region. Labels such as “Have a heartfelt talk” are much wider than the 110-pixel minimum. No scrolling/width constraint is present. The idle screenshots do not show this state. Pause is readable in text, while speed buttons have no visible selected state.

Impact: a normal filled queue risks covering controls or leaving the window; users cannot always tell which speed is selected.

Acceptance: queue eight mixed long-name activities at target and smaller window sizes, keep all cancellations reachable and all HUD controls visible; mark current speed persistently.

### P2 — Improve first live framing and instruction placement

The active Lifelet is approximately 65 pixels tall in the opening view, and a front tree/plant competes with their silhouette. The wide notification overlays the kitchen/fridge region while instructing players to click furniture. The notification does expire after 5.5 seconds in source, which limits the obstruction.

Acceptance: slightly closer default live camera or first-action focus; keep the active silhouette unobstructed and a context instruction small enough that the demonstrated object remains visible. Retain an easy whole-lot view.

### P2 — Resolve conspicuous creator rendering seams

The creator shows pronounced shoulder/cuff separations, wrist joins, a horizontal trouser yoke seam and knee material/shape discontinuity. The face's eyelid rims project at corners, and the hard long shadow makes the model look like a display mannequin. Character-only art progressed from 4 → 5.5 → 6/10 across reviewed sculpt iterations; integration should preserve improvements.

Acceptance: show front, three-quarter, side and rotated views under softer creator lighting; remove visibly floating rims and mechanical-looking garment/joint breaks. Add at least two distinct outfit silhouettes and show two meaningfully different faces/bodies before claiming robust creation.

### P2 — Make progression legible beyond counts

The skills tab shows level only; the career tab shows level/pay and a work button without a visible performance meter, schedule or next requirement. Code contains partial progress that the UI could expose.

Acceptance: show progress to the next skill/career milestone, explain the source of mood and trait effects, and make completed aspiration rewards useful rather than a disconnected score.

## Scope and next review evidence

The most consequential scope gaps are multiple controlled household members, editable structures/openings, genuinely differentiated identity/outfits, longer social/family progression and neighborhood travel. They cannot be erased by visual polish. Current graphics do not merit a 10, and known missing pillars prevent an overall 10.

Next review needs: two distinct created Lifelets, all lot choices, active object/social frames, full queue, a changed house, small-window view, one simulated day, and a save/reopen comparison of appearance/time/funds/needs/relationships/skills/build objects. Technical reviewer results can support this evidence but do not replace hands-on behavior.

**Decision: iterate.** The visual starter-house milestone is promising and reviewable. Full user objective remains substantially incomplete.
