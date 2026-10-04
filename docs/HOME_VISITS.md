# Inviting a neighbor over

From **People**, choose **Invite over** beside a neighbor once any household member has at least 20 friendship with them. Invite at home in Live mode. One invited neighbor can visit at a time. The starter home uses its existing navigation view; inviting does not convert or rebuild saved construction.

The neighbor walks to a clear spot outside the home's actual exterior door. Moving or rebuilding that doorway changes the arrival point. On arrival, the guest card offers **Welcome them in**, and fast simulation slows to normal speed. Your selected Lifelet finishes earlier work, waits beside the doorway while the guest enters, touches the handle to close the door behind them, then shares a short hallway greeting. Only the completed ordinary friendly action earns friendship. A second Lifelet can queue a social interaction during entry; they wait clear of the doorway until the welcome finishes.

A guest waits up to 120 game minutes for the welcome to begin. Arrival and entry have a 180-minute limit. The ordinary visit lasts 360 game minutes after the hallway greeting; **Ask to Stay Over** extends it. Visitors remain selectable as they move or use an activity. A direct social command interrupts an activity when physically safe, while stair crossings retain their shared traversal rules.

**Say goodbye** is available throughout the visit. An active conversation finishes with its ordinary effects; later conversations with the departing guest are canceled while unrelated household instructions remain. A guest upstairs first returns safely to the ground floor, then follows the exit route to the sidewalk. Build mode and household travel wait for that departure. Move a nearby Lifelet in Live mode if they block the route.

Named saves retain the visit phase, host's identified welcome, guest and host routes, hallway greeting, and partly closed front door. Loading a paused save reconstructs those positions and the paid greeting without advancing time or charging again. Validation checks doorway support, body positions, route progress, and conversation ownership before replacing the live household. Older records without the coordinated entrance field retain their original welcome-then-entry sequence, and saves without a guest record still load normally.

Visitors can share household meals; see [guest meals](GUEST_MEALS.md). A visit alone does not make a neighbor a household member. The separate marriage flow handles a resident moving in.

## Several guests at once

An ordinary invitation still allows one neighbor at a time, and nothing about it changed. The code underneath, though, can now hold several guests together, which a party needs. `LifeResidents` keeps `home_visit` as the primary visit, used by the **Invite over** button, the doorbell and dates, and a list `party_visits` of extra `LifeHomeVisit` objects, one for each party guest. Every guest owns their own visit state, route, needs, activity and meal.

How code finds the right guest:

- `visits()` lists the primary visit followed by the party visits. With no party it is just `[home_visit]`, so a loop over it behaves exactly as the old single-guest code did.
- `visit_for(id)` returns the visit that owns that neighbor, and falls back to `home_visit` when nobody does. Anything that acts for "the guest with this id" (the guest's wheel, `Suggest an activity…`, `Come Join Me`, a conversation, the meal and television services) goes through it.
- `any_visit_active()` is true while any guest is here. Build mode, the property panel, household travel and driving lessons wait for it. `party_active()` is true while a party guest is here, and an ordinary invitation and the doorbell wait for that too.
- `guest_ids()` lists the neighbors who are guests, and `reserved_guest_points(except)` lists the ground places the other guests have claimed.

To keep guests from piling up, a visit refuses any standing place within `LifeHomeVisit.GUEST_GAP` (0.85 m) of another guest's claimed doorstep place, place inside, place at the kerb, entrance places or body. Three guests invited together therefore get three different doorstep and room places. A guest also never takes a seat, bed or other place another guest is already using, and a guest with a plate keeps their chair against the others. Television viewing, shared meals, pets and household conversations work for every guest.

**How a party starts a guest (for the party-hosting code).** Call `app.residents.invite_to_party(neighbor_id, party_serial, ends_at)`. `party_serial` is the party's number (a whole number from 1), and `ends_at` is the absolute game minute when that guest goes home, the same clock as `LifeHomeVisit._now()`: `(day - 1) * 1440 + minutes`. A saved party guest's end time can be no more than `LifeHomeVisit.PARTY_MAX_MINUTES` (300) game minutes after the save's own time. The call returns `false`, with the reason shown as a notice, when `party_requirement(id)` refuses (not at home in Live mode, friendship under 20, the neighbor is already a guest or is ringing the doorbell, a trip or conversation is under way, or no clear route). `party_requirement` skips only the one-neighbor rule; every other check of an ordinary invitation applies.

A party guest walks from the kerb to their own doorstep place and then straight in: no host is called, no greeting is queued, and the fast-forward speed is not slowed. Their visit state carries two optional keys, `party` (the serial) and `party_until` (the end time). `stay_deadline()` returns `party_until`, **Ask to Stay Over** is refused, and at that time the guest says goodbye and walks out like any other. To send a party guest home early, call `goodbye(message)` on their visit (`app.residents.visit_for(id).goodbye(...)`); the guest finishes any conversation and walks out the same way. An ordinary visitor who is already inside can join the party instead of being invited again: set both keys on `home_visit.state` and the same rules apply to them. Finished party visits are dropped from `party_visits` at the end of the next residents tick.

**Hosting a party.** The code that starts these guests is [party hosting](PARTY.md): its planner card calls `residents.invite_to_party` for each friend a few minutes apart, writes the household's `party` record (the serial, guest list and end time the visit validator checks against) and watches the visits. Two things in the visits themselves exist for it:

- A party guest who reaches the doorstep is admitted at once, but if the way in is blocked (a household member stands in the hall, or no clear place is left inside) they do **not** go home as an ordinary guest would. They stay on the doorstep, the player is told "Your guest's path is blocked. Move a nearby Lifelet in Live mode so they can pass.", and they ask to come in again every real second. The visit stays in its `arriving` phase until they are through, so a save made while they wait is an ordinary arriving party guest (a saved party guest is never in the `waiting` phase). If they wait more than the arrival limit (180 game minutes) they go home as before.
- While a party is on (`app.party_on()`), the ordinary invitation and the doorbell wait even when no party guest has arrived yet, and building, travel and driving lessons are refused.

The guests' own choices at a party (`dance`, `eat_party_food`, `bring_dish`, `sing_birthday`) are plans in `LifeGuestActivity`: `ALLOWED` lists them, `_choose` asks `party_flow.guest_choose` first for a party guest, and a plan with a `face` (a packed point) stands where the guest is and turns to face it. `dance`, `bring_dish` and the birthday song take only a place to stand, so the stereo and the table stay free for everyone else (`main._activity_resources`).

Named saves keep the primary visit under `home_visit` as before and write the party guests as an array under the optional `residents.party_visits`, one record per guest in the same format (`version`, `next_serial`, `visit`, `doorbell`, `next_bell_serial`). Older saves have no such key and load unchanged. Validation (`LifeHomeVisit.validate_saved`, now a loop over `validate_value`) checks each party record as it checks an ordinary one, and also that:

- a party record has `party` and `party_until`, with the end no earlier than the invitation and no more than five hours after the save's own time, no host greeting or entrance, never the `waiting` phase, and no doorbell caller;
- no neighbor appears twice, and the doorbell caller is not also a party guest;
- when the save holds a household `party` record, each guest matches its `serial`, is on its `guests` list (entries with an `id`) and goes home no later than its `ends_at`;
- guests on managed routes (the stairs) are checked in one journey with the highest counters of all, so two guests cannot share a stair lock or reuse a journey number. At runtime each restore keeps the highest counters seen so far;
- the food ledger accepts plates owned by any saved guest, each tied to that guest's own visit and meal (`LifeMeals.validate` and `validate_actions` take the extra guests as a list after the old single-guest argument, which still works alone).

## Clicking a person: the interaction wheel

Clicking a visitor, a housemate or a neighbor opens a wheel instead of a list. The name sits in the hub with three rings round it, **Social**, **Fun** and **Romantic**, each saying how many of its choices are open. Choosing a ring spreads its choices out; one that is not yet open is greyed, and pointing at it says what unlocks it (for example *Share three successful flirts before asking to become partners*). **Back** returns to the rings. A visitor can be clicked from the moment they set off: **Ask to Stay Over**, **Come Join Me** and **Suggest an activity…** are on the wheel throughout and open once they are inside. Furnishings keep their ordinary menu.

## What a visitor does by themselves

An idle, comfortable visitor chooses from everything the house offers, in an order that turns with each choice so they do not repeat themselves: the pets (petting, or playing when they are short of fun), each member of the household in turn (a baby is played with, a child is joked with or hugged, teenagers and adults are chatted to), the swing, pool and hot tub, the lawn games, the sofas, benches and garden chairs, and a cold drink from the fridge. Being short of fun brings the pets, the garden and the games up the order; being short of company brings the household up. A choice that cannot be carried out hands over to the next, and only when none can does the visitor wander. Needs come first and need no prompting: the toilet, then hand washing, the shower or bath, a meal or a snack, and sleep for a guest who is staying. If the host watches television the visitor joins the same sofa; if the host cooks, one extra portion is made and served to them. **Come Join Me** overrides all of this and places them at the host's own activity: the sofa, the swing, a lawn game, the table.

A visitor who goes into the pool or hot tub changes into swimwear and back into what they came in afterwards; the clothes they arrived in are kept on the visit record, so a paused save restores the same swimmer.

## Asking to stay over

**Ask to Stay Over** is a request, and it can be turned down. A guest accepts when any household member has at least 40 friendship with them, or is their partner; otherwise they thank the host and say they had better head home, and the visit carries on unchanged. A guest who accepts goes looking for a spare bed or the free half of the host's bed, and the visit is extended by twelve game hours.

## Partners and marriage

A friendship becomes a marriage in three gates, each earned by completed actions (never menu clicks):

1. **Partners.** The third successful **Flirt** opens the proposal *Would you like to be my girlfriend / boyfriend / partner?*, worded for the person being asked. Accepting makes you partners.
2. **Dates.** Two completed dates, either away from the lot or by inviting the partner home, open the proposal *Would you like to move in with me and become my wife / husband?*.
3. **Moving in.** On acceptance the proposal is spoken and answered, streamers fall and a short fanfare plays (`wedding_celebration.gd`; the fanfare obeys the sound switch), the spouse takes the surname of the resident whose home they move into, whatever either person's gender, and they join the household as a fully playable member.

