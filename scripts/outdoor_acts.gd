extends RefCounted
class_name LifeOutdoorActs
## What the outdoor furnishings do when a Lifelet walks up to them.
##
## The garden games already own their own fifty activities. This file owns the
## rest of the outside: the pool, the hot tub, the children's play equipment, the
## grown-up swing, and the two rules the brief states in its own words —
##
##   * a children's swing is for children and teenagers, and an adult pushes;
##     pushing lifts the child's Fun and the friendship between them;
##   * a sand pit is for playing in and never for a toilet, and playing lifts Fun
##     and the friendship between whoever is in it.
##
## This file is also the single owner of who may use an outdoor furnishing, which
## is why the catalogue carries no second age flag: `from` and `to` below are the
## one place that answers it, and a flag nobody read would only be a second
## answer waiting to disagree with this one.

## Pure static policy — no Nodes, no clock, no wallet.

## The action every one of these furnishings offers. One id for the family keeps
## the queue, the save and the availability rule single-valued while the placed
## furnishing supplies the flavour and the skill.
const ACTION_ID: String = "enjoy_outdoors"

## What each furnishing is, who may use it, and what it gives back.
##
## `from` / `to` are the youngest and oldest life stages that may use it, both
## inclusive, read against the lifecycle's own stage order. So a children's swing
## with `from: child, to: teen` is for children and teenagers exactly, and an
## adult is the one who pushes. `company` is the need the activity
## shares with anyone else doing it at the same furnishing, which is how playing
## together lifts a friendship.
const ACTS: Dictionary = {
	"pool": {
		"label": "Go for a swim", "note": "Swim a few lengths with a proper stroke through the water.",
		"duration": 60.0, "skill": "fitness", "xp": 40.0, "from": "child", "to": "young_adult",
		"changes": {"fun": 46.0, "energy": -18.0, "hygiene": 20.0, "social": 10.0},
	},
	"hot_tub": {
		"label": "Soak in the hot tub", "note": "Warm water and a long soak together. Not while pregnant.",
		"duration": 45.0, "skill": "", "xp": 0.0, "from": "child", "to": "adult",
		"changes": {"fun": 34.0, "energy": 12.0, "hygiene": 22.0, "social": 14.0},
		"block_pregnant": true,
	},
	"kids_swing": {
		"label": "Play on the swing set", "note": "Swing as high as you dare. An adult can push.",
		"duration": 40.0, "skill": "fitness", "xp": 20.0, "from": "child", "to": "teen",
		"changes": {"fun": 44.0, "energy": -10.0, "hygiene": -6.0, "social": 16.0},
		"companion": "friendship",
	},
	"sand_pit": {
		"label": "Play in the sand pit", "note": "Dig, build and knock it all down again. Only for playing.",
		"duration": 40.0, "skill": "creativity", "xp": 20.0, "from": "child",
		"changes": {"fun": 42.0, "hygiene": -10.0, "social": 20.0},
		"companion": "friendship", "not_a_toilet": true,
	},
	"kids_slide": {
		"label": "Go down the slide", "note": "Up the ladder and down again, over and over.",
		"duration": 30.0, "skill": "fitness", "xp": 18.0, "from": "child", "to": "child",
		"changes": {"fun": 40.0, "energy": -8.0, "hygiene": -5.0, "social": 14.0},
		"companion": "friendship",
	},
	"adult_slide": {
		"label": "Go down the big slide", "note": "Climb the tall ladder and race down.",
		"duration": 30.0, "skill": "fitness", "xp": 22.0, "from": "teen",
		"changes": {"fun": 42.0, "energy": -10.0, "hygiene": -5.0, "social": 12.0},
		"companion": "friendship",
	},
	"climbing_frame": {
		"label": "Climb the frame", "note": "Up the wall, across the bars and down the slide.",
		"duration": 45.0, "skill": "fitness", "xp": 30.0, "from": "child", "to": "teen",
		"changes": {"fun": 42.0, "energy": -14.0, "hygiene": -10.0, "social": 14.0},
		"companion": "friendship",
	},
	"outdoor_swing": {
		"label": "Sit in the garden swing", "note": "A proper sit-down, with room for the household.",
		"duration": 40.0, "skill": "", "xp": 0.0, "from": "teen",
		"changes": {"fun": 38.0, "energy": 10.0, "social": 24.0},
		"companion": "friendship",
	},
	# The floating toys are used in the pool rather than on their own, so they
	# offer the same swim with their own flavour.
	"pool_ring": {"label": "Float about", "note": "Tuck the ring under your arms and drift.", "duration": 40.0, "skill": "fitness", "xp": 16.0, "from": "child", "to": "young_adult", "changes": {"fun": 40.0, "hygiene": 12.0, "social": 12.0}, "needs_pool": true},
	"pool_noodle": {"label": "Float about", "note": "Lie back on the noodle and paddle.", "duration": 40.0, "skill": "fitness", "xp": 16.0, "from": "child", "to": "young_adult", "changes": {"fun": 40.0, "hygiene": 12.0, "social": 12.0}, "needs_pool": true},
	"pool_slide": {"label": "Go down the pool slide", "note": "Climb up and splash straight in.", "duration": 30.0, "skill": "fitness", "xp": 22.0, "from": "child", "to": "young_adult", "changes": {"fun": 46.0, "energy": -10.0, "hygiene": 14.0, "social": 12.0}, "needs_pool": true},
	"pool_ladder": {"label": "Use the pool ladder", "note": "Climb in and out the easy way.", "duration": 30.0, "skill": "fitness", "xp": 14.0, "from": "child", "to": "young_adult", "changes": {"fun": 36.0, "hygiene": 12.0, "social": 8.0}, "needs_pool": true},
	"pool_light": {"label": "Swim in the pool lights", "note": "A lit pool after dark is a treat on its own.", "duration": 40.0, "skill": "fitness", "xp": 18.0, "from": "child", "to": "young_adult", "changes": {"fun": 42.0, "hygiene": 12.0, "social": 10.0}, "needs_pool": true},
	"baby_pram": {
		"label": "Push the pram", "note": "Settle a baby in and stroll the neighbourhood. You can stop and chat.",
		"duration": 35.0, "skill": "", "xp": 0.0, "from": "teen",
		"changes": {"fun": 22.0, "social": 24.0, "energy": -6.0},
	},
	"pushchair": {
		"label": "Push the pushchair", "note": "Buckle a child in and walk the block. Stops for chats fill Social and Fun.",
		"duration": 35.0, "skill": "", "xp": 0.0, "from": "teen",
		"changes": {"fun": 24.0, "social": 24.0, "energy": -6.0},
	},
}

