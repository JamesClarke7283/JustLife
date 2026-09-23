extends Node
class_name LifeSim
## Deterministic single-household simulation. The world owns movement and calls tick.

signal changed()
signal action_started(action: Dictionary)
signal action_finished(action: Dictionary)
var meal_service: Node
var sanitation_service: Node
var household_service: Node
## Optional live kitchen: answers whether the household has food, and takes a
## meal out of the fridge when a recipe or a snack is cooked. A standalone
## simulation without a household leaves it invalid and keeps the old behaviour
## of paying for ingredients at the moment of cooking.
var grocery_service: Node
# Optional live resource admission; standalone simulations keep their old policy.
var autonomy_activity_available: Callable
## Optional live witness test for group social actions (host_a_chat). Given two
## member ids it answers whether they can actually see each other; a standalone
## simulation without a world leaves it invalid and keeps the old everyone-nearby
## policy.
var social_witness: Callable
const BLADDER_DESPERATE: float = 12.0
const BLADDER_GRACE_MINUTES: float = 10.0
var bladder_grace: float = 0.0
signal notice(text: String)
signal age_changed(previous: String, current: String)
signal away_changed(state: Dictionary)
signal life_changed(status: String)

const SAVE_PATH: String = "user://justlife_save.json"
const SAVE_VERSION: int = 1
## Bills arrive every week, as in the reference game, and the amount follows the
## value of the furnished home: a modest cottage bills far less than a mansion.
const BILL_PERIOD_DAYS: int = 7
const BILL_BASE: int = 120
const BILL_RATE_PER_1000_VALUE: float = 42.0
const BILL_DUE_DAYS: int = 4
const BILL_LATE_FEE: int = 60
## Shutoff makes an unpaid bill matter: no cooking, no hot water and nothing
## electrical until the household settles the arrears. Going to work is never
## gated, so a cut-off household can always earn its way back on.
const UTILITY_ACTIONS: Array[String] = ["cook", "experiment_recipe", "shower", "bath", "watch", "watch_together", "play_games", "study_hard", "practice_instrument", "play_piano", "drink_coffee"]

## What this home's weekly bill comes to, from the value of everything placed in
## it. A home with nothing in it still pays the base connection charge.
static func bill_amount_for(home_value: int) -> int:
	return BILL_BASE + int(round(float(maxi(0, home_value)) / 1000.0 * BILL_RATE_PER_1000_VALUE))
const GAME_MINUTES_PER_SECOND: float = 1.0
const MAX_QUEUE: int = 8
const NEED_NAMES: Array[String] = ["hunger", "energy", "hygiene", "bladder", "fun", "social"]
## At-home work that may be paused for a need and resumed with its progress
## intact. A break from these keeps the action's `elapsed`, so the progress bar
## continues where it stopped instead of restarting the whole shift.
const RESUMABLE_BREAK_ACTIONS: Array[String] = ["job"]
const LifeWantsManager = preload("res://scripts/wants_manager.gd")
const LifeLand = preload("res://scripts/land.gd")
const LifeProperties = preload("res://scripts/properties.gd")
const TRAIT_NAMES: Array[String] = ["Creative", "Outgoing", "Active", "Bookworm", "Foodie", "Neat"]
const ASPIRATION_NAMES: Array[String] = ["Maker", "Connected", "Successful", "Balanced"]
const NEED_DECAY: Dictionary = {"hunger": 3.5, "energy": 3.0, "hygiene": 2.1, "bladder": 4.0, "fun": 2.5, "social": 2.0}
## Temporary energy: what a coffee lifts a Lifelet with. It is deliberately NOT
## a seventh need — it is a pool of its own with its own name, its own decay per
## game hour and its own darker bar in the HUD, so a cup of coffee is a short
## second wind rather than a second way to fill `energy`. While any of it is
## left it pays the ordinary energy drain: caffeine carries the body, and when
## the pool runs out the metabolism resumes where it left off. It is capped at
## 100 like a need, saved with the Lifelet, and read and validated like one.
const SECOND_WIND_KEY: String = "second_wind"
const SECOND_WIND_LABEL: String = "Second wind"
const SECOND_WIND_DECAY_PER_HOUR: float = 14.0
const SECOND_WIND_MAX: float = 100.0
const SECOND_WIND_TOOLTIP: String = "Temporary energy from a coffee. It fades on its own at %d a game hour and cannot be topped up above %d; the ordinary Energy need is untouched by it." % [int(SECOND_WIND_DECAY_PER_HOUR), int(SECOND_WIND_MAX)]
var second_wind: float = 0.0
const SKILL_NAMES: Array[String] = ["cooking", "creativity", "charisma", "logic", "gardening", "parenting", "fitness", "music"]
## What a home insurance policy is. The catalogue lives here so a save and the
## phone price the same product; the household owns the purchased record.
const INSURANCE_POLICIES: Dictionary = {
	# Burglar cover priced at the same ℒ600 a break-in can take, so the phone
	# charge and the loss the policy answers are one figure the player recognises.
	"home":{"label":"Home insurance","premium":600,"payout_multiple":1.0},
	# Higher cover on a bigger house: a larger premium, and a break-in is paid
	# back with interest rather than merely made even.
	"premium":{"label":"Premium home insurance","premium":900,"payout_multiple":1.5},
	# Recurring base cover for a household with children. Bought beside home
	# insurance; the house record keeps it on its own key so both can be in force.
	"baby":{"label":"Baby & Child Insurance","premium":500,"payout_multiple":1.0},
}
## The nightly break-in that makes a policy worth buying: a real loss, capped at
## what the purse actually holds so funds can never go negative.
const ROBBERY_PERIOD_DAYS: int = 3
const ROBBERY_LOSS: int = 600

var needs: Dictionary = {}
var character: Dictionary = {}
var lifecycle: Dictionary = {}
var education: Dictionary = {}
var away_state: Dictionary = {}
## The highest qualification this Lifelet has finished: no degree, a Bachelors,
## a Masters or a PHD. A job that asks for one pays more for it, and a PHD is a
## doctor whatever the job.
var degree: String = "none"
## The criminal record: how often this Lifelet has been caught, what that cost,
## and the day they are free again. Empty for anybody who has never been inside.
var criminal_record: Dictionary = {}
var cooperation_owner: Node = null
var cooperation_member_id: String = ""
var _notification_depth: int = 0
var _pending_notifications: Array = []
var skills: Dictionary = {}
var relationships: Dictionary = {}
var career: Dictionary = {}
var wants: Array = []
var whims: Dictionary = {}
var funds: int = 2500
var day: int = 1
var minutes: float = 480.0
var speed: int = 1
var autonomy: bool = true
var action_queue: Array = []
var satisfaction: int = 0
var last_bill_day: int = 0
## Household bills, modelled on the way a life simulation makes them a decision
## rather than a silent tax: a bill is issued every BILL_PERIOD_DAYS, its size
## follows what the home is worth, and it carries a due date. Paying it from the
## phone marks it paid; letting it lapse charges a late fee and cuts the
## utilities, which the household can only clear by settling up.
var pending_bill: Dictionary = {}
## The game day the full-length mirror last gave its Charisma level. A furniture
## panel request rides the action itself (`open_wardrobe_panel`), not this state.
var _mirror_level_day: int = -1
var bills_paid_total: int = 0
var bills_late: int = 0
var utilities_cut: bool = false
## A purchased home insurance policy, or {} while uninsured. Held on the bill
## owner like the ledger: the household buys one policy, every member mirrors it.
var insurance_policy_id: String = ""
## The value of the furnished home, which sets the size of the next bill. The
## owning scene supplies a provider, so the amount is read from the furnishings
## actually placed at the moment a bill is issued.
var home_value_provider: Callable = Callable()

## What the furnished home is worth right now; zero when nothing reports it.
func home_value() -> int:
	return maxi(0, int(home_value_provider.call())) if home_value_provider.is_valid() else 0

## The provider travels with the household when members are created or restored.
func set_home_value_provider(provider: Callable) -> void:
	home_value_provider = provider
var purchased_perks: Array[String] = []  # reward ids bought from the store; permanent ones persist
var _targets: Array = []
var _idle_minutes: float = 0.0
var autonomy_state: Dictionary = {"version":1,"contacts":{},"deferred":{}}
var social_cooldowns: Dictionary = {}  # neighbour id -> game minute until which the chooser skips them
var last_hugs: Dictionary = {}  # neighbour id -> game minute of the last hug
var last_gossip: Dictionary = {}  # neighbour id -> game minute of the last gossip
var visited_venue: String = ""  # non-empty while the Lifelet is at a visited venue (a resident's home)
var last_hosted_credit: float = -1e18  # absolute game minute of the last hosted-activity credit
var last_companion_credit: float = -1e18  # absolute game minute of the last routine-venue companion credit
var companion_anchors: Dictionary = {}  # routine resident id -> their anchor object position
var routine_memory_days: Dictionary = {}  # host id -> game day of the last remembered routine encounter
var _change_accumulator: float = 0.0
var _warned_needs: Dictionary = {}
var _actions: Dictionary = {}
var household_bills_enabled: bool = true
var moodlets: Array = []
var memories: Array = []
var aspiration_stage: int = 1
var aspiration_next_day: int = 0
var aspiration_history: Array = []
var story_events: Array = []
var story_history: Array = []
var _story_generated_day: int = 1
const STORY_KINDS: Array[String] = ["neighbor_invitation", "career_opportunity", "hobby_exhibition", "garden_exchange", "learning_circle", "community_picnic", "block_party", "flea_market"]
const SOCIAL_ACTIONS: Array[String] = ["friendly", "joke", "deep_talk", "hug", "share_interests", "sympathize", "gossip", "flirt", "argue", "ask_partner", "commit", "break_up", "playful_prank", "bold_introduction", "comfort_loss", "share_memories"]
# Spending satisfaction: a perk is bought once and changes a multiplier at the
# same call sites the traits already use, while a potion acts on the spot.
const REWARDS: Dictionary = {
	"steel_bladder":{"label":"Steel Bladder","description":"Bedtimes and long journeys stop ruling the day. Bladder drains 30% slower, forever.","cost":250,"permanent":true,"effect":{"decay":{"bladder":0.7}}},
	"hardy_constitution":{"label":"Hardy Constitution","description":"Late nights cost less. Energy drains 15% slower, forever.","cost":350,"permanent":true,"effect":{"decay":{"energy":0.85}}},
	"carefree":{"label":"Carefree","description":"Boredom keeps its distance. Fun drains 15% slower, forever.","cost":300,"permanent":true,"effect":{"decay":{"fun":0.85}}},
	"great_kisser":{"label":"Great Kisser","description":"Romance lands more easily: flirting earns 35% more romance, forever.","cost":300,"permanent":true,"effect":{"romance":1.35}},
	"connections":{"label":"Connections","description":"A word in the right ear: every career performance gain rises 25%, forever.","cost":450,"permanent":true,"effect":{"performance":1.25}},
	"instant_meal":{"label":"Instant Meal","description":"One use. A hot, filling plate appears at once and restores Hunger completely.","cost":120,"permanent":false,"effect":{"restore":{"hunger":100.0}}},
	"rejuvenating_soak":{"label":"Rejuvenating Soak","description":"One use. Restores Energy and Hygiene completely in a single moment.","cost":180,"permanent":false,"effect":{"restore":{"energy":100.0,"hygiene":100.0}}},
	"inspiring_presence":{"label":"Inspiring Presence","description":"One use. Grants the Inspired mood for 8 game hours, unlocking creative work.","cost":200,"permanent":false,"effect":{"moodlet":{"label":"Inspired by a gift","emotion":"Inspired","description":"Something in the air makes creating feel effortless.","remaining":480.0,"strength":3}}}
}
# One habit per trait: the option simply does not exist for anyone else.
const TRAIT_ACTIONS: Dictionary = {"sketch_for_fun":"Creative", "host_a_chat":"Outgoing", "morning_run":"Active", "deep_read":"Bookworm", "experiment_recipe":"Foodie", "deep_clean":"Neat"}
# One opportunity per mood: only offered while that feeling is the strongest one.
const EMOTION_ACTIONS: Dictionary = {"paint_masterpiece":"Inspired", "study_hard":"Focused", "playful_prank":"Playful", "push_through":"Energized", "bold_introduction":"Confident"}
const AGE_GATED_ACTIONS: Array[String] = ["jog", "play_toys", "morning_run", LifeGardenGames.ACTION_ID]
## Built once from the skill roster: the computer's mastery actions, one per skill.
const COMPUTER_MASTERY_ACTIONS: Array[String] = ["computer_cooking", "computer_creativity", "computer_charisma", "computer_logic", "computer_gardening", "computer_parenting", "computer_fitness", "computer_music"]
const LEISURE_ACTIONS: Array[String] = ["paint", "read", "watch", "relax", "play_piano", "play_chess", "dance", "play_games", "practice_speech", "stretch", "warm_up", "jog", "play_toys", "sketch_for_fun", "deep_read", "experiment_recipe", "morning_run", "push_through", LifeGardenGames.ACTION_ID]
const PRE_DUTY_LEISURE: Array[String] = ["relax", "read", "watch", "stretch", "warm_up", "paint"]  # brief pastimes before a school or work day; the short ones sit ahead of the canvas
const DEPARTURE_WALK: float = 15.0  # game minutes allowed for the walk from a pastime to the lot exit in a busy home
const LEISURE_APPROACH: float = 10.0  # game minutes allowed for the walk to a pastime before it starts
const WEAR_ACTIONS: Dictionary = {"wear_casual":0, "wear_jacket":1, "wear_cardigan":2, "wear_tee":3, "wear_hoodie":4}
const WEAR_CATEGORY_ACTIONS: Dictionary = {"wear_everyday":"everyday", "wear_formal":"formal", "wear_athletic":"athletic", "wear_sleep":"sleep", "wear_party":"party"}
const ACTIVITY_OUTFITS: Dictionary = {
	"sleep":"sleep", "nap":"sleep",
	"jog":"athletic", "morning_run":"athletic", "stretch":"athletic",
	"dance":"party",
	"career_day":"formal", "ask_partner":"formal", "commit":"formal",
	"school_day":"everyday",
	"visit":"everyday",
	"return_home":"everyday",
}
const HOME_AFTER: Array[String] = ["sleep", "nap", "career_day", "school_day", "jog", "morning_run", "stretch", "visit"]
## How long a trip across town keeps the solo traveller at the destination.
const TRIP_MINUTES: float = 15.0
const SPIRIT_BLOCKED: Array[String] = [
	"career_day", "school_day", "job", "work", "birthday",
	"cook", "snack", "eat_meal", "store_meal",
	"flirt", "ask_partner", "commit", "break_up",
]
const PASSING_CAUSES: Dictionary = {
	"old_age": "a long life, well lived",
	"hunger": "going too long without a meal",
	"exhaustion": "pushing past the last of their strength",
}
const STARVATION_MINUTES: float = 180.0
const EXHAUSTION_MINUTES: float = 45.0
const DEFERRED_PASSING_MINUTES: float = 240.0
var starvation_minutes: float = 0.0
var exhaustion_minutes: float = 0.0
var deferred_passing_minutes: float = 0.0
const RELATIONSHIP_ACTIONS: Array[String] = ["ask_partner", "commit", "break_up"]
const SOCIAL_STAGES: Array[String] = ["met", "friends", "close_friends", "spark", "partners", "committed", "separated"]
var social_history: Array = []
var romantic_partner: String = ""
var _social_member_id: String = "player"
var _promotion_notice_day: int = -1
var _leisure_history: Array[String] = []  # the last few leisure choices, so autonomy varies its pastimes
var _recent_target_use: Dictionary = {}  # target id -> game minute of this Lifelet's last completed action there
const LEISURE_HISTORY: int = 5
const NOVELTY_FRESH_MINUTES: float = 720.0  # a furnishing nobody used for twelve hours draws the household
const NOVELTY_RECENT_MINUTES: float = 120.0  # one used in the last two hours is a little less tempting
var _social_partners: Dictionary = {}
var _social_adults: Dictionary = {}
var _social_reciprocal: Dictionary = {}
var _social_family: Dictionary = {}
var _recent_social_events: Array = []
const MAX_STORY_EVENTS: int = 3
const MAX_PROGRESS_HISTORY: int = 60


func _init() -> void:
	_build_actions()
	new_household({})


func new_household(profile: Dictionary) -> void:
	character = profile.duplicate(true)
	character["age_stage"] = LifeLifecycle.stage_for(profile)
	lifecycle = LifeLifecycle.fresh()
	character["life_stage"] = LifeLifecycle.eligibility(str(character.age_stage))
	if str(character.life_stage) not in ["adult", "minor", "unknown"]:
		character.life_stage = "unknown"
	character["name"] = str(profile.get("name", "Alex Rivera")).strip_edges().left(48)
	if str(character["name"]).is_empty():
		character["name"] = "Alex Rivera"
	var selected_traits: Array = []
	var requested_traits: Variant = profile.get("traits", ["Creative", "Outgoing"])
	if requested_traits is Array:
		for trait_name: Variant in requested_traits:
			if str(trait_name) in TRAIT_NAMES and not selected_traits.has(str(trait_name)):
				selected_traits.append(str(trait_name))
			if selected_traits.size() == 3:
				break
	character["traits"] = selected_traits
	var aspiration: String = str(profile.get("aspiration", "Balanced"))
	character["aspiration"] = aspiration if aspiration in ASPIRATION_NAMES else "Balanced"
	character["life_status"] = "passed" if str(profile.get("life_status", "living")) == "passed" else "living"
	if str(character["life_status"]) != "passed":
		character["life_status"] = "living"
	character["passing_cause"] = str(profile.get("passing_cause", "")) if str(character["life_status"]) == "passed" else ""
	LifeCharacterIdentity.ensure_wardrobe(character)
	bladder_grace = 0.0
	starvation_minutes = 0.0
	exhaustion_minutes = 0.0
	deferred_passing_minutes = 0.0
	needs = {"hunger": 76.0, "energy": 85.0, "hygiene": 86.0, "bladder": 78.0, "fun": 62.0, "social": 58.0}
	skills.clear()
	for skill_name: String in SKILL_NAMES:
		skills[skill_name] = {"level": 1, "xp": 0.0}
	relationships = {}
	for index: int in LifeResidentCatalogue.IDS.size():
		var resident_id: String = LifeResidentCatalogue.IDS[index]
		relationships[resident_id] = {"name": str(LifeResidentCatalogue.PEOPLE[resident_id].name), "friendship": 12.0 - 4.0 * float(index), "romance": 0.0, "status": "Acquaintance"}
	for relationship: Dictionary in relationships.values():
		_normalize_relationship(relationship, false)
	romantic_partner = ""
	social_history.clear()
	_recent_social_events.clear()
	_social_partners.clear()
	_social_adults.clear()
	_social_reciprocal.clear()
	_social_family.clear()
	# The default is the way into work: a Lifelet with no skills and no degree
	# starts waiting tables, which is the lowest rung and the only one open to
	# them. Everything above it asks for something they have not earned yet.
	degree = "none"
	criminal_record = {}
	career = {"schedule":LifeCareerSchedule.fresh(1),"track":LifeCareers.DEFAULT_JOB,
		"title":LifeCareers.title_at(LifeCareers.DEFAULT_JOB,1),"level":1,"performance":0.0,
		"salary":LifeCareers.base_pay(LifeCareers.DEFAULT_JOB,1),"worked_day":0}
	moodlets.clear();memories.clear()
	aspiration_stage = 1
	aspiration_next_day = 0
	aspiration_history.clear()
	story_events.clear()
	story_history.clear()
	_story_generated_day = 1
	funds = 2500
	day = 1
	education = LifeEducation.fresh(str(character.age_stage),day)
	minutes = 480.0
	speed = 1
	autonomy = true
	action_queue.clear()
	away_state = {}
	satisfaction = 0
	last_bill_day = 0
	pending_bill = {}
	bills_paid_total = 0
	bills_late = 0
	utilities_cut = false
	insurance_policy_id = ""
	second_wind = 0.0
	purchased_perks.clear()
	_idle_minutes = 0.0
	autonomy_state = {"version":1,"contacts":{},"deferred":{}}
	_leisure_history.clear()
	_warned_needs.clear()
	_create_wants()
	var wants_and_fears_enabled: bool = bool(profile.get("wants_and_fears", false))
	whims = LifeWantsManager.fresh_state(character, str(get_mood().label), needs, wants_and_fears_enabled)
	_emit_changed()


func _build_actions() -> void:
	_define("arrive_home","Arriving home",1.0,{},0,"",0.0,"Walk into your new home. Canceling the walk keeps this Lifelet in the family.")
	_define("career_day", "Go to work", LifeCareerSchedule.LENGTH, {"hunger":30.0,"bladder":52.0,"hygiene":26.0,"social":24.0,"energy":-12.0,"fun":12.0}, 0, "", 0.0, "Weekday work, 09:00–17:00. Arrive by 10:00; late arrivals until noon reduce pay and performance. Lunch, bathroom and washroom breaks are included.")
	_define("school_day", "Go to school", 420.0, {"hunger":22.0,"bladder":46.0,"hygiene":18.0,"social":35.0,"energy":-7.0,"fun":10.0}, 0, "", 0.0, "Leave for school on weekdays from 08:00. Arrive by 09:00 to be on time; late arrival is possible until 12:00. Return at 15:00. Lunch, bathroom and washroom breaks are part of the school day.")
	_define("visit", "A trip across town", TRIP_MINUTES, {}, 0, "", 0.0, "Travel to a place in Juniper Bay on your own while the household stays home. The shared car takes fifteen minutes each way.")
	_define("help_homework", "Help with homework", 45.0, {}, 0, "", 0.0, "Support a child or teen through one assignment and build Parenting skill.")
	_define("school", "Attend online classes", 180.0, {}, 0, "", 0.0, "Weekday lessons at your desk, 08:00–14:00. Prepared homework improves learning and grades.")
	_define("homework", "Do homework", 45.0, {}, 0, "", 0.0, "Complete a weekday assignment and prepare for the next attended class.")
	_define("birthday", "Celebrate a birthday", 45.0, {"fun":30.0,"social":20.0}, 30, "", 0.0, "Celebrate the next chapter of your life. Advances this Lifelet to the next age stage.")
	_define("serve_meal","Serve the meal",2.0,{},0,"",0.0,"Carry the serving dish to a table or counter.")
	_define("eat_meal","Take a serving",32.0,{},0,"",0.0,"Collect a plate and eat at an available dining chair.")
	_define("store_meal","Put away leftovers",5.0,{},0,"",0.0,"Carry the remaining servings to the fridge to keep them fresh longer.")
	_define("put_in_fridge","Put food in the fridge",5.0,{},0,"",0.0,"Gather the servings left out and put them back in the fridge while they are still fresh.")
	_define("discard_meal","Clear this meal",5.0,{},0,"",0.0,"Carry the serving dish to the sink and discard its remaining food.")
	_define("bin_meal","Throw it in the bin",5.0,{},0,"",0.0,"Carry spoiled food to the rubbish bin and tip it out. The bin takes it; nothing is eaten.")
	_define("clean_plate","Wash this plate",10.0,{"hygiene":-1.0},0,"",0.0,"Carry the used plate to a sink and wash it.")
	# The espresso machine's own action. A cup costs a few ℒ of beans and leaves
	# a real `second_wind` behind: the pool, not the need, is what a coffee
	# gives, and the action is listed in UTILITY_ACTIONS because the machine
	# needs the power the household's bills pay for.
	_define("drink_coffee", "Drink a coffee", 15.0, {"fun": 6.0, "second_wind": 55.0}, 6, "", 0.0, "Pull a shot of espresso and drink it. The beans cost ℒ6 and the lift is a temporary second wind that fades on its own.")
	_define("snack", "Grab a snack", 15.0, {"hunger": 32.0}, 4, "", 0.0, "A quick bite to keep the day going.")
	_define("cook", "Cook a fresh meal", 45.0, {"fun": 8.0, "hygiene": -5.0}, 8, "cooking", 34.0, "Choose a recipe to prepare and share. Cooking skill unlocks more dishes. Eating restores hunger. Ingredients start at ℒ8.")
	_define("sleep", "Sleep", 360.0, {"energy": 95.0, "fun": 15.0}, 0, "", 0.0, "A full night's rest restores energy and chases the boredom away.")
	_define("try_for_baby", "Try for Baby", LifeBabyPlan.DURATION, {"social": 20.0, "fun": 14.0, "energy": -6.0}, 0, "", 0.0, "An intimate moment with your partner while you share the bed. If you both want to, this can begin a pregnancy.")
	_define("nap", "Take a nap", 75.0, {"energy": 38.0}, 0, "", 0.0, "A short, refreshing nap.")
	_define("shower", "Take a shower", 30.0, {"hygiene": 85.0, "fun": 4.0}, 0, "", 0.0, "Freshen up and feel ready for the day.")
	_define("wash_hands", "Wash your hands", 5.0, {"hygiene": 16.0}, 0, "", 0.0, "Soap and warm water at the sink. A quick freshen up after the bathroom, cooking or time outdoors.")
	_define("brush_teeth", "Brush your teeth", 8.0, {"hygiene": 22.0, "fun": 2.0}, 0, "", 0.0, "Two minutes at the sink for a minty, clean feeling.")
	_define("clear_table", "Clear the table", 10.0, {"hygiene": -1.0}, 0, "", 0.0, "Gather the used plates and finished dishes from this surface and take them to the sink.")
	_define("empty_bin", "Empty the bin", 8.0, {"hygiene": -2.0}, 0, "", 0.0, "Take the full rubbish bag out to the street. A tidy home smells fresher.")
	_define("practice_instrument", "Practise an instrument", 60.0, {"fun": 38.0, "energy": -5.0}, 0, "music", 36.0, "Play through a few pieces. Music skill grows with every session.")
	_define("study_book", "Study from a book", 60.0, {"fun": 12.0, "energy": -4.0}, 0, "", 0.0, "Work through a book from the shelf. Skill books teach every skill up to level 9; the computer takes a Lifelet the rest of the way to 10.")
	_define("buy_book", "Buy a skill book…", 0.0, {}, 0, "", 0.0, "Choose a skill book for this shelf. One subject per skill; books stay here ready to study up to level 9.")
	_define("switch_light", "Switch the light", 1.0, {}, 0, "", 0.0, "Turn this light on or off. A dark room is cosy; a bright one is easier to work in.")
	_define("watch_together", "Watch TV together", 60.0, {"fun": 46.0, "social": 26.0, "energy": 4.0}, 0, "charisma", 8.0, "Share the sofa and a show with your guest. Company makes it twice the fun.")
	_define("toilet", "Use toilet", 15.0, {"bladder": 95.0, "hygiene": -3.0}, 0, "", 0.0, "Take care of a pressing need. Your Lifelet washes their hands afterwards.")
	_define("plant_wee", "Wee in plant pot (desperate)", 10.0, {"bladder":85.0,"hygiene":-12.0}, 0, "", 0.0, "An emergency option when bladder is 12 or lower. Walk to the pot first. A toilet is more hygienic.")
	_define("mop_puddle", "Mop up accident", 8.0, {"hygiene":-2.0}, 0, "", 0.0, "Clean this puddle from the floor. Canceling leaves it for later.")
	_define("relax", "Relax", 40.0, {"fun": 25.0, "energy": 12.0}, 0, "", 0.0, "Put your feet up and unwind.")
	_define("watch", "Watch a show", 60.0, {"fun": 48.0, "energy": 5.0}, 0, "", 0.0, "Enjoy a favorite show.")
	_define("read", "Read a book", 60.0, {"fun": 32.0}, 0, "logic", 25.0, "Lose yourself in a good book and build Logic.")
	_define("paint", "Paint & sell a canvas", 90.0, {"fun": 40.0, "hygiene": -5.0}, 20, "creativity", 42.0, "Create an original canvas; its value grows with your skill.")
	_define("work", "Do freelance work", 120.0, {"fun": -8.0, "energy": -10.0}, 0, "logic", 24.0, "Complete a small freelance project for income.")
	_define("study", "Study a skill", 90.0, {"fun": 12.0, "energy": -5.0}, 0, "logic", 40.0, "Practice Logic and prepare for career advancement.")
	_define("job", "Work a shift from home", 360.0, {"hunger": -12.0, "energy": -18.0, "fun": -15.0, "social": 12.0}, 0, "logic", 30.0, "Optional six-hour home shift. Shares today’s paid attendance with going to work.")
	_define("water", "Tend the plants", 25.0, {"fun": 15.0, "hygiene": -4.0}, 0, "gardening", 28.0, "Care for greenery and learn Gardening.")
	_define("bath", "Take a long bath", 40.0, {"hygiene": 90.0, "fun": 14.0, "energy": 8.0}, 0, "", 0.0, "Sink into warm water. Slower than a shower, but restful.")
	_define("practice_speech", "Practice a speech", 40.0, {"fun": 10.0, "social": 6.0}, 0, "charisma", 30.0, "Rehearse in front of the mirror and build Charisma.")
	_define("talk_to_myself", "Talk to yourself", 30.0, {"fun": 8.0}, 0, "charisma", 0.0, "Hold your own gaze in a full-length mirror and say it out loud. A whole level of Charisma, once a day.")
	_define("change_in_mirror", "Change wardrobe…", 6.0, {}, 0, "", 0.0, "Open your wardrobe here and try a look on in the glass before you buy it.")
	_define("do_makeup", "Do your makeup…", 8.0, {"fun": 6.0}, 0, "", 0.0, "Sit at the dressing table and try a lip or eye look on before you buy it.")
	_define("change_jewelry", "Change jewelry…", 6.0, {}, 0, "", 0.0, "Try a stud, a hoop or a chain on at the dressing table before you buy it.")
	_define("play_piano", "Play the piano", 60.0, {"fun": 36.0}, 0, "music", 38.0, "Practice scales and songs. Music skill grows with every session.")
	_define("play_chess", "Play chess", 60.0, {"fun": 30.0}, 0, "logic", 36.0, "Think a few moves ahead and build Logic.")
	_define("jog", "Go for a run", 45.0, {"fun": 18.0, "energy": -14.0, "hygiene": -18.0}, 0, "fitness", 40.0, "A steady run builds Fitness. Expect to need a shower afterwards.")
	_define("stretch", "Stretch and breathe", 30.0, {"fun": 12.0, "energy": 10.0}, 0, "fitness", 24.0, "Gentle stretching restores a little energy and builds Fitness.")
	_define("dance", "Dance to a record", 35.0, {"fun": 40.0, "energy": -8.0, "hygiene": -6.0}, 0, "fitness", 12.0, "Put a record on and move. Great fun, a little tiring.")
	# The shared dance is the same record with company. Its numbers are the solo
	# dance's own, so every dancer gains exactly what dancing alone would give;
	# the household binds up to five Lifelets to one shared clock.
	_define("dance_together", "Dance together", 35.0, {"fun": 40.0, "energy": -8.0, "hygiene": -6.0}, 0, "fitness", 12.0, "Share one record with the household. Everyone dances, and everyone hears the same song.")

	_define("read_post", "Read the post", 10.0, {"fun": 4.0}, 0, "", 0.0, "Open the post box and read what has arrived. A bill can be settled straight from its letter.")
	# Every outdoor furnishing shares this one action; the placed object supplies
	# the flavour, the gate and the skill, exactly as the garden games do.
	_define(LifeOutdoorActs.ACTION_ID, "Enjoy the garden", 40.0, {}, 0, "", 0.0, "Use what is standing in the garden.")
	_define(LifeOutdoorActs.PUSH_ID, "Push the children", LifeOutdoorActs.PUSH.duration, LifeOutdoorActs.PUSH.changes.duplicate(), 0, "", 0.0, "Push whoever is on the swings. Good fun for the pusher and the child alike.")
	_define("ride_bike", "Go for a ride", 60.0, {"fun": 34.0, "energy": -16.0, "hygiene": -14.0, "social": 6.0}, 0, "fitness", 42.0, "Ride out along the lane and back. Needs a helmet, and builds Fitness fast.")
	_define("wear_helmet", "Put on a helmet", 4.0, {}, 0, "", 0.0, "Strap on a bicycle helmet. Riding a bike needs one.")
	_define("play_toys", "Play with toys", 45.0, {"fun": 42.0, "social": 4.0}, 0, "creativity", 14.0, "Imaginative play for children. Builds a little Creativity.")
	# Every garden game shares this one action. The placed game supplies the
	# flavour, so a new game model is playable the moment it is catalogued.
	_define(LifeGardenGames.ACTION_ID, "Play", LifeGardenGames.DURATION, LifeGardenGames.CHANGES.duplicate(), 0, "", 0.0, "Have a proper go on a garden game. Builds the skill that game teaches.")
	_define("change_outfit", "Change outfit", 4.0, {}, 0, "", 0.0, "Switch to the next saved outfit type in your wardrobe.")
	_define("change_in_wardrobe", "Open the wardrobe…", 6.0, {}, 0, "", 0.0, "Browse your tops, hair, makeup and jewelry and see each one on before you keep it.")
	_define("wear_everyday", "Wear everyday clothes", 4.0, {}, 0, "", 0.0, "Change into the Everyday look you designed.")
	_define("wear_formal", "Wear formal clothes", 4.0, {}, 0, "", 0.0, "Change into the Formal look you designed.")
	_define("wear_athletic", "Wear athletic clothes", 4.0, {}, 0, "", 0.0, "Change into the Athletic look you designed.")
	_define("wear_sleep", "Wear sleep clothes", 4.0, {}, 0, "", 0.0, "Change into the Sleep look you designed.")
	_define("wear_party", "Wear party clothes", 4.0, {}, 0, "", 0.0, "Change into the Party look you designed.")
	_define("wear_casual", "Wear the casual shirt", 4.0, {}, 0, "", 0.0, "Change into the short-sleeve shirt.")
	_define("wear_jacket", "Wear the jacket", 4.0, {}, 0, "", 0.0, "Change into the cropped bomber jacket.")
	_define("wear_cardigan", "Wear the cardigan", 4.0, {}, 0, "", 0.0, "Change into the open knit cardigan.")
	_define("wear_tee", "Wear the tee", 4.0, {}, 0, "", 0.0, "Change into the plain crew tee.")
	_define("wear_hoodie", "Wear the hoodie", 4.0, {}, 0, "", 0.0, "Change into the soft hoodie.")
	_define("warm_up", "Warm up by the fire", 25.0, {"fun": 16.0, "energy": 8.0}, 0, "", 0.0, "A quiet moment by the hearth.")
	_define("mourn", "Mourn", 30.0, {"fun": -4.0}, 0, "", 0.0, "Spend a quiet moment in respectful silence. Shedding tears eases grief.")
	_define("leave_flowers", "Leave fresh flowers", 15.0, {"fun": 10.0}, 15, "", 0.0, "Place fresh blooms (ℒ15) at the memorial to honour their memory.")
	_define("remember_passed", "Reminisce", 25.0, {"fun": 14.0, "social": 4.0}, 0, "", 0.0, "Reflect on fond memories and wisdom shared with the departed.")
	_define("order_groceries", "Order the weekly shop", 5.0, {}, 0, "", 0.0, "Order a grocery delivery from the computer. The van arrives later today, or tomorrow if it is already evening, and the kitchen is restocked when it does.")
	_define("play_games", "Play video games", 45.0, {"fun": 40.0, "energy": -4.0}, 0, "logic", 10.0, "An hour of games at the computer. Great fun, a little Logic.")
	_define("friendly", "Have a friendly chat", 25.0, {"social": 28.0, "fun": 6.0}, 0, "charisma", 18.0, "Say hello, catch up and grow your friendship.")
	_define("joke", "Tell a joke", 20.0, {"social": 22.0, "fun": 16.0}, 0, "charisma", 16.0, "Share a laugh and strengthen your friendship.")
	_define("deep_talk", "Have a heartfelt talk", 45.0, {"social": 45.0, "fun": 8.0}, 0, "charisma", 28.0, "A deeper conversation works best with someone you know.")
	_define("hug", "Share a hug", 15.0, {"social": 24.0, "fun": 5.0}, 0, "charisma", 12.0, "A warm hug for someone you care about. Works best on a real friend.")
	_define("share_interests", "Share interests", 35.0, {"social": 38.0, "fun": 10.0}, 0, "charisma", 20.0, "Talk about what you love. Lifelets with shared traits connect deeply.")
	_define("sympathize", "Offer sympathy", 20.0, {"social": 20.0, "fun": 4.0}, 0, "charisma", 14.0, "Sit with someone having a hard day and really listen. Comforts a struggling friend most.")
	_define("gossip", "Share a bit of gossip", 20.0, {"social": 16.0, "fun": 8.0}, 0, "charisma", 10.0, "Trade the neighborhood's small stories. Fun, but the same story twice lands flat.")
	_define("flirt", "Flirt", 25.0, {"social": 26.0, "fun": 10.0}, 0, "charisma", 20.0, "Express interest. Friendship helps your advances land well.")
	_define("argue", "Argue", 20.0, {"social": 8.0, "fun": -12.0}, 0, "charisma", 8.0, "Vent your frustration, at a cost to the relationship.")
	_define("ask_partner", "Ask to become partners", 35.0, {"social": 15.0, "fun": 8.0}, 0, "charisma", 12.0, "Choose a relationship together. Both adults need 45 friendship and 35 romance, and must be available.")
	_define("commit", "Make a commitment", 45.0, {"social": 20.0, "fun": 10.0}, 0, "charisma", 16.0, "Affirm your shared future with your current partner, with 65 friendship and 65 romance.")
	_define("break_up", "End the relationship", 25.0, {"social": 5.0, "fun": -8.0}, 0, "", 0.0, "End your partnership honestly. Friendship falls by 12 and romance by 35; both become available again.")
	_define("comfort_loss", "Comfort over loss", 25.0, {"social": 32.0, "fun": 8.0}, 0, "charisma", 20.0, "Console a grieving friend or family member. Warm words make the sorrow easier to bear.")
	_define("share_memories", "Share memories", 30.0, {"social": 28.0, "fun": 12.0}, 0, "charisma", 16.0, "Talk about happy times spent together, keeping their spirit alive in the home.")
	# Emotion-gated opportunities: offered only while that feeling is the strongest.
	_define("paint_masterpiece", "Paint a masterpiece", 120.0, {"fun": 45.0, "hygiene": -7.0}, 30, "creativity", 60.0, "Ride the inspiration into something remarkable. Sells for far more than an ordinary canvas.")
	_define("study_hard", "Study hard", 120.0, {"fun": 6.0, "energy": -12.0}, 0, "logic", 70.0, "Deep work while your mind is sharp. Builds Logic quickly.")
	_define("push_through", "Push through", 60.0, {"fun": 14.0, "energy": -22.0, "hygiene": -22.0}, 0, "fitness", 65.0, "Sprint past the comfortable pace while the energy is there. Fitness grows fast.")
	_define("playful_prank", "Play a playful prank", 20.0, {"social": 18.0, "fun": 20.0}, 0, "charisma", 18.0, "A joke with a little mischief in it. A big friendly swing, but a thin friendship can take it badly.")
	_define("bold_introduction", "Give a bold introduction", 20.0, {"social": 30.0, "fun": 8.0}, 0, "charisma", 18.0, "Walk up and introduce yourself like you own the room. A larger friendship gain than an ordinary hello.")
	# Trait habits: only a Lifelet with that trait ever sees the option.
	_define("sketch_for_fun", "Sketch for fun", 30.0, {"fun": 26.0}, 0, "creativity", 12.0, "A quick sketch with no sale in mind. Cheap, short and good fun.")
	_define("host_a_chat", "Host a chat", 60.0, {"social": 40.0, "fun": 20.0}, 0, "charisma", 16.0, "Gather the household for a proper conversation. Everyone nearby feels more connected.")
	_define("morning_run", "Morning run", 45.0, {"fun": 16.0, "energy": -18.0, "hygiene": -20.0}, 0, "fitness", 60.0, "Head out of the front door for a long run around the block. Builds Fitness faster than the treadmill, and costs energy.")
	_define("deep_read", "Deep read", 120.0, {"fun": 20.0, "energy": -6.0}, 0, "logic", 65.0, "Settle in with a demanding book for a long stretch. High Logic progress.")
	_define("experiment_recipe", "Experiment with a recipe", 45.0, {"fun": 30.0, "hygiene": -5.0}, 0, "creativity", 30.0, "Try a dish nobody has written down. Fun and creativity, and something new to eat.")
	# Time with the household's animals. Teaching is slow and patient work that
	# builds Parenting, and a tummy rub is the plain affection a dog asks for.
	_define("teach_pet_trick", "Teach a trick", 30.0, {"fun": 20.0, "social": 6.0, "energy": -4.0}, 0, "parenting", 30.0, "Spend a little while teaching the household pet something new. Patience and treats do the work.")
	_define("pet_tummy_rub", "Give a tummy rub", 20.0, {"fun": 18.0, "social": 12.0}, 0, "parenting", 12.0, "Roll your dog over and rub their tummy properly. A dog's favourite minute of the day.")
	# A dog's coat needs washing. A cat looks after its own hygiene by licking,
	# so this is offered for dogs only and the availability gate says why.
	_define("bathe_pet", "Bathe the dog", 35.0, {"fun": 10.0, "hygiene": -6.0, "energy": -5.0}, 0, "parenting", 26.0, "Soap, warm water and a good towel. A clean coat, and a very happy dog afterwards.")
	# ------------------------------------------------------------ baby care
	# A caregiver does these for the baby, so the actions are offered to whoever
	# the player is controlling and the target is the child. Each one answers a
	# real need on the baby's own side, the way the needs panel shows it.
	_define("feed_baby_bottle", "Prepare Bottle", 25.0, {"social": 8.0, "fun": 6.0, "energy": -3.0}, 0, "parenting", 18.0, "Warm a bottle from the fridge and feed the baby. Fills their hunger and settles them.")
	_define("feed_baby_food", "Get Baby Food", 30.0, {"social": 10.0, "fun": 8.0, "energy": -4.0}, 0, "parenting", 24.0, "Take a jar from the fridge and spoon-feed the baby. A proper meal, and a messy face afterwards.")
	_define("pet_feed", "Feed Dog", 15.0, {"social": 6.0}, 0, "parenting", 8.0, "Pick up the food and pour kibble into the bowl. Fills the dog's hunger.")
	_define("pet_play", "Play with Dog", 30.0, {"fun": 18.0, "social": 14.0, "energy": -6.0}, 0, "fitness", 10.0, "Play until you are both out of breath.")
	_define("pet_tug", "Tug-of-war", 22.0, {"fun": 24.0, "social": 14.0, "energy": -8.0}, 0, "fitness", 14.0, "Grab the rope toy and pull. Dog and Lifelet both love it.")
	_define("pet_teach_trick", "Play Tricks", 35.0, {"fun": 20.0, "social": 12.0, "energy": -4.0}, 0, "logic", 26.0, "Hand signals and cues for the next trick. Builds the pet's trick skill.")
	_define("pet_walk", "Take for a Walk", 40.0, {"fun": 16.0, "social": 14.0, "energy": -8.0}, 0, "fitness", 22.0, "Clip on a leash and walk the neighbourhood. You can stop and chat with neighbours.")
	_define("pet_pet", "Pet", 12.0, {"fun": 10.0, "social": 12.0}, 0, "parenting", 6.0, "Stroke the coat. Warm affection for you both.")
	_define("pet_train", "Train obedience", 25.0, {"fun": 8.0, "social": 10.0}, 0, "parenting", 18.0, "Patient repetition. Builds Obedience and your own Parenting.")
	_define("drive_car", "Drive…", 0.0, {}, 0, "", 0.0, "Open the door, get in, and pick a destination on the town map. With a baby or child, buckle them into a car seat first.")
	_define("push_pram", "Push the pram", 35.0, {"fun": 22.0, "social": 24.0, "energy": -6.0}, 0, "", 0.0, "Settle a baby in and stroll. Stops for chats fill Social and Fun.")
	_define("push_pushchair", "Push the pushchair", 35.0, {"fun": 24.0, "social": 24.0, "energy": -6.0}, 0, "", 0.0, "Buckle a child in and walk the block.")
	_define("change_nappy", "Change Nappy", 20.0, {"fun": 4.0, "hygiene": -6.0}, 0, "parenting", 16.0, "A clean nappy on the changing table. The baby's hygiene and bladder are seen to and they stop fussing.")
	_define("cuddle_baby", "Pick Up for Cuddle", 20.0, {"social": 26.0, "fun": 14.0}, 0, "parenting", 14.0, "Carry the baby and talk to them quietly. Their social need fills and they feel safe.")
	_define("talk_to_baby", "Talk To", 18.0, {"social": 16.0, "fun": 8.0}, 0, "parenting", 10.0, "Chat softly with the baby. Their social need fills.")
	_define("spin_baby_mobile", "Spin the baby mobile", 20.0, {"fun": 6.0}, 0, "parenting", 8.0, "Set the nursery mobile turning. The baby watches and their fun need rises.")
	_define("play_with_baby", "Play with the baby", 30.0, {"fun": 20.0, "social": 16.0, "energy": -4.0}, 0, "parenting", 20.0, "Sit on the floor with the baby's toys and play together. Fun for both of you, and their social need too.")
	_define("play_rattle", "Shake the rattle", 16.0, {"fun": 4.0}, 0, "parenting", 6.0, "Shake a rattle for a sitting baby. Logic and fun tick up together.")
	_define("play_baby_mat", "Sit on the baby mat", 22.0, {"fun": 6.0, "social": 4.0}, 0, "parenting", 8.0, "Settle on the mat with the baby. Social, logic and fun all get a lift.")
	_define("use_potty", "Potty training", 24.0, {"hygiene": 8.0}, 0, "parenting", 12.0, "Help a toddler practise on the potty.")
	_define("play_dollhouse", "Play with the dollhouse", 28.0, {"fun": 18.0, "social": 8.0}, 0, "parenting", 10.0, "A toddler play session at the dollhouse.")
	_define("child_desk_study", "Sit at the child desk", 30.0, {"fun": 6.0}, 0, "logic", 14.0, "A toddler or child settles at their own desk.")
	_define("deep_clean", "Deep clean", 45.0, {"hygiene": 6.0, "fun": 10.0}, 0, "", 0.0, "Scrub the surfaces until the room sparkles. Slow, but oddly satisfying.")
	_define("remember_life", "Remember a life", 20.0, {"social": 12.0, "fun": 6.0}, 0, "", 0.0, "Stand with the stone and remember who they were.")
	# The computer is where a subject is truly mastered. A skill book stops at
	# level 9; only focused screen work carries a Lifelet to level 10, so a
	# bookshelf is the cheap route and the computer the final one.
	for skill_name: String in SKILL_NAMES:
		_define("computer_"+skill_name, "Master %s on the computer" % skill_name.capitalize(), 120.0, {"fun": 4.0, "energy": -14.0}, 0, skill_name, 70.0, "Concentrated study of %s at the computer. This is the only way to reach level 10." % skill_name.capitalize())


