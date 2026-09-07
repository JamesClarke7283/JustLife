# JustLife independent quality rubric

Research date: 2026-09-07. Critic: independent agent. Target: an original life simulation with the connected character-creation, home-building, and household-play experience requested by the user. A polished small demo is a milestone, not proof of parity with a large commercial life simulation.

## Reference findings

- **Three connected modes.** EA identifies Create-a-Sim, Build, and Live as the game's three modes. The evaluation must follow a new player through the whole loop rather than assess a furnished screenshot alone. [EA mode overview](https://www.ea.com/en-gb/games/the-sims/cheats)
- **Identity has appearance and behavior.** EA's overview describes physical and clothing customization alongside personality, aspirations, relationships, careers, and player-directed stories. JustLife therefore needs recognizable individual characters and meaningful choices beyond color swaps. [EA ways to play](https://www.ea.com/games/the-sims/the-sims-4/how-to-play-the-sims)
- **Home design is a system.** EA describes customizing buildings, furnishing, landscaping, and locations, with furnished room examples. Placement needs to support the character's life and remain usable after edits. [EA design homes](https://thesims-api.ea.com/game-info/weirder-stories)
- **Character state affects possibilities.** The launch-era official guide describes interactions affected by emotions, traits, and skills; it is useful for foundational mode structure, not a complete account of today's content. [EA player guide](https://cdn-assets-ts4.pulse.ea.com/Guide/TheSims4_Players_Guide.pdf)
- **Progression must have effects.** EA describes trait effects on learning and skill progression with resulting benefits. Skills and ambitions should visibly change outcomes or available actions. [EA skills guide](https://help.ea.com/en/articles/the-sims/the-sims-4/skills/)

The criteria below are the critic's design judgments, informed by those references. They are not claims that every criterion is an exact feature of a particular Sims release. References are for analysis; shipped artwork, characters, branding, and interface expression must be JustLife originals.

## Scoring

Rate each dimension from 1–10, then calculate the weighted mean to one decimal. Report dimension scores and the overall score together; do not conceal weak mechanics with an attractive scene. Mark untested areas **unverified**, never assume they pass. If a score is provisional, state the evidence available and the uncertainty.

| Dimension | Weight | What earns a high score |
|---|---:|---|
| Visual and character quality | 20% | Cohesive original art direction; attractive, legible human anatomy and faces; differentiated hair and outfits; convincing proportions/materials/lighting; furnished interiors with coherent scale; expressive animation and object contact; consistent iconography and interface finish. No clipping or placeholder geometry presented as finished character art. |
| Usability and flow | 15% | Clear title/start/resume; understandable creation with immediate preview; deliberate move-in transition; legible live HUD; discoverable object/social interactions; useful hover/focus feedback; visible action queue with cancellation; camera/pause/speed controls; clear mode changes; accessible contrast/scaling; reliable keyboard/mouse behavior. |
| Simulation and interaction depth | 25% | Needs decay at playable rates and recover through spatially grounded actions; routing and occupancy work; characters animate appropriate actions; traits/emotions/relationships influence decisions and results; autonomy respects player actions; skills/careers/economy create tradeoffs; interacting systems yield varied, explainable stories. |
| Creative breadth and sustained play | 25% | Rich character/body/face/outfit identity; multiple household members; housing and neighborhood choice; a practical build/buy system with rooms/walls/openings and varied usable furnishings; social relationships and progression; enough events/content to sustain several game days. A narrow one-house slice scores on its actual breadth, not future plans. |
| Reliability and delivery | 15% | Clean project import/start; no runtime errors; stable frame pacing at target settings; save/resume retains consequential state; build/live transitions preserve state; blocked/invalid actions fail clearly; UI fits supported resolutions; a runnable artifact plus truthful controls and limitations. |

## Anchors and score constraints

| Score | Meaning |
|---:|---|
| 1–2 | Concept or broken assembly; core loop absent or inaccessible. |
| 3–4 | Working prototype; recognizable genre, severe gaps in presentation, agency, or continuity. |
| 5–6 | Coherent playable slice; multiple meaningful systems work, substantial polish/content gaps remain. |
| 7–8 | Strong game experience; attractive and dependable, with clear remaining limitations relative to the requested breadth. |
| 9 | Exceptional, broadly complete experience with only minor remaining issues and extensive verification. |
| 10 | All requested pillars are convincingly delivered, no material known quality gaps, broad hands-on verification, and an independent final review supports the score. A 10 is not granted because iterations have stopped. |

- A crash or blocked new-game path caps the overall score at 3 until fixed.
- An unusable core mode, or no verified save/resume, caps the overall score at 5.
- Screenshots alone can support visual critique; they cannot establish mechanics, reliability, or a final overall score.
- A starter lot with one character, recolors, needs meters, and timer-based actions remains a prototype even if technically complete as a vertical slice.
- Scope may be reported separately (for example, “starter-house milestone”), but the full-request score must not silently adopt that smaller target.

## Minimum review sequence

1. Start from no save. Create two visibly different character appearances; verify names and behavioral choices persist into play.
2. Complete the move-in flow. Explain the first useful action using only the presented interface.
3. Navigate the lot from several camera angles. Check furniture/walls for visibility, selection, collision, and accessibility.
4. Queue and cancel actions; pause and change speed; perform all available need-recovery actions. Confirm costs, durations, benefits, animation, and route behavior are coherent.
5. Perform social interaction and a progression action. Verify state changes have visible consequences and are not only decorative counters.
6. Enter build mode; buy/place/rotate/move/remove where available, attempt invalid placement, and return to live play. Check funds, routing, and feedback.
7. Run through at least one in-game day for a slice and several days for a high overall score; observe autonomous behavior and competing needs.
8. Save, close, reopen, resume. Compare character, time, funds, needs, relationships, progression, and built objects.
9. Inspect screenshots at the target resolution and one smaller supported window. Check character close-up, live view, build view, and modal/interaction states.
10. Record errors, measured performance where available, untested areas, and the three highest-impact changes for the next iteration.

## Review report template

**Build / evidence / review date:**

**Scores:** visuals _/10; usability _/10; mechanics _/10; breadth _/10; reliability _/10. **Full-request weighted score:** _/10 (or unverified).

**What works:** concrete observations only.

**Required next changes:** prioritize P0 blockers, P1 defects/core gaps, then P2 polish. For each, identify the observed problem, its player impact, and a checkable acceptance condition.

**Verification limits and scope remaining:** explicitly list unplayed or missing parts. Keep screenshots/code evidence distinct from hands-on behavior.

**Decision:** iterate / milestone accepted with limitations / full target met. Never use a milestone acceptance as a claim of full-target completion.
