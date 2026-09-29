extends RefCounted
class_name LifePassingPolicy
## The rules of a casual moment with somebody walking past the home: a wave, a
## hello, a little small talk, a compliment for a dog on a lead, or a hello and
## a pat for a dog trotting by. Pure policy over a `LifeSim`: which moments a
## passer offers, when they are available, what they give and how a Lifelet who
## keeps meeting the same face warms to them. The walking, the passer's pause and
## the conversation's animation live in `LifePassingChat`.

const PERSON_ACTIONS: Array[String] = ["wave_to_passer", "greet_passer", "passing_chat"]
const DOG_TALK: String = "compliment_passer_dog"
const PET_ACTIONS: Array[String] = ["greet_passing_pet", "pet_passing_pet"]
const ALL: Array[String] = ["wave_to_passer", "greet_passer", "passing_chat", "compliment_passer_dog", "greet_passing_pet", "pet_passing_pet"]

## Game minutes before the same passer will chat again, per moment. A wave is
## cheap and comes round sooner than a conversation.
const COOLDOWN: Dictionary = {
	"wave_to_passer": 20.0, "greet_passer": 45.0, "passing_chat": 90.0,
	"compliment_passer_dog": 60.0, "greet_passing_pet": 30.0, "pet_passing_pet": 60.0,
}
## Game minutes between any two passing moments of one Lifelet, so hellos to
## different passers cannot be chained into a free Social meter.
const GAP: float = 6.0
## Each earlier meeting with a face adds this much Social to the next, up to the cap.
const FAMILIAR_STEP: float = 1.5
const FAMILIAR_CAP: float = 6.0
## How many game minutes a Lifelet who is idle outside waits before they may
## start a passing moment on their own again.
const AUTONOMY_WINDOW: float = 20.0
const AUTONOMY_CHANCE: int = 40

const DEFINITIONS: Dictionary = {
	"wave_to_passer": {"label": "Wave hello", "duration": 4.0, "changes": {"social": 5.0, "fun": 2.0}, "skill": "charisma", "xp": 3.0,
		"description": "A friendly wave to somebody walking past."},
	"greet_passer": {"label": "Say hello", "duration": 8.0, "changes": {"social": 10.0, "fun": 3.0}, "skill": "charisma", "xp": 6.0,
		"description": "Call out a hello and pass the time of day."},
	"passing_chat": {"label": "Make small talk", "duration": 16.0, "changes": {"social": 18.0, "fun": 6.0}, "skill": "charisma", "xp": 12.0,
		"description": "Stop for a proper natter about the day. Familiar faces are warmer every time."},
	"compliment_passer_dog": {"label": "Compliment their dog", "duration": 6.0, "changes": {"social": 9.0, "fun": 6.0}, "skill": "charisma", "xp": 5.0,
		"description": "Everybody loves hearing their dog is a good one."},
	"greet_passing_pet": {"label": "Say hello to the dog", "duration": 6.0, "changes": {"social": 5.0, "fun": 8.0}, "skill": "", "xp": 0.0,
		"description": "A hello for a dog trotting past. Expect a wag."},
	"pet_passing_pet": {"label": "Pet the dog", "duration": 10.0, "changes": {"social": 6.0, "fun": 14.0}, "skill": "", "xp": 0.0,
		"description": "A quick pat for a friendly dog on its walk."},
}

## What each kind of passer offers a chat about, so the menu reads like the
## person: the label and hint the shared `passing_chat` action wears.
const TALK_LABELS: Dictionary = {
	"child": {"label": "Ask how school is going", "description": "A friendly word with a neighbourhood child."},
	"teen": {"label": "Ask about their day", "description": "Small talk with a teenager on their way somewhere."},
	"adult": {"label": "Chat about the neighbourhood", "description": "Swap news about the street with a neighbour."},
	"elder": {"label": "Ask for a story", "description": "Long-time neighbours always have a story worth stopping for."},
}


static func define_all(sim: Object) -> void:
	for id: String in ALL:
		var entry: Dictionary = DEFINITIONS[id]
		sim._define(id, str(entry.label), float(entry.duration), (entry.changes as Dictionary).duplicate(), 0, str(entry.skill), float(entry.xp), str(entry.description))


static func entry_for(sim: Object, target_id: String) -> Dictionary:
	for target: Dictionary in sim._targets:
		if str(target.get("id", "")) == target_id and str(target.get("kind", "")) == "passer":
			return target
	return {}


## The moments a passer of this kind offers, in menu order.
static func action_ids(passer_kind: String, walks_dog: bool) -> Array:
	if passer_kind == "pet":
		return PET_ACTIONS.duplicate()
	var ids: Array = PERSON_ACTIONS.duplicate()
	if walks_dog:
		ids.append(DOG_TALK)
	return ids


## The moments a passer's menu lists. A Lifelet indoors has no live target for
## the passer, so the menu is built from the street's cast instead and each
## entry is disabled with the reason.
static func action_ids_for(sim: Object, target_id: String) -> Array:
	var target: Dictionary = entry_for(sim, target_id)
	if not target.is_empty():
		return action_ids(str(target.get("passer_kind", "")), bool(target.get("walks_dog", false)))
	for entry: Dictionary in LifeStreetLife.ROSTER:
		if str(entry.id) == target_id:
			var walks_dog: bool = LifeStreetLife.ROSTER.any(func(other: Dictionary) -> bool: return str(other.get("follows", "")) == target_id)
			return action_ids(str(entry.kind), walks_dog)
	return []