func _define(id: String, label: String, duration: float, changes: Dictionary, cost: int, skill: String, xp: float, description: String) -> void:
	_actions[id] = {"id": id, "label": label, "duration": duration, "changes": changes, "cost": cost, "skill": skill, "xp": xp, "description": description}


func get_actions_for(kind: String, target_id: String = "") -> Array:
	if is_instance_valid(meal_service) and kind in ["meal","plate"]:return meal_service.actions_for(self,kind,target_id)
	var ids: Array = []
	match kind:
		"lot_exit":
			ids = ["school_day"] if str(character.age_stage) in LifeEducation.SCHOOL_STAGES else (["career_day"] if str(character.life_stage)=="adult" else [])
			ids.append("morning_run")
		"fridge":
			ids = ["cook", "snack", "order_groceries", "birthday"]
			# The bottle and the jar are fetched from the fridge.
			if _has_baby(): ids.append_array(["feed_baby_bottle", "feed_baby_food"])
		"stove", "kitchen": ids = ["cook", "experiment_recipe"]
		"sink": ids = ["wash_hands", "brush_teeth", "deep_clean"]
		"dining", "counter", "coffee_table": ids = ["clear_table", "deep_clean"]
		"rubbish_bin": ids = ["empty_bin"]
		"bed": ids = ["sleep", "nap", "try_for_baby"]
		"shower", "bath": ids = ["shower"]
		"toilet": ids = ["toilet"]
		"sofa", "chair", "armchair", "loveseat", "stool": ids = ["relax", "nap", "host_a_chat"]
		"bench": ids = ["relax", "read", "nap", "host_a_chat"]
		"tv": ids = ["watch", "watch_together"]
		"guitar", "violin": ids = ["practice_instrument"]
		"bookshelf", "book_nook": ids = ["read", "study", "study_book", "buy_book", "deep_read"]
		"easel": ids = ["paint", "paint_masterpiece", "sketch_for_fun"]
		"desk": ids = ["work", "study", "job", "study_hard"]
		"computer": ids = ["order_groceries", "work", "study", "job", "play_games", "study_hard"] + COMPUTER_MASTERY_ACTIONS
		"plant": ids = ["water","plant_wee"] if float(needs.bladder)<=BLADDER_DESPERATE else ["water"]
		"puddle": ids = ["mop_puddle"]
		"bathtub": ids = ["bath"]
		"mirror": ids = ["talk_to_myself", "change_in_mirror", "practice_speech"]
		"dressing_table": ids = ["do_makeup", "change_jewelry"]
		"piano": ids = ["play_piano"]
		"chess": ids = ["play_chess"]
		"treadmill": ids = ["jog", "push_through"]  # children see the disabled entry with its reason
		"yoga_mat": ids = ["stretch"]
		"stereo": ids = ["dance"]
		"coffee_machine": ids = ["drink_coffee"]
		"toybox": ids = ["play_toys"]  # adults see the disabled entry with its reason
		"wardrobe":
			var worn_category: String = LifeCharacterIdentity.normalize_category(character.get("outfit_category", "everyday"))
			# The wardrobe opens the styling panel, where every option is shown on
			# the Lifelet before it is kept. The instant category swaps stay below
			# it, so a player who already knows what they want is one click away.
			ids.append("change_in_wardrobe")
			ids.append("change_outfit")
			for wear_id: String in WEAR_CATEGORY_ACTIONS:
				if str(WEAR_CATEGORY_ACTIONS[wear_id]) != worn_category: ids.append(wear_id)
			for wear_id: String in WEAR_ACTIONS:
				if int(WEAR_ACTIONS[wear_id]) != int(character.get("outfit", 0)): ids.append(wear_id)
		"garden_bed": ids = ["water"]
		# The post box is where the household's post arrives, so it offers its own
		# box of letters rather than being decoration.
		"post_box": ids = ["read_post"]
		# A bicycle is ridden, not sat on: riding builds Fitness and needs a
		# helmet, which the availability gate checks rather than the menu hiding.
		"bike_adult", "bike_kids": ids = ["ride_bike"]
		"fireplace": ids = ["warm_up"]
		"urn", "tombstone", "memorial": ids = ["remember_life", "mourn", "leave_flowers", "remember_passed"]
		"neighbor", "maya", "leo", "priya", "tom": ids = SOCIAL_ACTIONS
		"pet": ids = ["pet_feed", "pet_pet", "pet_tummy_rub", "pet_play", "pet_tug", "pet_teach_trick", "pet_walk", "pet_train", "bathe_pet"]
		# Baby care. The changing table is where a nappy is changed, the toys are
		# what play happens on, and the cot is where a cuddle happens without a
		# toy in hand. Each is offered only when a baby is in the household.
		"changing_table": ids = ["change_nappy"] if _has_baby() else []
		"baby_toys": ids = ["play_with_baby"] if _has_baby() else []
		"cot": ids = ["cuddle_baby", "talk_to_baby", "sleep", "nap"] if _has_baby() else ["sleep", "nap"]
		"baby_mobile": ids = ["spin_baby_mobile"] if _has_baby() else []
		"baby_rattle": ids = ["play_rattle"] if _infant_at_least(LifeBabyPlan.INFANT_SITTING) else []
		"baby_mat": ids = ["play_baby_mat"] if _infant_at_least(LifeBabyPlan.INFANT_SITTING) else []
		"rocking_chair": ids = ["cuddle_baby", "relax"] if _has_baby() else ["relax"]
		"potty": ids = ["use_potty"] if _infant_at_least(LifeBabyPlan.INFANT_TODDLER) else []
		"dollhouse": ids = ["play_dollhouse"] if _infant_at_least(LifeBabyPlan.INFANT_TODDLER) else []
		"child_desk": ids = ["child_desk_study"] if _infant_at_least(LifeBabyPlan.INFANT_TODDLER) or str(character.age_stage)=="child" else []
		"train_set": ids = ["play_toys"] if _infant_at_least(LifeBabyPlan.INFANT_TODDLER) or str(character.age_stage)=="child" else []

	if LifeGardenGames.is_game(kind): ids = [LifeGardenGames.ACTION_ID]
	elif LifeOutdoorActs.is_outdoor_act(kind):
		ids = [LifeOutdoorActs.ACTION_ID]
		if LifeOutdoorActs.can_push(kind): ids.append(LifeOutdoorActs.PUSH_ID)
	elif LifeOutdoorActs.is_leisure_only(kind):
		# Bought garden furniture a Lifelet can simply enjoy: a seat, a plant to
		# tend, a table to clear, a television to watch. Each reuses the one action
		# the brief's own equivalent already has, rather than a second rule.
		ids = LifeOutdoorActs.leisure_actions(kind, float(needs.bladder) <= BLADDER_DESPERATE)
	if str(character.age_stage) in LifeEducation.SCHOOL_STAGES:
		if kind in ["desk","computer"]: ids = ["school","homework","study","study_hard"] + (["play_games"] if kind == "computer" else [])
		elif kind == "bookshelf": ids = ["read","homework","study","study_book","buy_book","deep_read"]
	var result: Array = []
	for id: String in ids:
		var data: Dictionary = _actions[id].duplicate(true)
		var availability: Dictionary = get_action_availability(id, target_id)
		data["available"] = availability.available
		data["unavailable_reason"] = availability.reason
		result.append(data)
	if kind=="fridge" and is_instance_valid(meal_service):
		var out:Dictionary={"id":"put_in_fridge","label":"Put away the food left out","cost":0,"duration":5,"available":true,"description":"Gather the servings sitting out and return them to the fridge while they are still fresh."}
		var reason:String=meal_service.action_availability(self,"put_in_fridge",target_id)
		out["available"]=reason.is_empty();out["unavailable_reason"]=reason
		result.append(out)
		result.append({"id":"choose_leftovers","label":"Choose leftovers…","available":true,"cost":0,"duration":0,"description":"See the food stored in this fridge."})
	return result


func get_action_definition(id: String) -> Dictionary:
	return _actions.get(id, {}).duplicate(true)


## Why this Lifelet may not ride this bicycle, or "" when they may. The bicycle's
## own catalogue entry names the ages that fit it, and a helmet must actually
## stand in the home: the rule is that you must wear one to ride.
func _ride_bike_error(target_id: String) -> String:
	var kind: String = _target_kind_of(target_id)
	var data: Dictionary = LifeCatalog.get_item(kind)
	if data.is_empty(): return "Choose a bicycle to ride."
	if is_away(): return "Wait until this Lifelet is home."
	var stage: String = str(character.age_stage)
	var from: String = str(data.get("ride_from", ""))
	var until: String = str(data.get("ride_until", ""))
	if not from.is_empty() and not LifeLifecycle.at_least(stage, from):
		return "That bike is too big for a %s. The kids' bike fits them." % str(LifeLifecycle.LABELS.get(stage, stage)).to_lower()
	if not until.is_empty() and LifeLifecycle.at_least(stage, until):
		return "That bike is too small for a %s now. An adult bike fits them." % str(LifeLifecycle.LABELS.get(stage, stage)).to_lower()
	if not _helmet_available():
		return "You must wear a helmet to ride. Buy one and place it in the home."
	return ""


## Whether the household owns a placed bicycle helmet. Riding is refused without
## one, which is the rule rather than a suggestion.
func _helmet_available() -> bool:
	if is_instance_valid(household_service) and household_service.has_method("owns_helmet"):
		return bool(household_service.call("owns_helmet"))
	return true


## Whether a pool stands in this home. The pool's own toys are used in one, so
## they are refused with a reason rather than silently doing nothing.
func _pool_present() -> bool:
	for entry: Dictionary in _targets:
		if str(entry.get("kind", "")) == "pool": return true
	return false


## The selected household member is the active pregnancy's mother.
func _actor_is_pregnant() -> bool:
	if not is_instance_valid(cooperation_owner) or not cooperation_owner.has_method("member_is_pregnant"):
		return false
	return bool(cooperation_owner.member_is_pregnant(_social_member_id))


## How many other Lifelets are already using this furnishing. Playing together is
## what makes a shared garden activity lift a friendship, so the count is read at
## queue time and carried on the action.
func _company_at(target_id: String) -> int:
	if target_id.is_empty(): return 0
	var count: int = 0
	for member: Dictionary in _autonomy_household_members():
		if member.sim == self: continue
		var other: Dictionary = member.sim.get_current_action()
		if str(other.get("target_id", "")) == target_id: count += 1
	return count


## The kind of the furnishing an action names. The garden games share one action
## id, so the target's own kind is what tells one game from another.
func _target_kind_of(target_id: String) -> String:
	for target: Dictionary in _targets:
		if str(target.get("id", "")) == target_id: return str(target.get("kind", ""))
	return ""


func is_away() -> bool:
	return not away_state.is_empty()


func get_away_state() -> Dictionary:
	return away_state.duplicate(true)


func school_departure_reason() -> String:
	return _school_departure_error("lot_exit")


func _school_departure_error(target_id: String, ignore_queue: bool = false) -> String:
	if str(character.age_stage) not in LifeEducation.SCHOOL_STAGES:
		return "Only children and teens attend school."
	if is_away(): return "This Lifelet is already away from home."
	if not LifeEducation.weekday(day): return "School runs Monday through Friday."
	if day < int(education.first_class_day): return "Classes begin on the next school day."
	if int(education.last_attendance_day) == day: return "Today's school attendance is already complete."
	if minutes < 480.0 or minutes > 720.0: return "Leave for school between 08:00 and 12:00. Arrivals after 09:00 affect school performance."
	if not target_id.is_empty() and _education_target_kind(target_id) != "lot_exit":
		return "Choose the neighborhood exit to leave for school."
	if not ignore_queue:
		for action: Dictionary in action_queue:
			if str(action.id) in ["school","school_day"]: return "School is already in this Lifelet's plans."
	return ""


func _begin_school_departure(action: Dictionary) -> void:
	var problem: String = _school_departure_error(str(action.target_id),true)
	if problem.is_empty() and str(action.target_id).is_empty(): problem = "School needs a real neighborhood exit."
	for need: String in ["hunger","energy","bladder"]:
		if float(needs[need]) < 12.0: problem = "Take care of urgent needs before leaving for school."
	if bool(action.get("autonomous",false)):
		# The same projection the chooser used: with the commute counted, so a
		# pupil sent to the exit is not turned back there by a stricter re-check.
		if not _autonomy_projection_need("school_day",60.0).is_empty(): problem = "Get ready for the school day before leaving."
		for later: Dictionary in action_queue.slice(1):
			if not bool(later.get("autonomous",false)): problem = "Following your plans before leaving for school."
	if not problem.is_empty():
		cancel_action()
		_emit_notice(problem)
		return
	_wear_for_activity("school_day")
	# The controller calls this only after the Lifelet reaches the registered exit.
	action.merge({"phase":"active","paid":true,"started_day":day,"started_minutes":minutes,
		"elapsed":0.0,"progress":0.0,"duration":900.0-minutes},true)
	for need:String in action.changes:action.changes[need]=float(action.changes[need])*float(action.duration)/420.0
	away_state = {"version":1,"activity":"school","phase":"away","departure_day":day,
		"departure_minutes":minutes,"return_day":day,"return_minutes":900.0,
		"exit_id":str(action.target_id),"exit_position":action.target_position,
		"age_stage":str(character.age_stage),"completed":false,"ended_at":0.0}
	_publish("away_changed",[get_away_state()])
	_emit_changed()
	_emit_notice("%s has left for school and will be home after 15:00." % str(character.name))


func _tick_away(_game_minutes: float) -> void:
	if not is_away() or str(away_state.phase) != "away": return
	if str(away_state.activity)=="career":
		_tick_career_away()
		return
	# A prison sentence is not a school day with a curriculum: the Lifelet is
	# simply not here until the household's own release tick brings them home,
	# so time passes without an action to progress.
	if str(away_state.activity)=="prison":
		return
	if str(away_state.activity)=="hospital":
		# Hospital stays end when Welcome Baby Home clears the away-state, not
		# on a school-style clock return.
		return
	if day != int(away_state.departure_day) or str(character.age_stage) != str(away_state.age_stage):
		request_return_home()
		return
	if action_queue.is_empty():
		# An absence with no action to progress cannot advance; the household
		# owns the return, so nothing is silently stranded here.
		return
	var action: Dictionary = action_queue[0]
	var elapsed: float = clampf(minutes-float(away_state.departure_minutes),0.0,float(action.duration))
	var gained: float = maxf(0.0,elapsed-float(action.elapsed))
	action.elapsed = elapsed
	action.progress = elapsed/float(action.duration)
	_apply_continuous_effects(action,gained/float(action.duration))
	if minutes < float(away_state.return_minutes): return
	# Attendance is earned when the school day ends, even if the route home is slow.
	# Commit the returning state before any school-result notification is dispatched.
	begin_notifications()
	var result: Dictionary = LifeEducation.complete(education,str(character.age_stage),day,900.0,"school")
	away_state.phase = "returning"
	away_state.ended_at = float(day-1)*1440.0+900.0
	away_state.completed = bool(result.ok)
	if bool(result.ok):
		var late:float=maxf(0.0,float(away_state.departure_minutes)-540.0)
		result.state["late_minutes"]=float(result.state.get("late_minutes",0.0))+late
		for skill:String in result.effects.get("skill_xp",{}):result.effects.skill_xp[skill]*=float(action.duration)/420.0
		_apply_education_result(result)
		if late>0:
			_emit_notice("Arrived %d minutes late. School performance reflects the missed lessons." % int(late))
		add_moodlet("School day complete","Focused","Lessons are finished. Time to head home.",120,2)
		remember("A day at school","Finished today's lessons and came home with something new to learn.")
		_record_chapter_activity("school",0)
	else:
		_emit_notice(str(result.get("error","Today's school attendance could not be recorded.")))
	_publish("away_changed",[get_away_state()])
	_emit_changed()
	_wear_home_clothes()
	_emit_notice("%s is returning from school." % str(character.name))
	dispatch_notifications(release_notifications())


func autonomy_need_choice(need:String,excluded_target_ids:Array=[]) -> Dictionary:
	# The player's "take care of this" click shares the autonomy chooser, so a
	# directed fix respects queues, loads and fitting pre-duty pastimes.
	return _autonomy_need_choice(need,excluded_target_ids)

func request_return_home() -> bool:
	if not is_away(): return false
	if str(away_state.phase) == "returning": return true
	var action: Dictionary = action_queue[0]
	var elapsed: float = clampf(_autonomy_now()-(float(away_state.departure_day-1)*1440.0+float(away_state.departure_minutes)),0.0,float(action.duration))
	var gained: float = maxf(0.0,elapsed-float(action.elapsed))
	action.elapsed = elapsed
	action.progress = elapsed/float(action.duration)
	_apply_continuous_effects(action,gained/float(action.duration))
	var returning_from_work:bool=str(away_state.activity)=="career"
	defer_autonomous_responsibility("career_day" if returning_from_work else "school_day",maxf(1.0,721.0-minutes))
	away_state.phase = "returning"
	away_state.ended_at = _autonomy_now()
	away_state.completed = false
	_publish("away_changed",[get_away_state()])
	_emit_changed()
	_emit_notice(("%s is leaving work early. Today’s full shift and pay have not been earned." if returning_from_work else "%s is leaving school early. Today’s attendance has not been earned.") % str(character.name))
	return true


## A solo trip's own refusal, re-checked when the traveller reaches the exit.
## It never asks about housemates: nobody else is travelling.
func _visit_departure_error(target_id: String) -> String:
	if is_away(): return "This Lifelet is already away from home."
	if not target_id.is_empty() and _education_target_kind(target_id) != "lot_exit":
		return "Choose the neighborhood exit to leave on a trip."
	return ""


func _begin_visit_departure(action: Dictionary) -> void:
	_wear_for_activity("visit")
	action.merge({"phase":"active","paid":true,"started_day":day,"started_minutes":minutes,
		"elapsed":0.0,"progress":0.0,"duration":TRIP_MINUTES},true)
	away_state = {"version":1,"activity":"visit","phase":"away","departure_day":day,
		"departure_minutes":minutes,"return_day":day,"return_minutes":minutes+TRIP_MINUTES,
		"destination":str(action.get("destination","")),"exit_id":str(action.target_id),
		"exit_position":action.target_position,"completed":false,"ended_at":0.0}
	_publish("away_changed",[get_away_state()])
	_emit_changed()
	_emit_notice("%s is on their way across town." % str(character.name))


func _tick_visit_away() -> void:
	if day != int(away_state.departure_day):request_return_home();return
	var action: Dictionary = action_queue[0]
	var elapsed: float = clampf(minutes-float(away_state.departure_minutes),0.0,float(action.duration))
	action.elapsed = elapsed
	action.progress = elapsed/float(action.duration)
	if minutes < float(away_state.return_minutes): return
	# The visit itself is the whole point of the trip: it is earned when the
	# time away is up, and the drive home only has to be walked afterwards.
	away_state.phase = "returning"
	away_state.ended_at = float(day-1)*1440.0+float(away_state.return_minutes)
	away_state.completed = true
	var place:String=str(away_state.get("destination",""))
	if LifeNeighborhood.PLACES.has(place):
		remember("A trip across town","Spent the afternoon at "+str(LifeNeighborhood.PLACES[place].name)+" and came back with something to tell.")
		add_moodlet("A change of scene","Inspired","A little time away from the house clears the head.",120,2)
	_publish("away_changed",[get_away_state()])
	_emit_changed()
	_wear_home_clothes()
	_emit_notice("%s is heading home." % str(character.name))


func _validate_visit_away_state(state: Dictionary) -> String:
	var value: Dictionary = state.get("away_state",{})
	var pending: Array = state.action_queue.filter(func(action:Dictionary)->bool:return str(action.id)=="visit")
	if pending.size() != 1 or state.action_queue.is_empty() or str(state.action_queue[0].id) != "visit":
		return "Save has an away traveller without its active trip."
	if not _autonomy_integer(value.get("version"),1,1) or value.get("activity") != "visit" or str(value.get("phase","")) not in ["away","returning"]:
		return "Save contains an unsupported away activity."
	if not _autonomy_integer(value.get("departure_day"),1,int(state.day)) or not _autonomy_integer(value.get("return_day"),int(value.departure_day),int(value.departure_day)):
		return "Save contains an invalid trip calendar."
	if not _number_in_range(value.get("departure_minutes"),0.0,1439.99999) or not _number_in_range(value.get("return_minutes"),0.0,1439.99999) or not value.get("completed") is bool:
		return "Save contains invalid trip departure or return times."
	if not LifeNeighborhood.PLACES.has(str(value.get("destination",""))) or str(value.get("exit_id","")) != "lot_exit":
		return "Save contains an invalid trip destination or exit."
	var position: Variant = value.get("exit_position")
	if position is Vector3:
		if not position.is_finite(): return "Save contains an invalid trip position."
	elif position is Array and position.size() == 3:
		for component: Variant in position:
			if not _number_in_range(component,-100000.0,100000.0): return "Save contains an invalid trip position."
	else: return "Save contains an invalid trip position."
	var departed: float = float(value.departure_day-1)*1440.0+float(value.departure_minutes)
	var now: float = float(state.day-1)*1440.0+float(state.minutes)
	if now < departed: return "Save contains a trip that has not departed yet."
	var action: Dictionary = pending[0]
	if action.get("paid") != true or not action.get("paid") is bool or str(action.get("target_id","")) != "lot_exit" or str(action.get("target_kind","")) != "lot_exit" or not _as_vector3(action.target_position).is_equal_approx(_as_vector3(position)):
		return "Save contains a mismatched trip action or exit."
	if not _number_in_range(action.get("duration"),TRIP_MINUTES,TRIP_MINUTES):
		return "Save contains an invalid trip duration."
	if str(value.phase) == "away":
		if bool(value.completed) or float(value.ended_at) != 0.0 or now-departed-TRIP_MINUTES >= 0.0:
			return "Save contains an expired or already-finished trip."
		if not _number_in_range(action.get("elapsed"),maxf(0.0,minf(now-departed,TRIP_MINUTES)-.00001),minf(TRIP_MINUTES,maxf(0.0,now-departed)+.00001)):
			return "Save contains impossible trip progress."
	else:
		if float(value.ended_at) != departed+TRIP_MINUTES or not bool(value.completed):
			return "Save contains an invalid trip return."
	return ""


func complete_away_return() -> bool:
	if not is_away() or str(away_state.phase) != "returning": return false
	# Arrival is owned by the world; never teleport or begin the later queue here.
	var action: Dictionary = action_queue.pop_front()
	action.phase = "complete" if bool(away_state.completed) else "cancelled"
	action["attendance_earned"] = bool(away_state.completed)
	away_state = {}
	_idle_minutes = 0.0
	_publish("away_changed",[{}])
	if bool(action.attendance_earned): _emit_action_finished(action)
	_start_front()
	_emit_changed()
	return true


func queue_action(id: String, target_id: String = "", target_position: Vector3 = Vector3.ZERO, recipe: String = "garden_skillet") -> bool:
	if id=="arrive_home":return false # Only the validated household transaction creates arrival.
	if id=="career_day":
		var problem:String=_career_departure_error(target_id)
		if target_id.is_empty():problem="Choose the neighborhood exit to leave for work."
		if not problem.is_empty():_emit_notice(problem);return false
	if id == "school_day" and target_id.is_empty():
		_emit_notice("Choose the neighborhood exit to leave for school.")
		return false
	if id == "school_day" and not _school_departure_error(target_id).is_empty():
		_emit_notice(_school_departure_error(target_id))
		return false
	if id == "help_homework":
		_emit_notice("Choose Do homework together at a desk to arrange both Lifelets.")
		return false
	if id == LifeDancePlan.ACTION_ID:
		_emit_notice("Choose Dance together at the music player to invite the household.")
		return false
	if id == LifeBabyPlan.ACTION_ID:
		_emit_notice("Choose Try for Baby on the bed both partners are sleeping in.")
		return false
	if id == "visit" and (is_away() or action_queue.any(func(queued:Dictionary)->bool:return str(queued.id)=="visit")):
		_emit_notice("Finish the trip you are already on before leaving again.")
		return false
	if not _actions.has(id):
		return false
	if action_queue.size() >= MAX_QUEUE:
		_emit_notice("Your action queue is full. Finish or cancel an activity first.")
		return false
	if id in ["school","homework"] and target_id.is_empty():
		_emit_notice("Choose furniture for that school activity.")
		return false
	var definition: Dictionary = _actions[id]
	if id=="cook":
		var reason:String=LifeMeals.recipe_error(recipe,int(skills.cooking.level),str(character.age_stage),funds)
		if not reason.is_empty():_emit_notice(reason);return false
		definition=LifeMeals.cooking_definition(definition,recipe)
	if id == LifeOutdoorActs.ACTION_ID:
		var act_kind: String = _target_kind_of(target_id)
		if not LifeOutdoorActs.is_outdoor_act(act_kind):
			_emit_notice("Choose something in the garden to use.")
			return false
		var act_reason: String = LifeOutdoorActs.act_error(act_kind, str(character.age_stage), is_away(), _pool_present(), _actor_is_pregnant())
		if not act_reason.is_empty():
			_emit_notice(act_reason)
			return false
		definition = definition.duplicate(true)
		definition["label"] = LifeOutdoorActs.act_label(act_kind)
		definition["duration"] = float(LifeOutdoorActs.acts(act_kind).get("duration", 40.0))
		definition["changes"] = LifeOutdoorActs.changes_for(act_kind, _company_at(target_id))
		definition["skill"] = LifeOutdoorActs.skill_for(act_kind)
		definition["xp"] = LifeOutdoorActs.xp_for(act_kind)
		definition["description"] = str(LifeOutdoorActs.acts(act_kind).get("note", ""))
	if id == LifeOutdoorActs.PUSH_ID:
		var swing_kind: String = _target_kind_of(target_id)
		var push_reason: String = LifeOutdoorActs.push_refusal(swing_kind, str(character.age_stage), is_away())
		if not push_reason.is_empty():
			_emit_notice(push_reason)
			return false
		definition = definition.duplicate(true)
		definition["changes"] = LifeOutdoorActs.PUSH.changes.duplicate(true)
	if id == LifeGardenGames.ACTION_ID:
		# A garden game shares one action id, so the placed furnishing supplies the
		# skill it builds and the flavour the player reads. Binding both at queue
		# time keeps a save taken mid-game faithful to the game that was played.
		var game_kind: String = _target_kind_of(target_id)
		if not LifeGardenGames.is_game(game_kind):
			_emit_notice("Choose a garden game to play on.")
			return false
		var game_reason: String = LifeGardenGames.play_error(game_kind, str(character.age_stage), is_away())
		if not game_reason.is_empty():
			_emit_notice(game_reason)
			return false
		definition = definition.duplicate(true)
		definition["skill"] = LifeGardenGames.skill(game_kind)
		definition["xp"] = LifeGardenGames.xp(game_kind)
		definition["description"] = LifeGardenGames.blurb(game_kind)
		definition["label"] = "Play on the %s" % str(LifeCatalog.get_item(game_kind).get("label", "garden game")).to_lower()
	if id=="study_book" and is_instance_valid(household_service):
		# The shelf owns which subject a session teaches. Bind it now so a save
		# taken mid-read remembers what the Lifelet was actually studying, and so
		# a shelf of finished books cannot be read for a free skill.
		var subject:String=household_service.study_skill_for(self,target_id)
		if subject.is_empty():
			_emit_notice(household_service.action_availability(self,id,target_id))
			return false
		definition=household_service.study_definition(definition,subject)
	if funds < int(definition["cost"]):
		_emit_notice("You need ℒ%d for %s." % [int(definition["cost"]), str(definition["label"]).to_lower()])
		return false
	if id in ["job","career_day"] and int(career["worked_day"]) == day:
		_emit_notice("Today's shift is complete. You can work again tomorrow.")
		return false
	if id in SOCIAL_ACTIONS or EMOTION_ACTIONS.has(id) or TRAIT_ACTIONS.has(id) or COMPUTER_MASTERY_ACTIONS.has(id) or id in ["plant_wee", "mop_puddle", "birthday", "job", "work", "cook", "school", "homework", "eat_meal", "store_meal", "clean_plate", "discard_meal", "bin_meal", "jog", "play_toys", "put_in_fridge", LifeGardenGames.ACTION_ID, LifeOutdoorActs.ACTION_ID, LifeOutdoorActs.PUSH_ID]:
		var availability: Dictionary = get_action_availability(id, target_id)
		if not bool(availability.available):
			_emit_notice(str(availability.reason))
			return false
	if id not in ["school_day","career_day"] and not action_queue.is_empty() and str(action_queue[0].id) in ["school_day","career_day"] and bool(action_queue[0].get("autonomous",false)) and not is_away():
		# A valid new player instruction takes ownership before departure.
		cancel_action()
	var action: Dictionary = definition.duplicate(true)
	if id in ["school_day","career_day"]: action["target_kind"] = "lot_exit"
	if id in ["school","homework"]: action["target_kind"] = _education_target_kind(target_id)
	if id == "birthday": action["birthday_from_stage"] = str(character.age_stage)
	action.merge({"target_id": target_id, "target_position": target_position, "phase": "queued", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false}, true)
	if _has_trait("Active") and id == "nap":
		action["duration"] = 60.0
	action_queue.append(action)
	_idle_minutes = 0.0
	if action_queue.size() == 1:
		_start_front()
	_emit_changed()
	return true


