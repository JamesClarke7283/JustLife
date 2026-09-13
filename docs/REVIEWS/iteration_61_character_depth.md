# Iteration 61 — rounded hair, sealed shells, a spendable reward store

13 September 2026. Build from the working tree at `3b0aef5` plus this iteration's
changes. Reviewed with the headless suites, an independent full-game critic, and
rendered captures from the real game and from Blender.

| Dimension | Weight | Iteration 60 | Iteration 61 | Basis |
|---|---:|---:|---:|---|
| Visual and character quality | 20% | 8.0 (own) / 6.5 (critic) | 6.5 → 7.0 | 36 flat plank locks re-sectioned to rounded cords and 12 zero-thickness shells closed in all four families; the eyes, lips and hands remain unfinished at close range |
| Usability and flow | 15% | 8.0 / 7.5 | 7.5 | Creator, live HUD, build catalogue, reward store and every panel render cleanly with good contrast; unchanged from the critic's 7.5 |
| Simulation and interaction depth | 25% | 8.3 / 8.0 | 8.0 → 8.3 | A spendable eight-reward store, five emotion-gated and six trait-gated interactions with real effects |
| Creative breadth and sustained play | 25% | 8.0 / 7.0 | 7.0 | Unchanged breadth at the far end of a life: 3 recipes, one neighbourhood, no death or inheritance |
| Reliability and delivery | 15% | 8.2 / 6.0 | 6.0 → 6.7 | The shipped tree's own suite battery went from 4 failures to 0 on this iteration's regression; the rendered runners still fail on this hardware and the frame budget is unqualified below the verified desktop |

**Independent critic score on the pre-fix tree: 7.1/10.** The critic put visuals at
6.5 against the project's own 8.0. Its dimension split is the number to trust;
the visual and reliability movement above is this iteration's claim, not a
re-scored independent result. The 10/10 target remains open.

## What changed

### Rounded hair sections and sealed shells (`tools/hair_lock_v61/`)

Two measured defects in the qualified v60 hair:

- **Flat planks.** v60 measures each lock's root-ring aspect (depth/width) and
  holds that ratio constant down the whole strand. The measured median
  depth/width was **0.505**, so every lock read as a plank in profile and the
  free length had no volume. v61 keeps the authored root aspect — roots must
  stay flat against the scalp — and ramps the section toward circular along the
  lock while holding the cross-section *area* constant, so mass is unchanged.
  Measured after: median **0.608**, with the middle and free length of every
  lock at 1.00 (fully round).
- **Zero-thickness sheets.** Twelve shells were open surfaces with no SOLIDIFY
  modifier. glTF materials are single-sided, so Godot culls their back faces and
  the inside of the garment shows through. This is the origin of the
  collar/shoulder sliver that iteration 60 recorded, and of hair that reads as
  see-through against a background. Each now has a closed 7 mm shell inserted
  before the armature, so the finished closed surface is what deforms. The
  hoodie hood went from 392 to 784 exported vertices, exactly doubling as a
  closed shell should.

Sealing is chosen by material because thickness must match the surface's scale:
`Hair` is the main shell and is sealed, while `Hair_highlight` ribbons are 3–6 mm
decorative strips (`Hair_Bob_Strand` is 3 mm thick) that a 7 mm shell would
double, so they are left alone.

Ownership is declared and asserted. Per family exactly 48 objects change: the 36
locks and the 12 shells. Every other object (412 in adult/child/teen, 420 in
elder) is byte-compared before and after across geometry, UVs, weights, shape
keys, modifiers, transforms, materials and visibility.

The decoded glTF contract is asserted per family against that family's own
qualified baseline, so face identity cannot drift silently:

| Family | Primitives | Morph primitives | Materials | Morph targets |
| --- | ---: | ---: | ---: | ---: |
| adult | 430 | 30 | 20 | 9 |
| child | 430 | 28 | 20 | 9 |
| teen | 430 | 28 | 20 | 9 |
| elder | 438 | 36 | 21 | 9 |

All nine morph target names survive in all sixteen variants, and the lock and cap
nodes survive LOD decimation. Character GLBs grow about 3.6% (adult 16.7 MB →
17.3 MB).

### A spendable reward store

Satisfaction accumulated from completed wants and story choices, was displayed
twice, and was never decremented. It now buys eight rewards: five permanent
perks (Steel Bladder, Hardy Constitution, Great Kisser, Connections, Carefree)
that scale the same need-decay and skill/performance multipliers the traits
already use, plus three one-use potions (Instant Meal, Rejuvenating Soak,
Inspiring Presence). `available_rewards()`, `can_buy_reward(id, reason)` and
`buy_reward(id)` sit beside the existing action registry; `purchased_perks` is
saved, restored and validated (an unknown id, a non-permanent reward or a
duplicate id rejects the whole save rather than loading a corrupt one). The
**Rewards** button sits beside Wishes on the bottom bar.

### Emotion-gated and trait-gated interactions

