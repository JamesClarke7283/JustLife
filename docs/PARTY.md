# Hosting a party

A party is a small gathering of up to four friends (the neighbors) that runs for up to five game hours. It is built from pieces that already existed: guests who visit together ([several guests at once](HOME_VISITS.md)), the party items in Build & buy (balloons, streamers, a platter and a festive tablecloth), a dish a friend brings (`brought_by` in the meal ledger), the birthday ritual and the party music. This page is the guide to how they fit together.

## Hosting one

Open **People** and press **Host a party…** (it sits between **Family tree** and **Back to life**). The button is grey, with the reason in its tooltip, when a party is already on, when you are not at home in Live mode, when it is before 07:00 or after 22:00, or when no neighbor has 20 friendship with anyone in the household.

The planner card asks:

- **Whose party is it?** A household member, or "No one in particular". A member whose birthday is waiting for its cake comes first, with "birthday" beside the name, and is chosen to begin with.
- **Who to ask.** Each neighbor has an **Invite** box and a **Brings …** box naming the dish the friend would make (Maya a garden fresh salad, Leo a fluffy pancake stack, Priya mushroom soup, Tom herb garden pasta). A neighbor who cannot come is greyed with the reason (under 20 friendship, already visiting, living with you).
- **How long.** One to five hours with a stepper, five to begin with.
- **Lively party music.** On to begin with.

Under the choices the card says how many festive touches the home has (each bunch of balloons, each set of streamers and each table wearing a cloth, on the ground floor) and sums up who is coming. **Send invitations** is greyed, with the reason in the summary line, until at least one friend is ticked.

Hosting costs nothing. Dishes are the friends' own.

## What happens