func get_current_action() -> Dictionary:
	return {} if action_queue.is_empty() else action_queue[0]


func begin_current_action() -> void:
	if is_away(): return
	if action_queue.is_empty() or str(action_queue[0]["phase"]) != "approach":
		return
	var action: Dictionary = action_queue[0]
	if str(action.id)=="arrive_home":return # Physical arrival is confirmed by the controller.
	if str(action.id)=="career_day":
		_begin_career_departure(action)
		return
	if str(action.id)=="visit":
		var visit_reason:String=_visit_departure_error(str(action.target_id))
		if not visit_reason.is_empty():
			_emit_notice(visit_reason);cancel_action();return
		_begin_visit_departure(action)
		return
	if str(action.id) == "school_day":
		_begin_school_departure(action)
		return
	if action.has("cooperation_id"):
		if is_instance_valid(cooperation_owner): cooperation_owner.mark_cooperative_ready(cooperation_member_id)
		return
	if str(action.id) in AGE_GATED_ACTIONS:
		var age_reason:Dictionary=get_action_availability(str(action.id),str(action.get("target_id","")))
		if not bool(age_reason.available):
			_emit_notice(str(age_reason.reason));cancel_action();return
	if str(action.id) in ["plant_wee","mop_puddle"]:
		var sanitation_reason:String=_sanitation_reason(str(action.id),str(action.target_id),bool(action.paid) and float(action.elapsed)>0.0)
		if not sanitation_reason.is_empty():
			_emit_notice(sanitation_reason);cancel_action();return
	if is_instance_valid(meal_service) and not meal_service.before_begin(self,action):return
	var cost: int = int(action["cost"])
	if str(action.id) == "birthday" and str(action.get("birthday_from_stage","")) != str(character.age_stage):
		_emit_notice("This birthday has already arrived. Choose a new celebration for the next stage.")
		cancel_action()
		return
	if str(action.id) in ["school","homework"]:
		var school_error: String = _school_action_error(action)
		if not school_error.is_empty():
			_emit_notice(school_error)
			cancel_action()
			return
	if str(action.id)=="cook":
		# With a live kitchen the ingredients come out of the fridge rather than
		# being bought at the stove, so an empty kitchen is what stops a meal —
		# not the household's purse. A standalone simulation keeps the old rule.
		if is_instance_valid(grocery_service):
			var kitchen_reason:String=str(grocery_service.cooking_availability(self,str(action.get("target_id",""))))
			if not kitchen_reason.is_empty():_emit_notice(kitchen_reason);cancel_action();return
		else:
			var recipe_reason:String=LifeMeals.recipe_error(str(action.get("recipe","garden_skillet")),int(skills.cooking.level),str(character.age_stage),funds,bool(action.paid))
			if not recipe_reason.is_empty():_emit_notice(recipe_reason);cancel_action();return
	if str(action.id) in RELATIONSHIP_ACTIONS or str(action.id) in ["flirt", "birthday", "job", "work"]:
		var availability: Dictionary = get_action_availability(str(action.id), str(action.target_id))
		if not bool(availability.available):
			_emit_notice(str(availability.reason))
			cancel_action()
			return
	# A queued emotion or trait opportunity is re-checked on arrival: a mood
	# that has already passed cannot still pay for a prank or a masterpiece.
	if EMOTION_ACTIONS.has(str(action.id)) or TRAIT_ACTIONS.has(str(action.id)):
		var locked: Dictionary = get_action_availability(str(action.id), str(action.target_id))
		if not bool(locked.available):
			_emit_notice(str(locked.reason))
			cancel_action()
			return
	if not bool(action["paid"]):
		if bool(action.get("autonomous",false)) and str(action.id) in ["school","homework","job"]:
			var outside_work_hours:bool=str(action.id)=="job" and (not LifeEducation.weekday(day) or minutes<540.0 or minutes>960.0)
			if outside_work_hours or not _autonomy_projection_need(str(action.id)).is_empty():
				_emit_notice("Taking care of the day before starting another responsibility.")
				cancel_action()
				return
		# Cooking and snacking are paid for out of the kitchen, not the purse: a
		# recipe takes one meal's ingredients from the fridge, and an empty kitchen
		# refuses the action with the reason the kitchen itself gives.
		var from_kitchen:bool=is_instance_valid(grocery_service) and str(action.id) in ["cook","snack"]
		if from_kitchen:
			var drawn:Dictionary=grocery_service.take_meal_for(self,str(action.id))
			if not bool(drawn.get("ok",false)):
				_emit_notice(str(drawn.get("error","The kitchen is empty. Order a delivery from the computer.")))
				cancel_action()
				return
			action["paid"] = true
			action["from_kitchen"] = true
		else:
			if funds < cost:
				_emit_notice("There isn't enough money for that activity anymore.")
				cancel_action()
				return
			if str(action["id"]) == "job" and int(career["worked_day"]) == day:
				_emit_notice("You have already worked today's shift.")
				cancel_action()
				return
			funds -= cost
			action["paid"] = true
	if not action.has("started_minutes"):
		action["started_day"] = day
		action["started_minutes"] = minutes
	_wear_for_activity(str(action.id))
	action["phase"] = "active"
	_emit_changed()

func _wear_for_activity(action_id: String) -> void:
	var category: String = str(ACTIVITY_OUTFITS.get(action_id, ""))
	if category.is_empty():
		return
	if LifeCharacterIdentity.normalize_category(character.get("outfit_category", "everyday")) == category:
		return
	LifeCharacterIdentity.apply_category(character, category)

func _wear_home_clothes() -> void:
	if is_spirit():
		return
	_wear_for_activity("return_home")


func cancel_action(index: int = 0) -> void:
	if index < 0 or index >= action_queue.size():
		return
	if index == 0 and is_away():
		request_return_home()
		return
	if action_queue[index].has("cooperation_id") and is_instance_valid(cooperation_owner):
		cooperation_owner.cancel_cooperative_action(cooperation_member_id)
		return
	if is_instance_valid(meal_service):meal_service.canceled(self,action_queue[index])
	action_queue.remove_at(index)
	if index == 0:
		_start_front()
	_idle_minutes = 12.0 if _retry_soon else 0.0
	_retry_soon = false
	_emit_changed()


func _start_front() -> void:
	if is_away(): return
	if action_queue.is_empty():
		return
	action_queue[0]["phase"] = "approach"
	_emit_action_started(action_queue[0])


func set_speed(value: int) -> void:
	if value not in [0, 1, 3, 8]:
		return
	speed = value
	_emit_changed()


func register_targets(targets: Array, reconcile:bool=true) -> void:
	_targets.clear()
	for entry: Variant in targets:
		if entry is Dictionary and entry.has("id") and entry.has("kind") and entry.get("position") is Vector3:
			_targets.append(entry.duplicate(true))
	if reconcile:_prune_school_actions()


func tick(delta: float) -> void:
	if speed == 0 or delta <= 0.0 or not is_finite(delta):
		return
	var remaining: float = minf(delta, 60.0) * GAME_MINUTES_PER_SECOND * float(speed)
	# Minute-sized steps make effects and midnight processing stable at every speed.
	while remaining > 0.00001:
		var step: float = minf(remaining, 1.0)
		_step(step)
		remaining -= step
	_change_accumulator += delta
	if _change_accumulator >= 0.2:
		_change_accumulator = 0.0
		_emit_changed()


func _step(game_minutes: float) -> void:
	var bladder_before:float=float(needs.bladder)
	for i in range(moodlets.size()-1,-1,-1):
		moodlets[i].remaining=maxf(0,float(moodlets[i].remaining)-game_minutes)
		if float(moodlets[i].remaining)<=0:moodlets.remove_at(i)
	minutes += game_minutes
	while minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
		_new_day()
	_advance_age(game_minutes)
	_update_passing_pressure(game_minutes)
	if ready_to_starve() or ready_to_overexert() or ready_to_pass_on():
		pass_on()
	_prune_school_actions()
	for need_name: String in NEED_NAMES:
		if need_name == "energy" and second_wind > 0.0:
			# Caffeine carries the body: while any second wind is left, the
			# ordinary energy need does not drain at all. The pool alone pays for
			# the wakefulness, and it is drawn down in exactly one place below,
			# so the rate the player sees is the pool's own and nothing else.
			continue
		var decay: float = float(NEED_DECAY[need_name])
		if need_name == "social" and _has_trait("Outgoing"):
			decay *= 1.35
		if need_name == "fun" and _has_trait("Creative"):
			decay *= 1.2
		if need_name == "hygiene" and _has_trait("Neat"):
			decay *= 0.75
		if need_name == "energy" and _has_trait("Active"):
			decay *= 0.8
		decay *= _perk_decay_multiplier(need_name)
		needs[need_name] = clampf(float(needs[need_name]) - decay * game_minutes / 60.0, 0.0, 100.0)
	# The temporary pool fades on the shared clock at its own, faster rate,
	# whether the Lifelet is at home, away or asleep. Nothing refills it but a
	# coffee, so a cup is a second wind and not a second sleep.
	second_wind = clampf(second_wind - SECOND_WIND_DECAY_PER_HOUR * game_minutes / 60.0, 0.0, SECOND_WIND_MAX)
	if is_away():
		bladder_grace=0.0 # School and work include bathroom breaks.
		_tick_away(game_minutes)
		_check_need_notices()
		_update_wants()
		return
	_reconsider_active_autonomy()
	if not action_queue.is_empty() and str(action_queue[0]["phase"]) == "active" and str(action_queue[0].id) != "help_homework" and not (str(action_queue[0].id) == LifeBabyPlan.ACTION_ID and not bool(action_queue[0].get("cooperation_primary",false))):
		var action: Dictionary = action_queue[0]
		var actual_step: float = minf(game_minutes, float(action["duration"]) - float(action["elapsed"]))
		action["elapsed"] = float(action["elapsed"]) + actual_step
		# Accumulating the timer minute by minute leaves it a hair short of the
		# boundary it was meant to cross (a duration of 60.0 reached through a
		# 0.78 split lands on 59.99999999999999). Once that shortfall falls below
		# elapsed's own ULP, adding it is a no-op and the action would sit at
		# 100% forever, so snap to the boundary when we are within a microsecond
		# of it. Durations are game minutes, so this is far below a frame.
		if float(action["duration"]) - float(action["elapsed"]) <= 1e-6:
			action["elapsed"] = float(action["duration"])
		action["progress"] = clampf(float(action["elapsed"]) / float(action["duration"]), 0.0, 1.0)
		_apply_continuous_effects(action, actual_step / float(action["duration"]))
		# A meal can expire and cancel during its effects callback. Never finish
		# a replacement action using the removed action’s progress.
		if action_queue.is_empty() or not is_same(action_queue[0],action):return
		if float(action["progress"]) >= 1.0:
			_finish_front()
	elif action_queue.is_empty():
		_idle_minutes += game_minutes
		# An idle Lifelet pauses a quarter hour between pastimes, but not while a
		# school or work day is open or when an urgent need requires recovery:
		# then the next choice follows within a minute.
		var pressing_need: bool = false
		for need_name: String in NEED_NAMES:
			if float(needs[need_name]) < 40.0:
				pressing_need = true
				break
		if autonomy and (_idle_minutes >= 15.0 or (_idle_minutes >= 1.0 and (not _autonomy_duty_id().is_empty() or pressing_need))):
			_choose_autonomous_action()
	_tick_bladder(game_minutes,bladder_before)
	_check_need_notices()
	_update_wants()


func _tick_bladder(game_minutes:float,bladder_before:float) -> void:
	# Apply toilet/plant relief first, including the first minute at the target.
	if float(needs.bladder)>0.0:
		bladder_grace=0.0
		return
	var empty_minutes:float=maxf(0.0,game_minutes-bladder_before/(float(NEED_DECAY.bladder)/60.0)) if bladder_before>0.0 else game_minutes
	bladder_grace=minf(BLADDER_GRACE_MINUTES,bladder_grace+empty_minutes)
	if bladder_grace<BLADDER_GRACE_MINUTES:return
	# The world must confirm a present Lifelet and real floor position. A
	# detached simulation or car journey never creates a puddle at stale coordinates.
	if not is_instance_valid(sanitation_service) or not sanitation_service.accident(self):return
	bladder_grace=0.0
	needs.bladder=75.0
	needs.hygiene=maxf(0.0,float(needs.hygiene)-35.0)
	add_moodlet("An awkward accident","Embarrassed","Could not reach the bathroom in time. A shower and a mop will help.",180.0,3)
	_emit_notice(str(character.name)+" could not hold on any longer. Click the puddle to mop it up.")


func _sanitation_reason(id:String,target:String,resuming:bool=false) -> String:
	if is_away():return "This Lifelet will be available after coming home."
	if LifeOutdoorActs.is_not_a_toilet(_target_kind_of(target)):
		return "A sand pit is for playing in, not for a toilet. Use an indoor toilet."
	if id=="plant_wee":
		if float(needs.bladder)>BLADDER_DESPERATE and not resuming:return "This emergency option is only available at 12 bladder or lower."
		var found:bool=false
		for entry:Dictionary in _targets:
			if str(entry.id)==target and str(entry.kind)=="plant":found=true;break
		if not found:return "Choose a real plant pot in this location."
	if not is_instance_valid(sanitation_service):return "That activity needs a current location."
	return sanitation_service.action_availability(self,id,target)


func _apply_continuous_effects(action: Dictionary, fraction: float) -> void:
	if str(action.id)=="eat_meal" and is_instance_valid(meal_service):meal_service.consume(self,action,fraction*float(action.duration))
	var changes: Dictionary = action["changes"]
	for need_name: String in changes:
		var amount: float = float(changes[need_name]) * fraction
		if need_name == SECOND_WIND_KEY:
			# Temporary energy is its own pool, so it is applied here and not
			# through the need dictionary.
			second_wind = clampf(second_wind + amount, 0.0, SECOND_WIND_MAX)
			continue
		if need_name == "fun":
			if (_has_trait("Creative") and action["id"] == "paint") or (_has_trait("Bookworm") and action["id"] == "read"):
				amount *= 1.5
			if _has_trait("Foodie") and action["id"] == "cook":
				amount *= 2.0
		if need_name == "social" and _has_trait("Outgoing") and amount > 0.0:
			amount *= 1.2
		needs[need_name] = clampf(float(needs[need_name]) + amount, 0.0, 100.0)
	if str(action["id"]) == "shower" and _has_trait("Neat"):
		needs["fun"] = minf(100.0, float(needs["fun"]) + 15.0 * fraction)
	var skill_name: String = str(action["skill"])
	if not skill_name.is_empty():
		var multiplier: float = 1.0
		if (skill_name == "creativity" and _has_trait("Creative")) or (skill_name == "charisma" and _has_trait("Outgoing")) or (skill_name == "logic" and _has_trait("Bookworm")) or (skill_name == "cooking" and _has_trait("Foodie")):
			multiplier = 1.4
		# The strongest moodlet and the activity's own emotion both count: the best
		# bonus applies once, and any penalty applies once, even while a nagging
		# need keeps the mood label at "Unsettled".
		var bonus: float = 1.0
		var penalty: float = 1.0
		for effect: Dictionary in [emotion_effect(str(get_mood().label)), emotion_effect(_activity_emotion(str(action["id"])))]:
			if effect.is_empty() or not (effect.skills.has("*") or effect.skills.has(skill_name)): continue
			if float(effect.multiplier) >= 1.0: bonus = maxf(bonus, float(effect.multiplier))
			else: penalty = minf(penalty, float(effect.multiplier))
		multiplier *= bonus * penalty
		# A book session teaches only as far as the book ceiling; the computer's
		# mastery actions carry the usual level-10 cap.
		var book_limit: int = LifeHouseholdFlow.BOOK_MAX_LEVEL if str(action.get("book_skill","")) == skill_name else 0
		_gain_skill(skill_name, float(action["xp"]) * fraction * multiplier, float(action["xp"]) * fraction, book_limit)


func _activity_emotion(id: String) -> String:
	# The feeling an activity carries on its own, matching the live mood labels.
	match id:
		"paint": return "Inspired" if _has_trait("Creative") else ""
		"paint_masterpiece": return "Inspired"
		"read", "study", "work", "job", "school", "homework", "play_chess", "play_games", "study_hard", "deep_read": return "Focused"
		"jog", "stretch", "dance", "dance_together", "push_through", "morning_run": return "Energized"
		"playful_prank": return "Playful"
		"bold_introduction": return "Confident"
	return ""


static func emotion_effect(emotion: String) -> Dictionary:
	# Emotions change how quickly skills grow, so a mood is a reason to choose an activity, not only a label.
	match emotion:
		"Inspired": return {"skills":["creativity","music"], "multiplier":1.25, "summary":"Creative and musical skills grow 25% faster, and paintings sell for more."}
		"Focused": return {"skills":["logic","cooking"], "multiplier":1.25, "summary":"Logic and Cooking grow 25% faster."}
		"Energized": return {"skills":["fitness"], "multiplier":1.3, "summary":"Fitness grows 30% faster."}
		"Playful": return {"skills":["charisma"], "multiplier":1.2, "summary":"Charisma grows 20% faster."}
		"Confident": return {"skills":["charisma"], "multiplier":1.15, "summary":"Charisma grows 15% faster."}
		"Happy": return {"skills":["*"], "multiplier":1.1, "summary":"Every skill grows 10% faster."}
		"Tense": return {"skills":["*"], "multiplier":0.8, "summary":"Skills grow 20% slower until this passes."}
		"Embarrassed": return {"skills":["charisma"], "multiplier":0.7, "summary":"Charisma grows 30% slower until this passes."}
	return {}


static func emotion_color(emotion: String) -> Color:
	# One shared palette for the HUD pill, the moodlet tiles and the selection gem.
	var colors: Dictionary = {"Happy":"65a68b","Energized":"c8aa5d","Confident":"6b9ac0","Focused":"629db3","Inspired":"9a85b3","Playful":"cf8aaa","Tense":"cf8669"}
	return Color(colors.get(emotion,"7aaf89"))


## Grow one skill from outside the action queue. A pet interaction credits the
## person's own learning this way, so a child teaching a trick grows in Logic and
## an adult training a pet grows in Parenting by exactly the advertised amount.
func gain_skill(skill_name: String, amount: float) -> void:
	if not SKILL_NAMES.has(skill_name) or amount <= 0.0: return
	_gain_skill(skill_name, amount)
	_emit_changed()


func _gain_skill(skill_name: String, amount: float, practice: float = -1.0, book_limit: int = 0) -> void:
	# Chapter practice counts the effort put in; emotion and trait bonuses only speed the skill.
	_record_practice(skill_name, amount if practice < 0.0 else practice)
	var skill: Dictionary = skills[skill_name]
	if int(skill["level"]) >= 10:
		return
	skill["xp"] = float(skill["xp"]) + amount
	var required: float = float(int(skill["level"]) * 50)
	var ceiling: int = book_limit if book_limit > 0 else 10
	while float(skill["xp"]) >= required and int(skill["level"]) < ceiling:
		skill["xp"] = float(skill["xp"]) - required
		skill["level"] = int(skill["level"]) + 1
		_emit_notice("%s reached %s level %d!" % [character["name"], skill_name.capitalize(), int(skill["level"])])
		required = float(int(skill["level"]) * 50)
	# A book cannot carry a skill past level 9: the tenth level is the computer's.
	# Leftover XP stays banked, so the shelf keeps teaching until the ceiling is
	# reached and the computer then continues from exactly here.
	if book_limit > 0 and int(skill["level"]) >= book_limit:
		skill["xp"] = minf(float(skill["xp"]), required - 1.0)


func _finish_front() -> void:
	if not action_queue.is_empty() and action_queue[0].has("cooperation_id") and is_instance_valid(cooperation_owner):
		cooperation_owner.finish_cooperative_action(str(action_queue[0].cooperation_id))
		return
	var action: Dictionary = action_queue.pop_front()
	var id: String = str(action["id"])
	var earned: int = 0
	if id in LEISURE_ACTIONS or id=="bath":
		_leisure_history.erase(id);_leisure_history.push_front(id)
		while _leisure_history.size()>LEISURE_HISTORY:_leisure_history.pop_back()
		autonomy_state["leisure"]=_leisure_history.duplicate()
	if not str(action.get("target_id","")).is_empty():_recent_target_use[str(action.target_id)]=_autonomy_now()
	_maybe_credit_host(id)
	_maybe_credit_companion(id,action.get("target_position"))
	if id in AGE_GATED_ACTIONS and not bool(get_action_availability(id, str(action.get("target_id",""))).available):
		# A restored or edited queue cannot grant an activity this age may not do.
		_emit_notice(str(get_action_availability(id, str(action.get("target_id",""))).reason))
		_start_front()
		_emit_changed()
		return
	if id in ["school","homework"]:
		var target_error: String = _school_action_error(action)
		if not target_error.is_empty():
			_emit_notice(target_error)
			_start_front()
			_emit_changed()
			return
		var result: Dictionary = LifeEducation.complete(education,str(character.age_stage),day,minutes,id)
		if not bool(result.ok):
			_emit_notice(str(result.error))
			action["phase"] = "cancelled"
			_start_front()
			_emit_changed()
			return
		_apply_education_result(result)
		if id == "school": add_moodlet("Something learned","Focused","Online lessons are complete for today.",120,2)
		else: add_moodlet("Ready for class","Focused","The next assignment is prepared.",120,1)
	elif id == "birthday":
		if str(action.get("birthday_from_stage","")) == str(character.age_stage): celebrate_birthday(false)
	elif id == "paint" or id == "paint_masterpiece":
		# A masterpiece rides the Inspired mood: its canvas is worth far more
		# than an ordinary sale, and the mood bonus stacks on top.
		var sale: int = 55 + int(skills["creativity"]["level"]) * 35
		if str(get_mood().label) == "Inspired": sale = int(sale * 1.25)
		if id == "paint_masterpiece":
			sale = 130 + int(skills["creativity"]["level"]) * 60
			if str(get_mood().label) == "Inspired": sale = int(sale * 1.5)
		funds += sale
		earned = sale
		_emit_notice("Canvas sold for ℒ%d. A little creativity goes a long way." % sale)
	elif id == "host_a_chat":
		# A host gathers the room: every housemate who can actually see the host
		# shares the social lift. Somebody on the far side of a partition is not
		# in the room and hears none of it.
		var lifted: int = 0
		for member: Dictionary in _autonomy_household_members():
			if member.sim == self or is_instance_valid(member.sim) and member.sim.is_away(): continue
			if social_witness.is_valid() and not bool(social_witness.call(_social_member_id,str(member.id))): continue
			member.sim.needs["social"] = minf(100.0, float(member.sim.needs["social"]) + 25.0)
			lifted += 1
		if lifted > 0:
			_emit_notice("%d %s drawn into the conversation." % [lifted, "housemate was" if lifted == 1 else "housemates were"])
	elif id == "work":
		var income: int = 55 + int(skills["logic"]["level"]) * 20
		funds += income
		earned = income
		career["performance"] = minf(100.0, float(career["performance"]) + _career_performance_gain(8.0))
		_emit_notice("Freelance project complete. Earned ℒ%d." % income)
	elif id == "job":
		var income: int = int(career["salary"])
		funds += income
		earned = income
		career["worked_day"] = day
		career.schedule=LifeCareerSchedule.attend(career.get("schedule",LifeCareerSchedule.fresh(day)),day,0.0)
		# A home shift is the same work as the commute, so it trains the same
		# skill and is judged by it — a trade with no skill of its own simply
		# has none to raise.
		var job_skill: String = str(LifeCareers.job(str(career.get("track", ""))).get("skill", ""))
		var skill_rank: float = 0.0
		if SKILL_NAMES.has(job_skill):
			_gain_skill(job_skill, 24.0)
			skill_rank = float(skills[job_skill].level)
		var comfort: float = (float(needs["hunger"]) + float(needs["energy"]) + float(needs["fun"])) / 3.0
		# At the top of the ladder there is no promotion left to spend performance
		# on, so it would accumulate for ever — past the ceiling the save validator
		# allows, which made a maxed career impossible to save. It is capped where
		# the ladder ends, exactly as the freelance and scheduled work already cap
		# theirs.
		career["performance"] = minf(100.0 if int(career["level"]) >= LifeCareers.MAX_LEVEL else 1000.0,
			float(career["performance"]) + _career_performance_gain(18.0 + comfort * 0.15 + skill_rank * 2.0))
		_emit_notice("Shift finished. Earned ℒ%d." % income)
		_check_promotion()
	elif id in SOCIAL_ACTIONS:
		action["social_accepted"] = _apply_social(action)
		if bool(action.social_accepted): _record_autonomy_contact(_social_target(str(action.target_id)),id)
		action["social_events"] = _recent_social_events.duplicate(true)
	elif id == "talk_to_myself":
		# A full-length mirror is a real confidence practice: one full level of
		# Charisma a day, and the moodlet that comes with feeling good.
		var granted:bool=_mirror_level_grant()
		add_moodlet("Feeling sure of myself","Confident","A good long look in the mirror does wonders.",240,2)
		_emit_notice("A whole level of Charisma, and it shows." if granted else "A good talk with the mirror. You have already gained from this today.")
		action["open_wardrobe_panel"]=true
	elif id == "change_in_wardrobe" or id == "change_in_mirror" or id == "do_makeup" or id == "change_jewelry":
		action["open_wardrobe_panel"]=id
	elif id == "water":
		_emit_notice("The plants look happier. Gardening skill improved.")
	elif id == "change_outfit" or WEAR_CATEGORY_ACTIONS.has(id) or WEAR_ACTIONS.has(id):
		if WEAR_ACTIONS.has(id):
			character["outfit"] = int(WEAR_ACTIONS[id])
			LifeCharacterIdentity.store_current(character)
			_emit_notice("%s changed into the %s outfit." % [character["name"], ["casual", "jacket", "cardigan", "tee", "hoodie"][int(character["outfit"])]])
		else:
			var category: String = str(WEAR_CATEGORY_ACTIONS[id]) if WEAR_CATEGORY_ACTIONS.has(id) else LifeCharacterIdentity.next_category(character.get("outfit_category", "everyday"))
			LifeCharacterIdentity.apply_category(character, category)
			_emit_notice("%s changed into their %s look." % [character["name"], LifeCharacterIdentity.category_label(category).to_lower()])
		add_moodlet("Freshly changed", "Confident", "A new outfit, a new outlook.", 120, 1)
	elif id == "cook" and _has_trait("Foodie"):
		_emit_notice("A delicious homemade meal! Your Foodie trait made it extra satisfying.")
	elif id == "toilet" and not is_away():
		# Washing hands afterwards is part of using the bathroom, not a separate
		# chore the player has to remember. A sink in reach queues the short
		# wash as this Lifelet's next action; without one the visit ends as before.
		_queue_follow_up("wash_hands")
	elif id == "empty_bin":
		if is_instance_valid(household_service):household_service.empty_bin(str(action.get("target_id","")))
		_emit_notice("The rubbish is out. The kitchen smells fresher already.")
	elif id == "order_groceries" and is_instance_valid(grocery_service):
		# The computer's own panel places this order through the household when a
		# player uses it. A Lifelet who reaches the kitchen's own order entry (the
		# fridge) has nobody at the keyboard, so the shop is placed here: the
		# largest basket the purse can afford, and the van is on its way.
		var placed:Dictionary=grocery_service.order_groceries_best()
		if not bool(placed.get("ok",false)):
			_emit_notice(str(placed.get("error","The shop could not be ordered just now.")))
	elif id == "watch_together":
		pass
	elif id in ["pet_feed", "pet_play", "pet_teach_trick", "pet_walk", "pet_pet", "pet_train", "pet_tug", "pet_tummy_rub"]:
		if is_instance_valid(cooperation_owner) and cooperation_owner.has_method("do_pet_interaction"):
			var cared:Dictionary=cooperation_owner.do_pet_interaction(str(action.get("target_id","")),_social_member_id,id)
			if bool(cared.get("ok",false)):
				var label:String=str(_actions.get(id,{}).get("label",id))
				_emit_notice("%s with %s." % [label, str(action.get("pet_name","your pet"))])
				if id == "pet_walk" and is_instance_valid(cooperation_owner) and cooperation_owner.has_method("credit_pet_walk_chat"):
					cooperation_owner.credit_pet_walk_chat(_social_member_id, str(action.get("target_id","")))
				# A stroke or a tummy rub is also remembered on the pet's own
				# record, as it was before these ran through LifePetCare.
				if id in ["pet_pet", "pet_tummy_rub"] and is_instance_valid(household_service):
					household_service.affectionate_pet(str(action.get("target_id","")),str(character.get("name","")))
				# Playing tricks is also a lesson in the next named trick, so the
				# pet's own record of what it knows still grows.
				if id == "pet_teach_trick" and is_instance_valid(household_service) and household_service.has_method("teach_pet_trick"):
					var taught:Dictionary=household_service.teach_pet_trick(str(action.get("target_id","")),str(character.get("name","")))
					if bool(taught.get("learned",false)):
						_emit_notice("%s learned to %s!" % [str(action.get("pet_name","the pet")), str(taught.get("trick",""))])
			else:
				_emit_notice(str(cared.get("error","That did not work with the pet.")))
	elif id == "teach_pet_trick":
		# Teaching is real progress: the pet keeps the trick it learned, and the
		# house's own record names what it can do.
		var learned:String = ""
		if is_instance_valid(household_service):
			var taught:Dictionary = household_service.teach_pet_trick(str(action.get("target_id","")),str(character.get("name","")))
			learned = str(taught.get("trick",""))
		if learned.is_empty():
			_emit_notice("A patient session, but nothing stuck today. Try again another time.")
		else:
			_emit_notice("%s learned to %s!" % [str(action.get("pet_name","the pet")), learned])
	elif id == "bathe_pet":
		# A bath really cleans the coat: the pet's own cleanliness is restored,
		# and the household's sink or tub is the place it happened.
		if is_instance_valid(household_service):
			household_service.bathe_pet(str(action.get("target_id","")),str(character.get("name","")))
		_emit_notice("%s is clean and fluffy again." % str(action.get("pet_name","The dog")))
	elif id in ["feed_baby_bottle", "feed_baby_food", "change_nappy", "cuddle_baby", "play_with_baby", "talk_to_baby", "spin_baby_mobile", "play_rattle", "play_baby_mat", "use_potty", "play_dollhouse"]:
		# The caregiver completes the action, but the need it answers is the
		# baby's own: feeding fills their hunger, a nappy their hygiene and
		# bladder, a cuddle and play their social and fun. The caregiver also
		# gains a little Parenting, because caring for a child is how it is
		# learned.
		_care_for_baby(id)
	_activity_memory(id)
	_record_chapter_activity(id, earned, _social_target(str(action.get("target_id", ""))) if bool(action.get("social_accepted", false)) else "")
	for want: Dictionary in wants:
		if str(want["id"]) == "first_meal" and id == "cook":
			want["progress"] = 1.0
		elif str(want["id"]) == "create" and id == "paint":
			want["progress"] = float(want["progress"]) + 1.0
		elif str(want["id"]) == "earn" and id in ["work", "job", "paint"]:
			want["progress"] = float(want["progress"]) + 1.0
	action["phase"] = "finished"
	if is_instance_valid(meal_service):meal_service.finished(self,action)
	if is_instance_valid(sanitation_service):sanitation_service.finished(self,action)
	if not whims.is_empty():
		var w_res: Dictionary = LifeWantsManager.evaluate_action(whims, id)
		if bool(w_res.get("fulfilled", false)):
			var rew: int = int(w_res.reward)
			satisfaction += rew
			var m: Dictionary = w_res.moodlet
			add_moodlet(str(m.label), str(m.emotion), str(m.description), float(m.duration), int(m.strength))
			_emit_notice("Desire fulfilled: %s! +%d satisfaction." % [str(w_res.whim.label), rew])
			LifeWantsManager.refresh_whims(whims, character, needs, str(get_mood().label))
		if bool(w_res.get("cured_fear", false)):
			var frew: int = int(w_res.fear_reward)
			satisfaction += frew
			var fm: Dictionary = w_res.fear_moodlet
			add_moodlet(str(fm.label), str(fm.emotion), str(fm.description), float(fm.duration), int(fm.strength))
			_emit_notice("Conquered fear: %s! +%d satisfaction!" % [str(w_res.fear.label), frew])
	if id in HOME_AFTER:
		_wear_home_clothes()
	_emit_action_finished(action)
	_idle_minutes = 0.0
	_update_wants()
	_start_front()
	_emit_changed()


## The mirror's own Charisma level. Once a game day, so a Lifelet cannot stand in
## front of the glass and level the whole skill in one afternoon.
func _mirror_level_grant() -> bool:
	if _mirror_level_day == day:return false
	_mirror_level_day = day
	skills["charisma"]["level"] = mini(int(skills["charisma"]["level"]) + 1, 10)
	skills["charisma"]["xp"] = 0.0
	return true


## The solo dance's finish effects, applied once for a group dancer. The needs
## and Fitness skill were already applied minute by minute while the record
## played; this is the moodlet, the chapter record and the host credit, exactly
## as the solo finish path pays them.
func _apply_dance_result(action: Dictionary) -> void:
	_maybe_credit_host("dance")
	_maybe_credit_companion("dance",action.get("target_position"))
	_activity_memory("dance")
	_record_chapter_activity("dance",0)

func _maybe_credit_host(action_id: String) -> void:
	# Doing a leisure activity at a resident's home warms the friendship with
	# the host, at most once an in-game hour. Distinct from the resident's own
	# self-started contacts: this is the member as a guest at the host's place.
	if visited_venue.is_empty() or visited_venue=="home":return
	if not (action_id in LEISURE_ACTIONS or action_id=="study"):return
	if _autonomy_now()-last_hosted_credit<60.0:return
	var host: String = str(LifeNeighborhood.PLACES.get(visited_venue,{}).get("resident",""))
	if host.is_empty() or not relationships.has(host):return
	last_hosted_credit=_autonomy_now()
	var person: Dictionary = relationships[host]
	person["friendship"] = clampf(float(person["friendship"]) + 3.0, -100.0, 100.0)
	_update_relationship_status(person)
	if int(routine_memory_days.get(host,-1))!=day:
		routine_memory_days[host]=day
		remember("Time at "+str(person["name"]).split(" ")[0]+"'s place","Spent part of the day together at their home.")
	_emit_notice("Time at %s's place brings you closer." % str(person["name"]).split(" ")[0])


func _maybe_credit_companion(action_id: String, at: Vector3) -> void:
	# A routine resident working at their venue during the window joins a
	# matching leisure activity NEAR their anchor object: friendship with
	# them grows, at most once an in-game hour. Separate throttle from the
	# hosted-visit credit.
	if visited_venue.is_empty() or visited_venue=="home":return
	if not (action_id in LEISURE_ACTIONS or action_id=="study"):return
	if _autonomy_now()-last_companion_credit<60.0:return
	for resident_id: String in LifeResidentCatalogue.IDS:
		var person: Dictionary = LifeResidentCatalogue.PEOPLE[resident_id]
		var routine: Dictionary = person.get("routine", {})
		if routine.is_empty() or str(routine.get("venue",""))!=visited_venue:continue
		if not LifeResidentCatalogue.routine_active(person,LifeEducation.weekday(day),minutes):continue
		if not relationships.has(resident_id):continue
		var anchor: Vector3 = companion_anchors.get(resident_id, Vector3.INF)
		if at.distance_to(anchor)>2.5:continue
		last_companion_credit=_autonomy_now()
		var rel: Dictionary = relationships[resident_id]
		rel["friendship"] = clampf(float(rel["friendship"]) + 2.0, -100.0, 100.0)
		_update_relationship_status(rel)
		if int(routine_memory_days.get(resident_id,-1))!=day:
			routine_memory_days[resident_id]=day
			remember("Time with "+str(person["name"]).split(" ")[0],"Shared part of a weekday at "+str(routine.get("place","the room"))+".")
		_emit_notice("%s is here too, and %s feels less quiet with company." % [str(person["name"]).split(" ")[0],str(routine.get("place","the room"))])
		return


func _normalize_relationship(person: Dictionary, legacy: bool) -> void:
	person["life_stage"] = str(person.get("life_stage", "adult"))
	person["bond"] = str(person.get("bond", "none"))
	person["family_role"] = str(person.get("family_role", "none"))
	if not person.has("milestones"):
		person["milestones"] = []
		if legacy:
			if float(person.friendship) >= 35.0: person.milestones.append("friends")
			if float(person.friendship) >= 65.0: person.milestones.append("close_friends")
			if float(person.romance) >= 20.0: person.milestones.append("spark")


func set_social_context(member_id: String, partners: Dictionary, adults: Dictionary, reciprocal: Dictionary = {}, family_roles: Dictionary = {}) -> void:
	_social_member_id = member_id
	_social_partners = partners.duplicate(true)
	_social_adults = adults.duplicate(true)
	_social_reciprocal = reciprocal.duplicate(true)
	_social_family = family_roles.duplicate(true)


func _family_role(target: String) -> String:
	return str(_social_family.get(target,relationships.get(target,{}).get("family_role","none")))


func _social_target(target_id: String) -> String:
	if target_id.is_empty():
		return "maya"
	if relationships.has(target_id):
		return target_id
	for known_id: String in relationships:
		if target_id == "neighbor_" + known_id:
			return known_id
	return ""