Five interactions are offered only in the right emotion — *Paint a masterpiece*
while Inspired (sells for `130 + 60 × creativity level`, ×1.5 while Inspired),
*Study hard* while Focused, *Push through* while Energized, *Bold introduction*
while Confident, and *Playful prank* while Playful, which can backfire into the
Tense moodlet below 30 friendship. Each of the six traits unlocks one action of
its own: Creative sketches, Outgoing hosts a chat that lifts the room, Active
takes a morning run from the lot exit, Bookworm deep-reads, Foodie experiments
with a recipe, Neat deep-cleans. Gating happens in `get_action_availability()`
before the target rules and is re-checked in `begin_current_action()`, so the
interaction is absent for everyone else and refused with a reason if forced.

## The regression this iteration introduced, and its fix

The critic found the shipped tree's own suite battery was red. Chasing it found
the cause: the systems work had **halved the recipe costs** (25/32/52 → 12/16/24)
and the snack cost (8 → 4) without that being asked for, then updated two of the
four affected assertions. `tests/test_household.gd` was left part-migrated
(2496 updated, 2637/2602 not) and `test_simulation.gd` likewise.

Both the price change and the test edits were reverted, because the request was
to add a reward store and gated interactions, not to rebalance the economy:

| Suite | Before the fix | After |
| --- | --- | --- |
| `test_household` | 20 assertions, 4 failures | 20 assertions, 0 failures |
| `test_simulation` | 51 assertions, 1 failure | 51 assertions, 0 failures |

The reward store and gated interactions are unaffected by the revert and remain
green (`test_depth_v61` 98 checks, 0 failures).

## Verification at this revision

| Suite | Result |
|---|---|
| `test_depth_v61` (new) | 98 checks, 0 failures |
| `test_household` | 20 assertions, 0 failures |
| `test_simulation` | 51 assertions, 0 failures |
| `test_actor` | 612 checks, 0 failures |
| `test_autonomy_policy` | 167 checks, 0 failures |
| `test_career_day` | 89 checks, 0 failures |
| `test_story` | 88 checks, 0 failures |
| `test_education` | 67 checks, 0 failures |
| `test_school_integration` | 64 checks, 0 failures |
| `test_actor_grip` | 60 checks, 0 failures |
| `test_make_baby` | 53 checks, 0 failures |
| `test_baby_stage` | 51 checks, 0 failures |
| `test_progression` | 16 assertions, 0 failures |
| `test_save_library` | 36 checks, 0 failures |
| `test_living_v60` | 35 checks, 0 failures |
| `test_household_extras` | 26 checks, 0 failures |
| `test_hygiene_putaway` | 15 checks, 0 failures |
| `test_shared_bed` | 7 checks, 0 failures |
| `tests/probe_character61.gd` (rendered) | 4 checks, 0 failures, 27 captures |
| `tools/verify_character_exports.py` | VERIFY_OK on the re-qualified adult PINS |
| `test_relationships` | 41 checks, 1 failure — **pre-existing**, reproduced identically on a pristine `git archive HEAD` copy |

## Retained failures and limits

- **The rendered home and neighbourhood runners do not pass on this machine.**
  `python3 tests/run_playthrough.py --source . --suite home` reports 210
  assertions / 24 failures, and `--suite neighborhood` 239 assertions / 15
  failures, on this Intel HD 520 desktop. They fail identically on a pristine
  `3b0aef5` export, so this is environmental, not an iteration-61 regression. The
  dominant cause is `Input.warp_mouse` not reaching the requested coordinates
  (observation distance ~450 px with a 1876×900 viewport against a requested
  ~898), so the iteration-60 table's "exit 0, 0 runtime errors" describes the
  RTX 5090 machine this project was verified on, not this one. The project's
  documented 1440×900 override was not reproduced by the runner.
- **The frame budget is unqualified below the verified desktop.** `probe_frames`
  on this Intel HD 520 reads p50 70.8 ms / p95 104.2 ms uncapped, against the
  iteration-60 reading of p50 6.2 / p95 8.3 ms on an RTX 5090. This is
  hardware-conditioned; the README already says other graphics hardware has not
  been qualified, and this number belongs beside that statement.
- **The character close-up is still not finished art.** Eyes are flat elliptical
  irises on a spherical sclera with a hard skin boundary and no upper-lid crease,
  lash line or tear duct; the lips have no philtrum, vermilion border or cupid's
  bow; and the hands are a fused paddle with no separated digits in the exported
  GLB (`Hand_Grip_L/R` morphs sit on an arm-fill mesh). The creator's Face tab
  zooms straight into the weakest surface. Hair — the largest of these — is now
  fixed; the rest remain.
- **Breadth at the far end of a life.** Three recipes, one neighbourhood with
  four homes, and no death, inheritance, fears or whims. Households can grow but
  never shrink or end.
- No unscripted multi-day save was played by hand; behaviour is covered by
  directed public-callback suites. Audio was unverified (all runs used
  `--audio-driver Dummy`). No 960×600 window was inspected.

## Decision: iterate

10/10 remains open. The largest honest gaps are the character close-up (eyes,
lips, hands), the far-end breadth of a life, and the fact that the 33 ms frame
budget has only ever been demonstrated on one machine.
