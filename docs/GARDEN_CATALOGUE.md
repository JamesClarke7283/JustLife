# Garden, pool and vehicles

What a household can buy for outside the house, and how one model serves many
choices. Everything here is an ordinary catalogue entry: bought, placed, moved
and sold through the same Build & buy path as an indoor chair, so reach, support,
doorway and wallet checks apply unchanged.

## Money

The household's money is measured in **Lifeons**, written **ℒ** — `ℒ2,500` at
move-in. One name and one symbol live on the palette (`LifePalette.CURRENCY_NAME`,
`LifePalette.CURRENCY_SYMBOL`), so a price is written the same way everywhere it
appears: the HUD purse, the catalogue, a quote card, a refusal, a notice.

The body face carries no script L, so `LifePalette.body_font()` sets the display
face as a fallback on the shared body font. That is one place, on the fonts the
theme and the world labels already use, rather than a per-label override.

## Styles, colours and sizes

A catalogue entry may declare any of three independent variant axes. An entry
with none behaves exactly as it did before variants existed.

| Axis | Key | What it changes | How it is authored |
| --- | --- | --- | --- |
| **Style** | `"styles": ["a","b"]` | The silhouette | One authored model per style: `assets/models/<kind>_<style>.glb` |
| **Colour** | `"tint": true` and/or `"colors": [...]` | The paint | A named `Tint` surface on the model, recoloured at runtime |
| **Size** | `"sizes": ["small","medium","large"]` | The footprint and the scale | The authored mesh, scaled uniformly |

`scripts/catalog_variants.gd` (`LifeCatalogVariants`) owns all of it as pure
static policy. The rules that matter:

* **A style is a different model, not a recolour.** `Variants.model_path(kind, style)`
  resolves `<kind>_<style>.glb`, so two styles are two silhouettes.
* **`Tint` is the recolourable surface.** A colour-variant model authors exactly
  one mesh named `Tint` — a painted trim, cushion, panel or accent that reads
  clearly against the rest of the object. `_apply_variant_colour` overrides that
  surface's material by name, which is the same technique the pet collar uses.
* **`small` is the authored size.** It scales by exactly 1, so an unsized
  furnishing and a `small` one build identically. `medium` is ×1.45, `large` ×2.
* **A size scales the height by the same factor as the footprint**, so a large
  object is the same object made bigger rather than a stretched one.
* **A live furnishing keeps its footprint under `size`** (a `Vector2`, read by
  every placement, seat and approach calculation) and its choice under `variant`.
  The two meanings never collide.
* **Only the axes an entry offers are written to the save**, so an unsized
  furnishing stores no `size` key and two saves describing the same object
  compare equal.

### Pricing

Three shapes, tried in this order by `Variants.price(data, size)`:

1. **`rate_per_square_metre`** — priced from the face it really occupies
   (`footprint.x × height`). This is how a **fence** is sold: `ℒ10` per square
   metre, so a 2 m × 1.2 m panel is `ℒ24` and a large one `ℒ96`, from one rate
   rather than a second price table to keep in step.
2. **`size_prices`** — a stated price per size, which every sized family uses
   because the objective prices them apart (a small pool `ℒ400`, medium `ℒ600`,
   large `ℒ800`).
3. **`price`** — one price, which is also the price of `small`.

Sale value is seven tenths of the price of the size the object actually is
(`main.sale_value`), so a large furnishing sells for more than the small one it
was bought alongside. Home value, and therefore the household bill, reads the
same number.

### Seats

A furnishing's own place count comes from the catalogue: `Variants.seats(data, size)`,
which a sized family states per size. `LifeWorld.seat_capacity(item)` reads it and
`seat_slots(item)` names that many places. A bed keeps its named `left`/`right`
halves, because the intimacy action and the save both name them; every other
multi-seat furnishing numbers its places along its own width. A large garden table
that advertises ten places therefore really seats ten people in turn, rather than
only ever offering its two end places.

## What is on offer