func get_action_availability(id: String, target_id: String = "") -> Dictionary:
	var reason: String = ""
	if id in ["plant_wee","mop_puddle"]:
		reason=_sanitation_reason(id,target_id)
		if not reason.is_empty():return {"available":false,"reason":reason}
	if is_instance_valid(meal_service) and id in ["cook","eat_meal","store_meal","clean_plate","discard_meal","bin_meal","put_in_fridge"]:
		reason=meal_service.action_availability(self,id,target_id)
		if not reason.is_empty():return {"available":false,"reason":reason}
	# A recipe and a snack both come out of the kitchen, so an empty fridge is
	# what refuses them. The reason names the computer, which is where the
	# household orders its delivery from.
	if is_instance_valid(grocery_service) and id in ["cook","snack"]:
		reason=str(grocery_service.cooking_availability(self,target_id))
		if not reason.is_empty():return {"available":false,"reason":reason}
	# An order is placed for the whole household, so whether one may be placed at
	# all is the household's own answer: a delivery already on its way, a purse
	# that cannot afford even the smallest basket, or a kitchen already stocked.
	if is_instance_valid(grocery_service) and str(id) == "order_groceries":
		reason=str(grocery_service.grocery_availability())
		if not reason.is_empty():return {"available":false,"reason":reason}
	if not _actions.has(id):
		return {"available":false, "reason":"That activity is unavailable."}
	# A mood or a trait can be the price of admission. This sits before every
	# target and queue rule, so a caller that never sees the option and one that
	# asks for it directly are refused with the same reason.
	if EMOTION_ACTIONS.has(id) and str(get_mood().label) != str(EMOTION_ACTIONS[id]):
		return {"available":false, "reason":"Only available while %s." % str(EMOTION_ACTIONS[id])}
	if TRAIT_ACTIONS.has(id) and not _has_trait(str(TRAIT_ACTIONS[id])):
		return {"available":false, "reason":"Only a %s Lifelet thinks to do this." % str(TRAIT_ACTIONS[id])}
	# An unpaid bill has a real cost: the utilities are cut, so the home cannot
	# cook, run hot water or run anything electrical until the household settles.
	if utilities_cut and id in UTILITY_ACTIONS:
		return {"available":false, "reason":"The utilities are cut. Pay the outstanding ℒ%d bill from the phone." % bill_total_due()}
	# A baby is driven by a caregiver: it keeps its recovery and play set and is
	# refused everything else here, before any target or queue rule applies.
	var stage_reason: String = LifeStagePolicy.action_error(str(character.age_stage), str(character.life_stage), id)
	if not stage_reason.is_empty():
		return {"available":false, "reason":stage_reason}
	# A garden game's own gate names the game, so the reason a player reads says
	# which game is too old for them rather than naming only the action.
	if id == LifeGardenGames.ACTION_ID:
		var game_kind: String = _target_kind_of(target_id)
		var game_reason: String = LifeGardenGames.play_error(game_kind, str(character.age_stage), is_away())
		if not game_reason.is_empty():
			return {"available":false, "reason":game_reason}
	elif id == LifeOutdoorActs.ACTION_ID:
		var act_kind: String = _target_kind_of(target_id)
		var act_reason: String = LifeOutdoorActs.act_error(act_kind, str(character.age_stage), is_away(), _pool_present(), _actor_is_pregnant())
		if not act_reason.is_empty():
			return {"available":false, "reason":act_reason}
	elif id == LifeOutdoorActs.PUSH_ID:
		var push_reason: String = LifeOutdoorActs.push_refusal(_target_kind_of(target_id), str(character.age_stage), is_away())
		if not push_reason.is_empty():
			return {"available":false, "reason":push_reason}
	if is_spirit() and (id in SPIRIT_BLOCKED or id == LifeBabyPlan.ACTION_ID):
		return {"available":false, "reason":"A spirit has finished that chapter of life."}
	# A bicycle's own entry names the ages that fit it, and a helmet must really
	# stand in the home. The rule is stated plainly: you must wear one to ride.
	if id == "ride_bike":
		return {"available":false, "reason":_ride_bike_error(target_id)} if not _ride_bike_error(target_id).is_empty() else {"available":true, "reason":""}
	if id=="career_day":
		reason=_career_departure_error(target_id)
		if reason.is_empty() and is_instance_valid(cooperation_owner) and cooperation_owner.has_method("pregnancy_mother_id"):
			if str(cooperation_owner.pregnancy_mother_id())==_social_member_id and LifeBabyPlan.on_maternity_leave(cooperation_owner.pregnancy,day,minutes):
				reason="Maternity leave: no work shifts on the last two days before the baby arrives."
	elif id == LifeBabyPlan.ACTION_ID:
		reason=_try_for_baby_error(target_id)
	elif id == "school_day":
		reason = _school_departure_error(target_id)
	elif id in ["school","homework"]:
		reason = _school_availability(id,target_id)
	elif id == "birthday" and LifeLifecycle.next_stage(str(character.age_stage)).is_empty():
		reason = "This Lifelet has no further birthday stage."
	elif id in ["job", "work"] and str(character.life_stage) != "adult":
		reason = "Full-time careers and freelance work are available to adults."
	elif COMPUTER_MASTERY_ACTIONS.has(id):
		# The computer is allowed to finish the tenth level, and refused exactly
		# there: once a subject is mastered the screen has nothing left to teach.
		var mastery_skill:String=id.trim_prefix("computer_")
		if int(skills.get(mastery_skill,{"level":1}).level)>=10:
			reason = "%s is already at level 10. This Lifelet has mastered it." % mastery_skill.capitalize()
	elif is_instance_valid(household_service) and id in LifeHouseholdFlow.SERVICE_ACTIONS:
		reason=household_service.action_availability(self,id,target_id)
	elif id == "cook" and str(character.age_stage) == "child":
		reason = "Children can grab a snack. An older Lifelet can use the stove."
	elif id == "jog" and str(character.age_stage) == "child":
		reason = "The treadmill is for teens and adults."
	elif id in ["push_through"] and str(character.age_stage) == "child":
		reason = "The treadmill is for teens and adults."
	elif id == "morning_run" and str(character.age_stage) == "child":
		reason = "Long runs around the block are for teens and adults."
	elif id == "play_toys" and str(character.age_stage) != "child":
		reason = "The toy chest is for children."
	elif funds < int(_actions[id].cost):
		reason = "Requires ℒ%d." % int(_actions[id].cost)
	elif id == "job" and int(career.worked_day) == day:
		reason = "Today's shift is already complete."
	elif id=="job" and day<int(career.get("schedule",LifeCareerSchedule.fresh(day)).first_day):
		reason="Your first shift begins on the next workday."
	elif id in ["teach_pet_trick","pet_tummy_rub","bathe_pet","pet_feed","pet_play","pet_teach_trick","pet_walk","pet_pet","pet_train","pet_tug"]:
		reason=_pet_action_error(id,target_id)
	elif id in SOCIAL_ACTIONS:
		var target: String = _social_target(target_id)
		if target.is_empty() or target == _social_member_id:
			reason = "Choose another Lifelet to talk with."
		elif id in RELATIONSHIP_ACTIONS or id == "flirt":
			var person: Dictionary = relationships[target]
			var mutual_friendship: float = float(person.friendship)
			var mutual_romance: float = float(person.romance)
			if _social_reciprocal.has(target):
				mutual_friendship = minf(mutual_friendship, float(_social_reciprocal[target].friendship))
				mutual_romance = minf(mutual_romance, float(_social_reciprocal[target].romance))
			var both_adults: bool = str(character.get("life_stage", "adult")) == "adult" and str(person.get("life_stage", "adult")) == "adult"
			both_adults = both_adults and bool(_social_adults.get(target, true))
			if LifeFamilyGraph.is_family(_family_role(target)):
				reason = "Romantic actions are unavailable between siblings." if _family_role(target)=="siblings" else "Romantic actions are unavailable between family members."
			elif not both_adults:
				reason = "Romantic relationships are available only between adults."
			elif id == "ask_partner":
				if not romantic_partner.is_empty():
					reason = "End your current partnership before starting another."
				elif not str(_social_partners.get(target, "")).is_empty():
					reason = "%s is already in a partnership." % person.name
				elif mutual_friendship < 45.0 or mutual_romance < 35.0:
					reason = "Both Lifelets need at least 45 friendship and 35 romance before becoming partners."
			elif id == "commit":
				if romantic_partner != target or str(person.get("bond", "none")) != "partners":
					reason = "Make a commitment with your current partner."
				elif mutual_friendship < 65.0 or mutual_romance < 65.0:
					reason = "Both Lifelets need at least 65 friendship and 65 romance before making a commitment."
			elif id == "break_up" and romantic_partner != target:
				reason = "You are not currently partners."
	return {"available":reason.is_empty(), "reason":reason}


## Whether this Lifelet can do this with that animal. A tummy rub is a dog's own
## request — a cat will not have it — so the species rule lives here rather than
## in the menu, and a hidden option and a direct request are refused alike.
func _pet_action_error(id:String,target_id:String) -> String:
	var record:Dictionary=_pet_record_for(target_id)
	if record.is_empty():
		return "That pet is not part of this household."
	var species:String=str(record.get("species","dog"))
	if id in LifePetCare.interaction_ids():
		return LifePetCare.interaction_error(id, str(character.age_stage), is_away(), species)
	if id=="pet_tummy_rub" and species != "dog":
		return "%s is a cat. Cats keep their tummies to themselves." % str(record.get("name","This pet"))
	if id=="bathe_pet":
		if not LifePetCare.stage_handles(str(character.age_stage)):
			return "A %s is too young to bathe a pet." % str(LifeLifecycle.LABELS.get(str(character.age_stage),"Lifelet")).to_lower()
		if is_away():return "Wait until this Lifelet is home."
		if not LifePets.needs_bathing(species):
			return "%s is a cat. Cats keep themselves clean by licking." % str(record.get("name","This pet"))
		# The coat lives in the LifePetCare condition the bath restores; a record
		# from before that kept `needs.cleanliness` on the pet itself.
		var care_needs:Dictionary=((record.get("care",{}) as Dictionary).get("needs",{}) as Dictionary) if record.get("care") is Dictionary else {}
		var coat:float=float(care_needs.get("hygiene",(record.get("needs",{}) as Dictionary).get("cleanliness",100.0)))
		if coat>=92.0:
			return "%s is already clean." % str(record.get("name","This pet"))
	if id=="teach_pet_trick" and is_instance_valid(household_service):
		if not household_service.has_method("next_trick") or str(household_service.call("next_trick",target_id)).is_empty():
			return "%s already knows every trick you can teach." % str(record.get("name","This pet"))
	return ""

## The household's live pet record, or empty when the id names no pet here. The
## simulation reaches it through the live household service, exactly as it
## reaches the meal and sanitation ledgers.
func _pet_record_for(pet_id:String) -> Dictionary:
	if not is_instance_valid(household_service) or not household_service.has_method("pet_record"):
		return {}
	var record:Variant=household_service.call("pet_record",pet_id)
	return record if record is Dictionary else {}

## Whether this household has a baby to care for. The baby-care actions are only
## offered when one is really here, so a household without a baby never sees a
## button it cannot use.
func _has_baby() -> bool:
	return _baby_in_household() != null

func _infant_at_least(phase: String) -> bool:
	var baby: LifeSim = _baby_in_household()
	if baby == null:
		return false
	var order: Array[String] = [LifeBabyPlan.INFANT_NEWBORN, LifeBabyPlan.INFANT_SITTING, LifeBabyPlan.INFANT_TODDLER]
	var have: String = LifeBabyPlan.advance_infant_phase(baby.character, day)
	return order.find(have) >= order.find(phase)

## Hospital stay after birth: mother and newborn wait off-lot until Welcome Baby
## Home clears this away-state. No school-style auto-return.
func begin_hospital_stay(exit_position: Vector3) -> void:
	action_queue.clear()
	away_state = {
		"version": 1,
		"activity": "hospital",
		"phase": "away",
		"departure_day": day,
		"departure_minutes": minutes,
		"return_day": day + 30,
		"return_minutes": minutes,
		"exit_id": "lot_exit",
		"exit_position": exit_position,
		"age_stage": str(character.age_stage),
		"completed": false,
		"ended_at": 0.0,
	}
	_publish("away_changed", [get_away_state()])
	_emit_changed()

func end_hospital_stay() -> void:
	if str(away_state.get("activity", "")) != "hospital":
		return
	away_state = {}
	_publish("away_changed", [get_away_state()])
	_emit_changed()

## The baby this caregiver is caring for, so a care action can answer the
## child's own needs rather than the caregiver's. A baby is a household member
## like any other, so this reads the household's own member list.
func _baby_in_household() -> LifeSim:
	var owner: Variant = cooperation_owner
	if not is_instance_valid(owner) or not owner is Node: return null
	var family: Variant = owner.get("members")
	if not family is Array: return null
	for entry: Variant in family:
		if not entry is Dictionary: continue
		var other: Variant = (entry as Dictionary).get("sim")
		if other is LifeSim and is_instance_valid(other) and str(other.character.age_stage) == "baby":
			return other
	return null


## Answer a baby's own needs for a care action the caregiver just finished. The
## caregiver's own need changes ride the action definition; this is the child's
## side of the same minute, and the notice names the baby so a player with two
## children knows who was seen to.
func _care_for_baby(action_id: String) -> void:
	var baby: LifeSim = _baby_in_household()
	if baby == null:
		_emit_notice("There is no baby here to care for just now.")
		return
	var name: String = str(baby.character.name).split(" ")[0]
	match action_id:
		"feed_baby_bottle":
			baby.needs["hunger"] = minf(100.0, float(baby.needs.get("hunger", 0.0)) + 42.0)
			_emit_notice("%s finishes the bottle." % name)
		"feed_baby_food":
			baby.needs["hunger"] = minf(100.0, float(baby.needs.get("hunger", 0.0)) + 62.0)
			baby.needs["fun"] = minf(100.0, float(baby.needs.get("fun", 0.0)) + 8.0)
			_emit_notice("%s has had a proper meal." % name)
		"change_nappy":
			baby.needs["hygiene"] = minf(100.0, float(baby.needs.get("hygiene", 0.0)) + 55.0)
			baby.needs["bladder"] = minf(100.0, float(baby.needs.get("bladder", 0.0)) + 70.0)
			_emit_notice("%s is clean and comfortable again." % name)
		"cuddle_baby":
			baby.needs["social"] = minf(100.0, float(baby.needs.get("social", 0.0)) + 45.0)
			baby.needs["fun"] = minf(100.0, float(baby.needs.get("fun", 0.0)) + 20.0)
			_emit_notice("%s is happy in your arms." % name)
		"talk_to_baby":
			baby.needs["social"] = minf(100.0, float(baby.needs.get("social", 0.0)) + 28.0)
			baby.needs["fun"] = minf(100.0, float(baby.needs.get("fun", 0.0)) + 10.0)
			_emit_notice("A quiet chat settles %s." % name)
		"spin_baby_mobile":
			baby.needs["fun"] = minf(100.0, float(baby.needs.get("fun", 0.0)) + 34.0)
			_emit_notice("%s watches the mobile spin." % name)
		"play_rattle":
			baby.needs["fun"] = minf(100.0, float(baby.needs.get("fun", 0.0)) + 22.0)
			baby._gain_skill("logic", 4.0)
			_emit_notice("%s shakes along with the rattle." % name)
		"play_baby_mat":
			baby.needs["fun"] = minf(100.0, float(baby.needs.get("fun", 0.0)) + 26.0)
			baby.needs["social"] = minf(100.0, float(baby.needs.get("social", 0.0)) + 18.0)
			baby._gain_skill("logic", 6.0)
			_emit_notice("%s practises sitting on the mat." % name)
		"use_potty":
			baby.needs["hygiene"] = minf(100.0, float(baby.needs.get("hygiene", 0.0)) + 30.0)
			baby.needs["bladder"] = minf(100.0, float(baby.needs.get("bladder", 0.0)) + 40.0)
			_emit_notice("Potty practice with %s." % name)
		"play_dollhouse":
			baby.needs["fun"] = minf(100.0, float(baby.needs.get("fun", 0.0)) + 36.0)
			baby.needs["social"] = minf(100.0, float(baby.needs.get("social", 0.0)) + 16.0)
			_emit_notice("%s plays house for a while." % name)
		"play_with_baby":
			baby.needs["fun"] = minf(100.0, float(baby.needs.get("fun", 0.0)) + 40.0)
			baby.needs["social"] = minf(100.0, float(baby.needs.get("social", 0.0)) + 32.0)
			_emit_notice("%s giggles through the whole game." % name)
	# The baby remembers who looked after them, the way a pet remembers a cuddle.
	baby.add_moodlet("Loved","Happy","Somebody took care of me just now.",120,2)
	baby._emit_changed()

func _try_for_baby_error(bed_id: String) -> String:
	# The household owns the pair's identities and the family state; the
	# simulation only binds them to this Lifelet's own bed click.
	if not is_instance_valid(cooperation_owner) or not cooperation_owner.has_method("try_for_baby_plan"):
		return "Try for Baby needs a live household."
	if is_away():return "This Lifelet will be available after coming home."
	var plan:Dictionary=cooperation_owner.try_for_baby_plan(_social_member_id,bed_id)
	return "" if bool(plan.ok) else str(plan.get("error","Try for Baby is unavailable right now."))

func _social_detail(stage: String, name: String) -> Dictionary:
	match stage:
		"met": return {"label":"A new conversation", "detail":"You took time to get to know %s." % name}
		"friends": return {"label":"A friendship takes root", "detail":"You and %s have become friends." % name}
		"close_friends": return {"label":"Someone to count on", "detail":"Your friendship with %s has grown close." % name}
		"spark": return {"label":"A mutual spark", "detail":"Your connection with %s is becoming romantic." % name}
		"partners": return {"label":"Choosing each other", "detail":"You and %s agreed to become partners." % name}
		"committed": return {"label":"A shared future", "detail":"You and %s made a commitment to each other." % name}
		_: return {"label":"Going separate ways", "detail":"You and %s ended your partnership." % name}


func _record_social_event(target: String, stage: String, announce: bool = true) -> void:
	var name: String = str(relationships[target].name)
	var text: Dictionary = _social_detail(stage, name)
	var entry: Dictionary = {"day":day, "minutes":int(minutes), "target_id":target, "target_name":name, "stage":stage, "label":text.label, "detail":text.detail}
	social_history.push_front(entry)
	while social_history.size() > MAX_PROGRESS_HISTORY:
		social_history.pop_back()
	_recent_social_events.append(entry.duplicate(true))
	remember(str(text.label), str(text.detail))
	if announce:
		_emit_notice(str(text.detail))


func _record_social_milestones(target: String, action_id: String) -> void:
	var person: Dictionary = relationships[target]
	_normalize_relationship(person, false)
	var achieved: Array[String] = []
	if action_id in ["friendly", "joke", "deep_talk", "hug", "share_interests", "sympathize", "gossip", "playful_prank", "bold_introduction"]: achieved.append("met")
	if float(person.friendship) >= 35.0: achieved.append("friends")
	if float(person.friendship) >= 65.0: achieved.append("close_friends")
	if float(person.romance) >= 20.0 and not LifeFamilyGraph.is_family(_family_role(target)): achieved.append("spark")
	for stage: String in achieved:
		if not person.milestones.has(stage):
			person.milestones.append(stage)
			_record_social_event(target, stage)


func _apply_relationship_action(id: String, target: String) -> bool:
	var person: Dictionary = relationships[target]
	match id:
		"ask_partner":
			romantic_partner = target
			person.bond = "partners"
			add_moodlet("Choosing each other", "Happy", "A relationship you both want to grow.", 240, 3)
			_record_social_event(target, "partners")
		"commit":
			person.bond = "committed"
			add_moodlet("A shared future", "Confident", "You have affirmed your commitment to each other.", 360, 3)
			_record_social_event(target, "committed")
		"break_up":
			romantic_partner = ""
			person.bond = "separated"
			person.friendship = maxf(-100.0, float(person.friendship) - 12.0)
			person.romance = maxf(0.0, float(person.romance) - 35.0)
			add_moodlet("A difficult conversation", "Tense", "An honest ending takes time to process.", 240, 2)
			_record_social_event(target, "separated")
	_update_relationship_status(person)
	return true


func receive_social_result(source_id: String, source_name: String, source_life_stage: String, relationship: Dictionary, action_id: String, events: Array) -> void:
	var mirrored: Dictionary = relationship.duplicate(true)
	mirrored.name = source_name
	mirrored.life_stage = source_life_stage
	mirrored.family_role = str(_social_family.get(source_id,LifeFamilyGraph.inverse(str(relationship.get("family_role","none")))))
	relationships[source_id] = mirrored
	if action_id in ["ask_partner", "commit"]:
		romantic_partner = source_id
	elif action_id == "break_up" and romantic_partner == source_id:
		romantic_partner = ""
	for event: Dictionary in events:
		_record_social_event(source_id, str(event.stage), false)
	_update_relationship_status(mirrored)
	_record_autonomy_contact(source_id,action_id)
	# The other Lifelet also took part in this completed conversation. Keep the
	# reward in their ordinary tick so the household wallet accounts for it once.
	for want:Dictionary in wants:
		if not bool(want.complete) and str(want.get("metric",""))=="familiar_chat" and want.get("actions",[]).has(action_id) and float(mirrored.friendship)>=35.0:
			want.progress=1.0
	_emit_changed()


func _apply_social(action: Dictionary) -> bool:
	_recent_social_events.clear()
	var target: String = _social_target(str(action["target_id"]))
	if target.is_empty():
		return false
	if str(action.id) in RELATIONSHIP_ACTIONS or str(action.id)=="flirt":
		var availability: Dictionary = get_action_availability(str(action.id), target)
		if not bool(availability.available):
			_emit_notice(str(availability.reason))
			return false
		if str(action.id) in RELATIONSHIP_ACTIONS: return _apply_relationship_action(str(action.id), target)
	var person: Dictionary = relationships[target]
	var change: float = 0.0
	match str(action["id"]):
		"friendly": change = 12.0
		"joke": change = 10.0 + float(skills["charisma"]["level"])
		"deep_talk":
			if float(person["friendship"]) >= 20.0:
				change = 20.0
			else:
				change = 4.0
				_emit_notice("%s appreciates the chat, but needs time to open up." % person["name"])
		"hug":
			if float(person["friendship"]) >= 25.0:
				var last:float=float(last_hugs.get(target,-1e18))
				# Absolute game minutes: the 600-minute window survives
				# midnight and a save/reload instead of wrapping at the
				# time-of-day clock.
				change=14.0 if _autonomy_now()-last>=600.0 else 6.0
				if change<14.0:_emit_notice("%s cherishes the hug, though you hugged not long ago." % person["name"])
				last_hugs[target]=_autonomy_now()
			else:
				change=3.0
				_emit_notice("%s isn't ready for a hug yet. Build the friendship first." % person["name"])
		"share_interests":
			var shared:int=0
			var mine:Array=character.get("traits",[])
			var theirs:Array=_social_reciprocal[target].get("traits",[]) if _social_reciprocal.has(target) else []
			for t:Variant in mine:
				if str(t) in theirs:shared+=1
			if shared>0:
				change=18.0
				_emit_notice("You and %s really get each other." % person["name"])
			else:
				change=5.0
		"flirt":
			if float(person["friendship"]) >= 30.0:
				person["romance"] = minf(100.0, float(person["romance"]) + 16.0 * _perk_multiplier("romance"))
				change = 5.0
				_emit_notice("There is a spark between you and %s." % person["name"])
			else:
				change = -7.0
				_emit_notice("%s seems uncomfortable. Try building a friendship first." % person["name"])
		"argue":
			change = -22.0
			person["romance"] = maxf(0.0, float(person["romance"]) - 12.0)
		"sympathize":
			# Household members carry a live Fun read; neighbors carry a
			# catalogue mood schedule — drained during weekday work hours.
			var their_fun:float=100.0
			var record:Variant=_social_reciprocal.get(target,{})
			if record is Dictionary:
				if record.has("resident_fun"):
					var at_work:bool=LifeEducation.weekday(day) and minutes>=540.0 and minutes<=960.0
					var mood:Dictionary=record["resident_fun"]
					their_fun=float(mood["work" if at_work else "off"])
				else:
					their_fun=float(record.get("fun",100.0))
			if their_fun<45.0:
				change=16.0
				_emit_notice("You sit with %s and really listen. They seem lighter." % person["name"])
			else:
				change=7.0
		"gossip":
			var last:float=float(last_gossip.get(target,-1e18))
			# Absolute game minutes, like the hug window.
			if _autonomy_now()-last<900.0:
				change=3.0
				_emit_notice("%s has heard this story before. It lands flat." % person["name"])
			else:
				change=9.0
			last_gossip[target]=_autonomy_now()
		"playful_prank":
			# A big friendly swing, but a thin friendship can take mischief badly:
			# below 30 friendship the joke lands as a slight and leaves the actor Tense.
			if float(person["friendship"]) >= 30.0:
				change=26.0
				_emit_notice("%s laughs until they cry. That was a good one." % person["name"])
			else:
				change=-8.0
				add_moodlet("That landed wrong","Tense","The prank did not read as a joke this time.",180,3)
				_emit_notice("%s does not find that funny. Build the friendship first." % person["name"])
		"bold_introduction":
			# Confidence carries: an introduction lands harder than an ordinary hello.
			change=22.0
			_emit_notice("%s is clearly impressed by the confidence." % person["name"])
	if _has_trait("Outgoing") and change > 0.0:
		change *= 1.2
	person["friendship"] = clampf(float(person["friendship"]) + change, -100.0, 100.0)
	_update_relationship_status(person)
	_record_social_milestones(target, str(action.id))
	return true


func _update_relationship_status(person: Dictionary) -> void:
	if LifeFamilyGraph.is_family(str(person.get("family_role", "none"))):
		person["status"] = LifeFamilyGraph.label(str(person.family_role))
	elif str(person.get("bond", "none")) == "committed":
		person["status"] = "Committed partner"
	elif str(person.get("bond", "none")) == "partners":
		person["status"] = "Partner"
	elif str(person.get("bond", "none")) == "separated":
		person["status"] = "Former partner"
	elif float(person["romance"]) >= 50.0:
		person["status"] = "Romantic interest"
	elif float(person["friendship"]) >= 65.0:
		person["status"] = "Close friend"
	elif float(person["friendship"]) >= 35.0:
		person["status"] = "Friend"
	elif float(person["friendship"]) < -15.0:
		person["status"] = "Strained"
	else:
		person["status"] = "Acquaintance"


## The highest qualification this Lifelet holds.
func _degree() -> String:
	return LifeCareers.normalise_degree(degree)


## This Lifelet's own pay at their current rung, including what their degree is
## worth to this job. The single place a salary is worked out, so the ladder, the
## notice and the save never disagree.
func career_pay() -> int:
	return LifeCareers.pay(str(career.get("track", LifeCareers.DEFAULT_JOB)), int(career.get("level", 1)), _degree())


## The rung above this Lifelet, and what reaching it takes. A job's ladder runs
## the whole ten levels the brief asks for: each step needs the job's own skill at
## the level reached, so a career rewards learning all the way to the top.
func promotion_requirement() -> Dictionary:
	var job_id: String = str(career.get("track", LifeCareers.DEFAULT_JOB))
	if not LifeCareers.has(job_id): return {}
	if int(career["level"]) >= LifeCareers.MAX_LEVEL: return {}
	var next_level: int = int(career["level"]) + 1
	var skill_name: String = str(LifeCareers.job(job_id).get("skill", ""))
	# The skill is asked for at the rung being left, so the first step is open to
	# a beginner and reaching the top really needs the trade learned to level 9.
	var required: int = int(career["level"])
	var have: int = int((skills.get(skill_name, {}) as Dictionary).get("level", 1))
	return {"skill": skill_name, "level": required, "met": have >= required,
		"next_title": LifeCareers.title_at(job_id, next_level)}


func _check_promotion() -> void:
	if float(career["performance"]) < 100.0 or int(career["level"]) >= LifeCareers.MAX_LEVEL:
		return
	var requirement: Dictionary = promotion_requirement()
	if not requirement.is_empty() and not bool(requirement.met):
		career["performance"] = 100.0
		if _promotion_notice_day != day:
			_promotion_notice_day = day
			_emit_notice("Performance is excellent. Reach %s level %d to become a %s." % [str(requirement.skill).capitalize(), int(requirement.level), str(requirement.next_title).to_lower()])
		return
	career["performance"] = float(career["performance"]) - 100.0
	career["level"] = int(career["level"]) + 1
	var job_id: String = str(career["track"])
	career["title"] = LifeCareers.title_at(job_id, int(career["level"]))
	career["salary"] = LifeCareers.pay(job_id, int(career["level"]), _degree())
	funds += 200
	_emit_notice("Promotion! You are now a %s. ℒ200 bonus and ℒ%d a shift." % [str(career["title"]).to_lower(), int(career["salary"])])
	add_moodlet("A step forward","Confident","Your hard work is paying off.",360,4)
	remember("A promotion",str(career.title))

## Take up a new line of work. The door is the job's own entry rule, so a job
## that wants a skill, a degree or a course fee is refused here exactly as the
## picker shows it — which is what makes moving between careers hard rather than
## free. The ladder restarts at its first rung, because experience in one trade is
## not experience in another.
func choose_career(track_id:String) -> bool:
	var entry_error:String=career_entry_error(track_id)
	if not entry_error.is_empty():_emit_notice(entry_error);return false
	if career.get("track",LifeCareers.DEFAULT_JOB)==track_id:return true
	for action in action_queue:
		if action.id in ["job","career_day"]:_emit_notice("Finish or cancel your shift before changing careers.");return false
	var job:Dictionary=LifeCareers.job(track_id)
	var entry:Dictionary=job.get("entry",{})
	var entry_fee:int=int(entry.get("cost",0))
	if entry_fee>0:funds-=entry_fee
	career={"schedule":LifeCareerSchedule.fresh(day,day+1 if minutes>LifeCareerSchedule.CLOSE else day),
		"track":track_id,"title":LifeCareers.title_at(track_id,1),"level":1,"performance":0.0,
		"salary":LifeCareers.pay(track_id,1,_degree()),"worked_day":int(career.worked_day)}
	remember("A new direction","Joined "+str(job.label))
	add_moodlet("New possibilities","Inspired","A new career is a chance to grow.",240,2)
	_emit_notice("Your new job: %s. ℒ%d per shift.%s" % [career.title,career.salary," ℒ%d course fee paid." % entry_fee if entry_fee>0 else ""])
	_emit_changed()
	return true


## Whether this Lifelet may take up a job, as the player-readable reason they may
## not. Empty means the door is open. The career picker, the queue and
## `choose_career` all read this one answer, so a greyed-out button and a refused
## call never disagree.
func career_entry_error(track_id:String) -> String:
	if is_imprisoned():
		return "This Lifelet is serving a sentence until day %d." % int(criminal_record.get("prison_until_day", 0))
	return LifeCareers.entry_error(track_id,str(character.life_stage),skills,_degree(),funds)


## What a job asks for, as the picker's own line of text.
func career_requirement_text(track_id:String) -> String:
	return LifeCareers.requirement_text(track_id)


## Every job offered to this Lifelet, in the order a picker should show them, with
## the reason each is shut. One list, so the picker and the gate agree.
func career_offers() -> Array:
	var out:Array=[]
	for job_id:String in LifeCareers.ordered():
		var job:Dictionary=LifeCareers.job(job_id)
		out.append({
			"id":job_id,"label":str(job.label),"current":str(career.get("track",""))==job_id,
			"first_title":LifeCareers.title_at(job_id,1),
			"top_title":LifeCareers.title_at(job_id,LifeCareers.MAX_LEVEL),
			"pay":LifeCareers.pay(job_id,1,_degree()),
			"pay_at_top":LifeCareers.pay(job_id,LifeCareers.MAX_LEVEL,_degree()),
			"requirements":LifeCareers.requirement_text(job_id),
			"criminal":LifeCareers.is_criminal(job_id),
			"detection":LifeCareers.detection_chance(job_id,1),
			"reason":career_entry_error(job_id),
		})
	return out


## Whether this Lifelet is inside today.
func is_imprisoned() -> bool:
	return int(criminal_record.get("prison_until_day",0))>day


## Whether this Lifelet is inside at the prison right now, as opposed to having a
## sentence they are serving at home. Being caught is a real absence: the Lifelet
## is taken to Blackmoor and is not on the household's lot until they are free,
## which is what makes visiting them there mean anything.
func is_at_prison() -> bool:
	return is_imprisoned() and not bool(criminal_record.get("serving_at_home",false))


## The prison absence this sentence imposes, in the shape the away machine
## already understands, so the body, the HUD and the save all agree about where
## an incarcerated Lifelet is.
func prison_away_state() -> Dictionary:
	if not is_at_prison():return {}
	return {"version":1,"activity":"prison","phase":"away","departure_day":day,
		"departure_minutes":minutes,"return_day":int(criminal_record.get("prison_until_day",day)),
		"return_minutes":480.0,"exit_id":"lot_exit","exit_position":Vector3.ZERO,
		"age_stage":str(character.age_stage),"career_track":str(career.get("track","")),
		"salary":0,"completed":true,"ended_at":0.0,"prison":true}


## What being caught costs: the fine, the days inside, and the record of it. The
## household purse pays, capped at what it holds, so a fine can never drive the
## household into the negative.
##
## Being caught really takes the Lifelet away: `away_state` is set to the prison,
## so they leave the household's lot and stay at Blackmoor until the sentence
## ends. A Lifelet already away from home (at work, or on a trip) cannot be
## arrested into a second absence, so their sentence is served from home instead —
## the record is identical either way, and only the body differs.
func serve_sentence(fine:int,days:int) -> Dictionary:
	var paid:int=mini(maxi(fine,0),funds)
	funds-=paid
	var previous:int=int(criminal_record.get("caught_count",0))
	var until:int=day+maxi(1,days)
	var from_home:bool=is_away()
	criminal_record={"version":1,"caught_count":previous+1,
		"prison_until_day":until,
		"fines_paid":int(criminal_record.get("fines_paid",0))+paid,
		"serving_at_home":from_home}
	if not from_home:
		# The Lifelet is taken to Blackmoor; the household's own clock releases
		# them, driven by `prison_check`.
		away_state=prison_away_state()
		_publish("away_changed",[get_away_state()])
	add_moodlet("Behind bars","Tense","Caught, fined and locked up. That was the risk.",1440,4)
	remember("Caught","A fine and %d days inside." % maxi(1,days))
	_emit_notice("Caught! A ℒ%d fine and %d days inside at Blackmoor, free on day %d." % [paid,maxi(1,days),until])
	_emit_changed()
	return {"ok":true,"fine":paid,"days":maxi(1,days),"until":until,"at_prison":not from_home}


## Release a Lifelet whose sentence has ended: they come home, and the record of
## the sentence is cleared of the prison stay so a released Lifelet is simply a
## Lifelet at home again.
func prison_check() -> Dictionary:
	if not is_at_prison():return {"ok":false,"reason":"Not inside."}
	if day<int(criminal_record.get("prison_until_day",0)):return {"ok":false,"reason":"Still serving."}
	criminal_record["serving_at_home"]=false
	if str(away_state.get("activity",""))=="prison":
		away_state={}
		_publish("away_changed",[get_away_state()])
	_emit_notice("%s has been released and is coming home." % str(character.name))
	_emit_changed()
	return {"ok":true,"released":true}


## One day of criminal work, rolled once by the household on its own clock. A
## working criminal risks being caught; a practised one risks far less. Returns
## what happened so the household can report it.
func criminal_day_check() -> Dictionary:
	var job_id:String=str(career.get("track",LifeCareers.DEFAULT_JOB))
	if not LifeCareers.is_criminal(job_id):return {"ok":false,"reason":"Not on that line of work."}
	if is_imprisoned():return {"ok":false,"reason":"Already inside."}
	var chance:float=LifeCareers.detection_chance(job_id,int(career.get("level",1)))
	var roll:float=randf()
	if roll>=chance:return {"ok":true,"caught":false,"chance":chance}
	return serve_sentence(LifeCareers.fine(job_id,int(career.get("level",1))),LifeCareers.prison_days(job_id,int(career.get("level",1))))


## Finish a degree. The qualification is the household's to pay for and the
## Lifelet's to hold, and it rides the save so a doctor stays a doctor.
func award_degree(value:String) -> Dictionary:
	var step:Dictionary=LifeCareers.degree_step(value)
	if step.is_empty():return {"ok":false,"error":"That is not a qualification on offer."}
	degree=LifeCareers.normalise_degree(value)
	# A degree is worth more to the job this Lifelet already holds, so the pay
	# rises the moment it is awarded rather than only on the next promotion.
	career["salary"]=career_pay()
	add_moodlet("Graduated","Confident","A %s in hand and better paid for it." % LifeCareers.degree_label(degree),720,4)
	remember("Graduated","Awarded a %s." % LifeCareers.degree_label(degree))
	_emit_notice("%s graduated with a %s. Pay is now ℒ%d a shift." % [str(character.name),LifeCareers.degree_label(degree),int(career.salary)])
	_emit_changed()
	return {"ok":true,"degree":degree}


## The professional name this Lifelet is addressed by: a PHD is a doctor.
func honorific() -> String:
	return LifeCareers.honorific(_degree())


func add_moodlet(label:String,emotion:String,description:String,duration:float,strength:int=2) -> void:
	for i in range(moodlets.size()-1,-1,-1):
		if moodlets[i].label==label:moodlets.remove_at(i)
	moodlets.append({"label":label,"emotion":emotion,"description":description,"remaining":duration,"strength":strength})
	while moodlets.size()>8:moodlets.pop_front()

func remember(label:String,detail:String) -> void:
	memories.push_front({"day":day,"minutes":int(minutes),"label":label,"detail":detail})
	while memories.size()>40:memories.pop_back()

func _queue_follow_up(id:String) -> bool:
	# A short automatic continuation of the action that just finished (washing
	# hands after the bathroom). It rides the same queue as a player instruction,
	# so it survives a save and yields to any later plan the player already made.
	if id not in _actions or is_away() or action_queue.size() >= MAX_QUEUE:return false
	var chosen:Dictionary=_autonomy_target_for(id)
	if chosen.is_empty():return false
	var follow:Dictionary=_actions[id].duplicate(true)
	follow.merge({"target_id":str(chosen.target_id),"target_position":chosen.position,"phase":"queued",
		"elapsed":0.0,"progress":0.0,"paid":false,"autonomous":true},true)
	action_queue.push_front(follow)
	return true


