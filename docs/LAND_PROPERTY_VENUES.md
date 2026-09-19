# Land, property, venues and the kitchen

The systems this covers are the household's *place* in the world: the ground it
owns, the houses it lives in, the places it travels to, and the food it keeps in.
Each is a small pure-policy module plus state the household owns, so a save
resumes them exactly and a panel and a refusal always agree.

## The lot: `LifeLand`

The household's land is a rectangle that grows one bought plot at a time, west,
east and north. The frontage is the street and is not for sale, so the sidewalk,
the doorstep and every walk to the lot exit stay put.

- `LifeLand.BASE` is the starting plot; `rect(state)` is the whole lot.
- `PLOT_WIDTH` and `PLOT_DEPTH` are what one plot measures on a side.
- `price(state, side)` rises with each plot bought on that side, so land gets
  dearer the further out it is. `MAX_PLOTS_PER_SIDE` is far beyond any
  household's means, so the lot is effectively unlimited.
- `offers(state, funds)` and `purchase_error(state, side, funds)` are what the
  panel reads, and `purchase(state, side, funds)` is what it calls.
- `validate(value)` refuses a corrupt record before a navigation grid is built
  from it.

`LifeBuildingState.land` holds the live record and `LifeBuildingState.lot()` is
the one lot every dependent system reads — the building rules, the navigation
graph, the compatibility grid, the camera pan and the garden dressing. Buying a
plot therefore moves the boundary for all of them at once.

`LifeBuildTransactions.buy_land(side)` is the transaction: it prices the plot,
redraws the ground, rebuilds the graph, and charges the purse only if all of that
succeeded.

## Houses: `LifeProperties`

A household owns a set of homes rather than one.

- `TYPES` holds the five kinds of house. Three are free starters (`willow`,
  `sage`, `canvas`); two are bought (`rowan` with two real bedrooms, `juniper`
  with four). Each names a `LifeCatalog.starter_layout` index.
- `houses(state)` and `active(state)` are what the household owns and which one
  it lives in. `move_cost` is the house's price when it is not owned yet, plus
  `MOVING_FEE`; `move_into(...)` applies it.
- **Insurance is per house.** `POLICIES` holds the standard policy and a premium
  one that pays back more than was lost. `policy(state, house_id)`,
  `buy_policy(...)` and `cancel_policy(...)` are the record; the cover in force
  follows the house being lived in.
- `validate(value)` refuses an unknown house or policy, and an active house the
  household does not own.

The property record rides the world state beside the land. `_properties_for_save`
writes the live home's layout and land into its own record first, so moving away
and back returns to the same house on the same plot. `_apply_property_insurance`
mirrors the live house's policy onto the sims, and the household raises
`insurance_changed` so cover bought through the phone is written through to the
house's own record rather than living in two places.

## Venues: `LifeVenues`

The town's working places, joined to `LifeNeighborhood`'s originals so the travel
picker, the world builder, the save validator and the sanitation ledger treat a
café exactly as they treat a library.

- `PLACES` holds the new eight: `cafe`, `hairdresser`, `shopping_centre`,
  `gymnasium`, `petrol_station`, `school`, `university` and `prison`.
- `layout(place)` is built from existing catalogue furniture only, so no venue
  invents a model; `offers(place)` is the service list a panel shows.
- `LifeNeighborhood.places()`, `has(place)`, `info(place)`, `place_name(place)`,
  `is_venue(place)` and `travel_ids()` are the resolving accessors every caller
  uses instead of the raw `PLACES` table.
- `LifeApp.show_venue_services(place)` lists a venue's services on arrival and
  routes the ones with a real effect — a workout builds Fitness, a coffee feeds a
  Lifelet, the weekly shop opens the grocery order — to the system that owns them.

Two catalogue entries were added for the brief: `car_electric` and the
wall-mounted `electric_charger`, which names the car it charges and must be
placed against a wall. Both models were authored to the same contract as the
existing vehicles: one joined `Tint` surface and ground contact at y = 0.

## The kitchen: `LifeGroceries`