| Family | Kind | Styles | Colours | Sizes |
| --- | --- | --- | --- | --- |
| Post box | `post_box` | — | 10 | — |
| Fence | `fence` | 10 | 10 | 3, at `ℒ10/m²` |
| Path light | `garden_light` | 10 | 10 | — |
| Wall light | `garden_light_wall` | 10 | 10 | — |
| Garden table & chairs with parasol | `garden_table` | — | 10 | 3 (`ℒ50`/`ℒ70`/`ℒ90`; seats 4/8/10) |
| Barbecue | `bbq` | 3 | 10 | 3 (`ℒ100`/`ℒ300`/`ℒ500`) |
| Hot tub | `hot_tub` | 3 | 10 | — (`ℒ300`) |
| Outdoor television | `outdoor_tv` | 3 | 10 | 3 (`ℒ100`/`ℒ200`/`ℒ300`) |
| Garden swing (adults and teens) | `outdoor_swing` | 3 | 10 | 3 (`ℒ100`/`ℒ400`/`ℒ500`; seats 4/5/8) |
| Tree | `tree_garden` | 10 | 10 | 3 (`ℒ100`/`ℒ200`/`ℒ1,000`) |
| Shrub | `shrub` | 20 | 10 | 3 (`ℒ10`/`ℒ15`/`ℒ30`) |
| Flowers | `flowers` | 20 | 10 | 3 (`ℒ10`/`ℒ15`/`ℒ30`) |
| Ready-made garden | `garden_ready` | 4 | 10 | 3 |
| Swimming pool | `pool` | 3 | 10 | 3 (`ℒ400`/`ℒ600`/`ℒ800`) |
| Pool ladder | `pool_ladder` | — | 10 | — (`ℒ20`) |
| Pool slide | `pool_slide` | 3 | 10 | — (`ℒ20`) |
| Rubber ring | `pool_ring` | — | 5 | — (`ℒ5`) |
| Pool noodle float | `pool_noodle` | — | 5 | — (`ℒ5`) |
| Pool light | `pool_light` | — | 10 | — (`ℒ20` each) |
| Kids swing set | `kids_swing` | 3 | 10 | — (`ℒ100`; kids and teens only) |
| Kids sand pit | `sand_pit` | — | 5 | 3 (`ℒ100`/`ℒ300`/`ℒ500`; fits 2/3/5 players) |
| Kids slide | `kids_slide` | — | 5 | — (`ℒ100`) |
| Kids climbing frame | `climbing_frame` | 4 | 5 | — (`ℒ100`) |
| Adult bicycle | `bike_adult` | 4 | 5 | — (`ℒ100`) |
| Kids bicycle | `bike_kids` | 4 | 5 | — (`ℒ50`) |
| Bicycle helmet | `helmet` | 3 | 10 | — (`ℒ20`) |
| Car | `car` | 10 | 10 | 3 (`ℒ200`/`ℒ400`/`ℒ1,500`; seats 5/8/5) |
| Garage | `garage` | 5 | 10 | 3 (`ℒ100`/`ℒ200`/`ℒ500`; holds 2/4/8 cars) |
| Garden games | 50 `game_*` kinds | — | 10 | 3 each |

The **ready-made garden** encodes its own extras as styles: `plain`,
`tree`, `rocks` and `tree_rocks` — the same bordered layout with shrubs and
flowers, a choice of tree, a scatter of rocks in three sizes, or both.

## Buying one

A cell for a family with choices opens a picker rather than placing the first
style straight away. The picker shows the real model, and the picks redraw both
the preview and the price:

* **Style** — one button per style, the current one marked.
* **Size** — one button per size, each stating its own price and, where the
  family seats or holds anything, how many.
* **Colour** — a swatch grid, wrapped at ten per row so a ten-tone palette stays
  inside the panel.

Confirming begins the ordinary placement, so the ghost, the validity check and
the committed record all describe the object the player chose. A withdrawn
item from Storage keeps its style and size, and so does a moved one.

## Using it

Every new furnishing is **usable**, not decoration. `scripts/outdoor_acts.gd`
(`LifeOutdoorActs`) owns what the outdoor objects do:

| Furnishing | Action | Who may |
| --- | --- | --- |
| Pool | Go for a swim (Fitness) | child and up |
| Hot tub | Soak in the hot tub | teen and up |
| Swimming pool noodle, rubber ring, pool slide, pool ladder, pool light | Float, slide, climb or swim in the lit pool (Fitness) | child and up; refused with a reason while no pool stands |
| Kids swing set, kids slide, climbing frame | Play (Fitness, Creativity) | **child and teen exactly** |
| Kids swing set | **Push the children** | teen and up |
| Sand pit | Play in the sand pit (Creativity) | child and up; **play only, never a toilet** |
| Adult garden swing | Sit in the garden swing | teen and up |
| Garden tree, shrub, flowers, ready-made garden | Tend the plants (Gardening) | anyone |
| Garden path light, wall light | Switch the light | anyone |
| Outdoor television | Watch / Watch TV together | anyone |
| Barbecue | Grab a bite / Host a chat | anyone |
| Garden table and chairs | Clear the table / Host a chat | anyone |
| Car, adult bicycle, kids bicycle | Go for a ride (Fitness) | the bicycle's own age band, and only with a helmet |
| Garage | Do freelance work | adult |

**A children's swing is for children and teenagers, and an adult pushes.** The
age band is inclusive at both ends, so teenagers count. Pushing lifts the
pusher's own Fun and their friendship with the child on the swing; playing at the
same furnishing lifts everyone there and the friendship between them.

**A sand pit is for playing in, and never for a toilet.** The simulation refuses
the plant-pot emergency action at a sand pit with a reason naming the rule,
rather than allowing it silently.

Garden games (below) each offer their own single activity; the rest reuse an
action the game already has, so a bought garden table is cleared by exactly the
code that clears a dining table, and a car is driven by the bicycle's own rule.

## Garden games

Fifty games are catalogued, each its own authored model, and each offers one
activity: `scripts/garden_games.gd` (`LifeGardenGames`) owns what each game is,
who may play it and what it builds. Every game shares a single action id
(`play_garden_game`), so the queue, the save and the availability rule stay
single-valued while the placed game supplies the flavour and the skill.

* A game builds its own skill: badminton and the trampoline build **Fitness**,
  checkers and the dartboard build **Logic**, the mud kitchen builds
  **Creativity**, the parachute builds **Charisma**.
* A **child** may play; a **baby** is refused with a reason. The gate reads the
  lifecycle's own stage order, so a stage added there cannot silently lock a
  whole age out of the garden.
* Queuing a game binds the game's own skill and label at that moment, so a save
  taken mid-game remembers which game was actually played.

## The post box

`scripts/mail.gd` (`LifeMail`) owns a household's post. A **post box** placed in
the garden is where it arrives: a bill shows up as a letter carrying its amount
and due day, and reading it settles the bill through the ordinary settlement
path. The household's own days also produce letters — a utilities notice, and
room for school, adoption, pet and birthday letters.

A household with **no** post box lives exactly as it did before: bills arrive by
notice and are paid from the phone. The box adds a place, not a rule.
`LifeHousehold.post_bill` posts one bill at a time, and `post_milestone` writes
one letter per event, so a reload never re-posts the same thing.

## Files

| Path | Purpose |
| --- | --- |
| `scripts/catalog_variants.gd` | `LifeCatalogVariants`: styles, colours, sizes, prices, seats and the stored variant record. Pure static policy. |
| `scripts/garden_games.gd` | `LifeGardenGames`: the fifty games, their gate, their skill and their action. Pure static policy. |
| `scripts/outdoor_acts.gd` | `LifeOutdoorActs`: what the pool, hot tub, children's play equipment, adult swing and the rest actually do, and the two rules that govern them. Pure static policy. |
| `scripts/mail.gd` | `LifeMail`: letters, bills and a post box's save validation. Pure static policy. |
| `scripts/catalog.gd` | The catalogue itself. New families sit under `Garden`, `Pool`, `Kids`, `Outdoor` and `Vehicles`. |
| `tools/create_outdoor_water.py` | Regenerates the pool, hot tub, post box, fences and garden lights. |
| `tools/create_outdoor_garden.py` | Regenerates the barbecue, garden table, outdoor television and swing, and the kids' play equipment. |
| `tools/create_garden_plants.py` | Regenerates the trees, shrubs and flowers. |
| `tools/create_garden_games.py` | Regenerates the fifty garden games. |
| `tools/create_vehicles.py` | Regenerates the cars and garages. |
| `tests/test_pet_care.gd` | Covers the garden games' catalogue, models, gate, skills and placement. |
| `tests/test_garden_catalogue.gd` | Covers the variant axes, pricing, seats and the save record. |