func _activity_memory(id:String) -> void:
	match id:
		"cook":add_moodlet("Made with love","Happy","A fresh meal is a small pleasure.",180,2)
		"sleep":add_moodlet("Rested and ready","Energized","A good sleep makes everything feel possible.",240,2)
		"shower":add_moodlet("A fresh start","Confident","Feeling clean and ready to face the day.",120,1)
		"read","study":add_moodlet("A curious mind","Focused","A little learning goes a long way.",180,2)
		"paint":
			add_moodlet("In a creative flow","Inspired","You made something only you could make.",240,3)
			remember("An original canvas","Created and sold a painting.")
		"friendly","deep_talk":add_moodlet("Feeling connected","Happy","It's good to spend time with someone.",180,2)
		"hug":add_moodlet("A warm embrace","Happy","A hug makes everything feel a little kinder.",150,2)
		"share_interests":add_moodlet("Kindred spirits","Confident","Talking about what you love with someone who gets it.",200,2)
		"joke":add_moodlet("A shared laugh","Playful","That joke is still making you smile.",120,3)
		"argue":add_moodlet("Words linger","Tense","A difficult conversation takes time to shake off.",180,3)
		"remember_life":add_moodlet("Held close","Sad","A life remembered is still part of the house.",240,1)
		"work","job":
			add_moodlet("A job well done","Confident","You've earned a little time for yourself.",180,2)
			remember("A productive day","Finished work and earned a living.")
		"water":add_moodlet("Growing together","Happy","Looking after something living feels rewarding.",120,1)
		"bath":add_moodlet("Soaked and serene","Happy","A long bath washes the day away.",180,2)
		"practice_speech":add_moodlet("Finding your voice","Confident","Every rehearsal makes the next conversation easier.",150,2)
		"play_piano":add_moodlet("Music in the air","Inspired","A melody is still playing in your head.",180,3)
		"play_chess":add_moodlet("Sharp mind","Focused","A few moves ahead of everyone.",150,2)
		"jog","stretch":add_moodlet("Body in motion","Energized","Your body feels awake and strong.",180,2)
		"dance","dance_together":add_moodlet("Still humming","Playful","That song is still going round.",150,3)
		"play_toys":add_moodlet("Made-up worlds","Playful","Imagination made the afternoon fly by.",150,3)
		"warm_up":add_moodlet("Hearthside calm","Happy","Warm hands and a quiet mind.",120,1)
		"play_games":add_moodlet("One more level","Playful","That game is still on your mind.",120,2)
		"wash_hands":add_moodlet("Clean hands","Confident","Freshly washed and ready for what's next.",90,1)
		"brush_teeth":add_moodlet("Minty fresh","Confident","A clean, bright feeling that lasts.",150,1)
		"empty_bin":add_moodlet("A tidy home","Happy","Taking the rubbish out makes the whole room feel lighter.",120,1)
		"clear_table":add_moodlet("Tidied up","Happy","A cleared table makes the room feel calm again.",120,1)
		"study_book":add_moodlet("A curious mind","Focused","A little learning goes a long way.",180,2)
		"practice_instrument":add_moodlet("Music in the air","Inspired","A melody is still playing in your head.",180,3)
		"watch_together":add_moodlet("Good company","Happy","Laughing at the same show is better than watching alone.",180,2)
		"paint_masterpiece":
			add_moodlet("A real masterpiece","Inspired","You made something remarkable while the feeling lasted.",300,4)
			remember("A masterpiece finished","Painted and sold something far beyond an ordinary canvas.")
		"study_hard":add_moodlet("Deep focus","Focused","Hours of uninterrupted work paid off.",180,3)
		"push_through":add_moodlet("Pushed past the limit","Energized","The last stretch was worth the effort.",180,3)
		"playful_prank":add_moodlet("A little mischief","Playful","That prank is still funny to think about.",150,3)
		"bold_introduction":add_moodlet("Made an impression","Confident","Walking in like you own the room works.",180,2)
		"sketch_for_fun":add_moodlet("Just for the joy of it","Inspired","No sale, no pressure, just a pencil and paper.",150,2)
		"host_a_chat":add_moodlet("A full house","Happy","The room felt warmer with everyone talking.",180,2)
		"morning_run":add_moodlet("Morning air","Energized","The block went past in a blur of good effort.",180,3)
		"deep_read":add_moodlet("Lost in a book","Focused","The afternoon disappeared into the pages.",200,2)
		"experiment_recipe":add_moodlet("Something new on the stove","Playful","An invented dish that actually worked.",150,2)
		"deep_clean":add_moodlet("A tidy home","Happy","Every surface gleams, and it feels lighter in here.",180,2)
		"mourn":
			_ease_mourning(720.0)
			add_moodlet("Peaceful Remembrance","Happy","Taking time to grieve brings a quiet peace to the soul.",240,1)
		"leave_flowers":
			add_moodlet("Honoured Memory","Happy","Fresh blossoms by the memorial honour a life well lived.",360,2)
			remember("Placed fresh flowers","Honoured the memory of the departed with fresh blossoms.")
		"remember_passed":
			add_moodlet("Fond Memories","Inspired","Remembering their laughter and wisdom inspires you today.",300,2)
		"comfort_loss":
			_ease_mourning(960.0)
			add_moodlet("Shared Solace","Happy","Sharing grief with a friend lightens the heaviest burden.",360,2)
		"share_memories":
			add_moodlet("Cherished Stories","Happy","Talking through cherished memories keeps loved ones close.",240,1)

func _ease_mourning(amount: float) -> void:
	for moodlet: Dictionary in moodlets:
		if str(moodlet.get("label", "")) in ["Mourning", "In mourning"]:
			moodlet.remaining = maxf(0.0, float(moodlet.get("remaining", 0.0)) - amount)


func _new_day() -> void:
	var work_calendar:Dictionary=LifeCareerSchedule.advance(career.get("schedule",LifeCareerSchedule.fresh(day-1)),day,int(career.worked_day),str(character.life_stage)=="adult")
	career.schedule=work_calendar.state
	if int(work_calendar.missed)>0:
		career.performance=maxf(0.0,float(career.performance)-8.0*int(work_calendar.missed))
		_emit_notice("Missed a weekday shift. Career performance fell; the next workday is a fresh chance.")
	_advance_education()
	_cancel_school_actions("A new school day has begun. Choose a fresh class or assignment.")
	_warned_needs.clear()
	_advance_bill_cycle()
	for person: Dictionary in relationships.values():
		if float(person["friendship"]) > 0.0:
			person["friendship"] = maxf(0.0, float(person["friendship"]) - 1.5)
		_update_relationship_status(person)
	_offer_daily_story()


## The weekly bills cycle. A bill is issued every BILL_PERIOD_DAYS for what the
## home is worth; it falls due BILL_DUE_DAYS later. Settling it from the phone is
## the player's decision, so an unpaid bill is a real choice rather than a silent
## deduction, and a lapsed one adds a late fee and cuts the utilities.
func _advance_bill_cycle() -> void:
	if not household_bills_enabled:
		return
	if pending_bill.is_empty():
		if last_bill_day == 0 or day - last_bill_day >= BILL_PERIOD_DAYS:
			var amount: int = bill_amount_for(home_value())
			pending_bill = {"amount": amount, "issued_day": day, "due_day": day + BILL_DUE_DAYS, "late_fee": 0}
			# The week is anchored to the issue, not to the payment. Stamping the
			# payment instead made the period "seven days after the last payment",
			# so a household that settled a fortnight-old bill skipped every week
			# in between and was charged nothing, while a prompt payer kept the
			# promised weekly cadence.
			last_bill_day = day
			_emit_notice("The household bills arrived: ℒ%d, due by day %d. Pay them from the phone." % [amount, int(pending_bill.due_day)])
		return
	# A bill past its due date is overdue: one late fee, once.
	if day > int(pending_bill.due_day) and int(pending_bill.get("late_fee", 0)) == 0:
		pending_bill["late_fee"] = BILL_LATE_FEE
		bills_late += 1
		utilities_cut = true
		_emit_notice("The household bills are overdue. A ℒ%d late fee was added and the utilities were cut until they are paid." % BILL_LATE_FEE)


## The ledger is owned by the household's first member; every other member keeps
## a read-only mirror so action availability and the phone agree with it.
func set_bill_mirror(record: Dictionary, cut: bool, paid_total: int, late: int, paid_day: int = -1, policy: String = "") -> void:
	pending_bill = record.duplicate(true)
	utilities_cut = cut
	bills_paid_total = paid_total
	bills_late = late
	insurance_policy_id = policy
	if paid_day >= 0:
		last_bill_day = paid_day


## The household's insurance, as the phone reads it. Empty while uninsured.
func insurance_policy() -> Dictionary:
	if insurance_policy_id.is_empty() or not INSURANCE_POLICIES.has(insurance_policy_id):
		return {}
	return {"id":insurance_policy_id,"label":str(INSURANCE_POLICIES[insurance_policy_id].label),"premium":int(INSURANCE_POLICIES[insurance_policy_id].premium)}


## Buy the named policy. Refused, with its reason, while a policy is already in
## force or the policy is unknown; the premium is charged only on success so a
## refusal can never take the household's money.
func buy_insurance(policy_id:String="home") -> Dictionary:
	if not INSURANCE_POLICIES.has(policy_id):
		return {"ok":false,"error":"That policy is not offered."}
	if not insurance_policy_id.is_empty():
		return {"ok":false,"error":"The home is already insured for ℒ%d a term. Cancel it first to change cover." % int(INSURANCE_POLICIES[insurance_policy_id].premium)}
	var premium:int=int(INSURANCE_POLICIES[policy_id].premium)
	if funds<premium:
		return {"ok":false,"error":"The household needs ℒ%d for this policy and has ℒ%d." % [premium,funds]}
	funds-=premium
	insurance_policy_id=policy_id
	_emit_notice("Home insurance bought for ℒ%d. A break-in will be paid back in full." % premium)
	_emit_changed()
	return {"ok":true,"premium":premium,"label":str(INSURANCE_POLICIES[policy_id].label)}


## Give up the policy. Nothing is refunded: cover is a running cost, not a
## deposit, so canceling after a payout never turns a profit.
func cancel_insurance() -> Dictionary:
	if insurance_policy_id.is_empty():
		return {"ok":false,"error":"The home is not insured."}
	insurance_policy_id=""
	_emit_notice("Home insurance canceled. The household is uncovered again.")
	_emit_changed()
	return {"ok":true}


## A break-in takes a real sum and says so. An insured home is reimbursed the
## full loss in the same breath, so the notice still reports both halves; an
## uninsured home simply loses the money. The loss is capped at the purse so
## funds can never go negative.
func robbery() -> Dictionary:
	var loss:int=mini(ROBBERY_LOSS,funds)
	if loss<=0:
		return {"ok":false,"reason":"Nothing was taken. The house was empty."}
	funds-=loss
	if insurance_policy_id.is_empty():
		_emit_notice("A burglar broke in and took ℒ%d. Home insurance from the phone would have covered it." % loss)
		_emit_changed()
		return {"ok":true,"stolen":loss,"reimbursed":0,"insured":false}
	_emit_notice("A burglar broke in and took ℒ%d. Home insurance paid it all back." % loss)
	funds+=loss
	var multiple:float=float(INSURANCE_POLICIES[insurance_policy_id].get("payout_multiple",1.0))
	if multiple>1.0:
		var extra:int=roundi(float(loss)*(multiple-1.0))
		funds+=extra
		_emit_notice("Premium cover paid a further ℒ%d on top." % extra)
	_emit_changed()
	return {"ok":true,"stolen":loss,"reimbursed":loss,"insured":true}


## The nightly crime check. Only the bill owner rolls, so one household hears one
## break-in; the household drives this, exactly like the bill cycle.
func robbery_check() -> Dictionary:
	if day%ROBBERY_PERIOD_DAYS!=0:
		return {"ok":false,"reason":"No break-in tonight."}
	return robbery()


## The full amount owed right now, including any late fee. Every member carries
## the same record, so this is consistent whoever the phone is looking at.
func bill_total_due() -> int:
	if pending_bill.is_empty():
		return 0
	return int(pending_bill.amount) + int(pending_bill.get("late_fee", 0))


## Settle the outstanding bill. Returns a result dictionary so the phone panel can
## report exactly what happened instead of guessing.
func pay_bill() -> Dictionary:
	if pending_bill.is_empty():
		return {"ok": false, "reason": "There is no bill to pay right now."}
	var owed: int = bill_total_due()
	if funds < owed:
		return {"ok": false, "reason": "The household needs ℒ%d and has ℒ%d." % [owed, funds]}
	funds -= owed
	bills_paid_total += owed
	pending_bill.clear()
	var restored: bool = utilities_cut
	utilities_cut = false
	_emit_notice("Bills paid: ℒ%d.%s" % [owed, " The utilities are back on." if restored else ""])
	_emit_changed()
	return {"ok": true, "paid": owed, "restored_utilities": restored}


func _check_need_notices() -> void:
	for need_name: String in NEED_NAMES:
		if float(needs[need_name]) < 15.0 and not _warned_needs.has(need_name):
			_warned_needs[need_name] = true
			var messages: Dictionary = {"hunger": "is very hungry. A meal would help.", "energy": "is exhausted. Time for some sleep.", "hygiene": "needs a shower to feel fresh again.", "bladder": "really needs the bathroom.", "fun": "feels bored. Make time for something enjoyable.", "social": "feels lonely. Try talking to a neighbor."}
			_emit_notice("%s %s" % [character["name"], messages[need_name]])
		elif float(needs[need_name]) >= 35.0:
			_warned_needs.erase(need_name)


func _autonomy_now() -> float:
	return float(day-1)*1440.0+minutes

func _autonomy_household_members() -> Array:
	if is_instance_valid(cooperation_owner) and cooperation_owner.get("members") is Array:
		return cooperation_owner.members
	return []

func _autonomy_cohort(school:bool) -> Array:
	var cohort:Array=[]
	for member:Dictionary in _autonomy_household_members():
		var other:LifeSim=member.sim
		if (str(other.character.age_stage) in LifeEducation.SCHOOL_STAGES)==school and (school or str(other.character.life_stage)=="adult"):
			cohort.append(member)
	if cohort.is_empty():cohort.append({"id":_social_member_id,"sim":self})
	var cohort_ids:Array[String]=[]
	for member:Dictionary in cohort:cohort_ids.append(str(member.id))
	cohort.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if school:
			if int(a.sim.education.missed)!=int(b.sim.education.missed):return int(a.sim.education.missed)>int(b.sim.education.missed)
			if int(a.sim.education.attended)!=int(b.sim.education.attended):return int(a.sim.education.attended)<int(b.sim.education.attended)
		else:
			if int(a.sim.career.worked_day)!=int(b.sim.career.worked_day):return int(a.sim.career.worked_day)<int(b.sim.career.worked_day)
		var offset:int=posmod(day-1,cohort.size())
		var ai:int=cohort_ids.find(str(a.id))
		var bi:int=cohort_ids.find(str(b.id))
		return posmod(ai-offset,cohort.size())<posmod(bi-offset,cohort.size()))
	return cohort

func _autonomy_turn(school:bool) -> int:
	var cohort:Array=_autonomy_cohort(school)
	for i:int in range(cohort.size()):
		if cohort[i].sim==self:return i
	return 0

func _autonomy_school_household() -> bool:
	for member:Dictionary in _autonomy_household_members():
		if str(member.sim.character.age_stage) in LifeEducation.SCHOOL_STAGES:return true
	return false

func _autonomy_duty_id() -> String:
	if is_away(): return ""
	if not LifeEducation.weekday(day):return ""
	var id:String=""
	if str(character.age_stage) in LifeEducation.SCHOOL_STAGES:
		if int(education.last_attendance_day)!=day and day>=int(education.first_class_day) and minutes>=480.0 and minutes<=720.0:
			id="school_day"
		elif int(education.last_homework_day)!=day and (int(education.last_attendance_day)==day or minutes>=900.0) and minutes>=600.0 and minutes<=1320.0:
			id="homework"
	elif str(character.life_stage)=="adult" and LifeCareers.has(str(career.get("track",""))) and int(career.worked_day)!=day:
		if day>=int(career.get("schedule",LifeCareerSchedule.fresh(day)).first_day) and minutes>=LifeCareerSchedule.OPEN and minutes<=LifeCareerSchedule.CLOSE:id="career_day"
	if not id.is_empty() and float(autonomy_state.deferred.get(id,-1.0))>_autonomy_now():return ""
	return id

func _autonomy_preparation_duty_id() -> String:
	var due:String=_autonomy_duty_id()
	if not due.is_empty():return due
	if not LifeEducation.weekday(day):return ""
	var id:String=""
	var start:float=0.0
	if str(character.age_stage) in LifeEducation.SCHOOL_STAGES and int(education.last_attendance_day)!=day and day>=int(education.first_class_day):
		id="school_day";start=480.0
	elif str(character.life_stage)=="adult" and not is_imprisoned() and LifeCareers.has(str(career.get("track",""))) and int(career.worked_day)!=day:
		id="career_day";start=LifeCareerSchedule.OPEN
		if day<int(career.get("schedule",LifeCareerSchedule.fresh(day)).first_day):return ""
	if id.is_empty() or minutes<start-180.0 or minutes>=start:return ""
	if float(autonomy_state.deferred.get(id,-1.0))>_autonomy_now():return ""
	return id

var _retry_soon: bool = false  # the next cancellation leaves only a short idle wait

func retry_autonomy_soon() -> void:
	# A blocked walk should not cost the usual fifteen idle minutes before the
	# next autonomous choice; the Lifelet reconsiders within three.
	_retry_soon=true

func defer_autonomous_responsibility(id:String,for_minutes:float=120.0) -> void:
	if id not in ["school","school_day","career_day","homework","job"] or not is_finite(for_minutes):return
	autonomy_state.deferred[id]=_autonomy_now()+clampf(for_minutes,0.0,1440.0)

func _autonomy_decay(need:String) -> float:
	var amount:float=float(NEED_DECAY[need])
	if need=="social" and _has_trait("Outgoing"):amount*=1.35
	if need=="fun" and _has_trait("Creative"):amount*=1.2
	if need=="hygiene" and _has_trait("Neat"):amount*=.75
	if need=="energy" and _has_trait("Active"):amount*=.8
	return amount*_perk_decay_multiplier(need)

func _autonomy_projection_need(id:String,travel_minutes:float=60.0,include_fun:bool=false) -> String:
	if id not in ["school","school_day","career_day","homework","job"]:return ""
	var action:Dictionary=_actions[id]
	var changes:Dictionary=action.changes.duplicate()
	var duration:float=float(action.duration)
	if id=="school_day":
		duration=900.0-minutes
		var lesson_minutes:float=maxf(0.0,900.0-maxf(480.0,minutes)-travel_minutes)
		for need:String in changes:changes[need]=float(changes[need])*lesson_minutes/420.0
		for need:String in {"energy":-10.0,"hunger":-8.0,"fun":-6.0,"social":16.0}:changes[need]=float(changes.get(need,0.0))+float({"energy":-10.0,"hunger":-8.0,"fun":-6.0,"social":16.0}[need])
	if id=="career_day":
		duration=LifeCareerSchedule.END-minutes
		var work_minutes:float=maxf(0.0,LifeCareerSchedule.END-maxf(LifeCareerSchedule.OPEN,minutes)-travel_minutes)
		for need:String in changes:changes[need]=float(changes[need])*work_minutes/LifeCareerSchedule.LENGTH
	if id=="school":changes={"energy":-10.0,"hunger":-8.0,"fun":-6.0,"social":16.0}
	elif id=="homework":changes={"energy":-3.0,"fun":-5.0}
	var lowest:float=20.0
	var problem:String=""
	for need:String in NEED_NAMES:
		# A school morning prepares physical needs for time away. Moderate
		# boredom or untidiness affects mood, but should not consume the day
		# in optional home activities before a physically safe departure.
		if id in ["school_day","career_day"] and need not in ["hunger","energy","bladder","fun"]:continue
		if need=="fun" and id in ["school_day","career_day"] and not include_fun:continue
		var projected:float=float(needs[need])-_autonomy_decay(need)*duration/60.0+float(changes.get(need,0.0))
		# While a day away is still being prepared, a Fun projection under 20 at
		# the evening return earns a brief break first; at departure time moderate
		# boredom never delays leaving.
		if need=="fun" and id in ["school_day","career_day"]:
			if projected<20.0 and projected<lowest:lowest=projected;problem=need
			continue
		if projected<lowest:lowest=projected;problem=need
	return problem

func _autonomy_target_load(target_id: String) -> float:
	# The current user's remaining minutes, plus a standing penalty for every
	# household member already heading for or waiting at the same resource, so
	# an occupied furnishing with a queue loses an equivalent free one.
	var load_minutes: float = 0.0
	for member: Dictionary in _autonomy_household_members():
		if member.sim == self:continue
		if member.sim.action_queue.is_empty():continue
		var front: Dictionary = member.sim.action_queue[0]
		if str(front.get("target_id", "")) != target_id:continue
		if str(front.get("phase", "")) == "active":
			load_minutes += maxf(1.0, float(front.duration) - float(front.elapsed))
		else:
			load_minutes += 20.0
	return load_minutes

func _autonomy_target_for(id:String,excluded_target_ids:Array=[]) -> Dictionary:
	var selected:Dictionary={}
	var lowest:float=INF
	for target:Dictionary in _targets:
		if excluded_target_ids.has(str(target.id)):continue
		var available:bool=false
		for definition:Dictionary in get_actions_for(str(target.kind),str(target.id)):
			if str(definition.id)!=id:continue
			available=bool(definition.available)
			if id=="career_day" and str(target.kind)=="lot_exit" and minutes>=LifeCareerSchedule.OPEN-180.0 and minutes<LifeCareerSchedule.OPEN and LifeEducation.weekday(day) and str(character.life_stage)=="adult" and int(career.worked_day)!=day and day>=int(career.get("schedule",LifeCareerSchedule.fresh(day)).first_day) and not is_away():available=true
			if id == "school_day" and str(target.kind) == "lot_exit" and minutes >= 300.0 and minutes < 480.0 and LifeEducation.weekday(day) and str(character.age_stage) in LifeEducation.SCHOOL_STAGES and int(education.last_attendance_day) != day and day >= int(education.first_class_day) and not is_away():
				# Preparation can locate tomorrow's route before departure opens.
				# The chooser separately requires a due duty before queueing it.
				available = true
			if id in ["school","homework"] and not action_queue.is_empty() and str(action_queue[0].id)==id and bool(action_queue[0].get("autonomous",false)):
				available=_school_availability(id,str(target.id),true).is_empty()
		if not available:continue
		var cost:float=_autonomy_target_load(str(target.id))
		# A bookshelf hosts homework first so desks stay open for classes and
		# home shifts, but a busy shelf must still yield to an idle desk:
		# one queued assignment is a longer wait than the protection is worth.
		if id=="homework" and str(target.kind) in ["desk","computer"]:cost+=15.0
		if cost<lowest:
			lowest=cost;selected={"id":id,"target_id":str(target.id),"position":target.position,"load":cost}
	return selected

func _record_autonomy_contact(target:String,id:String) -> void:
	if target.is_empty() or not relationships.has(target):return
	var previous:Dictionary=autonomy_state.contacts.get(target,{})
	autonomy_state.contacts[target]={"at":_autonomy_now(),"action":id,"count":mini(1000000,int(previous.get("count",0))+1)}

func _autonomy_social_choice(excluded_target_ids:Array=[]) -> Dictionary:
	var selected:Dictionary={}
	var best:float=-INF
	for target:Dictionary in _targets:
		var target_id:String=str(target.id)
		if excluded_target_ids.has(target_id) or str(target.kind)!="neighbor" or not relationships.has(target_id):continue
		# A neighbour whose approach kept failing routing stays on cooldown.
		if float(social_cooldowns.get(target_id,-1e18)) > _autonomy_now():continue
		var occupied:bool=false
		for member:Dictionary in _autonomy_household_members():
			if str(member.id)!=target_id:continue
			var doing:Dictionary=member.sim.get_current_action()
			occupied=not doing.is_empty() and str(doing.id) in ["school","school_day","career_day","homework","job","sleep","nap","shower","toilet"]
		if occupied:continue
		var person:Dictionary=relationships[target_id]
		var contact:Dictionary=autonomy_state.contacts.get(target_id,{})
		var hours:float=clampf((_autonomy_now()-float(contact.get("at",_autonomy_now()-2880.0)))/60.0,0.0,48.0)
		var score:float=hours*1.6+clampf(float(person.friendship),-40,65)*.25
		if LifeFamilyGraph.is_family(_family_role(target_id)):score+=6.0
		if target_id==romantic_partner:score+=8.0
		score-=minf(60.0,_autonomy_target_load(target_id))
		score+=float((_social_member_id+"|"+target_id+"|"+str(day)).hash()%1000)*.001
		var id:String="friendly"
		if not contact.is_empty():
			if str(contact.action)=="friendly":id="joke"
			elif str(contact.action)=="joke" and float(person.friendship)>=35.0:id="deep_talk"
		if not bool(get_action_availability(id,target_id).available):continue
		if score>best:best=score;selected={"id":id,"target_id":target_id,"position":target.position}
	return selected


func cool_social_target(target_id: String, until_game_minute: float) -> void:
	# Route failures kept re-selecting an unreachable neighbour; the chooser
	# skips them until the cooldown lapses.
	social_cooldowns[target_id] = until_game_minute