The fridge no longer sells food. Cooking and snacking take a meal *out of the
kitchen*, and the kitchen is restocked by ordering a delivery from the computer.

- `fresh()` holds `{stock, order}`: what is in the fridge in meals, and the
  delivery on its way.
- `BASKETS` are the three sizes. `order(state, basket, funds, day, minutes)`
  prices one, and an order placed after `LAST_ORDER_MINUTE` arrives tomorrow.
- `arrival_due(state, day, minutes)` and `collect(state)` are the van's side;
  `take_meal(state)` is what cooking calls.
- `validate(value)` refuses an impossible stock or an unknown basket.

The household owns the record, runs `_grocery_tick()` on its own clock, and
hands itself to each member as `grocery_service`, which is what the stove's menu,
the cook gate and the availability check read.

## The prison: sentences and visits

Being caught is not a fine with a note attached. `LifeSim.serve_sentence(fine, days)`
fines the purse from what it holds, records the arrest, and takes the Lifelet to
Blackmoor through the same away machinery the school run and the commute use.

- `is_imprisoned()` is whether a sentence is running; `is_at_prison()` is whether
  the Lifelet is *there* rather than serving the sentence from home.
- A Lifelet already away when caught cannot hold two absences at once, so the
  sentence is served from home and `criminal_record.serving_at_home` records it.
  The record is otherwise identical.
- `prison_away_state()` is the absence, whose `return_day` is the record's own
  `prison_until_day`, so the HUD and the record cannot disagree.
- The household's `_prison_release_tick()` runs on the shared clock and calls
  `prison_check()`, so a sentence really ends and the Lifelet comes home.

The prison's visiting desk (`LifeVenues.offers("prison")`) offers a family visit,
a parcel handed in, and meeting them at the gate. A visit really meets the
visitor's social need and leaves the family member inside feeling better and
remembering who came; all three are refused with a reason when nobody from the
household is serving.

A saved sentence is validated by `_validate_prison_away_state`: the record must
be valid, must not claim to be served at home and away at once, and the
absence's release day must agree with the record's.

## Save validation

Each record validates on load, before anything is adopted:

| Field | Validator | Refuses |
| --- | --- | --- |
| `land` | `LifeLand.validate` | a negative or impossible plot count, an unknown version, a lot too small or too large |
| `properties` | `LifeProperties.validate` | an unknown house or policy, living in a house that is not owned |
| `venue` | `LifeNeighborhood.has` | a place the town does not have |
| `groceries` | `LifeGroceries.validate` | an impossible stock, an unknown basket, an impossible delivery time |
| `business` | `LifeBusiness.validate_owned` | an unknown business, an employee hired twice, more staff than there is room for |

`LifeJourneyState.validate` checks the land and applies it *before* any layout is
judged, because a layout saved on a bought plot cannot be validated against the
starting plot.

## Tests

| Suite | Proves |
| --- | --- |
| `tests/test_land.gd` | buying plots, growing walkable ground, the hedge moving, the price rising, a refusal costing nothing, and a real save and load |
| `tests/test_properties.gd` | choosing the start house, buying and moving into the largest, premium cover, moving back, the panel rows, and saving both homes and both policies |
| `tests/test_room_extension.gd` | adding rooms, sharing a wall between two rooms, breaking it to merge them, cutting a doorway, extending onto bought land |
| `tests/test_venues.gd` | every venue valid with real services, sixteen places reachable, seven travelled to and built and walkable, a venue visit saved and resumed |
| `tests/test_groceries.gd` | the empty kitchen refusing a meal, the panel ordering, the purse paying once, the van arriving on the household clock, and the save |
| `tests/test_business.gd` | the level-9 bar, the two price points, buying, hiring raising the takings, the daily income and the save |
| `tests/test_education_degrees.gd` | the Bachelors/Masters/PHD ladder, the fees, the Dr title on the profile, pay rising with a degree but never past ℒ1,000, and the save |
| `tests/test_prison.gd` | being caught really taking a Lifelet to Blackmoor, the HUD and the job refusal, a real family visit, the release arriving on the household clock, a Lifelet caught while away serving from home, and the sentence's save record |
