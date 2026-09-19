extends RefCounted
class_name LifeGardenGames
## What each garden activity is, who may use it, and what it builds.
##
## Every game is an ordinary catalogue kind (`game_*`), so it is bought, placed,
## moved and sold through the build path like any other furnishing. This file
## only owns the activity side: which action a placed game offers, which life
## stages may use it, and which needs and skills it moves.
##
## Pure static policy — no Nodes, no clock, no wallet.

## The action every game offers. One action id for the whole family keeps the
## queue, the save and the availability rule single-valued, while the game itself
## supplies the flavour through its own label and description.
const ACTION_ID: String = "play_garden_game"

## What one session costs the player in time, and what it gives back. A garden
## game is a proper pastime: it lifts Fun, works the body and teaches a little.
const DURATION: float = 45.0
const CHANGES: Dictionary = {"fun": 44.0, "energy": -9.0, "hygiene": -7.0, "social": 12.0}
const SKILL: String = "logic"
const XP: float = 22.0

## A game shared with the household lifts more of everyone's spirits, so the
## social component scales with how many people the household has at home.
const COMPANY_SOCIAL_BONUS: float = 6.0

## The youngest stage that may play. A baby watches; a child plays.
const PLAY_FROM: String = "child"

## Each game teaches through its own idea, so the flavour differs while the
## mechanics stay one: `skill` names what it builds, `need` what it most lifts,
## and `blurb` what the player reads on the menu.
const GAMES: Dictionary = {
	"game_trampoline": {"blurb": "Bounce until your legs give out. Balance and nerve.", "skill": "fitness"},
	"game_hopscotch": {"blurb": "Hop the grid and count your way along.", "skill": "logic"},
	"game_hoop": {"blurb": "Swing the hoop around and around.", "skill": "fitness"},
	"game_skipping_rope": {"blurb": "Skip and count the turns.", "skill": "fitness"},
	"game_dartboard": {"blurb": "A steady hand and a little arithmetic.", "skill": "logic"},
	"game_croquet": {"blurb": "Send the ball through every hoop in turn.", "skill": "logic"},
	"game_ring_toss": {"blurb": "Judge the distance and toss.", "skill": "logic"},
	"game_mini_golf": {"blurb": "Read the green and take the putt.", "skill": "logic"},
	"game_bowling": {"blurb": "Line up the lane and roll.", "skill": "logic"},
	"game_table_tennis": {"blurb": "A quick rally across the table.", "skill": "fitness"},
	"game_badminton": {"blurb": "Keep the shuttlecock in the air.", "skill": "fitness"},
	"game_football_goal": {"blurb": "Take shots at the goal.", "skill": "fitness"},
	"game_basketball": {"blurb": "Practise your aim at the hoop.", "skill": "fitness"},
	"game_bean_bags": {"blurb": "Lob the bags into the target.", "skill": "logic"},
	"game_horseshoes": {"blurb": "Ring the stake with a horseshoe.", "skill": "logic"},
	"game_boules": {"blurb": "Roll the balls closest to the jack.", "skill": "logic"},
	"game_skittles": {"blurb": "Set them up and knock them down.", "skill": "fitness"},
	"game_quotis": {"blurb": "Ring the board with the quoits.", "skill": "logic"},
	"game_shuffleboard": {"blurb": "Slide the puck to the far end.", "skill": "logic"},
	"game_connect_four": {"blurb": "Four in a row, if you can see it coming.", "skill": "logic"},
	"game_giant_chess": {"blurb": "A slow game with big pieces.", "skill": "logic"},
	"game_checkers": {"blurb": "Take the pieces and keep your own.", "skill": "logic"},
	"game_dominoes": {"blurb": "Match the ends and keep the line going.", "skill": "logic"},
	"game_jenga": {"blurb": "Take a block without bringing it down.", "skill": "logic"},
	"game_twister": {"blurb": "A hand here, a foot there.", "skill": "fitness"},
	"game_obstacle_course": {"blurb": "Over the hurdles and through the tunnel.", "skill": "fitness"},
	"game_balance_beam": {"blurb": "Walk the beam without stepping off.", "skill": "fitness"},
	"game_monkey_bars": {"blurb": "Hand over hand to the far end.", "skill": "fitness"},
	"game_parallel_bars": {"blurb": "Support your weight and swing through.", "skill": "fitness"},
	"game_pull_up_bar": {"blurb": "Pull up and hold.", "skill": "fitness"},
	"game_sandpit_toys": {"blurb": "Build and dig and knock it down again.", "skill": "creativity"},
	"game_water_table": {"blurb": "Pour, float and splash about.", "skill": "creativity"},
	"game_mud_kitchen": {"blurb": "Cook up something in the mud.", "skill": "creativity"},
	"game_bubble_station": {"blurb": "Make the biggest bubbles you can.", "skill": "creativity"},
	"game_kite": {"blurb": "Catch the wind and let it out.", "skill": "logic"},
	"game_skate_ramp": {"blurb": "Drop in and roll away.", "skill": "fitness"},
	"game_roller_skates": {"blurb": "Lace up and find your balance.", "skill": "fitness"},
	"game_space_hopper": {"blurb": "Bounce your way down the garden.", "skill": "fitness"},
	"game_pogo_stick": {"blurb": "Bounce on the spot, if you dare.", "skill": "fitness"},
	"game_hula_hoop": {"blurb": "Keep it spinning around your waist.", "skill": "fitness"},
	"game_stilts": {"blurb": "Walk tall on the stilts.", "skill": "fitness"},
	"game_diy_den": {"blurb": "Build a den out of anything you can find.", "skill": "creativity"},
	"game_playhouse": {"blurb": "Make a whole little world indoors.", "skill": "creativity"},
	"game_wendy_house": {"blurb": "Serve pretend tea from the counter.", "skill": "creativity"},
	"game_climbing_net": {"blurb": "Climb the net to the top.", "skill": "fitness"},
	"game_slackline": {"blurb": "One foot after the other along the line.", "skill": "fitness"},
	"game_stilts_race": {"blurb": "Race on the stilt blocks.", "skill": "fitness"},
	"game_parachute": {"blurb": "Everyone lifts together and makes a dome.", "skill": "charisma"},
	"game_beanbag_chairs": {"blurb": "Sink into a seat and do nothing at all.", "skill": "charisma"},
	"game_hook_a_duck": {"blurb": "Hook a duck and win a prize.", "skill": "logic"},
}