func reconsider_waiting_autonomy(blocked_target_ids: Array, waited_game_minutes: float) -> bool:
	if not autonomy or action_queue.is_empty() or not is_finite(waited_game_minutes) or waited_game_minutes < 30.0: return false
	var current: Dictionary = action_queue[0]
	if not bool(current.get("autonomous",false)) or str(current.get("phase","")) != "approach" or current.has("cooperation_id"): return false
	var choice: Dictionary = _autonomous_choice(blocked_target_ids)
	if choice.is_empty() or (str(choice.id) == str(current.id) and str(choice.target_id) == str(current.target_id)):
		# Urgency is not the only reason to leave a queue: a mild need behind
		# an occupied resource reroutes to a free equivalent after half an
		# hour (the sofa nap while a housemate sleeps, the bathtub while the
		# shower is busy, the annex fridge while the kitchen one cooks).
		choice = _autonomy_need_choice(_restored_need(str(current.id)), blocked_target_ids)
		if choice.is_empty() or (str(choice.id) == str(current.id) and str(choice.target_id) == str(current.target_id)):return false
	if str(current.id) in ["school","school_day","career_day","homework","job"] and str(choice.id)!=str(current.id):
		var danger:bool=false
		for need:String in NEED_NAMES:
			if float(needs[need])<20.0:danger=true
		if not danger:return false
	var replacement: Dictionary = _actions[str(choice.id)].duplicate(true)
	if str(choice.id) in ["school","school_day","career_day","homework"]:replacement["target_kind"]=_education_target_kind(str(choice.target_id))
	replacement.merge({"target_id":str(choice.target_id),"target_position":choice.position,"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"autonomous":true})
	# Replanning must release the current meal's actual carrier before changing
	# its action identity. Later player instructions retain their exact objects.
	if is_instance_valid(meal_service):meal_service.canceled(self,current)
	action_queue[0] = replacement
	_idle_minutes=0.0
	_start_front()
	_emit_changed()
	return true


func _duty_deadline(id:String) -> float:
	# The latest minute a Lifelet can reach the lot exit and still arrive on time.
	if id=="career_day":return LifeCareerSchedule.ON_TIME
	if id=="school_day":return 540.0
	return INF

func _leisure_fits(id:String,duty:String) -> bool:
	if not _actions.has(id):return false
	return minutes+LEISURE_APPROACH+float(_actions[id].duration)+DEPARTURE_WALK<=_duty_deadline(duty)

func _brief_leisure_fits(duty:String,excluded_target_ids:Array=[]) -> bool:
	# A Fun break before a due day away is worth projecting only when some
	# pastime on offer ends in time for an on-time arrival and does not just
	# queue behind a busy seat: a lifelet whose only fitting pastime is a full
	# sofa is better off departing than waiting behind the queue.
	for id:String in PRE_DUTY_LEISURE:
		if not _leisure_fits(id,duty):continue
		var target:Dictionary=_autonomy_target_for(id,excluded_target_ids)
		if target.is_empty() or float(target.get("load",0.0))>45.0:continue
		return true
	return false

func _autonomy_need_candidates(need:String,excluded_target_ids:Array=[],preparing:bool=false) -> Array[String]:
	var candidates:Array[String]=[]
	match need:
		"hunger":
			# The starter "A taste of home" want only advances on a finished cook.
			# Prefer the stove while that want is open so autonomy does not snack
			# the fridge empty for sixty days and leave the chapter pinned forever.
			var needs_first_cook: bool = false
			for want: Dictionary in wants:
				if str(want.get("id", "")) == "first_meal" and not bool(want.get("complete", false)):
					needs_first_cook = true
					break
			if needs_first_cook:
				candidates = ["cook", "eat_meal", "snack"]
			else:
				candidates = ["eat_meal", "snack", "cook"]
		"energy":
			if preparing or (LifeEducation.weekday(day) and minutes>=240.0 and minutes<=960.0):candidates=["nap","sleep"]
			else:candidates=["sleep","nap"]
		"hygiene":candidates=["shower","bath","brush_teeth","wash_hands"]
		"bladder":candidates=["toilet"]
		"fun":
			var leisure_duty:String=_autonomy_preparation_duty_id()
			var briefing:bool=leisure_duty in ["school_day","career_day"] and not _autonomy_target_for(leisure_duty,excluded_target_ids).is_empty()
			if _has_trait("Bookworm"):candidates=["read","play_chess","practice_speech","watch","play_games","relax"]
			else:
				# Keep critical Fun recovery brief while an available school/work day is being prepared.
				if briefing:candidates=PRE_DUTY_LEISURE.duplicate()
				elif _has_trait("Active"):candidates=["jog","dance","stretch","paint","read","watch","play_games","relax"]
				else:candidates=["paint","read","watch","play_piano","play_chess","dance","play_games","practice_speech","stretch","warm_up","relax"]
				# A long soak counts as a pastime once the tub is worth it.
				if not briefing and float(needs.hygiene)<70.0:candidates.insert(3,"bath")
				# Outgoing Lifelets rehearse at the mirror early; Creative ones keep the easel first.
				if _has_trait("Outgoing") and candidates.has("practice_speech"):candidates.erase("practice_speech");candidates.insert(mini(3,candidates.size()),"practice_speech")
			# Children reach for their toys first on a free day, and last when a school morning needs brief recovery.
			if str(character.age_stage)=="child":
				if candidates[0]=="relax":candidates.append("play_toys")
				else:candidates.insert(0,"play_toys")
			if briefing:
				# Before a day away only pastimes that end in time for the walk to
				# the lot exit are offered, so the rotation cannot pick a canvas
				# that makes the Lifelet late. A critically bored Lifelet keeps
				# the shortest pastimes even when that costs a few late minutes.
				var fitting:Array[String]=[]
				var overflow:Array[String]=[]
				for id:String in candidates:
					if _leisure_fits(id,leisure_duty):fitting.append(id)
					else:overflow.append(id)
				if float(needs.fun)<12.0:
					overflow.sort_custom(func(a:String,b:String)->bool:return float(_actions[a].duration)<float(_actions[b].duration))
					fitting.append_array(overflow)
				candidates=fitting
	return candidates

func _autonomy_need_ranks_earlier(need:String,preferred_id:String,other_id:String) -> bool:
	# Catalogue order only: used to allow read→paint while Fun is critical without
	# also allowing the busy-easel fallback paint→read.
	var candidates:Array[String]=_autonomy_need_candidates(need)
	var preferred_at:int=candidates.find(preferred_id)
	var other_at:int=candidates.find(other_id)
	if preferred_at<0:return false
	if other_at<0:return true
	return preferred_at<other_at

func _autonomy_need_choice(need:String,excluded_target_ids:Array=[],preparing:bool=false) -> Dictionary:
	if need=="social":return _autonomy_social_choice(excluded_target_ids)
	# A kitchen with nothing in it has no meal to choose, so the household's own
	# shop is the recovery: a hungry Lifelet with an empty fridge and no delivery
	# on its way orders one rather than queueing a meal it cannot cook.
	if need=="hunger" and is_instance_valid(grocery_service) and str(grocery_service.grocery_availability()).is_empty():
		var shopping:Dictionary=_autonomy_target_for("order_groceries",excluded_target_ids)
		if not shopping.is_empty():return shopping
	var candidates:Array[String]=_autonomy_need_candidates(need,excluded_target_ids,preparing)
	if candidates.is_empty():return {}
	if need!="fun":
		# Physical needs keep their preference order and fair waiting: a bed is
		# worth a short queue even when a sofa nap is free. A queue longer than
		# forty-five minutes sends the Lifelet to the next candidate instead, so
		# eight people do not all stand beside one occupied bed.
		var fallback:Dictionary={}
		var fallback_load:float=INF
		for id:String in candidates:
			var chosen:Dictionary=_autonomy_target_for(id,excluded_target_ids)
			if chosen.is_empty():continue
			var load:float=float(chosen.get("load",0.0))
			if load<=45.0:return chosen
			if load<fallback_load:fallback_load=load;fallback=chosen
		return fallback
	# Leisure takes the favourite when it is free and fresh. Otherwise the
	# least-loaded candidate wins, with a small preference for the earlier
	# ones and a penalty for pastimes done recently: in a crowded home an idle
	# piano beats a queue at the easel, and nobody paints all week.
	var best:Dictionary={}
	var best_score:float=INF
	for index:int in range(candidates.size()):
		var chosen:Dictionary=_autonomy_target_for(candidates[index],excluded_target_ids)
		if chosen.is_empty():continue
		var load:float=float(chosen.get("load",0.0))
		if index==0 and load<=0.0 and not _leisure_history.has(candidates[index]):return chosen
		# Any queue costs at least forty minutes of preference, so a free pastime
		# always beats a busy one; recent pastimes cost twenty-five more.
		# A furnishing nobody in the home has touched for half a day draws the
		# household to it; one everybody used in the last two hours is a little
		# less tempting, so a crowded home spreads over its whole catalogue.
		var score:float=(load+40.0 if load>0.0 else 0.0)+float(index)*5.0+(25.0 if _leisure_history.has(candidates[index]) else 0.0)+_novelty_score(str(chosen.get("target_id","")))
		if score<best_score:best_score=score;best=chosen
	return best

func _novelty_score(target_id:String) -> float:
	var last:float=-INF
	var members:Array=_autonomy_household_members()
	if members.is_empty():last=float(_recent_target_use.get(target_id,-INF))
	for member:Dictionary in members:
		if is_instance_valid(member.sim):last=maxf(last,float(member.sim._recent_target_use.get(target_id,-INF)))
	var age:float=_autonomy_now()-last
	if age>=NOVELTY_FRESH_MINUTES:return -15.0
	if age<=NOVELTY_RECENT_MINUTES:return 10.0
	return 0.0

func _autonomous_choice(excluded_target_ids:Array=[]) -> Dictionary:
	var duty:String=_autonomy_duty_id()
	var leaving:bool=duty in ["school_day","career_day"] and _autonomy_projection_need(duty).is_empty() and not _autonomy_target_for(duty,excluded_target_ids).is_empty()
	var priorities:Array[String]=NEED_NAMES.duplicate()
	priorities.sort_custom(func(a:String,b:String)->bool:
		if not is_equal_approx(float(needs[a]),float(needs[b])):return float(needs[a])<float(needs[b])
		return NEED_NAMES.find(a)<NEED_NAMES.find(b))
	for need:String in priorities:
		if float(needs[need])>=20.0:break
		# Moderate boredom, loneliness or untidiness can wait until after a
		# scheduled day away. Truly critical needs still request recovery.
		if leaving and need not in ["hunger","energy","bladder"] and float(needs[need])>=12.0:continue
		var urgent:Dictionary=_autonomy_need_choice(need,excluded_target_ids)
		if not urgent.is_empty():return urgent
	var preparing:String=_autonomy_preparation_duty_id()
	if not preparing.is_empty() and not _autonomy_target_for(preparing,excluded_target_ids).is_empty():
		# Fun counts while the day is still being prepared, and once it is due for
		# as long as a brief pastime still ends in time for an on-time arrival.
		var preparation:String=_autonomy_projection_need(preparing,60.0,duty.is_empty() or _brief_leisure_fits(preparing,excluded_target_ids))
		if not preparation.is_empty():
			var recovery:Dictionary=_autonomy_need_choice(preparation,excluded_target_ids,true)
			if not recovery.is_empty():return recovery
		elif not duty.is_empty():
			var choice:Dictionary=_autonomy_target_for(duty,excluded_target_ids)
			if not choice.is_empty():return choice
	for need:String in priorities:
		if float(needs[need])>=52.0:break
		var choice:Dictionary=_autonomy_need_choice(need,excluded_target_ids)
		if not choice.is_empty():return choice
	# Housekeeping is an idle choice only, after ordinary needs, school/work
	# preparation and current responsibilities. Explicit queues remain untouched.
	if duty.is_empty() and preparing.is_empty() and is_instance_valid(meal_service):
		return meal_service.autonomous_cleanup_choice(self,excluded_target_ids)
	return {}

func _autonomy_eating_owned_portion(action: Dictionary) -> bool:
	# Eating restores hunger through the food ledger, not action.changes.
	# Protect only a real, fresh, unfinished portion already owned by this diner.
	if str(action.get("id",""))!="eat_meal" or str(action.get("meal_stage",""))!="eat" or not is_instance_valid(meal_service):return false
	if float(action.get("duration",0.0))<=0.0 or float(action.duration)>90.0:return false
	var plate: Dictionary=meal_service.food().portion(str(action.get("meal_plate","")))
	return not plate.is_empty() and str(plate.owner)==meal_service.member_id(self) and float(plate.progress)>=0.0 and float(plate.progress)<1.0 and _autonomy_now()<float(plate.expires)

func _reconsider_active_autonomy() -> void:
	if is_away(): return
	if not autonomy or action_queue.is_empty():return
	var current:Dictionary=action_queue[0]
	if not bool(current.get("autonomous",false)) or current.has("cooperation_id") or str(current.phase) not in ["active","approach"]:return
	# Queued player instructions retain their exact order and content.
	for later:Dictionary in action_queue.slice(1):
		if not bool(later.get("autonomous",false)):return
	# A short recovery must get a useful turn when several needs are critical.
	# Otherwise minute-by-minute replanning can repeatedly buy and abandon food.
	if str(current.phase)=="active":
		if _autonomy_eating_owned_portion(current):return
		if str(current.id) in ["nap","snack","shower","toilet"] and float(current.duration)<=90.0:return
		for need:String in NEED_NAMES:
			if float(current.changes.get(need,0.0))>0.0 and float(needs[need])<35.0:
				if float(current.duration)<=90.0 or float(current.elapsed)<60.0:return
		if int(current.get("cost",0))>0 and float(current.duration)<=90.0:return
	var danger:bool=false
	# Eating restores hunger through the food ledger, not `changes`, so a diner
	# already carrying their own fresh portion reads as a critical unmet hunger
	# here. That is not a danger while they are walking to it: diverting them to
	# the shop would release and reclaim the very plate they are about to eat.
	var eating_owned:bool=_autonomy_eating_owned_portion(current)
	for need:String in NEED_NAMES:
		if float(needs[need])<12.0 and float(current.changes.get(need,0.0))<=0.0:
			if need=="hunger" and eating_owned:continue
			var recovery:Dictionary=_autonomy_need_choice(need)
			if not recovery.is_empty() and (str(recovery.id)!=str(current.id) or str(recovery.target_id)!=str(current.target_id)):danger=true
	var duty:String=_autonomy_duty_id()
	var optional:bool=str(current.id) not in ["school","school_day","career_day","homework","job"]
	var duty_ready:bool=optional and not duty.is_empty() and _autonomy_projection_need(duty).is_empty() and not _autonomy_target_for(duty).is_empty()
	# A pastime that still ends in time for an on-time arrival is not cut short by the open duty.
	if duty_ready and duty in ["school_day","career_day"] and str(current.id) in LEISURE_ACTIONS and minutes+float(current.duration)-float(current.elapsed)+DEPARTURE_WALK<=_duty_deadline(duty):duty_ready=false
	var preparation_ready:bool=false
	var preparing:String=_autonomy_preparation_duty_id()
	if optional and not preparing.is_empty() and float(current.elapsed)>=30.0 and not _autonomy_target_for(preparing).is_empty():
		var need:String=_autonomy_projection_need(preparing)
		if not need.is_empty():
			var recovery:Dictionary=_autonomy_need_choice(need,[],true)
			preparation_ready=not recovery.is_empty() and (str(recovery.id)!=str(current.id) or str(recovery.target_id)!=str(current.target_id))
	if str(current.phase)=="active" and float(current.duration)-float(current.elapsed)<=15.0:duty_ready=false;preparation_ready=false
	if not danger and not duty_ready and not preparation_ready:return
	var next:Dictionary=_autonomous_choice()
	if next.is_empty() or (str(next.id)==str(current.id) and str(next.target_id)==str(current.target_id)):return
	# A low need only earns an interruption when the replacement actually
	# recovers it. Otherwise a free sink can cancel a walk to the easel and the
	# Lifelet starts reading, which was never the urgent errand.
	#
	# Accept the need's own autonomous recovery (cook for an open first-meal want)
	# as well as positive need deltas. Prefer an earlier catalogue pick for a
	# critical need the current action already raises (read → paint) without
	# allowing the busy-easel fallback (paint → read).
	if danger and not duty_ready and not preparation_ready:
		var next_changes:Dictionary=_actions.get(str(next.id),{}).get("changes",{})
		var addresses_danger:bool=false
		for need:String in NEED_NAMES:
			if float(needs[need])>=12.0:continue
			var current_helps:bool=float(current.changes.get(need,0.0))>0.0
			var next_helps:bool=float(next_changes.get(need,0.0))>0.0
			var recovery:Dictionary=_autonomy_need_choice(need)
			var next_is_recovery:bool=not recovery.is_empty() and str(recovery.id)==str(next.id) and str(recovery.target_id)==str(next.target_id)
			if not current_helps and (next_helps or next_is_recovery):
				addresses_danger=true;break
			if current_helps and next_is_recovery and _autonomy_need_ranks_earlier(need,str(next.id),str(current.id)):
				addresses_danger=true;break
		if not addresses_danger:return
	# A carried portion can resolve many meal targets to the same owned plate.
	# Let its real eating approach arrive instead of releasing and reclaiming
	# that plate every hunger check. Different urgent recoveries still interrupt.
	if str(current.phase)=="approach" and str(next.id)=="eat_meal" and _autonomy_eating_owned_portion(current):return
	# A waiting alternative must not immediately lose its turn to the same
	# still-occupied furnishing during ordinary emergency reconsideration.
	if autonomy_activity_available.is_valid() and not bool(autonomy_activity_available.call({"id":str(next.id),"target_id":str(next.target_id),"target_position":next.position})):return
	# Work from home pauses for a need it cannot meet at the desk, then resumes
	# with its progress bar intact: the half-finished shift goes back onto the
	# queue (behind the recovery) instead of being thrown away and restarted.
	var resumable:bool=str(current.id) in RESUMABLE_BREAK_ACTIONS and float(current.get("elapsed",0.0))>0.0
	var paused:Dictionary={}
	if resumable:
		paused=current.duplicate(true)
		paused.phase="queued"
	cancel_action()
	if resumable:
		if action_queue.is_empty():_choose_autonomous_action()
		# Insert behind the recovery that was just chosen, and ahead of any later
		# autonomous plans, so the shift resumes as soon as the need is met.
		var insert_at:int=mini(1,action_queue.size())
		action_queue.insert(insert_at,paused)
		_emit_changed()
		return
	if action_queue.is_empty():_choose_autonomous_action()

func _choose_autonomous_action() -> void:
	if not autonomy or not action_queue.is_empty():return
	_idle_minutes = 0.0
	var choice: Dictionary = _autonomous_choice()
	if not choice.is_empty() and queue_action(str(choice.id),str(choice.target_id),choice.position):
		action_queue.back()["autonomous"] = true

func _restored_need(action_id: String) -> String:
	# The need an action primarily refills, from its declared changes.
	var definition: Dictionary = _actions.get(action_id, {})
	var changes: Dictionary = definition.get("changes", {})
	var best: String = ""
	var best_value: float = 0.0
	for need: String in changes:
		if float(changes[need]) > best_value:best_value = float(changes[need]);best = need
	return best


func _has_trait(trait_name: String) -> bool:
	return character.get("traits", []).has(trait_name)


func _create_wants() -> void:
	wants = [
		{"id": "first_meal", "label": "A taste of home", "description": "Cook your first fresh meal.", "progress": 0.0, "target": 1.0, "reward": 60, "complete": false},
		_chapter_want("friend", "A familiar face", "Share a friendly chat, joke or heartfelt talk with someone at 35 friendship.", 1, 80, "familiar_chat", ["friendly", "joke", "deep_talk"])
	]
	match str(character["aspiration"]):
		"Maker": wants.append({"id": "create", "label": "Make your mark", "description": "Complete and sell three paintings.", "progress": 0.0, "target": 3.0, "reward": 180, "complete": false})
		"Connected": wants.append({"id": "close_friend", "label": "Better together", "description": "Make a close friend with 65 friendship.", "progress": 0.0, "target": 65.0, "reward": 180, "complete": false})
		"Successful": wants.append({"id": "earn", "label": "On the way up", "description": "Finish three money-making activities.", "progress": 0.0, "target": 3.0, "reward": 180, "complete": false})
		_: wants.append({"id": "balanced", "label": "A little balance", "description": "Bring every need above 65.", "progress": 0.0, "target": 6.0, "reward": 180, "complete": false})
	_adapt_child_wants()


func _adapt_child_wants() -> void:
	if str(character.age_stage) != "child": return
	# Children cannot use the stove. Also repair unfulfilled first-meal goals
	# in early child saves, preserving existing progress and reward accounting.
	for want: Dictionary in wants:
		if str(want.id) == "first_meal" and not bool(want.complete):
			want.merge({"id":"first_snack", "label":"A little independence", "description":"Get a snack from the fridge.",
				"metric":"actions", "actions":["snack"], "skill":"", "seen":[], "seen_days":[]},true)


func _update_wants() -> void:
	if aspiration_next_day > 0 and day >= aspiration_next_day:
		aspiration_stage += 1
		aspiration_next_day = 0
		_create_recurring_wants()
		_emit_notice("A new aspiration chapter: %s." % _aspiration_title())
	var friendship: float = 0.0
	for person: Dictionary in relationships.values():
		friendship = maxf(friendship, float(person["friendship"]))
	for want: Dictionary in wants:
		if bool(want["complete"]):
			continue
		if str(want["id"]) in ["friend", "close_friend"] and str(want.get("metric", "")) != "familiar_chat":
			want["progress"] = friendship
		elif str(want["id"]) == "balanced":
			var count: int = 0
			for need_name: String in NEED_NAMES:
				if float(needs[need_name]) >= 65.0:
					count += 1
			want["progress"] = float(count)
		elif str(want.get("metric", "")) == "care_days":
			var comfortable: bool = true
			for need_name: String in NEED_NAMES:
				comfortable = comfortable and float(needs[need_name]) >= 55.0
			if comfortable and not want["seen_days"].has(day):
				want["seen_days"].append(day)
				want["progress"] = float(want["seen_days"].size())
		if float(want["progress"]) + 0.00001 >= float(want["target"]):
			want["complete"] = true
			want["progress"] = float(want["target"])
			satisfaction += int(want["reward"])
			funds += int(want["reward"])
			_emit_notice("Want fulfilled: %s! +%d satisfaction and ℒ%d." % [want["label"], int(want["reward"]), int(want["reward"])])
	_archive_completed_chapter()


func _aspiration_title() -> String:
	if aspiration_stage == 1:
		return "Making a home"
	var titles: Dictionary = {"Maker":"A creative life", "Connected":"A circle of friends", "Successful":"Work with purpose", "Balanced":"A rhythm of your own"}
	return "%s · Chapter %d" % [titles[str(character["aspiration"])], aspiration_stage]


func get_aspiration_progress() -> Dictionary:
	return {"stage":aspiration_stage, "title":_aspiration_title(), "next_stage_day":aspiration_next_day, "history":aspiration_history.duplicate(true)}


# ------------------------------------------------------------------- rewards
# Satisfaction was earned and never spent. The store turns it into perks and
# potions: permanent buys are remembered in purchased_perks and change the same
# multipliers the traits already use, one-use potions act on the spot.

func _perk_has(id: String) -> bool:
	return purchased_perks.has(id)


func _perk_multiplier(channel: String) -> float:
	# Every permanent perk that names this channel, composed.
	var result: float = 1.0
	for reward_id: String in purchased_perks:
		var reward: Variant = REWARDS.get(reward_id, {})
		if not reward is Dictionary: continue
		var effect: Variant = reward.get("effect", {})
		if effect is Dictionary and effect.has(channel):
			result *= float(effect[channel])
	return result


func _perk_decay_multiplier(need: String) -> float:
	var result: float = 1.0
	for reward_id: String in purchased_perks:
		var reward: Variant = REWARDS.get(reward_id, {})
		if not reward is Dictionary: continue
		var effect: Variant = reward.get("effect", {})
		if not effect is Dictionary: continue
		var decay: Variant = effect.get("decay", {})
		if decay is Dictionary and decay.has(need):
			result *= float(decay[need])
	return result


func _career_performance_gain(base: float) -> float:
	# "Connections" multiplies every performance gain, wherever it is earned.
	return base * _perk_multiplier("performance")


func available_rewards() -> Array:
	# Every reward with its affordability, mirroring the action menu's shape.
	var result: Array = []
	for reward_id: String in REWARDS:
		var reward: Dictionary = REWARDS[reward_id]
		result.append({"id":reward_id, "label":str(reward.label), "description":str(reward.description),
			"cost":int(reward.cost), "permanent":bool(reward.permanent), "owned":_perk_has(reward_id),
			"affordable":satisfaction >= int(reward.cost)})
	return result


func can_buy_reward(id: String, reason: Variant = null) -> Dictionary:
	# Same contract as get_action_availability: one gate the UI and the queue share.
	var message: String = ""
	if not REWARDS.has(id):
		message = "That reward is not in the store."
	elif _perk_has(id):
		message = "You already own %s." % str(REWARDS[id].label)
	elif satisfaction < int(REWARDS[id].cost):
		message = "Requires %d satisfaction." % int(REWARDS[id].cost)
	var result: Dictionary = {"available":message.is_empty(), "reason":message}
	if reason is Array:
		reason.append(message)
	return result


func buy_reward(id: String) -> bool:
	if not REWARDS.has(id):
		_emit_notice("That reward is not in the store.")
		return false
	if _perk_has(id):
		_emit_notice("You already own %s." % str(REWARDS[id].label))
		return false
	var reward: Dictionary = REWARDS[id]
	var cost: int = int(reward.cost)
	if satisfaction < cost:
		_emit_notice("You need %d satisfaction for %s. You have %d." % [cost, str(reward.label), satisfaction])
		return false
	satisfaction -= cost
	if bool(reward.permanent):
		purchased_perks.append(id)
	var effect: Variant = reward.get("effect", {})
	if effect is Dictionary:
		var restore: Variant = effect.get("restore", {})
		if restore is Dictionary:
			for need_name: Variant in restore:
				if needs.has(str(need_name)):
					needs[str(need_name)] = clampf(float(restore[need_name]), 0.0, 100.0)
		var moodlet: Variant = effect.get("moodlet", {})
		if moodlet is Dictionary and not moodlet.is_empty():
			add_moodlet(str(moodlet.label), str(moodlet.emotion), str(moodlet.description), float(moodlet.remaining), int(moodlet.strength))
	_emit_notice("%s bought with %d satisfaction. %s" % [str(reward.label), cost, "It lasts for good." if bool(reward.permanent) else "Used at once."])
	_emit_changed()
	return true


func _chapter_want(id: String, label: String, description: String, target: float, reward: int, metric: String, actions: Array = [], skill: String = "") -> Dictionary:
	return {"id":id, "label":label, "description":description, "progress":0.0, "target":target, "reward":reward, "complete":false, "metric":metric, "actions":actions, "skill":skill, "seen":[], "seen_days":[]}


func _create_recurring_wants() -> void:
	var difficulty: int = mini(aspiration_stage - 1, 6)
	var reward: int = 100 + difficulty * 20
	var social_actions: Array = ["friendly", "joke", "deep_talk"]
	match str(character["aspiration"]):
		"Maker":
			var paintings: int = mini(2 + difficulty / 2, 5)
			wants = [
				_chapter_want("chapter_create", "A growing body of work", "Create and sell %d new paintings this chapter." % paintings, paintings, reward, "actions", ["paint"]),
				_chapter_want("chapter_explore", "Ideas from everyday life", "Try two different activities: cooking, reading, studying or gardening.", 2, reward, "variety", ["cook", "read", "study", "water"]),
				_chapter_want("chapter_share", "Share the process", "Enjoy friendly conversations on two different days.", 2, reward + 40, "social_days", social_actions)]
		"Connected":
			wants = [
				_chapter_want("chapter_connect", "Keep showing up", "Enjoy friendly conversations on two different days.", 2, reward + 40, "social_days", social_actions),
				_chapter_want("chapter_listen", "The art of conversation", "Earn %d Charisma XP this chapter through conversation or learning." % (60 + difficulty * 15), 60 + difficulty * 15, reward, "practice", [], "charisma"),
				_chapter_want("chapter_moments", "More than small talk", "Complete a friendly chat, a joke and a heartfelt talk.", 3, reward, "variety", social_actions)]
		"Successful":
			# An unskilled ladder names no skill of its own, and a chapter want
			# must name one the skill table actually holds, so the service trades
			# fall back to the Charisma every one of them works with.
			var career_skill: String = str(LifeCareers.job(str(career.get("track", ""))).get("skill", ""))
			if not SKILL_NAMES.has(career_skill): career_skill = "charisma"
			wants = [
				_chapter_want("chapter_income", "Build a cushion", "Earn ℒ%d from completed shifts, freelance work or paintings this chapter." % (200 + difficulty * 100), 200 + difficulty * 100, reward + 40, "income"),
				_chapter_want("chapter_practice", "Invest in your craft", "Earn %d %s XP this chapter; practice still counts at level 10." % [100 + difficulty * 20, career_skill.capitalize()], 100 + difficulty * 20, reward, "practice", [], career_skill),
				_chapter_want("chapter_unwind", "Room for a life", "Complete three different activities: cooking, sleeping, showering, reading, relaxing, watching a show or gardening.", 3, reward, "variety", ["cook", "sleep", "shower", "read", "relax", "watch", "water"])]
		_:
			wants = [
				_chapter_want("chapter_care", "Good days, gently made", "Bring every need to at least 55 on two different days.", 2, reward + 40, "care_days"),
				_chapter_want("chapter_variety", "A colorful week", "Complete five different activities: cooking, sleeping, showering, reading, relaxing, gardening, painting or friendly conversation.", 5, reward, "variety", ["cook", "sleep", "shower", "read", "relax", "water", "paint", "friendly"]),
				_chapter_want("chapter_company", "Leave room for company", "Complete two friendly chats, jokes or heartfelt talks.", 2, reward, "actions", social_actions)]


func _record_practice(skill_name: String, amount: float) -> void:
	for want: Dictionary in wants:
		if not bool(want["complete"]) and str(want.get("metric", "")) == "practice" and str(want.get("skill", "")) == skill_name:
			want["progress"] = minf(float(want["target"]), float(want["progress"]) + maxf(amount, 0.0))


func _record_chapter_activity(action_id: String, earned: int, target_id: String = "") -> void:
	for want: Dictionary in wants:
		if bool(want["complete"]):
			continue
		var metric: String = str(want.get("metric", ""))
		if metric == "income":
			want["progress"] = minf(float(want["target"]), float(want["progress"]) + float(earned))
		elif want.get("actions", []).has(action_id):
			if metric == "familiar_chat":
				if relationships.has(target_id) and float(relationships[target_id].friendship) >= 35.0:
					want["progress"] = 1.0
			elif metric == "actions":
				want["progress"] = minf(float(want["target"]), float(want["progress"]) + 1.0)
			elif metric == "variety" and not want["seen"].has(action_id):
				want["seen"].append(action_id)
				want["progress"] = float(want["seen"].size())
			elif metric == "social_days" and not want["seen_days"].has(day):
				want["seen_days"].append(day)
				want["progress"] = float(want["seen_days"].size())


func _archive_completed_chapter() -> void:
	if wants.is_empty() or aspiration_next_day > 0:
		return
	var total_reward: int = 0
	for want: Dictionary in wants:
		if not bool(want["complete"]):
			return
		total_reward += int(want["reward"])
	aspiration_history.push_front({"stage":aspiration_stage, "title":_aspiration_title(), "completed_day":day, "reward":total_reward, "wants":wants.duplicate(true)})
	while aspiration_history.size() > MAX_PROGRESS_HISTORY:
		aspiration_history.pop_back()
	aspiration_next_day = day + 1
	remember("An aspiration chapter complete", "%s. A new chapter begins tomorrow." % _aspiration_title())
	_emit_notice("Chapter complete! Your next aspiration chapter begins on day %d." % aspiration_next_day)


func _offer_daily_story() -> void:
	if day < 2 or _story_generated_day >= day:
		return
	_story_generated_day = day
	if story_events.size() >= MAX_STORY_EVENTS:
		return
	var kind: String = STORY_KINDS[(day - 2) % STORY_KINDS.size()]
	# A stride of three visits every resident across four days, and the
	# whole-cycle count (integer division by the kind period) shifts the table
	# one slot per eight-day cycle, so kind and host pairings drift instead of
	# locking one-to-one.
	var neighbor: String = LifeResidentCatalogue.IDS[(((day - 2) * 3) + (day - 2) / 8) % LifeResidentCatalogue.IDS.size()]
	var track: Dictionary = LifeCareers.job(str(career.get("track", "")))
	var story_skill: String = str(track.get("skill", ""))
	if not SKILL_NAMES.has(story_skill): story_skill = "charisma"
	story_events.append({"id":"story_day_%d" % day, "kind":kind, "day":day, "context":{"neighbor":neighbor, "skill":story_skill, "career_level":int(career.level), "creativity_level":int(skills.creativity.level)}})
	_emit_notice("A new story choice is waiting: %s." % _story_event(story_events.back()).title)


func _story_choice(id: String, label: String, changes: Dictionary = {}, requirements: Dictionary = {}) -> Dictionary:
	var available: bool = funds >= int(changes.get("cost", 0))
	var reason: String = "" if available else "Requires ℒ%d." % int(changes.get("cost", 0))
	if not requirements.is_empty() and int(skills[str(requirements.skill)].level) < int(requirements.level):
		available = false
		reason = "Requires %s level %d." % [str(requirements.skill).capitalize(), int(requirements.level)]
	return {"id":id, "label":label, "effects":_story_effects_text(changes), "available":available, "unavailable_reason":reason, "changes":changes, "requirements":requirements}


func _story_event(ticket: Dictionary) -> Dictionary:
	var context: Dictionary = ticket.context
	var neighbor: String = str(context.neighbor)
	var neighbor_name: String = str(relationships[neighbor].name)
	var skill_name: String = str(context.skill)
	var result: Dictionary = {"id":ticket.id, "kind":ticket.kind, "day":ticket.day, "title":"", "description":"", "choices":[]}
	match str(ticket.kind):
		"neighbor_invitation":
			result.title = "An extra place at the table"
			result.description = "%s is arranging a small neighborhood supper. You could bring something homemade, suggest a short walk together, or keep your day free." % neighbor_name
			result.choices = [
				_story_choice("bring_dish", "Bring a homemade dish", {"cost":24, "needs":{"hunger":12, "social":24, "fun":10, "energy":-8}, "skills":{"cooking":20}, "friendship":{neighbor:14}}),
				_story_choice("walk_together", "Suggest a walk together", {"needs":{"energy":-10, "fun":15, "social":18}, "skills":{"gardening":12}, "friendship":{neighbor:8}}),
				_story_choice("keep_day_free", "Keep today to myself")]
		"career_opportunity":
			result.title = "A project with room to grow"
			result.description = "A team has a small project that could use your %s skills. A stretch assignment pays immediately, while a mentoring session costs money and builds more skill." % skill_name
			result.choices = [
				_story_choice("stretch_assignment", "Take the stretch assignment", {"income":80 + int(context.career_level) * 25, "needs":{"energy":-18, "fun":-10}, "skills":{skill_name:45}, "performance":15}),
				_story_choice("mentoring", "Book a mentoring session", {"cost":30, "needs":{"energy":-6}, "skills":{skill_name:65}, "performance":6}),
				_story_choice("regular_work", "Keep my regular workload")]
		"hobby_exhibition":
			result.title = "Small works, big conversations"
			result.description = "The local studio is showing work by neighborhood makers. There is a table for your pieces, or you can help arrange the show and meet the people behind it."
			result.choices = [
				_story_choice("show_work", "Rent a table and show my work", {"cost":45, "income":55 + int(context.creativity_level) * 25, "needs":{"energy":-14, "fun":14, "social":10}, "skills":{"creativity":35}, "satisfaction":25}),
				_story_choice("hang_show", "Help hang the exhibition", {"needs":{"energy":-12, "social":18}, "skills":{"charisma":25, "creativity":18}, "friendship":{neighbor:8}}),
				_story_choice("studio_day", "Keep a quiet studio day")]
		"garden_exchange":
			result.title = "A cutting with a story"
			result.description = "%s has helped set up a plant exchange. You could bring home a cutting, earn a small thank-you for setting up tables, or leave it for another week." % neighbor_name
			result.choices = [
				_story_choice("new_cutting", "Choose a cutting and swap growing tips", {"cost":15, "needs":{"fun":10}, "skills":{"gardening":35}, "friendship":{neighbor:6}}),
				_story_choice("set_up", "Help set up the exchange", {"income":30, "needs":{"energy":-12, "hygiene":-8}, "skills":{"gardening":15}}),
				_story_choice("another_week", "Save it for another week")]
		"learning_circle":
			result.title = "Everyone knows something"
			result.description = "The library is hosting a skill circle. Join a practical workshop, teach a trick from your own experience, or ask the question other beginners might be holding back."
			result.choices = [
				_story_choice("workshop", "Join the practical workshop", {"cost":35, "needs":{"energy":-8, "fun":12}, "skills":{"logic":55}}),
				_story_choice("teach", "Teach a useful trick", {"income":45, "needs":{"energy":-10, "social":18}, "skills":{"charisma":30}}, {"skill":skill_name, "level":2}),
				_story_choice("ask", "Share a beginner's question", {"needs":{"energy":-4, "social":12}, "skills":{"charisma":18, "logic":20}})]
		"community_picnic":
			result.title = "A little space in the week"
			result.description = "A picnic is coming together in the garden. There is room to join the table, help prepare something fresh, or use the opening in your week for a quiet reset."
			result.choices = [
				_story_choice("join_picnic", "Join the garden picnic", {"cost":18, "needs":{"social":24, "fun":18, "energy":-10}, "friendship":{neighbor:12}}),
				_story_choice("prepare_food", "Help prepare the picnic food", {"needs":{"hunger":20, "energy":-12, "hygiene":-6}, "skills":{"cooking":35}, "friendship":{neighbor:6}}),
				_story_choice("quiet_reset", "Take a quiet reset", {"needs":{"energy":18, "fun":10}})]
		"block_party":
			result.title = "The lane closes for the evening"
			result.description = "%s is organizing the end-of-lane block party. Bring a dish to share, run the music corner, or keep your porch quiet and watch the string lights go up." % neighbor_name
			result.choices = [
				_story_choice("bring_party_dish", "Bring a dish to share", {"cost":20, "needs":{"social":20, "fun":12, "energy":-10}, "skills":{"cooking":30}, "friendship":{neighbor:10}}),
				_story_choice("music_corner", "Run the music corner", {"needs":{"energy":-14, "social":16, "fun":14}, "skills":{"creativity":25}, "friendship":{neighbor:6}}),
				_story_choice("porch_night", "Keep a quiet porch night", {"needs":{"energy":12, "fun":8}})]
		"flea_market":
			result.title = "One table, everything must go"
			result.description = "The empty lot becomes a flea market for the morning. Rent a table and sell what you no longer need, hunt for a bargain, or spend the morning at home."
			result.choices = [
				_story_choice("rent_table", "Rent a table and sell", {"income":60, "needs":{"energy":-12, "social":14}, "skills":{"charisma":20}, "satisfaction":10}),
				_story_choice("hunt_bargain", "Hunt for a bargain", {"cost":25, "needs":{"fun":14, "social":8}, "satisfaction":15}),
				_story_choice("home_morning", "Keep the morning at home", {"needs":{"energy":15, "fun":6}})]
	return result


func _story_effects_text(changes: Dictionary) -> String:
	var parts: PackedStringArray = []
	if int(changes.get("cost", 0)) > 0:
		parts.append("Pay ℒ%d" % int(changes.cost))
	if int(changes.get("income", 0)) > 0:
		parts.append("Earn ℒ%d" % int(changes.income))
	for need_name: String in changes.get("needs", {}):
		parts.append("%s %+d" % [need_name.capitalize(), int(changes.needs[need_name])])
	for skill_name: String in changes.get("skills", {}):
		parts.append("%s +%d XP" % [skill_name.capitalize(), int(changes.skills[skill_name])])
	for neighbor: String in changes.get("friendship", {}):
		parts.append("%s friendship %+d" % [relationships[neighbor].name, int(changes.friendship[neighbor])])
	if int(changes.get("performance", 0)) > 0:
		parts.append("Career performance +%d" % int(changes.performance))
	if int(changes.get("satisfaction", 0)) > 0:
		parts.append("Satisfaction +%d" % int(changes.satisfaction))
	return " · ".join(parts) if not parts.is_empty() else "No cost or stat changes."


func get_story_events() -> Array:
	var result: Array = []
	for ticket: Dictionary in story_events:
		var event: Dictionary = _story_event(ticket)
		for choice: Dictionary in event.choices:
			choice.erase("changes")
			choice.erase("requirements")
		result.append(event)
	return result


func choose_story_event(event_id: String, choice_id: String) -> bool:
	for event_index: int in range(story_events.size()):
		var ticket: Dictionary = story_events[event_index]
		if str(ticket.id) != event_id:
			continue
		var event: Dictionary = _story_event(ticket)
		for choice: Dictionary in event.choices:
			if str(choice.id) != choice_id:
				continue
			if not bool(choice.available):
				_emit_notice(str(choice.unavailable_reason))
				return false
			# Remove first, so listeners cannot replay the same choice during a signal.
			story_events.remove_at(event_index)
			var effects: Dictionary = choice.changes
			funds -= int(effects.get("cost", 0))
			funds += int(effects.get("income", 0))
			for need_name: String in effects.get("needs", {}):
				needs[need_name] = clampf(float(needs[need_name]) + float(effects.needs[need_name]), 0.0, 100.0)
			for skill_name: String in effects.get("skills", {}):
				_gain_skill(skill_name, float(effects.skills[skill_name]))
			for neighbor: String in effects.get("friendship", {}):
				relationships[neighbor].friendship = clampf(float(relationships[neighbor].friendship) + float(effects.friendship[neighbor]), -100.0, 100.0)
				_update_relationship_status(relationships[neighbor])
			if int(effects.get("performance", 0)) > 0:
				career.performance = minf(1000.0, float(career.performance) + _career_performance_gain(float(effects.performance)))
				_check_promotion()
			satisfaction += int(effects.get("satisfaction", 0))
			story_history.push_front({"event_id":event_id, "kind":ticket.kind, "title":event.title, "offered_day":ticket.day, "day":day, "minutes":int(minutes), "choice_id":choice_id, "choice_label":choice.label, "effects":choice.effects})
			while story_history.size() > MAX_PROGRESS_HISTORY:
				story_history.pop_back()
			remember(str(event.title), str(choice.label))
			_update_wants()
			_emit_notice("%s: %s." % [event.title, choice.label])
			_emit_changed()
			return true
		return false
	return false


## The HUD clock line. The weekday and whether this Lifelet is due at work or
## school matters more than how many days have passed, so the line names the day
## and what kind of day it is: a workday, a school day, or a day off. The day
## number stays on the line beside the weekday, because saves, bills and
## schedules all speak in day numbers.
func get_clock_text() -> String:
	var hour: int = int(minutes) / 60
	var minute: int = int(minutes) % 60
	return "%s · Day %d · %02d:%02d · %s" % [LifeEducation.weekday_name(day), day, hour, minute, day_kind_label()]

## What kind of day this is for this Lifelet, in the player's own words.
func day_kind_label() -> String:
	if is_spirit():
		return "At rest"
	if str(character.get("life_stage","adult"))=="minor":
		return "School day" if LifeEducation.weekday(day) else "Your day off"
	# Adults are due at work on the weekdays their own career schedule names.
	if LifeEducation.weekday(day) and not str(career.get("track","")).is_empty():
		return "Your workday"
	return "Your day off"


func get_mood() -> Dictionary:
	var lowest_name: String = "hunger"
	for need_name: String in NEED_NAMES:
		if float(needs[need_name]) < float(needs[lowest_name]):
			lowest_name = need_name
	if float(needs[lowest_name]) < 20.0:
		var labels: Dictionary = {"hunger": "Hungry", "energy": "Exhausted", "hygiene": "Grimy", "bladder": "Uncomfortable", "fun": "Bored", "social": "Lonely"}
		return {"label": labels[lowest_name], "description": "Your %s needs attention." % lowest_name, "color": Color("d77659")}
	if float(needs[lowest_name]) < 40.0:
		return {"label": "Unsettled", "description": "A little self-care would help.", "color": Color("dca657")}
	if not moodlets.is_empty():
		var strongest:Dictionary=moodlets[-1]
		for entry in moodlets:
			if int(entry.strength)>int(strongest.strength):strongest=entry
		return {"label":strongest.emotion,"description":strongest.description,"color":emotion_color(strongest.emotion)}
	if not action_queue.is_empty() and str(action_queue[0]["phase"]) == "active":
		var id: String = str(action_queue[0]["id"])
		if id == "paint" and _has_trait("Creative"):
			return {"label": "Inspired", "description": "Creating something entirely your own.", "color": Color("8d80b8")}
		if id in ["read", "study", "work"]:
			return {"label": "Focused", "description": "Your mind is in the moment.", "color": Color("629db3")}
	if float(needs[lowest_name]) >= 65.0:
		return {"label": "Flourishing", "description": "Life feels beautifully balanced.", "color": Color("65a68b")}
	return {"label": "Content", "description": "A good day with room for possibility.", "color": Color("7aaf89")}


func get_state() -> Dictionary:
	return {"version": SAVE_VERSION, "character": character.duplicate(true), "lifecycle": lifecycle.duplicate(true), "education": education.duplicate(true), "away_state":away_state.duplicate(true), "needs": needs.duplicate(true), "second_wind": second_wind, "bladder_grace":bladder_grace, "starvation_minutes":starvation_minutes, "exhaustion_minutes":exhaustion_minutes, "deferred_passing_minutes":deferred_passing_minutes, "skills": skills.duplicate(true), "relationships": relationships.duplicate(true), "career": career.duplicate(true), "degree": degree, "criminal_record": criminal_record.duplicate(true), "wants": wants.duplicate(true), "whims": whims.duplicate(true), "funds": funds, "day": day, "minutes": minutes, "speed": speed, "autonomy": autonomy, "autonomy_state":autonomy_state.duplicate(true), "action_queue": action_queue.duplicate(true), "satisfaction": satisfaction, "last_bill_day": last_bill_day, "pending_bill":pending_bill.duplicate(true), "bills_paid_total":bills_paid_total, "bills_late":bills_late, "utilities_cut":utilities_cut, "insurance_policy_id":insurance_policy_id, "purchased_perks": purchased_perks.duplicate(),"moodlets":moodlets.duplicate(true),"memories":memories.duplicate(true), "aspiration_stage":aspiration_stage, "aspiration_next_day":aspiration_next_day, "aspiration_history":aspiration_history.duplicate(true), "story_events":story_events.duplicate(true), "story_history":story_history.duplicate(true), "story_generated_day":_story_generated_day, "romantic_partner":romantic_partner, "social_history":social_history.duplicate(true), "last_hugs":last_hugs.duplicate(true), "last_gossip":last_gossip.duplicate(true), "social_cooldowns":social_cooldowns.duplicate(true), "last_hosted_credit":last_hosted_credit, "last_companion_credit":last_companion_credit, "routine_memory_days":routine_memory_days.duplicate(true)}


func save_game(world_data: Array = []) -> bool:
	var state: Dictionary = get_state()
	state["world"] = world_data.duplicate(true)
	var file: FileAccess = FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		_emit_notice("Could not save your household. Please check available disk space.")
		return false
	file.store_string(JSON.stringify(_json_safe(state), "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_emit_notice("Saving failed. Your previous save is still available.")
		return false
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH))
	if rename_error != OK:
		_emit_notice("Could not replace the save file.")
		return false
	_emit_notice("Household saved. Your story will be here when you return.")
	return true


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"ok": false, "error": "No saved household yet."}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Could not open the saved household."}
	if file.get_length() > 4 * 1024 * 1024:
		return {"ok": false, "error": "The save file is too large."}
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "The saved household is damaged."}
	return restore_state(parser.data)