## What kind of passer this is: child, teen, adult, elder or pet.
static func kind_of(sim: Object, target_id: String) -> String:
	var target: Dictionary = entry_for(sim, target_id)
	if not target.is_empty():
		return str(target.get("passer_kind", ""))
	for entry: Dictionary in LifeStreetLife.ROSTER:
		if str(entry.id) == target_id:
			return str(entry.kind)
	return ""


## The label and hint a passer's menu shows for one moment.
static func presentation(id: String, passer_kind: String) -> Dictionary:
	if id == "passing_chat" and TALK_LABELS.has(passer_kind):
		return TALK_LABELS[passer_kind]
	return {}


## Why this Lifelet may not do this with that passer right now, or "".
static func reason(sim: Object, id: String, target_id: String) -> String:
	if str(sim.character.get("age_stage", "")) == "baby":
		return "Babies cannot chat with passers-by yet."
	if sim.is_away():
		return "This Lifelet is away."
	var target: Dictionary = entry_for(sim, target_id)
	if target.is_empty():
		return "Step outside, in sight of the sidewalk, to greet someone passing by."
	var passer_kind: String = str(target.get("passer_kind", ""))
	var name: String = str(target.get("name", "them"))
	if not action_ids(passer_kind, bool(target.get("walks_dog", false))).has(id):
		return "That does not suit somebody who is just passing." if passer_kind != "pet" else "A dog is not one for small talk."
	var now: float = sim._autonomy_now()
	if now - float(sim.last_passing_any) < GAP:
		return "Give the last hello a moment to land."
	var record: Dictionary = sim.passing_contacts.get(target_id, {})
	var wait: float = float(COOLDOWN.get(id, 45.0)) - (now - float(record.get("at", -1e18)))
	if wait > 0.0:
		return "You spoke with %s a little while ago. Try again in about %d minutes." % [name, int(ceil(wait))]
	return ""


## The effects of a finished moment beyond the needs its action already paid
## minute by minute: the meeting is remembered, a familiar face is a little
## warmer, and a kind word leaves a good mood behind.
static func apply(sim: Object, action: Dictionary) -> void:
	var id: String = str(action.get("id", ""))
	var target_id: String = str(action.get("target_id", ""))
	var target: Dictionary = entry_for(sim, target_id)
	var name: String = str(target.get("name", action.get("passer_name", "your neighbour")))
	var record: Dictionary = sim.passing_contacts.get(target_id, {})
	var earlier: int = int(record.get("count", 0))
	var bonus: float = minf(FAMILIAR_CAP, float(earlier) * FAMILIAR_STEP)
	if bonus > 0.0:
		sim.needs["social"] = clampf(float(sim.needs["social"]) + bonus, 0.0, 100.0)
	var now: float = sim._autonomy_now()
	sim.passing_contacts[target_id] = {"at": now, "count": mini(earlier + 1, 1000000)}
	sim.last_passing_any = now
	if id in ["greet_passer", "passing_chat", "compliment_passer_dog"]:
		sim.add_moodlet("A friendly hello", "Happy", "A good word with somebody on the street lifts the day.", 120, 1)
	if bool(action.get("autonomous", false)):
		return
	var first: String = str(sim.character.get("name", "Your Lifelet")).split(" ")[0]
	var line: String = {
		"wave_to_passer": "%s waves and %s waves back.",
		"greet_passer": "%s says hello and %s answers warmly.",
		"passing_chat": "%s stops for a natter with %s.",
		"compliment_passer_dog": "%s compliments the dog and %s beams.",
		"greet_passing_pet": "%s says hello to %s, who wags all over.",
		"pet_passing_pet": "%s gives %s a good pat.",
	}.get(id, "%s has a moment with %s.")
	var suffix: String = " A familiar face by now." if earlier >= 2 else ""
	sim._emit_notice((line % [first, name]) + suffix)


## A Lifelet who is idle outside, low on company and in sight of somebody
## passing, may start a moment on their own. Which one grows with familiarity
## (a wave, then a hello, then small talk); the choice is deterministic for a
## Lifelet, a passer and a stretch of the day, so it is occasional rather than
## constant. Returns a chooser entry or {}.
static func autonomy_choice(sim: Object, excluded_target_ids: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var best_rank: int = -1
	var slot: int = int(floor(sim._autonomy_now() / AUTONOMY_WINDOW))
	for target: Dictionary in sim._targets:
		if str(target.get("kind", "")) != "passer":
			continue
		var target_id: String = str(target.id)
		if excluded_target_ids.has(target_id):
			continue
		var passer_kind: String = str(target.get("passer_kind", ""))
		var count: int = int(sim.passing_contacts.get(target_id, {}).get("count", 0))
		var id: String = "greet_passing_pet" if passer_kind == "pet" else ("wave_to_passer" if count == 0 else ("greet_passer" if count == 1 else "passing_chat"))
		if passer_kind == "pet" and count >= 1:
			id = "pet_passing_pet"
		if not reason(sim, id, target_id).is_empty():
			continue
		var draw: int = abs(("%s|%s|%d" % [sim._social_member_id, target_id, slot]).hash()) % 100
		if draw >= AUTONOMY_CHANCE:
			continue
		var rank: int = 100 - draw
		if rank > best_rank:
			best_rank = rank
			best = {"id": id, "target_id": target_id, "position": target.position}
	return best