static func is_game(kind: String) -> bool:
	return GAMES.has(kind)


static func game(kind: String) -> Dictionary:
	return GAMES.get(kind, {})


static func blurb(kind: String) -> String:
	return str(game(kind).get("blurb", "A garden game."))


## What one session of this game builds. A game with no entry falls back to the
## family default, so a new model is playable the moment it is catalogued.
static func skill(kind: String) -> String:
	return str(game(kind).get("skill", SKILL))


static func xp(kind: String) -> float:
	return XP


## Why this Lifelet may not play here, or "" when they may. One gate, so the
## greyed-out entry and a refused call say the same thing.
static func play_error(kind: String, stage: String, away: bool = false) -> String:
	if not is_game(kind): return "That is not a garden game."
	if away: return "Wait until this Lifelet is home."
	if not _stage_at_least(stage, PLAY_FROM):
		return "A %s is too young to play this. An older Lifelet can." % str(LifeLifecycle.LABELS.get(stage, stage)).to_lower()
	return ""


## The ranks come from the lifecycle itself, so a stage added there cannot
## silently lock a whole age out of the garden.
static func _stage_at_least(stage: String, minimum: String) -> bool:
	return LifeLifecycle.at_least(stage, minimum)


## The action this game offers as a placed furnishing, in the shape the ordinary
## menu, queue and save expect. `company` is how many other Lifelets are already
## out in the garden, which only colours the description.
static func action(kind: String, stage: String, away: bool = false, company: int = 0) -> Dictionary:
	var reason: String = play_error(kind, stage, away)
	var text: String = blurb(kind) + " Builds %s." % skill(kind).capitalize()
	if company > 0: text += " %d %s out here too." % [company, "Lifelet is" if company == 1 else "Lifelets are"]
	return {
		"id": ACTION_ID,
		"label": "Play",
		"duration": DURATION,
		"cost": 0,
		"available": reason.is_empty(),
		"unavailable_reason": reason,
		"description": text,
	}