1. **Sending** writes the party record (below), says "Invitations are out", and starts the friends going. Friends set off six minutes apart, in the order of the list. A friend bringing a dish first spends twenty minutes making it ("Maya is making garden fresh salad to bring.").
2. **Arriving.** Each friend is a *party visit* (`residents.invite_to_party`): they walk to a doorstep place of their own and straight in, with no host greeting. If somebody is standing in the hall and the way in is blocked, the guest waits on the doorstep, the player is told so, and they ask again every second; they go home only after waiting a long time. A friend whose visit cannot start (for example a conversation is in progress) is tried again every five game minutes, up to six times, and then stays away.
3. **The dish.** A friend with a dish holds it in both hands from the door, walks to the party table and sets it down as shared servings: a real batch in the meal ledger on a dining table in a cloth if there is one, else any table with room, with `brought_by` naming the friend and the host as its named cook (every saved dish needs a household cook). Everyone can eat from it.
4. **The party begins** when the first friend is inside. The household gets the **Festive home** mood if the home is decorated. Each guest arriving at a decorated home gains a little fun (5, or 8 with three or more festive touches).
5. **The party.** The friends choose for themselves. Two choices in three are party choices: a hungry friend (hunger under 80) takes a bite from a shared dish or the platter, otherwise they dance round the stereo, each on a place of their own, facing it. The third choice is left to the ordinary visitor choices, so they still chat with the household, sit, play with the pets and use the bathroom when they need to. Needs always come first, as with any visitor.
6. **The end.** At the end time every friend says goodbye and walks out together. **End the party** on the status card calls it off early, and the friends leave two game minutes apart. When the last one has gone the host and the birthday person are six friendship closer to each friend who came (nine when that friend's dish was eaten), the host gets a memory, and with two or more friends the household is left with **Great party**. The party is then forgotten.

While a party is on, **building, travelling and driving lessons wait**, the doorbell stays quiet and an ordinary invitation is refused ("Your party is still on."), even in the first minutes before anyone has arrived. A visitor who is already inside (invited the ordinary way) can stay; the party's own card then sits at the usual place and the visitor's card goes to its left.

### The status card

While a party is on, a **PartyStatus** card sits where the visitor card does (top right). It reads "Party · 2 of 3 guests here · ends 19:00" (or "waiting for 2 friends" before anyone has arrived, "winding down" at the end), says how many festive touches the home has and how many dishes are on the table, and offers **End the party** and a **Music on / Music off** button.

## A party for someone with a birthday

Choose a household member whose birthday is waiting (the default). The birthday's cake is part of the party:

- The family's cake waits for the guests, until every friend who is on the way is inside, or for an hour after the invitations went out at most.
- When the household gathers round the table, each guest inside is given a standing place on the ring round the table (clear, at least 0.6 m from everyone, within 2.6 m of it) and goes to stand there singing. They take the song's own clock from the birthday person, so they sway, hush, and cheer with the family, with ♪ bubbles and the same cheer lines. They stand down when the song ends.
- The layer cake that is set out afterwards is shared with the guests as well (guests choose from any shared dish).

A party for someone with no waiting birthday just names them; they get the same friendship at the end and nothing waits.

## Music

The party loop (`CelebrationAudio.party_loop()`, eight seconds, 124 BPM) plays while the party is active and the host's **Music** button says on. It comes from the stereo when there is a ground-floor one (a 3D speaker named `PartyMusic`, one meter above the stereo, 12 m `unit_size`, so it is louder near the stereo and fades with distance from the camera) and plays flat otherwise. It obeys the **Music** and **Sound** switches, holds still when the household is paused, and the birthday tune outranks it. The game's theme is turned down by volume, never paused. See [audio](AUDIO.md).

## The saved party

`household.party` is `{}` or

```
{version: 1, serial, phase: "inviting" | "active" | "ending", host_id, celebrant_id ("" for no one),
 created_at, started_at, ends_at (absolute game minutes: (day - 1) * 1440 + minutes),
 hours (1 to 5), music (bool),
 guests: [{id, potluck (recipe or ""), status: "preparing" | "walking" | "inside" | "left",
           depart_at, batch (meal id of the set-out dish or ""), brought (bool), came (bool)}]}
```

and `household.party_serial` counts the parties held. Both are written to a save as the optional keys `party` and `party_serial` only once a party has been sent, so an older save loads unchanged and a household that never hosts saves exactly what it did before. A party waiting birthday carries the party's number in the `party_serial` of its `celebrations` entry.

On a load, `LifePartyPlan.validate` checks the record before anything is adopted: the version, a party number no greater than the counter, a known phase, a host and celebrant who are members, times in order, a length greater than zero and at most 300 minutes, one to five hours, no more than four guests, each a neighbor who does not live in the household and appears once, a dish that is an ordinary recipe, a status that agrees with the visits in the save (a friend still preparing or already gone is not visiting; nobody is inside before the party begins; a friend inside has come), and a dish named in a guest's record being in the meal ledger as brought by that friend. The visitor validator (`LifeHomeVisit.validate_saved`) checks the other direction: each party visit is on the party's guest list, has its serial, and goes home no later than the party's end. A save that fails either check is refused without touching the live game.

After a load the party flow finds the record again, rebuilds what is only on the screen (the dishes in friends' hands, the status card, the music) and carries on; the friends' visits, routes, dishes and the birthday gathering come back from their own saves.

## Where the code is

| File | What it does |
| --- | --- |
| `scripts/party_plan.gd` (`LifePartyPlan`) | Pure rules: limits, who can be asked, building and checking the record, the decor lift, the friendship earned. |
| `scripts/party_flow.gd` (`LifePartyFlow`) | The planner card, sending, the friends' arrival, dishes, the guests' party choices, the birthday guests, the music, the status card and the ending. |
| `scripts/party_music.gd` | The party loop's speaker (`stereo_player`), alongside the flat player, under the same rules as before. |
| `scripts/guest_activity.gd` | Guest actions `dance`, `bring_dish`, `eat_party_food` and `sing_birthday`, and the hook that lets the party choose for a guest. |
| `scripts/home_visit.gd` | A party guest held at the door when the way in is blocked. |
| `scripts/household.gd` | The saved party and its validation. |
| `scripts/main.gd` | The People button, the card hook, `party_on()` and the refusals while a party is on. |

Tests: `tests/test_party_hosting.gd` (a visitor suite, run with `python3 tests/run_home_visits.py` or in a plugin-free copy) and `tests/test_party_music.gd`.