func restore_state(state: Dictionary, allow_cooperation: bool = false) -> Dictionary:
	state = state.duplicate(true)
	state["action_queue"]=state.get("action_queue",[]) # Legacy idle saves may omit this optional list.
	if not state.action_queue is Array:return {"ok":false,"error":"Save contains an invalid action queue."}
	if state.get("skills") is Dictionary:
		# Older saves predate later skills; they begin those at level 1.
		for skill_name: String in SKILL_NAMES:
			if not state.skills.has(skill_name): state.skills[skill_name] = {"level":1,"xp":0.0}
	for action: Variant in state.get("action_queue",[]):
		if action is Dictionary and (action.has("cooperation_id") or str(action.get("id","")) == "help_homework") and not allow_cooperation:
			return {"ok":false,"error":"Cooperative homework must be restored with its complete household."}
	# Validate everything before touching the live household.
	var error: String = _validate_state(state)
	if not error.is_empty():
		return {"ok": false, "error": error}
	_social_family.clear()
	character = state["character"].duplicate(true)
	character["age_stage"] = LifeLifecycle.stage_for(character)
	LifeCharacterIdentity.ensure_wardrobe(character)
	lifecycle = state.get("lifecycle", LifeLifecycle.fresh()).duplicate(true)
	lifecycle.progress = float(lifecycle.progress)
	for birthday: Dictionary in lifecycle.history: birthday.day = int(birthday.day)
	if is_spirit():
		lifecycle["passed"] = true
	needs = state["needs"].duplicate(true)
	# Temporary energy is an optional pool: an older save has none, and a
	# missing key means a Lifelet who has not had a coffee, not a broken save.
	second_wind = clampf(float(state.get("second_wind", 0.0)), 0.0, SECOND_WIND_MAX)
	bladder_grace=float(state.get("bladder_grace",0.0))
	starvation_minutes=float(state.get("starvation_minutes",0.0))
	exhaustion_minutes=float(state.get("exhaustion_minutes",0.0))
	deferred_passing_minutes=float(state.get("deferred_passing_minutes",0.0))
	if is_spirit() and str(character.get("passing_cause", "")).is_empty():
		character["passing_cause"] = "old_age"
	skills = state["skills"].duplicate(true)
	relationships = state["relationships"].duplicate(true)
	character["life_stage"] = str(character.get("life_stage", "adult"))
	for relationship: Dictionary in relationships.values():
		_normalize_relationship(relationship, true)
	romantic_partner = str(state.get("romantic_partner", ""))
	social_history = state.get("social_history", []).duplicate(true)
	for entry: Dictionary in social_history:
		entry.day = int(entry.day)
		entry.minutes = int(entry.minutes)
	_recent_social_events.clear()
	career = state["career"].duplicate(true)
	degree = LifeCareers.normalise_degree(str(state.get("degree", "none")))
	criminal_record = (state.get("criminal_record", {}) as Dictionary).duplicate(true)
	# A save made before this ladder grew can carry a rung and a title from the
	# old five-level table, so the record is rebuilt from the ladder it names.
	var saved_track: String = str(career.get("track", LifeCareers.DEFAULT_JOB))
	if not LifeCareers.has(saved_track):
		saved_track = LifeCareers.DEFAULT_JOB
	var saved_level: int = clampi(int(career.get("level", 1)), 1, LifeCareers.MAX_LEVEL)
	career["track"] = saved_track
	career["level"] = saved_level
	career["title"] = LifeCareers.title_at(saved_track, saved_level)
	career["salary"] = LifeCareers.pay(saved_track, saved_level, degree)
	career["schedule"]=career.get("schedule",LifeCareerSchedule.fresh(int(state.day)))
	wants = state["wants"].duplicate(true)
	moodlets=state.get("moodlets",[]).duplicate(true)
	memories=state.get("memories",[]).duplicate(true)
	aspiration_stage = int(state.get("aspiration_stage", 1))
	aspiration_next_day = int(state.get("aspiration_next_day", 0))
	aspiration_history = state.get("aspiration_history", []).duplicate(true)
	story_events = state.get("story_events", []).duplicate(true)
	story_history = state.get("story_history", []).duplicate(true)
	_story_generated_day = int(state.get("story_generated_day", state["day"]))
	# JSON numbers are floats. Normalize calendar identity fields so day-set
	# membership remains stable when a chapter is resumed partway through a day.
	for want: Dictionary in wants:
		_normalize_want_numbers(want)
	_adapt_child_wants()
	for chapter: Dictionary in aspiration_history:
		for key: String in ["stage", "completed_day", "reward"]:
			chapter[key] = int(chapter[key])
		for want: Dictionary in chapter.wants:
			_normalize_want_numbers(want)
	for ticket: Dictionary in story_events:
		ticket.day = int(ticket.day)
		ticket.context.career_level = int(ticket.context.career_level)
		ticket.context.creativity_level = int(ticket.context.creativity_level)
	for story: Dictionary in story_history:
		for key: String in ["day", "offered_day", "minutes"]:
			story[key] = int(story[key])
	# Repeat-interaction state survives saves so hug warmth, gossip staleness
	# and chooser cooldowns keep their consequences across a reload.
	last_hugs = {}
	for key: Variant in state.get("last_hugs", {}):last_hugs[str(key)] = float(state["last_hugs"][key])
	last_gossip = {}
	for key: Variant in state.get("last_gossip", {}):last_gossip[str(key)] = float(state["last_gossip"][key])
	social_cooldowns = {}
	for key: Variant in state.get("social_cooldowns", {}):social_cooldowns[str(key)] = float(state["social_cooldowns"][key])
	last_hosted_credit = float(state.get("last_hosted_credit", -1e18))
	last_companion_credit = float(state.get("last_companion_credit", -1e18))
	routine_memory_days = {}
	for key: Variant in state.get("routine_memory_days", {}):routine_memory_days[str(key)] = int(state["routine_memory_days"][key])
	funds = int(state["funds"])
	day = int(state["day"])
	minutes = float(state["minutes"])
	var school_state: Dictionary = state.get("education",LifeEducation.fresh(str(character.age_stage),day))
	education = LifeEducation.advance(school_state,str(character.age_stage),day).state
	speed = int(state.get("speed", 1))
	autonomy = bool(state.get("autonomy", true))
	autonomy_state = state.get("autonomy_state",{"version":1,"contacts":{},"deferred":{}}).duplicate(true)
	_leisure_history.clear()
	for pastime:Variant in autonomy_state.get("leisure",[]):_leisure_history.append(str(pastime))
	away_state = state.get("away_state",{}).duplicate(true)
	if not away_state.is_empty():
		away_state.exit_position = _as_vector3(away_state.exit_position)
		for key:String in ["version","departure_day","return_day"]: away_state[key] = int(away_state[key])
	satisfaction = int(state.get("satisfaction", 0))
	if state.has("whims"):
		whims = state.whims.duplicate(true)
	else:
		whims = LifeWantsManager.fresh_state(character, str(get_mood().label), needs)
	last_bill_day = int(state.get("last_bill_day", 0))
	pending_bill = state.get("pending_bill", {}).duplicate(true) if state.get("pending_bill", {}) is Dictionary else {}
	# Older saves recorded the last payment here. An outstanding bill retains
	# its issue date, which anchors the weekly cadence after it is paid.
	if not pending_bill.is_empty():
		last_bill_day = int(pending_bill.issued_day)
	bills_paid_total = int(state.get("bills_paid_total", state.get("bills_paid", 0)))
	bills_late = int(state.get("bills_late", 0))
	utilities_cut = bool(state.get("utilities_cut", false))
	insurance_policy_id = str(state.get("insurance_policy_id", state.get("insurance_policy","")))
	# Permanent perks survive the save; one-use potions were never recorded.
	purchased_perks.clear()
	for perk: Variant in state.get("purchased_perks", []):
		purchased_perks.append(str(perk))
	action_queue.clear()
	for stored: Dictionary in state.get("action_queue", []):
		var action: Dictionary = _actions[str(stored["id"])].duplicate(true)
		if str(action.id) in AGE_GATED_ACTIONS and not bool(get_action_availability(str(action.id), str(stored.get("target_id",""))).available):
			_emit_notice("%s: a saved activity no longer suits this age and was removed." % str(character.get("name","")))
			continue
		if str(action.id)=="cook":action=LifeMeals.cooking_definition(action,str(stored.get("recipe","garden_skillet")))
		action["target_id"] = str(stored.get("target_id", ""))
		action["target_position"] = _as_vector3(stored.get("target_position", [0.0, 0.0, 0.0]))
		action["duration"] = float(stored.get("duration", action["duration"]))
		action["elapsed"] = clampf(float(stored.get("elapsed", 0.0)), 0.0, float(action["duration"]))
		action["progress"] = clampf(float(action["elapsed"]) / float(action["duration"]), 0.0, 1.0)
		action["phase"] = "queued"
		action["paid"] = bool(stored.get("paid", false))
		action["autonomous"] = bool(stored.get("autonomous", false))
		if stored.has("started_day"): action["started_day"] = int(stored.started_day)
		if stored.has("started_minutes"): action["started_minutes"] = float(stored.started_minutes)
		if stored.has("target_kind"): action["target_kind"] = str(stored.target_kind)
		for key: String in ["cooperation_id","cooperation_role","meal_source","meal_stage","meal_plate","meal_seat","seat_slot"]:
			if stored.has(key): action[key] = str(stored[key])
		if stored.has("cooperation_primary"): action["cooperation_primary"] = bool(stored.cooperation_primary)
		if stored.has("partner_id"): action["partner_id"] = str(stored.partner_id)
		if stored.has("meal_standing"): action["meal_standing"] = stored.meal_standing
		if stored.has("adoption_serial"): action["adoption_serial"]=int(stored.adoption_serial)
		if stored.has("baby_serial"): action["baby_serial"]=int(stored.baby_serial)
		for key:String in ["home_visit_serial","home_visit_token"]:
			if stored.has(key):action[key]=int(stored[key])
		if str(action.id) == "birthday": action["birthday_from_stage"] = str(stored.get("birthday_from_stage",character.age_stage))
		if str(action.id) in ["school_day","career_day"] and is_away():
			action.phase = "active"
			for need:String in action.changes:action.changes[need]=float(action.changes[need])*float(action.duration)/(LifeCareerSchedule.LENGTH if str(action.id)=="career_day" else 420.0)
		action_queue.append(action)
	_idle_minutes = 0.0
	_warned_needs.clear()
	_start_front()
	_publish("away_changed",[get_away_state()])
	_emit_changed()
	_emit_notice("Welcome home, %s." % character["name"])
	return {"ok": true, "world": state.get("world", []).duplicate(true)}


func _autonomy_integer(value:Variant,minimum:int,maximum:int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=minimum and float(value)<=maximum

func _validate_social_repeat_state(state:Dictionary) -> String:
	# Hug/gossip stamps are absolute game minutes; chooser cooldowns are
	# absolute stamps no further than a three-hour cooldown ahead.
	var now:float=float(state.get("day",1)-1)*1440.0+float(state.get("minutes",0.0))
	for key:String in ["last_hugs","last_gossip"]:
		var stamps:Variant=state.get(key,{})
		if not stamps is Dictionary:return "Save contains invalid social stamps."
		for target:Variant in stamps:
			if not target is String or str(target).is_empty() or not _number_in_range(stamps[target],0.0,maxf(now,0.0)):
				return "Save contains invalid social stamps."
	var cooldowns:Variant=state.get("social_cooldowns",{})
	if not cooldowns is Dictionary:return "Save contains an invalid social cooldown."
	for target:Variant in cooldowns:
		if not target is String or str(target).is_empty() or not _number_in_range(cooldowns[target],0.0,now+181.0):
			return "Save contains an invalid social cooldown."
	return ""

func _validate_autonomy_state(state:Dictionary) -> String:
	var value:Variant=state.get("autonomy_state",{"version":1,"contacts":{},"deferred":{}})
	if not value is Dictionary or not _autonomy_integer(value.get("version"),1,1) or not value.get("contacts") is Dictionary or not value.get("deferred") is Dictionary:return "Save contains invalid autonomy history."
	if value.contacts.size()>state.relationships.size() or value.deferred.size()>4:return "Save contains too many autonomous history entries."
	var now:float=float(state.day-1)*1440.0+float(state.minutes)
	for id:Variant in value.contacts:
		var contact:Variant=value.contacts[id]
		if not id is String or not state.relationships.has(id) or not contact is Dictionary:return "Save contains an unknown social contact."
		if not _number_in_range(contact.get("at"),0.0,now) or str(contact.get("action","")) not in SOCIAL_ACTIONS or not _autonomy_integer(contact.get("count"),1,1000000):return "Save contains an invalid social contact time or activity."
	for id:Variant in value.deferred:
		if str(id) not in ["school","school_day","career_day","homework","job"] or not _number_in_range(value.deferred[id],0.0,now+1440.0):return "Save contains an invalid postponed responsibility."
	var leisure:Variant=value.get("leisure",[])
	if not leisure is Array or leisure.size()>LEISURE_HISTORY:return "Save contains an invalid pastime history."
	for id:Variant in leisure:
		if not id is String or (id not in LEISURE_ACTIONS and id!="bath"):return "Save contains an unknown recent pastime."
	return ""


func _validate_away_state(state:Dictionary) -> String:
	if not state.get("away_state",{}) is Dictionary:return "Save contains invalid away state."
	# A prison sentence is its own absence, owned by the criminal record rather
	# than by a queued action, so it is validated against that record.
	if str(state.get("away_state",{}).get("activity",""))=="prison":
		return _validate_prison_away_state(state)
	if str(state.get("away_state",{}).get("activity",""))=="hospital":
		return _validate_hospital_away_state(state)
	if str(state.get("away_state",{}).get("activity",""))=="career" or state.action_queue.any(func(action:Dictionary)->bool:return str(action.id)=="career_day"):
		return _validate_career_away_state(state)
	return _validate_school_away_state(state)


## Validate a saved prison sentence. The record is the authority: the absence
## must agree with it, and a Lifelet who is not inside must not have one.
func _validate_prison_away_state(state:Dictionary) -> String:
	var record:Variant=state.get("criminal_record",{})
	var record_error:String=LifeCareers.criminal_error(record)
	if not record_error.is_empty():return record_error
	if not record is Dictionary or record.is_empty():return "Save has a prison absence without a criminal record."
	if not bool(record.get("serving_at_home",false))==false:return "Save serves a prison sentence at home and away at once."
	var value:Dictionary=state.get("away_state",{})
	if not _autonomy_integer(value.get("version"),1,1) or str(value.get("phase","")) not in ["away","returning"]:return "Save contains an unsupported prison absence."
	if _autonomy_integer(value.get("departure_day"),1,int(state.day))==false:return "Save contains an invalid prison departure."
	if not _autonomy_integer(value.get("return_day"),int(value.get("departure_day",0)),1000000):return "Save contains an invalid prison release day."
	if int(value.get("return_day",0))!=int(record.get("prison_until_day",0)):return "Save disagrees about when the sentence ends."
	return ""


## Validate a saved hospital stay after a birth. It has no timed return: Welcome
## Baby Home ends it, so it only has to be a real, already-begun absence that no
## school or work departure contradicts.
func _validate_hospital_away_state(state:Dictionary) -> String:
	var value:Dictionary=state.get("away_state",{})
	if not _autonomy_integer(value.get("version"),1,1) or str(value.get("phase",""))!="away":return "Save contains an unsupported hospital stay."
	if state.action_queue.any(func(action:Dictionary)->bool:return str(action.id) in ["school_day","career_day"]):return "Save leaves for school or work from the hospital."
	if not _autonomy_integer(value.get("departure_day"),1,int(state.day)) or not _number_in_range(value.get("departure_minutes"),0.0,1439.99999):return "Save contains an invalid hospital arrival."
	if not _autonomy_integer(value.get("return_day"),int(value.departure_day),1000000):return "Save contains an invalid hospital stay."
	var position:Variant=value.get("exit_position")
	if position is Vector3:
		if not position.is_finite():return "Save contains an invalid hospital return position."
	elif position is Array and position.size()==3:
		for component:Variant in position:
			if not _number_in_range(component,-100000.0,100000.0):return "Save contains an invalid hospital return position."
	else:return "Save contains an invalid hospital return position."
	return ""


func _validate_school_away_state(state: Dictionary) -> String:
	var value: Variant = state.get("away_state",{})
	if not value is Dictionary: return "Save contains invalid away state."
	var pending: Array = state.action_queue.filter(func(action:Dictionary)->bool:return str(action.id) == "school_day")
	if pending.size() > 1: return "Save contains duplicate school departures."
	if value.is_empty():
		if pending.is_empty(): return ""
		var action: Dictionary = pending[0]
		if LifeLifecycle.stage_for(state.character) not in LifeEducation.SCHOOL_STAGES or not LifeEducation.weekday(int(state.day)) or float(state.minutes) < 480.0 or float(state.minutes) > 720.0 or int(state.education.last_attendance_day) == int(state.day):
			return "Save schedules an unavailable school departure."
		if action.get("paid") != false or not action.get("paid") is bool or not _number_in_range(action.get("elapsed"),0.0,0.0) or not _number_in_range(action.get("duration"),420.0,420.0):
			return "Save contains a departed pupil without away state."
		if str(action.get("target_kind","")) != "lot_exit" or str(action.get("target_id","")) != "lot_exit": return "Save contains a school departure without a neighborhood exit."
		return ""
	if not _autonomy_integer(value.get("version"),1,1) or value.get("activity") != "school" or str(value.get("phase","")) not in ["away","returning"]:
		return "Save contains an unsupported away activity."
	if pending.size() != 1 or state.action_queue.is_empty() or str(state.action_queue[0].id) != "school_day": return "Save has an away Lifelet without its active departure."
	if not _autonomy_integer(value.get("departure_day"),1,int(state.day)) or not _autonomy_integer(value.get("return_day"),int(value.departure_day),int(value.departure_day)) or not LifeEducation.weekday(int(value.departure_day)):
		return "Save contains an invalid away calendar."
	if not _number_in_range(value.get("departure_minutes"),480.0,720.0) or not _number_in_range(value.get("return_minutes"),900.0,900.0) or not value.get("completed") is bool:
		return "Save contains invalid school departure or return times."
	if str(value.get("age_stage","")) not in LifeEducation.SCHOOL_STAGES or str(value.get("exit_id","")) != "lot_exit": return "Save contains an invalid pupil or return location."
	var position: Variant = value.get("exit_position")
	if position is Vector3:
		if not position.is_finite(): return "Save contains an invalid return position."
	elif position is Array and position.size() == 3:
		for component: Variant in position:
			if not _number_in_range(component,-100000.0,100000.0): return "Save contains an invalid return position."
	else: return "Save contains an invalid return position."
	var departed: float = float(value.departure_day-1)*1440.0+float(value.departure_minutes)
	var due: float = float(value.return_day-1)*1440.0+900.0
	var now: float = float(state.day-1)*1440.0+float(state.minutes)
	if now < departed or not _number_in_range(value.get("ended_at"),0.0,now): return "Save contains future away progress."
	var action: Dictionary = pending[0]
	if action.get("paid") != true or not action.get("paid") is bool or str(action.get("target_id","")) != "lot_exit" or str(action.get("target_kind","")) != "lot_exit" or not _as_vector3(action.target_position).is_equal_approx(_as_vector3(position)):
		return "Save contains a mismatched away action or exit."
	if not _autonomy_integer(action.get("started_day"),int(value.departure_day),int(value.departure_day)) or not _number_in_range(action.get("started_minutes"),float(value.departure_minutes)-.00000001,float(value.departure_minutes)+.00000001) or not _number_in_range(action.get("duration"),due-departed-.00000001,due-departed+.00000001):
		return "Save contains an invalid away duration or start."
	var expected_elapsed: float = now-departed if str(value.phase) == "away" else float(value.ended_at)-departed
	if not _number_in_range(action.get("elapsed"),maxf(0.0,expected_elapsed-.00001),minf(due-departed+.00000001,expected_elapsed+.00001)):
		return "Save contains impossible time spent away."
	if str(value.phase) == "away":
		if bool(value.completed) or float(value.ended_at) != 0.0 or now >= due or LifeLifecycle.stage_for(state.character) != str(value.age_stage) or int(state.education.last_attendance_day) == int(value.departure_day):
			return "Save contains an expired or already-rewarded school day."
	else:
		if float(value.ended_at) < departed or float(value.ended_at) > due: return "Save contains an invalid return start."
		if bool(value.completed):
			if float(value.ended_at) != due or now < due: return "Save rewards an unfinished school day."
			var late: float = maxf(0.0,float(value.departure_minutes)-540.0)
			var earned: bool = str(state.education.stage) == str(value.age_stage) and int(state.education.last_attendance_day) >= int(value.departure_day) and float(state.education.get("late_minutes",0.0))+.00000001 >= late
			for record: Dictionary in state.education.records:
				if str(record.stage) == str(value.age_stage) and int(record.day) >= int(value.departure_day) and int(record.attended) > 0 and float(record.get("late_minutes",0.0))+.00000001 >= late: earned = true
			if not earned: return "Save has a school return without its earned attendance."
		elif float(value.ended_at) >= due:
			return "Save marks a completed school day as an early return."
	return ""


func _validate_state(state: Dictionary) -> String:
	if not _autonomy_integer(state.get("version"),SAVE_VERSION,SAVE_VERSION):
		return "This save uses an unsupported version."
	# Guard the clock before any lifecycle or career calendar conversion.
	if not _autonomy_integer(state.get("day"),1,1000000) or not _number_in_range(state.get("minutes"),0.0,1439.99999):return "Save contains an invalid clock."
	for key: String in ["character", "needs", "skills", "relationships", "career"]:
		if not state.get(key) is Dictionary:
			return "Save is missing valid %s data." % key
	if not state.get("wants") is Array or not state.get("action_queue", []) is Array or not state.get("world", []) is Array:
		return "Save contains invalid lists."
	var profile: Dictionary = state["character"]
	var age_error: String = LifeLifecycle.validate(profile, state.get("lifecycle", LifeLifecycle.fresh()))
	if not age_error.is_empty(): return age_error
	var life_status: String = str(profile.get("life_status", "living"))
	if life_status not in ["living", "passed"]:
		return "Save contains an invalid life status."
	var passing_cause: String = str(profile.get("passing_cause", "old_age"))
	if passing_cause.is_empty():
		passing_cause = "old_age"
	if profile.has("passing_cause") and str(profile.get("passing_cause", "")) != "" and passing_cause not in PASSING_CAUSES:
		return "Save contains an invalid passing cause."
	if life_status == "passed" and passing_cause not in PASSING_CAUSES:
		return "Save contains a Lifelet who passed without a known cause."
	for birthday: Dictionary in state.get("lifecycle", LifeLifecycle.fresh()).history:
		if int(birthday.day) > int(state.get("day", 0)): return "Save contains a future birthday."
	if not profile.get("name") is String or not profile.get("traits") is Array or str(profile.get("aspiration", "")) not in ASPIRATION_NAMES:
		return "Save contains an invalid character."
	for trait_name: Variant in profile["traits"]:
		if not trait_name is String or str(trait_name) not in TRAIT_NAMES:
			return "Save contains an invalid trait."
	# The household's land rides the world state. A corrupt plot count would
	# otherwise ask for a lot no navigation grid can be built for.
	var world_state: Variant = profile.get("world_state", {})
	if world_state is Dictionary:
		var land_error: String = LifeLand.validate(world_state.get("land"))
		if not land_error.is_empty(): return land_error
		var property_error: String = LifeProperties.validate(world_state.get("properties"))
		if not property_error.is_empty(): return property_error
		# The place the household is standing in must be one the town has, or a
		# later load would build a lot that does not exist.
		var saved_venue: Variant = world_state.get("venue")
		if saved_venue != null and (not saved_venue is String or not LifeNeighborhood.has(str(saved_venue))):
			return "Save contains an unknown venue."
	for need_name: String in NEED_NAMES:
		if not _number_in_range(state["needs"].get(need_name), 0.0, 100.0):
			return "Save contains an invalid need."
	# Temporary energy is either absent (an older save) or one bounded pool.
	if not _number_in_range(state.get("second_wind", 0.0), 0.0, SECOND_WIND_MAX):
		return "Save contains invalid temporary energy."
	if not _number_in_range(state.get("bladder_grace",0.0),0.0,BLADDER_GRACE_MINUTES):return "Save contains invalid bladder urgency."
	for key: String in ["starvation_minutes", "exhaustion_minutes", "deferred_passing_minutes"]:
		var limit: float = {"starvation_minutes":STARVATION_MINUTES, "exhaustion_minutes":EXHAUSTION_MINUTES, "deferred_passing_minutes":DEFERRED_PASSING_MINUTES}[key]
		if not _number_in_range(state.get(key, 0.0), 0.0, limit):
			return "Save contains invalid passing pressure."
		if life_status == "passed" and float(state.get(key, 0.0)) != 0.0:
			return "Save contains passing pressure for a spirit."
	if state.has("whims") and not LifeWantsManager.validate_save(state.whims):
		return "Save contains invalid wants and fears."
	for skill_name: String in SKILL_NAMES:
		var skill: Variant = state["skills"].get(skill_name)
		if not skill is Dictionary or not _number_in_range(skill.get("level"), 1.0, 10.0) or not _number_in_range(skill.get("xp"), 0.0, 10000.0):
			return "Save contains an invalid skill."
	# Legacy saves predate the larger roster: synthesise any catalogue
	# neighbour they lack so the expanded neighborhood joins mid-story.
	for resident_id:String in LifeResidentCatalogue.IDS:
		if not state["relationships"].has(resident_id):
			state["relationships"][resident_id] = {"name": str(LifeResidentCatalogue.PEOPLE[resident_id].name), "friendship": 8.0, "romance": 0.0, "status": "Acquaintance"}
	for required_id:String in ["maya","leo"]:
		if not state["relationships"].has(required_id):return "Save is missing a relationship."
	for person_id: String in state["relationships"]:
		var person: Variant = state["relationships"].get(person_id)
		if not person is Dictionary or not person.get("name") is String or not person.get("status") is String or not _number_in_range(person.get("friendship"), -100.0, 100.0) or not _number_in_range(person.get("romance"), 0.0, 100.0):
			return "Save contains an invalid relationship."
	var job: Dictionary = state["career"]
	# The career is validated by the policy that owns it, so a rung, a title and a
	# salary that disagree are rejected here exactly as the ladder defines them.
	if not job.get("title") is String or not _number_in_range(job.get("level"), 1.0, float(LifeCareers.MAX_LEVEL)) or not _number_in_range(job.get("performance"), 0.0, 1000.0) or not _number_in_range(job.get("salary"), 0.0, 1000000.0) or not _number_in_range(job.get("worked_day"), 0.0, 1000000.0):
		return "Save contains an invalid career."
	if not LifeCareers.has(str(job.get("track", ""))):
		return "Save contains an unknown career track."
	var degree_error: String = _validate_degree(state)
	if not degree_error.is_empty(): return degree_error
	var criminal_error: String = LifeCareers.criminal_error(state.get("criminal_record"))
	if not criminal_error.is_empty(): return criminal_error
	if job.has("schedule"):
		var schedule_error:String=LifeCareerSchedule.validate(job.schedule,int(state.day),int(job.get("worked_day",0)))
		if not schedule_error.is_empty():return schedule_error
	if not _number_in_range(state.get("funds"), 0.0, 1000000000.0) or not _number_in_range(state.get("day"), 1.0, 1000000.0) or not _number_in_range(state.get("minutes"), 0.0, 1439.99999):
		return "Save contains an invalid clock or funds."
	var autonomy_error:String=_validate_autonomy_state(state)
	if not autonomy_error.is_empty():return autonomy_error
	var repeat_error:String=_validate_social_repeat_state(state)
	if not repeat_error.is_empty():return repeat_error
	var school_error: String = _validate_school_state(state)
	if not school_error.is_empty(): return school_error
	if not _number_in_range(state.get("speed", 1), 0.0, 8.0) or int(state.get("speed", 1)) not in [0, 1, 3, 8] or not state.get("autonomy", true) is bool:
		return "Save contains invalid simulation settings."
	for key: String in ["satisfaction", "last_bill_day", "bills_paid", "bills_paid_total", "bills_late"]:
		if not _autonomy_integer(state.get(key, 0), 0, 1000000000):
			return "Save contains invalid progress."
	if int(state.get("last_bill_day", 0)) > int(state.day):
		return "Save contains a bill paid in the future."
	if not state.get("utilities_cut", false) is bool:
		return "Save contains invalid utility state."
	# Cover is either absent or one of the policies this build sells; an unknown
	# id would let a corrupt save mint free reimbursements.
	var saved_policy:Variant=state.get("insurance_policy_id",state.get("insurance_policy",""))
	if not saved_policy is String or (not str(saved_policy).is_empty() and not INSURANCE_POLICIES.has(str(saved_policy))):
		return "Save contains an unknown insurance policy."
	# A pending bill is either absent or a complete, self-consistent record.
	var bill: Variant = state.get("pending_bill", {})
	if not bill is Dictionary:
		return "Save contains an invalid pending bill."
	if not bill.is_empty():
		if bill.size() != 4 or not bill.has_all(["amount", "issued_day", "due_day", "late_fee"]):
			return "Save contains a malformed pending bill."
		if not _autonomy_integer(bill.get("amount"), 0, 1000000000) or not _autonomy_integer(bill.get("issued_day"), 1, 1000000000) or not _autonomy_integer(bill.get("due_day"), 1, 1000000000):
			return "Save contains an invalid pending bill amount or date."
		if int(bill.get("due_day", 0)) != int(bill.get("issued_day", 0)) + BILL_DUE_DAYS:
			return "Save contains a pending bill with an inconsistent due date."
		if not _autonomy_integer(bill.get("late_fee"), 0, BILL_LATE_FEE) or int(bill.late_fee) not in [0, BILL_LATE_FEE]:
			return "Save contains an invalid late fee."
		if int(bill.get("issued_day", 0)) > int(state.get("day", 1)):
			return "Save contains a bill issued in the future."
		if bool(state.get("utilities_cut", false)) != (int(bill.late_fee) > 0):
			return "Save contains inconsistent bill and utility state."
		if int(bill.late_fee) > 0 and int(state.day) <= int(bill.due_day):
			return "Save contains a late fee before its bill is overdue."
	elif bool(state.get("utilities_cut", false)):
		return "Save cuts utilities without an outstanding bill."
	if not state.get("purchased_perks", []) is Array or state.get("purchased_perks", []).size() > REWARDS.size():
		return "Save contains invalid reward history."
	var bought: Array[String] = []
	for perk: Variant in state.get("purchased_perks", []):
		if not perk is String or not REWARDS.has(str(perk)) or not bool(REWARDS[str(perk)].permanent) or bought.has(str(perk)):
			return "Save contains an invalid purchased reward."
		bought.append(str(perk))
	if not state.get("moodlets",[]) is Array or state.get("moodlets",[]).size()>8 or not state.get("memories",[]) is Array or state.get("memories",[]).size()>40:
		return "Save contains invalid memories."
	for entry in state.get("moodlets",[]):
		if not entry is Dictionary or not entry.get("label") is String or not entry.get("emotion") is String or not entry.get("description") is String or not _number_in_range(entry.get("remaining"),0,10000) or not _number_in_range(entry.get("strength"),0,10):return "Save contains an invalid mood."
	for entry in state.get("memories",[]):
		if not entry is Dictionary or not entry.get("label") is String or not entry.get("detail") is String or not _number_in_range(entry.get("day"),1,1000000) or not _number_in_range(entry.get("minutes"),0,1440):return "Save contains an invalid memory."
	for want: Variant in state["wants"]:
		if not want is Dictionary:
			return "Save contains an invalid want."
		for key: String in ["id", "label", "description"]:
			if not want.get(key) is String:
				return "Save contains an invalid want."
		if not _number_in_range(want.get("progress"), 0.0, 1000000.0) or not _number_in_range(want.get("target"), 1.0, 1000000.0) or not _number_in_range(want.get("reward"), 0.0, 1000000.0) or not want.get("complete") is bool:
			return "Save contains invalid want progress."
	var social_error: String = _validate_social_state(state)
	if not social_error.is_empty():
		return social_error
	var progression_error: String = _validate_progression(state)
	if not progression_error.is_empty():
		return progression_error
	if state.get("action_queue", []).size() > MAX_QUEUE:
		return "Save contains too many queued actions."
	for action: Variant in state.get("action_queue", []):
		if not action is Dictionary or not _actions.has(str(action.get("id", ""))):
			return "Save contains an invalid action."
		var action_id: String = str(action.id)
		if action_id in ["plant_wee","mop_puddle"]:
			var expected:Dictionary=_actions[action_id]
			if not action.get("target_id") is String or str(action.target_id).is_empty() or action.get("cost")!=0 or not action.get("paid") is bool or not action.get("autonomous") is bool or not _number_in_range(action.get("duration"),float(expected.duration),float(expected.duration)) or not _number_in_range(action.get("elapsed"),0.0,float(expected.duration)) or str(action.get("phase","")) not in ["queued","approach","active"]:
				return "Save contains invalid sanitation action progress."
			if (float(action.elapsed)>0.0 or str(action.phase)=="active") and not bool(action.paid):return "Save contains sanitation progress that never began."
		if action.has("adoption_serial") and action_id!="arrive_home":return "Save contains adoption metadata on an unrelated action."
		if action.has("baby_serial") and action_id!="arrive_home":return "Save contains birth metadata on an unrelated action."
		if action_id=="arrive_home":
			# A newborn and an adopted child both walk home from the street; the
			# newborn carries its birth serial where the adoption carries its
			# review serial, and exactly one of the two is present.
			var review_serial:Variant=action.get("adoption_serial")
			var birth_serial_value:Variant=action.get("baby_serial")
			var serial_ok:bool=(LifeAdoption.integer(review_serial,1,7) and not action.has("baby_serial")) or (LifeAdoption.integer(birth_serial_value,1,LifeBabyPlan.MAX_BIRTHS) and not action.has("adoption_serial"))
			if not serial_ok or action.get("paid")!=false or not action.get("paid") is bool or action.get("autonomous")!=false or not action.get("autonomous") is bool or not LifeAdoption.integer(action.get("cost"),0,0) or not LifeAdoption.integer(action.get("duration"),1,1) or not LifeAdoption.integer(action.get("elapsed"),0,0) or str(action.get("phase",""))!="approach" or str(action.get("target_id",""))!="lot_exit" or str(action.get("target_kind",""))!="lot_exit" or not LifeAdoption.point(action.get("target_position")):
				return "Save contains invalid adoption arrival progress."
		if action.has("home_visit_serial") or action.has("home_visit_token"):
			if action_id!="friendly" or not _autonomy_integer(action.get("home_visit_serial"),1,1000000000) or not _autonomy_integer(action.get("home_visit_token"),1,1000000):return "Save contains invalid home welcome metadata."
		if action.has("cooperation_id") or action.has("cooperation_role") or action_id == "help_homework":
			if not action.get("cooperation_id") is String or str(action.cooperation_id).is_empty():
				return "Save contains an invalid cooperative action."
			if action_id == LifeBabyPlan.ACTION_ID:
				# An intimate beat is symmetric: both members carry the same
				# session under their own id, and one of them owns the clock.
				if not str(action.cooperation_id).begins_with(LifeBabyPlan.TOKEN_PREFIX) or not action.get("cooperation_role") is String or not action.get("cooperation_primary") is bool or str(action.get("seat_slot","")) not in ["left","right"]:
					return "Save contains an invalid intimate action."
			elif action_id == LifeDancePlan.ACTION_ID:
				# A shared dance is symmetric too: every dancer carries the same
				# token and their own standing spot, and one owns the clock.
				if not str(action.cooperation_id).begins_with(LifeDancePlan.TOKEN_PREFIX) or str(action.get("cooperation_role","")) != LifeDancePlan.ROLE or not action.get("cooperation_primary") is bool or str(action.get("target_kind","")) != "stereo":
					return "Save contains an invalid shared dance action."
			elif str(action.get("cooperation_role","")) != ("helper" if action_id == "help_homework" else "learner") or action_id not in ["homework","help_homework"]:
				return "Save contains an invalid cooperative action."
			if action_id == "help_homework" and str(profile.get("life_stage","adult")) != "adult": return "Save contains a non-adult homework helper."
		if COMPUTER_MASTERY_ACTIONS.has(action_id):
			# A mastery action is bound to its subject by the id itself, so the
			# saved skill must agree and the Lifelet must not already be at 10.
			var mastery_skill:String=str(_actions[action_id].skill)
			if action_id!="computer_"+mastery_skill or int(state.skills.get(mastery_skill,{"level":1}).level)>=10:
				return "Save contains computer study for an unknown or mastered skill."
		if action.get("book_skill","")!="":
			# A shelf session is bound to the subject of the book it was started
			# from, and that subject must still be short of the book ceiling.
			var book_skill:String=str(action.get("book_skill",""))
			if action_id!="study_book" or str(_actions[action_id].skill)!=book_skill or not LifeHouseholdFlow.BOOK_SKILLS.has(book_skill) or int(state.skills.get(book_skill,{"level":1}).level)>=LifeHouseholdFlow.BOOK_MAX_LEVEL:
				return "Save contains a skill book session for an unknown or finished subject."
		if action_id in ["job","career_day","work"] and str(profile.get("life_stage","adult")) != "adult": return "Save contains adult work queued for a non-adult Lifelet."
		if action_id == "cook":
			var recipe:Variant=action.get("recipe","garden_skillet")
			if not recipe is String or not LifeMeals.RECIPES.has(recipe):return "Save contains an invalid cooking recipe."
			var recipe_error:String=LifeMeals.recipe_error(recipe,int(state.skills.cooking.level),LifeLifecycle.stage_for(profile),0,true)
			if not recipe_error.is_empty():return recipe_error
			var definition:Dictionary=LifeMeals.RECIPES[recipe]
			if not _number_in_range(action.get("duration"),float(definition.duration),float(definition.duration)) or not _number_in_range(action.get("elapsed",0),0,float(definition.duration)):return "Save contains invalid recipe progress."
			# The ingredients were paid at the counter when the dish was started, so
			# the record is checked against the charge actually made rather than
			# against today's price list: retuning a recipe's cost must not refuse a
			# player's own in-progress meal (a bake charged 52 when the bake cost 52
			# stopped loading the moment the recipe was retuned to 24). Every recipe
			# charges something, so a zero or negative charge is still impossible.
			if not _number_in_range(action.get("cost"), 1.0, 1000000000.0) or not action.get("paid") is bool:return "Save contains invalid recipe ingredients or learning."
			# Learning is still owed when the dish finishes, so it is not a historical
			# receipt like the charge: a retuned recipe may leave a modest surplus,
			# but the field cannot grant arbitrary skill and must stay inside the
			# band the recipe table itself uses.
			if not _number_in_range(action.get("xp"), 0.0, LifeMeals.max_recipe_xp()):return "Save contains invalid recipe learning."
			if str(action.get("phase","")) not in ["queued","approach","active"]:return "Save contains an invalid cooking phase."
			if (float(action.get("elapsed",0))>0 or str(action.get("phase",""))=="active") and not bool(action.paid):return "Save contains cooking progress without paid ingredients."
		if action_id == "birthday":
			if LifeLifecycle.next_stage(LifeLifecycle.stage_for(profile)).is_empty(): return "Save contains a birthday beyond the supported age stages."
			if str(action.get("birthday_from_stage",LifeLifecycle.stage_for(profile))) != LifeLifecycle.stage_for(profile): return "Save contains a birthday for an age stage that has already passed."
		if action.has("meal_standing") and (action_id!="eat_meal" or not action.meal_standing is bool):return "Save contains an invalid standing diner reservation."
		var saved_duration:Variant=action.get("duration",_actions[action_id].duration)
		var saved_elapsed:Variant=action.get("elapsed",0.0)
		var saved_paid:Variant=action.get("paid",false)
		if not _number_in_range(saved_duration,1.0,10000.0) or not _number_in_range(saved_elapsed,0.0,float(saved_duration)) or not saved_paid is bool:
			return "Save contains invalid action progress."
		# A paid interrupted action can approach again without losing progress.
		# Picking up an existing partial plate inherits its eating progress before
		# arrival/payment. Household ingress then requires the exact owned plate
		# and matching progress through LifeMeals.validate_actions.
		var inherited_meal:bool=action_id=="eat_meal" and action.get("meal_stage","")=="eat" and action.get("phase","")=="approach"
		if float(saved_elapsed)>0.0 and not saved_paid and not inherited_meal:return "Save contains progress on an action that has not begun."
		# Recipes and off-lot schedules validate their derived duration separately.
		# Ordinary activities keep their authored duration, including the explicit
		# shorter Active nap. The ordinary 75-minute nap remains a valid old state.
		if action_id not in ["cook","school_day","career_day"]:
			var expected_duration:float=float(_actions[action_id].duration)
			var active_nap:bool=action_id=="nap" and "Active" in profile.traits and float(saved_duration)==60.0
			if float(saved_duration)!=expected_duration and not active_nap:return "Save contains an invalid activity duration."
		var position: Variant = action.get("target_position", [0, 0, 0])
		if not position is Vector3:
			if not position is Array or position.size() != 3:
				return "Save contains an invalid action position."
			for component: Variant in position:
				if not _number_in_range(component, -100000.0, 100000.0):
					return "Save contains an invalid action position."
	return _validate_away_state(state)


func _validate_social_state(state: Dictionary) -> String:
	if str(state.character.get("life_stage", "adult")) not in ["adult", "minor", "unknown"]:
		return "Save contains an invalid Lifelet life stage."
	var partner: Variant = state.get("romantic_partner", "")
	if not partner is String or (not str(partner).is_empty() and not state.relationships.has(partner)):
		return "Save contains an invalid romantic partner."
	for target: String in state.relationships:
		var relationship: Dictionary = state.relationships[target]
		if str(relationship.get("life_stage", "adult")) not in ["adult", "minor", "unknown"] or str(relationship.get("bond", "none")) not in ["none", "partners", "committed", "separated"]:
			return "Save contains an invalid relationship stage."
		var bond: String = str(relationship.get("bond", "none"))
		var family_role: String = str(relationship.get("family_role", "none"))
		if family_role not in LifeFamilyGraph.ROLES:
			return "Save contains an invalid family role."
		if LifeFamilyGraph.is_family(family_role) and (float(relationship.romance) > 0.0 or bond != "none"):
			return "Save contains an invalid romantic relationship between family members."
		if (bond in ["partners", "committed"]) != (target == str(partner)):
			return "Save contains an inconsistent partnership."
		if bond in ["partners", "committed"] and (str(state.character.get("life_stage", "adult")) != "adult" or str(relationship.get("life_stage", "adult")) != "adult"):
			return "Save contains a partnership involving a non-adult Lifelet."
		if not relationship.get("milestones", []) is Array or relationship.get("milestones", []).size() > 7:
			return "Save contains invalid relationship milestones."
		for stage: Variant in relationship.get("milestones", []):
			if not stage is String or str(stage) not in SOCIAL_STAGES:
				return "Save contains an invalid relationship milestone."
			if LifeFamilyGraph.is_family(family_role) and str(stage) in ["spark","partners","committed","separated"]:
				return "Save contains a romantic milestone between family members."
	if not state.get("social_history", []) is Array or state.get("social_history", []).size() > MAX_PROGRESS_HISTORY:
		return "Save contains invalid social history."
	for entry: Variant in state.get("social_history", []):
		if not entry is Dictionary:
			return "Save contains an invalid social memory."
		for key: String in ["target_id", "target_name", "stage", "label", "detail"]:
			if not entry.get(key) is String or str(entry[key]).length() > 2000:
				return "Save contains an invalid social memory."
		if str(entry.stage) not in SOCIAL_STAGES or not _number_in_range(entry.get("day"), 1, float(state.day)) or not _number_in_range(entry.get("minutes"), 0, 1440):
			return "Save contains an invalid social memory date."
		if state.relationships.has(str(entry.target_id)) and LifeFamilyGraph.is_family(str(state.relationships[str(entry.target_id)].get("family_role", "none"))) and str(entry.stage) in ["spark", "partners", "committed", "separated"]:
			return "Save contains an invalid romantic history between family members."
	for action: Variant in state.get("action_queue", []):
		if not action is Dictionary or str(action.get("id", "")) not in RELATIONSHIP_ACTIONS + ["flirt"]:
			continue
		var target: String = str(action.get("target_id", ""))
		if target.is_empty(): target = "maya"
		if target.begins_with("neighbor_"): target = target.trim_prefix("neighbor_")
		if not state.relationships.has(target):
			return "Save contains a romantic action with an unknown Lifelet."
		if state.relationships.has(target):
			var relationship: Dictionary = state.relationships[target]
			if LifeFamilyGraph.is_family(str(relationship.get("family_role", "none"))):
				return "Save contains a romantic action queued between family members."
			if str(state.character.get("life_stage", "adult")) != "adult" or str(relationship.get("life_stage", "adult")) != "adult":
				return "Save contains a romantic action involving a non-adult Lifelet."
	return ""


func _normalize_want_numbers(want: Dictionary) -> void:
	want.progress = float(want.progress)
	want.target = float(want.target)
	want.reward = int(want.reward)
	if want.get("seen_days") is Array:
		for index: int in range(want.seen_days.size()):
			if _number_in_range(want.seen_days[index], 1, 1000000):
				want.seen_days[index] = int(want.seen_days[index])


func _validate_progression(state: Dictionary) -> String:
	var saved_day: int = int(state.day)
	if not _number_in_range(state.get("aspiration_stage", 1), 1, 1000000) or not _number_in_range(state.get("aspiration_next_day", 0), 0, saved_day + 1):
		return "Save contains an invalid aspiration chapter."
	if state.wants.size() > 4:
		return "Save contains too many current wants."
	for want: Dictionary in state.wants:
		var metric: String = str(want.get("metric", ""))
		if metric.is_empty():
			continue
		if metric not in ["actions", "variety", "social_days", "practice", "care_days", "income", "familiar_chat"]:
			return "Save contains an invalid aspiration goal."
		if not want.get("actions") is Array or not want.get("seen") is Array or not want.get("seen_days") is Array or want.actions.size() > 20 or want.seen.size() > 20 or want.seen_days.size() > 10:
			return "Save contains invalid aspiration activity progress."
		for action_id: Variant in want.actions + want.seen:
			if not action_id is String or not _actions.has(action_id):
				return "Save contains an invalid aspiration activity."
		for seen_day: Variant in want.seen_days:
			if not _number_in_range(seen_day, 1, saved_day):
				return "Save contains an invalid aspiration day."
		if metric == "practice" and str(want.get("skill", "")) not in SKILL_NAMES:
			return "Save contains an invalid aspiration skill."
	if not state.get("aspiration_history", []) is Array or state.get("aspiration_history", []).size() > MAX_PROGRESS_HISTORY:
		return "Save contains invalid aspiration history."
	for chapter: Variant in state.get("aspiration_history", []):
		if not chapter is Dictionary or not _number_in_range(chapter.get("stage"), 1, float(state.get("aspiration_stage", 1))) or not _number_in_range(chapter.get("completed_day"), 1, saved_day) or not chapter.get("title") is String or not _number_in_range(chapter.get("reward"), 0, 4000000) or not chapter.get("wants") is Array or chapter.wants.size() > 4:
			return "Save contains an invalid completed chapter."
		for archived: Variant in chapter.wants:
			if not archived is Dictionary:
				return "Save contains an invalid archived want."
			for key: String in ["id", "label", "description"]:
				if not archived.get(key) is String:
					return "Save contains an invalid archived want."
			if not archived.get("complete") is bool or not bool(archived.complete) or not _number_in_range(archived.get("progress"), 0, 1000000) or not _number_in_range(archived.get("target"), 1, 1000000) or not _number_in_range(archived.get("reward"), 0, 1000000):
				return "Save contains invalid archived want progress."
	if not _number_in_range(state.get("story_generated_day", saved_day), 1, saved_day):
		return "Save contains an invalid story calendar."
	if not state.get("story_events", []) is Array or state.get("story_events", []).size() > MAX_STORY_EVENTS or not state.get("story_history", []) is Array or state.get("story_history", []).size() > MAX_PROGRESS_HISTORY:
		return "Save contains invalid story lists."
	var event_ids: Array[String] = []
	for ticket: Variant in state.get("story_events", []):
		if not ticket is Dictionary or not ticket.get("id") is String or str(ticket.get("kind", "")) not in STORY_KINDS or not _number_in_range(ticket.get("day"), 2, float(state.get("story_generated_day", saved_day))) or not ticket.get("context") is Dictionary:
			return "Save contains an invalid story event."
		if str(ticket.id) != "story_day_%d" % int(ticket.day) or event_ids.has(str(ticket.id)) or str(ticket.kind) != STORY_KINDS[(int(ticket.day) - 2) % STORY_KINDS.size()]:
			return "Save contains an invalid story identity."
		event_ids.append(str(ticket.id))
		var context: Dictionary = ticket.context
		if str(context.get("neighbor", "")) not in LifeResidentCatalogue.IDS or str(context.get("skill", "")) not in SKILL_NAMES or not _number_in_range(context.get("career_level"), 1, LifeCareers.MAX_LEVEL) or not _number_in_range(context.get("creativity_level"), 1, 10):
			return "Save contains an invalid story context."
	for story: Variant in state.get("story_history", []):
		if not story is Dictionary:
			return "Save contains an invalid story memory."
		for key: String in ["event_id", "kind", "title", "choice_id", "choice_label", "effects"]:
			if not story.get(key) is String or str(story[key]).length() > 2000:
				return "Save contains an invalid story memory."
		if not _number_in_range(story.get("day"), 2, saved_day) or not _number_in_range(story.get("offered_day"), 2, float(story.day)) or not _number_in_range(story.get("minutes"), 0, 1440) or str(story.kind) not in STORY_KINDS:
			return "Save contains an invalid story decision date."
		if str(story.event_id) != "story_day_%d" % int(story.offered_day) or event_ids.has(str(story.event_id)):
			return "Save contains a repeated story decision."
		event_ids.append(str(story.event_id))
	return ""


func _number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _json_safe(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Color:
		return value.to_html(true)
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[str(key)] = _json_safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_json_safe(entry))
		return result
	return value


func _education_target_kind(target_id: String) -> String:
	for target: Dictionary in _targets:
		if str(target.id) == target_id: return str(target.kind)
	return ""


func _school_availability(id: String, target_id: String, ignore_queue: bool = false) -> String:
	if str(character.age_stage) not in LifeEducation.SCHOOL_STAGES:
		return "Online classes and homework are for children and teens."
	var kind: String = _education_target_kind(target_id)
	if not target_id.is_empty() and not _school_target_allowed(id,kind):
		return "Choose a desk or computer for online classes." if id == "school" else "Choose a desk, computer, or bookshelf for homework."
	if not ignore_queue:
		for queued: Dictionary in action_queue:
			if id == "school" and str(queued.id) == "school_day" and bool(queued.get("autonomous",false)) and not is_away(): continue
			if str(queued.id) == id or (id == "school" and str(queued.id) == "school_day"): return "That school activity is already queued."
	for action: Dictionary in LifeEducation.actions(education,str(character.age_stage),day,minutes):
		if str(action.id) == id:
			return str(action.unavailable_reason)
	return "School records are unavailable."


func _school_action_error(action: Dictionary) -> String:
	var id: String = str(action.id)
	if not _school_target_allowed(id,_education_target_kind(str(action.target_id))):
		return "That school activity needs a suitable desk or bookshelf."
	if bool(action.get("paid",false)):
		if str(character.age_stage) not in LifeEducation.SCHOOL_STAGES or int(action.get("started_day",0)) != day:
			return "That school activity belongs to an earlier school day or age stage."
		var result: Dictionary = LifeEducation.complete(education,str(character.age_stage),day,minutes,id)
		return "" if bool(result.ok) else str(result.error)
	return _school_availability(id,str(action.target_id),true)


func _school_target_allowed(id: String, kind: String) -> bool:
	return kind in ["desk","computer"] or (id == "homework" and kind == "bookshelf")


func _apply_education_result(result: Dictionary) -> void:
	if not bool(result.get("ok",false)): return
	education = result.state
	var effects: Dictionary = result.get("effects",{})
	for key: String in effects.get("needs",{}):
		needs[key] = clampf(float(needs[key])+float(effects.needs[key]),0.0,100.0)
	for key: String in effects.get("skill_xp",{}):
		_gain_skill(key,float(effects.skill_xp[key]))
	for message: String in result.get("notices",[]): _emit_notice(message)
	for record: Dictionary in education.records:
		if int(record.day) == day and str(record.stage) in LifeEducation.SCHOOL_STAGES:
			var label: String = "School graduation" if str(record.outcome) == "graduated" else "School report"
			var detail: String = "%s: grade %s, %d days attended." % ["Willow School" if str(record.stage) == "child" else "Morrow Secondary",str(record.grade),int(record.attended)]
			var already_recorded: bool = false
			for memory: Dictionary in memories:
				if str(memory.label) == label and str(memory.detail) == detail and int(memory.day) == day: already_recorded = true
			if not already_recorded: remember(label,detail)


func _advance_education() -> void:
	var result: Dictionary = LifeEducation.advance(education,str(character.age_stage),day,minutes)
	if bool(result.ok): _apply_education_result(result)
	else: _emit_notice(str(result.error))


func _cancel_school_actions(message: String, start_next: bool = true) -> void:
	var front_removed: bool = not action_queue.is_empty() and (str(action_queue[0].id) in ["school","homework"] or (str(action_queue[0].id) == "school_day" and not is_away()))
	var cancelled: bool = false
	for index: int in range(action_queue.size()-1,-1,-1):
		if str(action_queue[index].id) in ["school","homework"] or (str(action_queue[index].id) == "school_day" and not is_away()):
			action_queue.remove_at(index)
			cancelled = true
	if cancelled:
		if front_removed and start_next: _start_front()
		_emit_notice(message)
		_emit_changed()


func _cancel_age_actions() -> Dictionary:
	# Silent queue mutation is part of the birthday transaction. Signals happen
	# after age, school records, and lifecycle history all describe the new stage.
	var result: Dictionary = {"front_removed":false,"removed":false}
	for index: int in range(action_queue.size()-1,-1,-1):
		var action: Dictionary = action_queue[index]
		var invalid: bool = str(action.id) in ["school","homework"] or (str(action.id) == "school_day" and not is_away())
		invalid = invalid or (str(action.id) == "birthday" and str(action.get("birthday_from_stage","")) != str(character.age_stage))
		if invalid:
			result.front_removed = bool(result.front_removed) or index == 0
			action_queue.remove_at(index)
			result.removed = true
	return result


func _prune_school_actions() -> void:
	var front_removed: bool = false
	var removed: bool = false
	var messages: Array[String] = []
	for index: int in range(action_queue.size()-1,-1,-1):
		var action: Dictionary = action_queue[index]
		if str(action.id) in ["school_day","career_day"]:
			if is_away(): continue
			var departure_error: String = _career_departure_error(str(action.target_id),true) if str(action.id)=="career_day" else _school_departure_error(str(action.target_id),true)
			if departure_error.is_empty(): continue
			front_removed = front_removed or index == 0
			action_queue.remove_at(index)
			removed = true
			if departure_error not in messages: messages.append(departure_error)
			continue
		if str(action.id) not in ["school","homework"]: continue
		var error: String = _school_action_error(action)
		if error.is_empty(): continue
		front_removed = front_removed or index == 0
		removed = true
		action_queue.remove_at(index)
		if error not in messages: messages.append(error)
	if removed:
		if front_removed: _start_front()
		for message: String in messages: _emit_notice(message)
		_emit_changed()


## Validate the qualification a save carries. An unknown degree would let a
## corrupt save mint a raise it never studied for, so only the three the game
## sells are accepted.
func _validate_degree(state: Dictionary) -> String:
	if not state.get("degree", "none") is String:
		return "Save contains an invalid qualification."
	if not LifeCareers.DEGREES.has(str(state.get("degree", "none"))):
		return "Save contains an unknown qualification."
	return ""


func _validate_school_state(state: Dictionary) -> String:
	var saved_day: int = int(state.day)
	var stage: String = LifeLifecycle.stage_for(state.character)
	var saved: Variant = state.get("education",LifeEducation.fresh(stage,saved_day))
	var error: String = LifeEducation.validate(saved,stage,saved_day)
	if not error.is_empty(): return error
	var ids: Array[String] = []
	for entry: Variant in state.get("action_queue",[]):
		if not entry is Dictionary or str(entry.get("id","")) not in ["school","homework"]: continue
		var id: String = str(entry.id)
		if not state.has("education") or stage not in LifeEducation.SCHOOL_STAGES or id in ids:
			return "Save contains an impossible or duplicate school activity."
		ids.append(id)
		if not entry.get("target_id") is String or str(entry.target_id).is_empty() or not _school_target_allowed(id,str(entry.get("target_kind",""))):
			return "Save contains a school activity without suitable furniture."
		if not _number_in_range(entry.get("duration"),float(_actions[id].duration),float(_actions[id].duration)) or not _number_in_range(entry.get("elapsed",0),0.0,float(_actions[id].duration)-.000001) or not entry.get("paid",false) is bool:
			return "Save contains invalid school activity progress."
		if bool(entry.get("paid",false)):
			if not _number_in_range(entry.get("started_day"),saved_day,saved_day) or not _number_in_range(entry.get("started_minutes"),0.0,float(state.minutes)):
				return "Save contains a school activity started on an impossible date."
			var started: float = float(entry.started_minutes)
			if float(entry.get("elapsed",0)) > float(state.minutes)-started+.001:
				return "Save school progress exceeds its elapsed calendar time."
			for option: Dictionary in LifeEducation.actions(saved,stage,saved_day,started):
				if str(option.id) == id and not bool(option.available): return "Save contains a school activity begun outside its schedule."
			if not bool(LifeEducation.complete(saved,stage,saved_day,float(state.minutes),id).ok):
				return "Save contains a school activity that cannot finish on this day."
		elif float(entry.get("elapsed",0)) != 0.0:
			return "Save contains progress on a school activity that has not begun."
	return ""

func set_aging(lifespan: String, enabled: bool) -> bool:
	if lifespan not in LifeLifecycle.SPANS: return false
	lifecycle.lifespan = lifespan
	lifecycle.auto_age = enabled
	_emit_changed()
	return true

func _advance_age(game_minutes: float) -> void:
	if is_spirit(): return
	if not bool(lifecycle.auto_age) or str(character.age_stage) == "unknown": return
	var duration: float = LifeLifecycle.duration(str(character.age_stage), str(lifecycle.lifespan)) * 1440.0
	lifecycle.progress = minf(1.0, float(lifecycle.progress) + game_minutes / duration)
	if float(lifecycle.progress) >= 1.0 - .0000001 and not LifeLifecycle.next_stage(str(character.age_stage)).is_empty():
		celebrate_birthday()

func is_spirit() -> bool:
	return str(character.get("life_status", "living")) == "passed"

func _update_passing_pressure(game_minutes: float) -> void:
	if is_spirit():
		starvation_minutes = 0.0
		exhaustion_minutes = 0.0
		deferred_passing_minutes = 0.0
		return
	if float(needs.hunger) <= 0.001:
		starvation_minutes += game_minutes
	else:
		starvation_minutes = 0.0
	var athletic: bool = false
	if not action_queue.is_empty() and str(action_queue[0].get("phase", "")) == "active":
		athletic = str(action_queue[0].id) in ["jog", "morning_run"]
	if float(needs.energy) <= 0.001 and athletic:
		exhaustion_minutes += game_minutes
	else:
		exhaustion_minutes = 0.0
	if LifeLifecycle.due_to_pass_on(str(character.age_stage), lifecycle) and (is_away() or (not action_queue.is_empty() and str(action_queue[0].get("phase", "")) == "active")):
		deferred_passing_minutes += game_minutes

func ready_to_starve() -> bool:
	return not is_spirit() and starvation_minutes >= STARVATION_MINUTES

func ready_to_overexert() -> bool:
	return not is_spirit() and exhaustion_minutes >= EXHAUSTION_MINUTES

func ready_to_pass_on() -> bool:
	if is_spirit():
		return false
	if not LifeLifecycle.due_to_pass_on(str(character.age_stage), lifecycle):
		return false
	if deferred_passing_minutes >= DEFERRED_PASSING_MINUTES:
		return true
	if is_away():
		return false
	if action_queue.is_empty():
		return true
	return str(action_queue[0].get("phase", "")) != "active"

func passing_cause() -> String:
	var cause: String = str(character.get("passing_cause", ""))
	return cause if cause in PASSING_CAUSES else "old_age"

func pass_on(cause: String = "") -> bool:
	if is_spirit():
		return false
	if cause.is_empty():
		if ready_to_starve():
			cause = "hunger"
		elif ready_to_overexert():
			cause = "exhaustion"
		elif ready_to_pass_on():
			cause = "old_age"
		else:
			return false
	if cause not in PASSING_CAUSES:
		return false
	if cause == "old_age" and not LifeLifecycle.due_to_pass_on(str(character.age_stage), lifecycle):
		return false
	if cause == "hunger" and not ready_to_starve():
		return false
	if cause == "exhaustion" and not ready_to_overexert():
		return false
	character["life_status"] = "passed"
	character["passing_cause"] = cause
	lifecycle["passed"] = true
	# A passing ends every plan, and a queued meal action owns a dish in the
	# meal ledger. Release that custody exactly as cancelling the action does:
	# otherwise the plate stays owned with no action to claim it, and the
	# household's own save is refused afterwards with "A carried or active food
	# has no matching action."
	for action: Dictionary in action_queue.duplicate():
		if is_instance_valid(meal_service):
			meal_service.canceled(self,action)
	action_queue.clear()
	away_state = {}
	starvation_minutes = 0.0
	exhaustion_minutes = 0.0
	deferred_passing_minutes = 0.0
	var why: String = str(PASSING_CAUSES[cause])
	add_moodlet("At peace", "Sad", why.capitalize() + ".", 720, 1)
	remember("Passed on", "Reached the end through %s." % why)
	_emit_notice("%s has passed on, and remains as a gentle spirit." % str(character.name))
	_publish("life_changed", ["passed"])
	_emit_changed()
	return true

func celebrate_birthday(start_next_action: bool = true) -> bool:
	if is_spirit(): return false
	# Close a due school day before changing the age and archiving its record.
	# This also keeps the legitimate exact-bell transition serializable.
	if is_away() and str(away_state.phase)=="away" and _autonomy_now()>=float(away_state.return_day-1)*1440.0+float(away_state.return_minutes):_tick_away(0.0)
	var previous: String = str(character.age_stage)
	var next: String = LifeLifecycle.next_stage(previous)
	if next.is_empty(): return false
	var school_result: Dictionary = LifeEducation.advance(education,next,day,minutes)
	if not bool(school_result.ok):
		_emit_notice(str(school_result.error))
		return false
	if is_away() and str(away_state.phase) == "away": request_return_home()
	character.age_stage = next
	character.life_stage = LifeLifecycle.eligibility(next)
	# Elders keep their face and frame, but hair should read as aged. Birthdays
	# used to only flip the stage label, so a sixty-day elder still looked adult.
	if next == "elder":
		var elder_hairs: Array = preload("res://scripts/character_identity.gd").ELDER_HAIR_COLORS
		if not elder_hairs.is_empty():
			var pick: int = absi(int(hash(str(character.get("name", "")) + ":" + str(day)))) % elder_hairs.size()
			character["hair_color"] = str(elder_hairs[pick])
	if LifeLifecycle.eligibility(previous)!="adult" and str(character.life_stage)=="adult":career.schedule=LifeCareerSchedule.fresh(day,day+1 if minutes>LifeCareerSchedule.CLOSE else day)
	lifecycle.progress = 0.0
	lifecycle.history.append({"from":previous,"to":next,"day":day})
	education = school_result.state
	var cancelled: Dictionary = _cancel_age_actions()
	_emit_age_changed(previous,next)
	_apply_education_result(school_result)
	add_moodlet("A new chapter", "Happy", "A birthday full of possibilities.", 360, 2)
	remember("Happy birthday", "Became %s." % LifeLifecycle.with_article(next))
	_emit_notice("Happy birthday, %s! Now %s." % [character.name, LifeLifecycle.with_article(next)])
	if bool(cancelled.removed):
		_emit_notice("A new age stage begins. Earlier schoolwork and birthday plans are cleared.")
	if bool(cancelled.front_removed) and start_next_action: _start_front()
	_emit_changed()
	return true

func relationship_order() -> Array:
	var ids: Array = relationships.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var left: Dictionary = relationships[a]
		var right: Dictionary = relationships[b]
		var left_priority: int = 2 if a == romantic_partner else (1 if str(left.get("family_role", "none")) != "none" else 0)
		var right_priority: int = 2 if b == romantic_partner else (1 if str(right.get("family_role", "none")) != "none" else 0)
		if left_priority != right_priority: return left_priority > right_priority
		if float(left.friendship) != float(right.friendship): return float(left.friendship) > float(right.friendship)
		if str(left.name).nocasecmp_to(str(right.name)) != 0: return str(left.name).nocasecmp_to(str(right.name)) < 0
		return a < b)
	return ids