## The action an adult takes at a children's swing instead of riding it. Pushing
## the child lifts the pusher's own Fun and their friendship with the child, which
## is the rule the brief states in its own words.
const PUSH_ID: String = "push_the_swing"
const PUSH: Dictionary = {
	"label": "Push the children",
	"note": "Gather the little ones onto the swings and push. Good fun for everyone.",
	"duration": 40.0,
	"changes": {"fun": 26.0, "energy": -8.0, "social": 20.0},
	"from": "teen",
}

## The furnishings a push may be given at.
const PUSHABLE: Array[String] = ["kids_swing"]

## What a pushed child gains. The child is found at the swing, so the push is a
## real shared moment rather than a stat on the pusher alone.
const PUSH_CHILD_FUN: float = 30.0
const PUSH_CHILD_SOCIAL: float = 14.0


## The bought garden furnishings that reuse an action the game already has,
## because the brief's own equivalent already does exactly that. A bench is read
## on, a plant is watered, a table is cleared, a tree is watered, a barbecue is
## eaten at, a television is watched, a car is driven, a garage is worked in.
##
## Keeping them here rather than inventing a second rule per object means every
## one of them already respects the availability, queue, save and animation paths
## the identical indoor furnishing uses.
const LEISURE: Dictionary = {
	"tree_garden": ["water"],
	"shrub": ["water"],
	"flowers": ["water"],
	"garden_ready": ["water"],
	"garden_light": ["switch_light"],
	"garden_light_wall": ["switch_light"],
	"outdoor_tv": ["watch", "watch_together"],
	"bbq": ["snack", "host_a_chat"],
	"garden_table": ["clear_table", "host_a_chat"],
	"outdoor_swing": ["host_a_chat"],
	"fence": [],
	"car": ["drive_car"],
	"car_electric": ["drive_car"],
	"electric_car": ["drive_car"],
	"garage": ["work"],
	"car_garage": ["open_garage_door", "work"],
	"helmet": [],
}


static func is_leisure_only(kind: String) -> bool:
	return LEISURE.has(kind)


## The actions a leisure-only garden furnishing offers. `desperate` adds the
## plant pot's own emergency option, exactly as it is offered indoors.
static func leisure_actions(kind: String, desperate: bool = false) -> Array:
	var out: Array = (LEISURE.get(kind, []) as Array).duplicate()
	if desperate and kind in ["tree_garden", "shrub", "flowers", "garden_ready"]:
		out.append("plant_wee")
	return out


static func acts(kind: String) -> Dictionary:
	return ACTS.get(kind, {})


static func is_outdoor_act(kind: String) -> bool:
	return ACTS.has(kind)


static func act_label(kind: String) -> String:
	return str(acts(kind).get("label", "Enjoy the garden"))


static func can_push(kind: String) -> bool:
	return PUSHABLE.has(kind)


