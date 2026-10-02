# Inviting a neighbor over

From **People**, choose **Invite over** beside a neighbor once any household member has at least 20 friendship with them. Invite at home in Live mode. One invited neighbor can visit at a time. The starter home uses its existing navigation view; inviting does not convert or rebuild saved construction.

The neighbor walks to a clear spot outside the home's actual exterior door. Moving or rebuilding that doorway changes the arrival point. On arrival, the guest card offers **Welcome them in**, and fast simulation slows to normal speed. Your selected Lifelet finishes earlier work, waits beside the doorway while the guest enters, touches the handle to close the door behind them, then shares a short hallway greeting. Only the completed ordinary friendly action earns friendship. A second Lifelet can queue a social interaction during entry; they wait clear of the doorway until the welcome finishes.

A guest waits up to 120 game minutes for the welcome to begin. Arrival and entry have a 180-minute limit. The ordinary visit lasts 360 game minutes after the hallway greeting; **Ask to Stay Over** extends it. Visitors remain selectable as they move or use an activity. A direct social command interrupts an activity when physically safe, while stair crossings retain their shared traversal rules.

**Say goodbye** is available throughout the visit. An active conversation finishes with its ordinary effects; later conversations with the departing guest are canceled while unrelated household instructions remain. A guest upstairs first returns safely to the ground floor, then follows the exit route to the sidewalk. Build mode and household travel wait for that departure. Move a nearby Lifelet in Live mode if they block the route.

Named saves retain the visit phase, host's identified welcome, guest and host routes, hallway greeting, and partly closed front door. Loading a paused save reconstructs those positions and the paid greeting without advancing time or charging again. Validation checks doorway support, body positions, route progress, and conversation ownership before replacing the live household. Older records without the coordinated entrance field retain their original welcome-then-entry sequence, and saves without a guest record still load normally.

Visitors can share household meals; see [guest meals](GUEST_MEALS.md). A visit alone does not make a neighbor a household member. The separate marriage flow handles a resident moving in.

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