# Household transactions delay notifications until every participant and the
# shared clock are committed. Ordinary standalone actions still notify directly.
func begin_notifications() -> void:
	_notification_depth += 1

func release_notifications() -> Array:
	_notification_depth = maxi(0,_notification_depth-1)
	if _notification_depth > 0: return []
	var pending: Array = _pending_notifications
	_pending_notifications = []
	return pending

func dispatch_notifications(events: Array) -> void:
	for event: Dictionary in events:
		if str(event.name) == "action_started" and not action_queue.has(event.args[0]): continue
		_publish(str(event.name),event.args)

func _publish(event: String, args: Array = []) -> void:
	if _notification_depth > 0:
		_pending_notifications.append({"name":event,"args":args})
		return
	if is_instance_valid(cooperation_owner): cooperation_owner.before_member_notification()
	match event:
		"changed": changed.emit()
		"notice": notice.emit(str(args[0]))
		"action_started": action_started.emit(args[0])
		"action_finished": action_finished.emit(args[0])
		"age_changed": age_changed.emit(str(args[0]),str(args[1]))
		"away_changed": away_changed.emit(args[0])
		"life_changed": life_changed.emit(str(args[0]))

func _emit_changed() -> void: _publish("changed")
func _emit_notice(message: String) -> void: _publish("notice",[message])
func _emit_action_started(action: Dictionary) -> void: _publish("action_started",[action])
func _emit_action_finished(action: Dictionary) -> void: _publish("action_finished",[action])
func _emit_age_changed(previous: String, current: String) -> void: _publish("age_changed",[previous,current])

func _career_departure_error(target_id:String,ignore_queue:bool=false) -> String:
	if str(character.life_stage)!="adult":return "Full-time careers become available in young adulthood."
	if is_away():return "This Lifelet is already away from home."
	if not LifeEducation.weekday(day):return "Ordinary work runs Monday through Friday."
	if day<int(career.get("schedule",LifeCareerSchedule.fresh(day)).first_day):return "Your first shift begins on the next workday."
	if int(career.worked_day)==day:return "Today's paid shift is already complete."
	if minutes<LifeCareerSchedule.OPEN or minutes>LifeCareerSchedule.CLOSE:return "Leave for work between 09:00 and 12:00. Arrivals after 10:00 affect pay and performance."
	if not target_id.is_empty() and _education_target_kind(target_id)!="lot_exit":return "Choose the neighborhood exit to leave for work."
	if not ignore_queue:
		for action:Dictionary in action_queue:
			if str(action.id) in ["job","career_day"]:return "Work is already in this Lifelet's plans."
	return ""

func _begin_career_departure(action:Dictionary) -> void:
	var problem:String=_career_departure_error(str(action.target_id),true)
	if str(action.target_id).is_empty():problem="Work needs a real neighborhood exit."
	for need:String in ["hunger","energy","bladder"]:
		if float(needs[need])<12.0:problem="Take care of urgent needs before leaving for work."
	if bool(action.get("autonomous",false)):
		if not _autonomy_projection_need("career_day",60.0).is_empty():problem="Get ready for the workday before leaving."
		for later:Dictionary in action_queue.slice(1):
			if not bool(later.get("autonomous",false)):problem="Following your plans before leaving for work."
	if not problem.is_empty():cancel_action();_emit_notice(problem);return
	_wear_for_activity("career_day")
	action.merge({"phase":"active","paid":true,"started_day":day,"started_minutes":minutes,"elapsed":0.0,"progress":0.0,"duration":LifeCareerSchedule.END-minutes},true)
	for need:String in action.changes:action.changes[need]=float(action.changes[need])*float(action.duration)/LifeCareerSchedule.LENGTH
	away_state={"version":1,"activity":"career","phase":"away","departure_day":day,"departure_minutes":minutes,"return_day":day,"return_minutes":LifeCareerSchedule.END,"exit_id":str(action.target_id),"exit_position":action.target_position,"age_stage":str(character.age_stage),"career_track":str(career.get("track","studio")),"salary":int(career.salary),"completed":false,"ended_at":0.0}
	_publish("away_changed",[get_away_state()]);_emit_changed()
	_emit_notice("%s has left for %s and will be home after 17:00."%[str(character.name),LifeCareers.workplace(str(career.get("track","")))])

func _tick_career_away() -> void:
	if day!=int(away_state.departure_day) or str(character.life_stage)!="adult":request_return_home();return
	var action:Dictionary=action_queue[0]
	var elapsed:float=clampf(minutes-float(away_state.departure_minutes),0.0,float(action.duration))
	var gained:float=maxf(0.0,elapsed-float(action.elapsed))
	action.elapsed=elapsed;action.progress=elapsed/float(action.duration)
	_apply_continuous_effects(action,gained/float(action.duration))
	if minutes<LifeCareerSchedule.END:return
	begin_notifications()
	away_state.phase="returning";away_state.ended_at=float(day-1)*1440.0+LifeCareerSchedule.END
	away_state.completed=int(career.worked_day)!=day
	if bool(away_state.completed):
		var proportion:float=float(action.duration)/LifeCareerSchedule.LENGTH
		var late:float=maxf(0.0,float(away_state.departure_minutes)-LifeCareerSchedule.ON_TIME)
		var income:int=roundi(float(away_state.salary)*proportion)
		funds+=income;career.worked_day=day
		career.schedule=LifeCareerSchedule.attend(career.get("schedule",LifeCareerSchedule.fresh(day)),day,late)
		var career_skill:String=str(LifeCareers.job(str(away_state.career_track)).get("skill",""))
		# A service job trains no trade of its own, so a shift there still counts
		# as a real day's work for performance but grows no skill.
		var skill_rank:float=0.0
		if SKILL_NAMES.has(career_skill):
			_gain_skill(career_skill,30.0*proportion)
			skill_rank=float(skills[career_skill].level)
		var comfort:float=(float(needs.hunger)+float(needs.energy)+float(needs.fun))/3.0
		# The same ceiling as a shift worked from home. At the top of the ladder
		# nothing spends the earned performance, so without this an ordinary
		# working life banks past the limit a save may hold and the household
		# becomes unsaveable.
		career.performance=clampf(float(career.performance)+_career_performance_gain((18.0+comfort*.15+skill_rank*2.0)*proportion)-late/20.0,0.0,
			100.0 if int(career.level)>=LifeCareers.MAX_LEVEL else 1000.0)
		_emit_notice("Shift finished. Earned ℒ%d for %d minutes at work%s."%[income,int(action.duration),"; arrived %d minutes late"%int(late) if late>0.0 else ""])
		_check_promotion();_activity_memory("job");_record_chapter_activity("job",income)
		for want:Dictionary in wants:
			if str(want.id)=="earn":want.progress=float(want.progress)+1.0
		_update_wants()
	_publish("away_changed",[get_away_state()]);_emit_changed()
	_wear_home_clothes()
	_emit_notice("%s is returning from work."%str(character.name))
	dispatch_notifications(release_notifications())

func _validate_career_away_state(state:Dictionary) -> String:
	var eligibility:String=LifeLifecycle.eligibility(LifeLifecycle.stage_for(state.character))
	var value:Dictionary=state.get("away_state",{})
	var pending:Array=state.action_queue.filter(func(action:Dictionary)->bool:return str(action.id)=="career_day")
	if pending.size()!=1 or state.action_queue.any(func(action:Dictionary)->bool:return str(action.id)=="school_day"):return "Save contains duplicate or conflicting departures."
	var action:Dictionary=pending[0]
	if value.is_empty():
		if eligibility!="adult" or int(state.day)<int(state.career.get("schedule",LifeCareerSchedule.fresh(int(state.day))).first_day) or not LifeEducation.weekday(int(state.day)) or float(state.minutes)<LifeCareerSchedule.OPEN or float(state.minutes)>LifeCareerSchedule.CLOSE or int(state.career.worked_day)==int(state.day):return "Save schedules an unavailable work departure."
		if action.get("paid")!=false or not action.get("paid") is bool or not _number_in_range(action.get("elapsed"),0.0,0.0) or not _number_in_range(action.get("duration"),LifeCareerSchedule.LENGTH,LifeCareerSchedule.LENGTH):return "Save contains a departed worker without away state."
		if str(action.get("target_kind",""))!="lot_exit" or str(action.get("target_id",""))!="lot_exit":return "Save contains work without a neighborhood exit."
		return ""
	if not _autonomy_integer(value.get("version"),1,1) or value.get("activity")!="career" or str(value.get("phase","")) not in ["away","returning"]:return "Save contains an unsupported work absence."
	if state.action_queue.is_empty() or str(state.action_queue[0].id)!="career_day":return "Save has an away worker without its active departure."
	if not _autonomy_integer(value.get("departure_day"),1,int(state.day)) or not _autonomy_integer(value.get("return_day"),int(value.departure_day),int(value.departure_day)) or not LifeEducation.weekday(int(value.departure_day)):return "Save contains an invalid work calendar."
	if not state.career.has("schedule") or int(value.get("departure_day",0))<int(state.career.schedule.first_day):return "Save starts work before employment begins."
	if not _number_in_range(value.get("departure_minutes"),LifeCareerSchedule.OPEN,LifeCareerSchedule.CLOSE) or not _number_in_range(value.get("return_minutes"),LifeCareerSchedule.END,LifeCareerSchedule.END) or not value.get("completed") is bool:return "Save contains invalid work departure or return times."
	if LifeLifecycle.eligibility(str(value.get("age_stage","")))!="adult" or str(value.get("exit_id",""))!="lot_exit" or not LifeCareers.has(str(value.get("career_track",""))) or str(value.career_track)!=str(state.career.get("track","")) or not _autonomy_integer(value.get("salary"),0,1000000):return "Save contains an invalid worker, salary or career."
	if str(value.phase)=="away" and int(value.salary)!=int(state.career.salary):return "Save contains a changed salary during work."
	var position:Variant=value.get("exit_position")
	if position is Vector3:
		if not position.is_finite():return "Save contains an invalid work return position."
	elif position is Array and position.size()==3:
		for component:Variant in position:
			if not _number_in_range(component,-100000.0,100000.0):return "Save contains an invalid work return position."
	else:return "Save contains an invalid work return position."
	var departed:float=float(value.departure_day-1)*1440.0+float(value.departure_minutes)
	var due:float=float(value.return_day-1)*1440.0+LifeCareerSchedule.END
	var now:float=float(state.day-1)*1440.0+float(state.minutes)
	if now<departed or not _number_in_range(value.get("ended_at"),0.0,now):return "Save contains future work progress."
	if action.get("paid")!=true or not action.get("paid") is bool or str(action.get("target_id",""))!="lot_exit" or str(action.get("target_kind",""))!="lot_exit" or not _as_vector3(action.target_position).is_equal_approx(_as_vector3(position)):return "Save contains a mismatched work action or exit."
	if not _autonomy_integer(action.get("started_day"),int(value.departure_day),int(value.departure_day)) or not _number_in_range(action.get("started_minutes"),float(value.departure_minutes)-.00000001,float(value.departure_minutes)+.00000001) or not _number_in_range(action.get("duration"),due-departed-.00000001,due-departed+.00000001):return "Save contains an invalid work duration or start."
	var elapsed:float=now-departed if str(value.phase)=="away" else float(value.ended_at)-departed
	if not _number_in_range(action.get("elapsed"),maxf(0.0,elapsed-.00001),minf(due-departed+.00000001,elapsed+.00001)):return "Save contains impossible time at work."
	if str(value.phase)=="away":
		if bool(value.completed) or float(value.ended_at)!=0.0 or now>=due or eligibility!="adult" or int(state.career.worked_day)>=int(value.departure_day):return "Save contains an expired or already-paid workday."
	else:
		if float(value.ended_at)<departed or float(value.ended_at)>due:return "Save contains an invalid work return start."
		if bool(value.completed):
			if float(value.ended_at)!=due or now<due or int(state.career.worked_day)!=int(value.departure_day):return "Save rewards an unfinished workday."
			var schedule:Dictionary=state.career.get("schedule",{})
			if int(schedule.get("last_attendance_day",0))!=int(value.departure_day) or float(schedule.get("late_minutes",0.0))+.00000001<maxf(0.0,float(value.departure_minutes)-LifeCareerSchedule.ON_TIME):return "Save has a work return without earned attendance and lateness."
		elif float(value.ended_at)>=due:return "Save marks a completed workday as an early return."
	return ""


func complete_adoption_arrival(action:Dictionary) -> bool:
	if action_queue.is_empty() or not is_same(action_queue[0],action) or str(action.get("id",""))!="arrive_home":return false
	action_queue.pop_front()
	_emit_action_finished(action)
	_start_front();_emit_changed()
	return true

func get_whims() -> Array:
	return whims.get("whims", [])

func get_fears() -> Array:
	return whims.get("fears", [])

func pin_whim(index: int, pinned: bool) -> bool:
	var ok: bool = LifeWantsManager.pin_whim(whims, index, pinned)
	if ok: _emit_changed()
	return ok

## Pin the whim a player is actually looking at. The Wishes panel runs while the
## simulation keeps ticking, so the whim in a slot can be replaced between the
## moment the card is drawn and the moment its button is pressed. Pinning by
## index would then suppress a whim the player never saw; pinning by identity
## applies to the card's own whim, and does nothing once that whim has refreshed.
func pin_whim_id(whim_id: String, pinned: bool) -> bool:
	return pin_whim(_whim_index(whim_id), pinned) if not whim_id.is_empty() else false

func dismiss_whim_id(whim_id: String) -> bool:
	if whim_id.is_empty():
		return false
	return dismiss_whim(_whim_index(whim_id))

func _whim_index(whim_id: String) -> int:
	var active: Array = get_whims()
	for index: int in range(active.size()):
		if str((active[index] as Dictionary).get("id", "")) == whim_id:
			return index
	return -1

func dismiss_whim(index: int) -> bool:
	var ok: bool = LifeWantsManager.dismiss_whim(whims, index, character, needs, str(get_mood().label))
	if ok: _emit_changed()
	return ok

func trigger_fear(fear_id: String) -> bool:
	var ok: bool = LifeWantsManager.add_fear(whims, fear_id)
	if ok: _emit_changed()
	return ok