## Why this Lifelet may not use this furnishing, or "" when they may. One gate, so
## the withheld option and a refused call say exactly the same thing.
## `pregnant` refuses hot-tub soaks: the menu shows the can't-do reason rather
## than hiding the option.
static func act_error(kind: String, stage: String, away: bool = false, pool_available: bool = true, pregnant: bool = false) -> String:
	var act: Dictionary = acts(kind)
	if act.is_empty(): return "That is not something to do in the garden."
	if away: return "Wait until this Lifelet is home."
	var from: String = str(act.get("from", ""))
	var to: String = str(act.get("to", ""))
	if not from.is_empty() and not LifeLifecycle.at_least(stage, from):
		return "A %s is too young for that. An older Lifelet can." % str(LifeLifecycle.LABELS.get(stage, stage)).to_lower()
	if not to.is_empty() and LifeLifecycle.above(stage, to):
		return "That is for %s and younger." % str(LifeLifecycle.LABELS.get(to, to)).to_lower()
	if bool(act.get("needs_pool", false)) and not pool_available:
		return "Buy a pool first. This belongs in one."
	if pregnant and bool(act.get("block_pregnant", false)):
		return "Pregnant Lifelets cannot use the hot tub."
	return ""


## Why this Lifelet may not push at this swing, or "" when they may. Named
## `push_refusal` rather than `push_error`, which is Godot's own global.
static func push_refusal(kind: String, stage: String, away: bool = false) -> String:
	if not can_push(kind): return "There is nothing here to push."
	if away: return "Wait until this Lifelet is home."
	if not LifeLifecycle.at_least(stage, PUSH["from"]):
		return "A %s is too young to push the swings. An older Lifelet can." % str(LifeLifecycle.LABELS.get(stage, stage)).to_lower()
	return ""


## The action one furnishing offers, in the shape the ordinary menu, queue and
## save expect. `company` is how many others are already using it, which is what
## playing together is.
static func action(kind: String, stage: String, away: bool = false, company: int = 0, pool_available: bool = true, pregnant: bool = false) -> Dictionary:
	var act: Dictionary = acts(kind)
	if act.is_empty(): return {}
	var reason: String = act_error(kind, stage, away, pool_available, pregnant)
	var text: String = str(act.get("note", ""))
	var skill: String = str(act.get("skill", ""))
	if not skill.is_empty(): text += " Builds %s." % skill.capitalize()
	if company > 0: text += " %d %s here too." % [company, "Lifelet is" if company == 1 else "Lifelets are"]
	return {
		"id": ACTION_ID, "label": str(act.get("label", "Enjoy the garden")),
		"duration": float(act.get("duration", 40.0)), "cost": 0,
		"available": reason.is_empty(), "unavailable_reason": reason, "description": text,
	}


static func push_action(kind: String, stage: String, away: bool = false, children: int = 0) -> Dictionary:
	if not can_push(kind): return {}
	var reason: String = push_refusal(kind, stage, away)
	var text: String = str(PUSH["note"])
	if children > 0: text += " %d %s on a swing." % [children, "child is" if children == 1 else "children are"]
	return {
		"id": PUSH_ID, "label": str(PUSH["label"]), "duration": float(PUSH["duration"]),
		"cost": 0, "available": reason.is_empty(), "unavailable_reason": reason, "description": text,
	}


## What one act changes on the actor: its own needs and the skill it builds.
## `company` adds the social lift that playing together carries.
static func changes_for(kind: String, company: int = 0) -> Dictionary:
	var act: Dictionary = acts(kind)
	var out: Dictionary = (act.get("changes", {}) as Dictionary).duplicate(true)
	if company > 0 and out.has("social"):
		out["social"] = float(out["social"]) + float(company) * 6.0
	return out


static func skill_for(kind: String) -> String:
	return str(acts(kind).get("skill", ""))


static func xp_for(kind: String) -> float:
	return float(acts(kind).get("xp", 0.0))


## Whether this furnishing shares a moment with whoever else is using it, which is
## how it lifts a friendship.
static func shares_company(kind: String) -> bool:
	return str(acts(kind).get("companion", "")) == "friendship"


## Whether the sand pit's own rule applies: it is for playing in and never for a
## toilet. The simulation consults this before offering a bladder action here.
static func is_not_a_toilet(kind: String) -> bool:
	return bool(acts(kind).get("not_a_toilet", false))


## Pool, hot tub and outdoor seating invite company with an explicit Ask to Join.
## Other outdoor acts lift Social when someone happens to be there already; these
## open a partner panel so the player chooses who comes along.
const JOINABLE: Array[String] = ["pool", "hot_tub", "garden_table", "bbq", "outdoor_swing"]
const MAX_JOIN: int = 4
const JOIN_ACTION: String = "ask_to_join"
const CALL_FRIEND_ACTION: String = "call_friend_over"
const STAY_OVER_ACTION: String = "ask_to_stay_over"


static func can_ask_to_join(kind: String) -> bool:
	return kind in JOINABLE


static func can_call_friend(kind: String) -> bool:
	return kind in JOINABLE
