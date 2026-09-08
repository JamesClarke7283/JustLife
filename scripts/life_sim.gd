extends Node
class_name LifeSim
## Deterministic single-household simulation. The world owns movement and calls tick.

signal changed()
signal action_started(action: Dictionary)
signal action_finished(action: Dictionary)
signal notice(text: String)
signal age_changed(previous: String, current: String)

const SAVE_PATH: String = "user://justlife_save.json"
const SAVE_VERSION: int = 1
const GAME_MINUTES_PER_SECOND: float = 6.0
const MAX_QUEUE: int = 8
const NEED_NAMES: Array[String] = ["hunger", "energy", "hygiene", "bladder", "fun", "social"]
const TRAIT_NAMES: Array[String] = ["Creative", "Outgoing", "Active", "Bookworm", "Foodie", "Neat"]
const ASPIRATION_NAMES: Array[String] = ["Maker", "Connected", "Successful", "Balanced"]
const NEED_DECAY: Dictionary = {"hunger": 3.5, "energy": 3.0, "hygiene": 2.1, "bladder": 4.0, "fun": 2.5, "social": 2.0}
const SKILL_NAMES: Array[String] = ["cooking", "creativity", "charisma", "logic", "gardening", "parenting"]
const CAREER_TRACKS: Dictionary = {
	"studio":{"label":"Creative studio","skill":"creativity","base_salary":180,"titles":["Studio assistant","Project coordinator","Creative specialist","Studio lead","Creative director"]},
	"culinary":{"label":"Culinary arts","skill":"cooking","base_salary":160,"titles":["Kitchen assistant","Prep cook","Line chef","Sous chef","Head chef"]},
	"technology":{"label":"Technology","skill":"logic","base_salary":200,"titles":["Support specialist","Junior developer","Software engineer","Technical lead","Principal engineer"]},
	"community":{"label":"Community work","skill":"charisma","base_salary":150,"titles":["Community assistant","Event organizer","Outreach specialist","Program manager","Community director"]}
}

var needs: Dictionary = {}
var character: Dictionary = {}
var lifecycle: Dictionary = {}
var education: Dictionary = {}
var cooperation_owner: Node = null
var cooperation_member_id: String = ""
var _notification_depth: int = 0
var _pending_notifications: Array = []
var skills: Dictionary = {}
var relationships: Dictionary = {}
var career: Dictionary = {}
var wants: Array = []
var funds: int = 2500
var day: int = 1
var minutes: float = 480.0
var speed: int = 1
var autonomy: bool = true
var action_queue: Array = []
var satisfaction: int = 0
var bills_paid: int = 0
var last_bill_day: int = 0
var _targets: Array = []
var _idle_minutes: float = 0.0
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
const STORY_KINDS: Array[String] = ["neighbor_invitation", "career_opportunity", "hobby_exhibition", "garden_exchange", "learning_circle", "community_picnic"]
const SOCIAL_ACTIONS: Array[String] = ["friendly", "joke", "deep_talk", "flirt", "argue", "ask_partner", "commit", "break_up"]
const RELATIONSHIP_ACTIONS: Array[String] = ["ask_partner", "commit", "break_up"]
const SOCIAL_STAGES: Array[String] = ["met", "friends", "close_friends", "spark", "partners", "committed", "separated"]
var social_history: Array = []
var romantic_partner: String = ""
var _social_member_id: String = "player"
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
	needs = {"hunger": 76.0, "energy": 85.0, "hygiene": 86.0, "bladder": 78.0, "fun": 62.0, "social": 58.0}
	skills.clear()
	for skill_name: String in SKILL_NAMES:
		skills[skill_name] = {"level": 1, "xp": 0.0}
	relationships = {
		"maya": {"name": "Maya Chen", "friendship": 12.0, "romance": 0.0, "status": "Acquaintance"},
		"leo": {"name": "Leo Morgan", "friendship": 4.0, "romance": 0.0, "status": "Acquaintance"}
	}
	for relationship: Dictionary in relationships.values():
		_normalize_relationship(relationship, false)
	romantic_partner = ""
	social_history.clear()
	_recent_social_events.clear()
	_social_partners.clear()
	_social_adults.clear()
	_social_reciprocal.clear()
	_social_family.clear()
	career = {"track":"studio","title": "Studio assistant", "level": 1, "performance": 0.0, "salary": 180, "worked_day": 0}
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
	satisfaction = 0
	bills_paid = 0
	last_bill_day = 0
	_idle_minutes = 0.0
	_warned_needs.clear()
	_create_wants()
	_emit_changed()


func _build_actions() -> void:
	_define("help_homework", "Help with homework", 45.0, {}, 0, "", 0.0, "Support a child or teen through one assignment and build Parenting skill.")
	_define("school", "Attend online classes", 180.0, {}, 0, "", 0.0, "Weekday lessons at your desk, 08:00–14:00. Prepared homework improves learning and grades.")
	_define("homework", "Do homework", 45.0, {}, 0, "", 0.0, "Complete a weekday assignment and prepare for the next attended class.")
	_define("birthday", "Celebrate a birthday", 45.0, {"fun":30.0,"social":20.0}, 30, "", 0.0, "Celebrate the next chapter of your life. Advances this Lifelet to the next age stage.")
	_define("snack", "Grab a snack", 15.0, {"hunger": 32.0}, 8, "", 0.0, "A quick bite to keep the day going.")
	_define("cook", "Cook a fresh meal", 45.0, {"hunger": 70.0, "fun": 8.0, "hygiene": -5.0}, 25, "cooking", 34.0, "Make a wholesome meal and build Cooking skill.")
	_define("sleep", "Sleep", 360.0, {"energy": 95.0}, 0, "", 0.0, "A full night's rest restores energy.")
	_define("nap", "Take a nap", 75.0, {"energy": 38.0}, 0, "", 0.0, "A short, refreshing nap.")
	_define("shower", "Take a shower", 30.0, {"hygiene": 85.0, "fun": 4.0}, 0, "", 0.0, "Freshen up and feel ready for the day.")
	_define("toilet", "Use toilet", 15.0, {"bladder": 95.0, "hygiene": -3.0}, 0, "", 0.0, "Take care of a pressing need.")
	_define("relax", "Relax", 40.0, {"fun": 25.0, "energy": 12.0}, 0, "", 0.0, "Put your feet up and unwind.")
	_define("watch", "Watch a show", 60.0, {"fun": 48.0, "energy": 5.0}, 0, "", 0.0, "Enjoy a favorite show.")
	_define("read", "Read a book", 60.0, {"fun": 32.0}, 0, "logic", 25.0, "Lose yourself in a good book and build Logic.")
	_define("paint", "Paint & sell a canvas", 90.0, {"fun": 40.0, "hygiene": -5.0}, 20, "creativity", 42.0, "Create an original canvas; its value grows with your skill.")
	_define("work", "Do freelance work", 120.0, {"fun": -8.0, "energy": -10.0}, 0, "logic", 24.0, "Complete a small freelance project for income.")
	_define("study", "Study a skill", 90.0, {"fun": 12.0, "energy": -5.0}, 0, "logic", 40.0, "Practice Logic and prepare for career advancement.")
	_define("job", "Work a shift", 360.0, {"hunger": -12.0, "energy": -18.0, "fun": -15.0, "social": 12.0}, 0, "logic", 30.0, "Work one paid shift per day and progress your career.")
	_define("water", "Tend the plants", 25.0, {"fun": 15.0, "hygiene": -4.0}, 0, "gardening", 28.0, "Care for greenery and learn Gardening.")
	_define("friendly", "Have a friendly chat", 25.0, {"social": 28.0, "fun": 6.0}, 0, "charisma", 18.0, "Say hello, catch up and grow your friendship.")
	_define("joke", "Tell a joke", 20.0, {"social": 22.0, "fun": 16.0}, 0, "charisma", 16.0, "Share a laugh and strengthen your friendship.")
	_define("deep_talk", "Have a heartfelt talk", 45.0, {"social": 45.0, "fun": 8.0}, 0, "charisma", 28.0, "A deeper conversation works best with someone you know.")
	_define("flirt", "Flirt", 25.0, {"social": 26.0, "fun": 10.0}, 0, "charisma", 20.0, "Express interest. Friendship helps your advances land well.")
	_define("argue", "Argue", 20.0, {"social": 8.0, "fun": -12.0}, 0, "charisma", 8.0, "Vent your frustration, at a cost to the relationship.")
	_define("ask_partner", "Ask to become partners", 35.0, {"social": 15.0, "fun": 8.0}, 0, "charisma", 12.0, "Choose a relationship together. Both adults need 45 friendship and 35 romance, and must be available.")
	_define("commit", "Make a commitment", 45.0, {"social": 20.0, "fun": 10.0}, 0, "charisma", 16.0, "Affirm your shared future with your current partner, with 65 friendship and 65 romance.")
	_define("break_up", "End the relationship", 25.0, {"social": 5.0, "fun": -8.0}, 0, "", 0.0, "End your partnership honestly. Friendship falls by 12 and romance by 35; both become available again.")


func _define(id: String, label: String, duration: float, changes: Dictionary, cost: int, skill: String, xp: float, description: String) -> void:
	_actions[id] = {"id": id, "label": label, "duration": duration, "changes": changes, "cost": cost, "skill": skill, "xp": xp, "description": description}


func get_actions_for(kind: String, target_id: String = "") -> Array:
	var ids: Array = []
	match kind:
		"fridge": ids = ["cook", "snack", "birthday"]
		"stove", "kitchen": ids = ["cook"]
		"bed": ids = ["sleep", "nap"]
		"shower", "bath": ids = ["shower"]
		"toilet": ids = ["toilet"]
		"sofa", "chair": ids = ["relax", "nap"]
		"bench": ids = ["relax", "read", "nap"]
		"tv": ids = ["watch"]
		"bookshelf": ids = ["read", "study"]
		"easel": ids = ["paint"]
		"desk", "computer": ids = ["work", "study", "job"]
		"plant": ids = ["water"]
		"neighbor", "maya", "leo": ids = SOCIAL_ACTIONS
	if str(character.age_stage) in LifeEducation.SCHOOL_STAGES:
		if kind in ["desk","computer"]: ids = ["school","homework","study"]
		elif kind == "bookshelf": ids = ["read","homework","study"]
	var result: Array = []
	for id: String in ids:
		var data: Dictionary = _actions[id].duplicate(true)
		var availability: Dictionary = get_action_availability(id, target_id)
		data["available"] = availability.available
		data["unavailable_reason"] = availability.reason
		result.append(data)
	return result


func get_action_definition(id: String) -> Dictionary:
	return _actions.get(id, {}).duplicate(true)


func queue_action(id: String, target_id: String = "", target_position: Vector3 = Vector3.ZERO) -> bool:
	if id == "help_homework":
		_emit_notice("Choose Do homework together at a desk to arrange both Lifelets.")
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
	if funds < int(definition["cost"]):
		_emit_notice("You need §%d for %s." % [int(definition["cost"]), str(definition["label"]).to_lower()])
		return false
	if id == "job" and int(career["worked_day"]) == day:
		_emit_notice("Today's shift is complete. You can work again tomorrow.")
		return false
	if id in SOCIAL_ACTIONS or id in ["birthday", "job", "work", "cook", "school", "homework"]:
		var availability: Dictionary = get_action_availability(id, target_id)
		if not bool(availability.available):
			_emit_notice(str(availability.reason))
			return false
	var action: Dictionary = definition.duplicate(true)
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
	if action_queue.is_empty() or str(action_queue[0]["phase"]) != "approach":
		return
	var action: Dictionary = action_queue[0]
	if action.has("cooperation_id"):
		if is_instance_valid(cooperation_owner): cooperation_owner.mark_cooperative_ready(cooperation_member_id)
		return
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
	if str(action.id) in RELATIONSHIP_ACTIONS or str(action.id) in ["flirt", "birthday", "job", "work", "cook"]:
		var availability: Dictionary = get_action_availability(str(action.id), str(action.target_id))
		if not bool(availability.available):
			_emit_notice(str(availability.reason))
			cancel_action()
			return
	if not bool(action["paid"]):
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
	action["phase"] = "active"
	_emit_changed()


func cancel_action(index: int = 0) -> void:
	if index < 0 or index >= action_queue.size():
		return
	if action_queue[index].has("cooperation_id") and is_instance_valid(cooperation_owner):
		cooperation_owner.cancel_cooperative_action(cooperation_member_id)
		return
	action_queue.remove_at(index)
	if index == 0:
		_start_front()
	_idle_minutes = 0.0
	_emit_changed()


func _start_front() -> void:
	if action_queue.is_empty():
		return
	action_queue[0]["phase"] = "approach"
	_emit_action_started(action_queue[0])


func set_speed(value: int) -> void:
	if value not in [0, 1, 3, 8]:
		return
	speed = value
	_emit_changed()


func register_targets(targets: Array) -> void:
	_targets.clear()
	for entry: Variant in targets:
		if entry is Dictionary and entry.has("id") and entry.has("kind") and entry.get("position") is Vector3:
			_targets.append(entry.duplicate(true))
	_prune_school_actions()


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
	for i in range(moodlets.size()-1,-1,-1):
		moodlets[i].remaining=maxf(0,float(moodlets[i].remaining)-game_minutes)
		if float(moodlets[i].remaining)<=0:moodlets.remove_at(i)
	minutes += game_minutes
	while minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
		_new_day()
	_advance_age(game_minutes)
	_prune_school_actions()
	for need_name: String in NEED_NAMES:
		var decay: float = float(NEED_DECAY[need_name])
		if need_name == "social" and _has_trait("Outgoing"):
			decay *= 1.35
		if need_name == "fun" and _has_trait("Creative"):
			decay *= 1.2
		if need_name == "hygiene" and _has_trait("Neat"):
			decay *= 0.75
		if need_name == "energy" and _has_trait("Active"):
			decay *= 0.8
		needs[need_name] = clampf(float(needs[need_name]) - decay * game_minutes / 60.0, 0.0, 100.0)
	if not action_queue.is_empty() and str(action_queue[0]["phase"]) == "active" and str(action_queue[0].id) != "help_homework":
		var action: Dictionary = action_queue[0]
		var actual_step: float = minf(game_minutes, float(action["duration"]) - float(action["elapsed"]))
		action["elapsed"] = float(action["elapsed"]) + actual_step
		action["progress"] = clampf(float(action["elapsed"]) / float(action["duration"]), 0.0, 1.0)
		_apply_continuous_effects(action, actual_step / float(action["duration"]))
		if float(action["progress"]) >= 1.0:
			_finish_front()
	elif action_queue.is_empty():
		_idle_minutes += game_minutes
		if autonomy and _idle_minutes >= 15.0:
			_choose_autonomous_action()
	_check_need_notices()
	_update_wants()


func _apply_continuous_effects(action: Dictionary, fraction: float) -> void:
	var changes: Dictionary = action["changes"]
	for need_name: String in changes:
		var amount: float = float(changes[need_name]) * fraction
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
		_gain_skill(skill_name, float(action["xp"]) * fraction * multiplier)


func _gain_skill(skill_name: String, amount: float) -> void:
	_record_practice(skill_name, amount)
	var skill: Dictionary = skills[skill_name]
	if int(skill["level"]) >= 10:
		return
	skill["xp"] = float(skill["xp"]) + amount
	var required: float = float(int(skill["level"]) * 50)
	while float(skill["xp"]) >= required and int(skill["level"]) < 10:
		skill["xp"] = float(skill["xp"]) - required
		skill["level"] = int(skill["level"]) + 1
		_emit_notice("%s reached %s level %d!" % [character["name"], skill_name.capitalize(), int(skill["level"])])
		required = float(int(skill["level"]) * 50)


func _finish_front() -> void:
	if not action_queue.is_empty() and action_queue[0].has("cooperation_id") and is_instance_valid(cooperation_owner):
		cooperation_owner.finish_cooperative_homework(str(action_queue[0].cooperation_id))
		return
	var action: Dictionary = action_queue.pop_front()
	var id: String = str(action["id"])
	var earned: int = 0
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
	elif id == "paint":
		var sale: int = 55 + int(skills["creativity"]["level"]) * 35
		funds += sale
		earned = sale
		_emit_notice("Canvas sold for §%d. A little creativity goes a long way." % sale)
	elif id == "work":
		var income: int = 55 + int(skills["logic"]["level"]) * 20
		funds += income
		earned = income
		career["performance"] = minf(100.0, float(career["performance"]) + 8.0)
		_emit_notice("Freelance project complete. Earned §%d." % income)
	elif id == "job":
		var income: int = int(career["salary"])
		funds += income
		earned = income
		career["worked_day"] = day
		var comfort: float = (float(needs["hunger"]) + float(needs["energy"]) + float(needs["fun"])) / 3.0
		career["performance"] = float(career["performance"]) + 18.0 + comfort * 0.15 + float(skills["logic"]["level"]) * 2.0
		_emit_notice("Shift finished. Earned §%d." % income)
		_check_promotion()
	elif id in SOCIAL_ACTIONS:
		action["social_accepted"] = _apply_social(action)
		action["social_events"] = _recent_social_events.duplicate(true)
	elif id == "water":
		_emit_notice("The plants look happier. Gardening skill improved.")
	elif id == "cook" and _has_trait("Foodie"):
		_emit_notice("A delicious homemade meal! Your Foodie trait made it extra satisfying.")
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
	_emit_action_finished(action)
	_idle_minutes = 0.0
	_update_wants()
	_start_front()
	_emit_changed()


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
	if not _actions.has(id):
		return {"available":false, "reason":"That activity is unavailable."}
	if id in ["school","homework"]:
		reason = _school_availability(id,target_id)
	elif id == "birthday" and LifeLifecycle.next_stage(str(character.age_stage)).is_empty():
		reason = "This Lifelet has no further birthday stage."
	elif id in ["job", "work"] and str(character.life_stage) != "adult":
		reason = "Full-time careers and freelance work are available to adults."
	elif id == "cook" and str(character.age_stage) == "child":
		reason = "Children can grab a snack. An older Lifelet can use the stove."
	elif funds < int(_actions[id].cost):
		reason = "Requires §%d." % int(_actions[id].cost)
	elif id == "job" and int(career.worked_day) == day:
		reason = "Today's shift is already complete."
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
	if action_id in ["friendly", "joke", "deep_talk"]: achieved.append("met")
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
		"flirt":
			if float(person["friendship"]) >= 30.0:
				person["romance"] = minf(100.0, float(person["romance"]) + 16.0)
				change = 5.0
				_emit_notice("There is a spark between you and %s." % person["name"])
			else:
				change = -7.0
				_emit_notice("%s seems uncomfortable. Try building a friendship first." % person["name"])
		"argue":
			change = -22.0
			person["romance"] = maxf(0.0, float(person["romance"]) - 12.0)
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


func _check_promotion() -> void:
	if float(career["performance"]) < 100.0 or int(career["level"]) >= 5:
		return
	career["performance"] = float(career["performance"]) - 100.0
	career["level"] = int(career["level"]) + 1
	var track:Dictionary=CAREER_TRACKS.get(str(career.get("track","studio")),CAREER_TRACKS.studio)
	var titles: Array = track.titles
	career["title"] = titles[int(career["level"]) - 1]
	career["salary"] = int(track.base_salary) + (int(career["level"]) - 1) * 110
	funds += 200
	_emit_notice("Promotion! You are now a %s. §200 bonus and a higher daily salary." % str(career["title"]).to_lower())
	add_moodlet("A step forward","Confident","Your hard work is paying off.",360,4)
	remember("A promotion",str(career.title))

func choose_career(track_id:String) -> bool:
	if str(character.life_stage) != "adult":
		_emit_notice("Careers become available in young adulthood.");return false
	if not CAREER_TRACKS.has(track_id):return false
	if career.get("track","studio")==track_id:return true
	for action in action_queue:
		if action.id=="job":_emit_notice("Finish or cancel your shift before changing careers.");return false
	var track:Dictionary=CAREER_TRACKS[track_id]
	career={"track":track_id,"title":track.titles[0],"level":1,"performance":0.0,"salary":track.base_salary,"worked_day":int(career.worked_day)}
	remember("A new direction","Joined "+str(track.label))
	add_moodlet("New possibilities","Inspired","A new career is a chance to grow.",240,2)
	_emit_notice("Your new job: %s. §%d per shift." % [career.title,career.salary])
	_emit_changed()
	return true

func add_moodlet(label:String,emotion:String,description:String,duration:float,strength:int=2) -> void:
	for i in range(moodlets.size()-1,-1,-1):
		if moodlets[i].label==label:moodlets.remove_at(i)
	moodlets.append({"label":label,"emotion":emotion,"description":description,"remaining":duration,"strength":strength})
	while moodlets.size()>8:moodlets.pop_front()

func remember(label:String,detail:String) -> void:
	memories.push_front({"day":day,"minutes":int(minutes),"label":label,"detail":detail})
	while memories.size()>40:memories.pop_back()

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
		"joke":add_moodlet("A shared laugh","Playful","That joke is still making you smile.",120,3)
		"argue":add_moodlet("Words linger","Tense","A difficult conversation takes time to shake off.",180,3)
		"work","job":
			add_moodlet("A job well done","Confident","You've earned a little time for yourself.",180,2)
			remember("A productive day","Finished work and earned a living.")
		"water":add_moodlet("Growing together","Happy","Looking after something living feels rewarding.",120,1)


func _new_day() -> void:
	_advance_education()
	_cancel_school_actions("A new school day has begun. Choose a fresh class or assignment.")
	_warned_needs.clear()
	# Modest household costs every morning; no invisible automatic wages.
	var bill: int = 35
	if not household_bills_enabled:bill=0
	var charged: int = mini(funds, bill)
	funds -= charged
	bills_paid += charged
	last_bill_day = day
	if not household_bills_enabled:
		pass
	elif charged < bill:
		_emit_notice("Day %d: household bills used your remaining §%d. Earn money with work or painting." % [day, charged])
	else:
		_emit_notice("A new day. §%d paid for household bills." % charged)
	for person: Dictionary in relationships.values():
		if float(person["friendship"]) > 0.0:
			person["friendship"] = maxf(0.0, float(person["friendship"]) - 1.5)
		_update_relationship_status(person)
	_offer_daily_story()


func _check_need_notices() -> void:
	for need_name: String in NEED_NAMES:
		if float(needs[need_name]) < 15.0 and not _warned_needs.has(need_name):
			_warned_needs[need_name] = true
			var messages: Dictionary = {"hunger": "is very hungry. A meal would help.", "energy": "is exhausted. Time for some sleep.", "hygiene": "needs a shower to feel fresh again.", "bladder": "really needs the bathroom.", "fun": "feels bored. Make time for something enjoyable.", "social": "feels lonely. Try talking to a neighbor."}
			_emit_notice("%s %s" % [character["name"], messages[need_name]])
		elif float(needs[need_name]) >= 35.0:
			_warned_needs.erase(need_name)


func _autonomous_choice(excluded_target_ids: Array = []) -> Dictionary:
	var priorities: Array[String] = []
	for need_name: String in NEED_NAMES:
		if float(needs[need_name]) < 52.0: priorities.append(need_name)
	priorities.sort_custom(func(a: String,b: String) -> bool:
		if not is_equal_approx(float(needs[a]),float(needs[b])): return float(needs[a]) < float(needs[b])
		return NEED_NAMES.find(a) < NEED_NAMES.find(b))
	for lowest: String in priorities:
		var candidates: Array[String] = []
		match lowest:
			"hunger": candidates = ["snack", "cook"]
			"energy": candidates = ["sleep", "nap"]
			"hygiene": candidates = ["shower"]
			"bladder": candidates = ["toilet"]
			"fun":
				if _has_trait("Bookworm"): candidates = ["read", "watch", "relax"]
				else: candidates = ["paint", "read", "watch", "relax"]
			"social": candidates = ["friendly", "joke"]
		for id: String in candidates:
			for target: Dictionary in _targets:
				if excluded_target_ids.has(str(target.id)): continue
				for definition: Dictionary in get_actions_for(str(target.kind),str(target.id)):
					if str(definition.id) == id and bool(definition.available):
						return {"id":id,"target_id":str(target.id),"position":target.position}
	return {}

func _choose_autonomous_action() -> void:
	_idle_minutes = 0.0
	var choice: Dictionary = _autonomous_choice()
	if not choice.is_empty() and queue_action(str(choice.id),str(choice.target_id),choice.position):
		action_queue.back()["autonomous"] = true

func reconsider_waiting_autonomy(blocked_target_ids: Array, waited_game_minutes: float) -> bool:
	if not autonomy or action_queue.is_empty() or not is_finite(waited_game_minutes) or waited_game_minutes < 30.0: return false
	var current: Dictionary = action_queue[0]
	if not bool(current.get("autonomous",false)) or str(current.get("phase","")) != "approach" or current.has("cooperation_id"): return false
	var choice: Dictionary = _autonomous_choice(blocked_target_ids)
	if choice.is_empty() or (str(choice.id) == str(current.id) and str(choice.target_id) == str(current.target_id)): return false
	var replacement: Dictionary = _actions[str(choice.id)].duplicate(true)
	replacement.merge({"target_id":str(choice.target_id),"target_position":choice.position,"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"autonomous":true})
	action_queue[0] = replacement
	_idle_minutes=0.0
	_start_front()
	_emit_changed()
	return true


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
			_emit_notice("Want fulfilled: %s! +%d satisfaction and §%d." % [want["label"], int(want["reward"]), int(want["reward"])])
	_archive_completed_chapter()


func _aspiration_title() -> String:
	if aspiration_stage == 1:
		return "Making a home"
	var titles: Dictionary = {"Maker":"A creative life", "Connected":"A circle of friends", "Successful":"Work with purpose", "Balanced":"A rhythm of your own"}
	return "%s · Chapter %d" % [titles[str(character["aspiration"])], aspiration_stage]


func get_aspiration_progress() -> Dictionary:
	return {"stage":aspiration_stage, "title":_aspiration_title(), "next_stage_day":aspiration_next_day, "history":aspiration_history.duplicate(true)}


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
			var career_skill: String = str(CAREER_TRACKS.get(str(career.get("track", "studio")), CAREER_TRACKS.studio).skill)
			wants = [
				_chapter_want("chapter_income", "Build a cushion", "Earn §%d from completed shifts, freelance work or paintings this chapter." % (200 + difficulty * 100), 200 + difficulty * 100, reward + 40, "income"),
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
	var neighbor: String = "maya" if (day + day / 6) % 2 == 0 else "leo"
	var track: Dictionary = CAREER_TRACKS.get(str(career.get("track", "studio")), CAREER_TRACKS.studio)
	story_events.append({"id":"story_day_%d" % day, "kind":kind, "day":day, "context":{"neighbor":neighbor, "skill":str(track.skill), "career_level":int(career.level), "creativity_level":int(skills.creativity.level)}})
	_emit_notice("A new story choice is waiting: %s." % _story_event(story_events.back()).title)


func _story_choice(id: String, label: String, changes: Dictionary = {}, requirements: Dictionary = {}) -> Dictionary:
	var available: bool = funds >= int(changes.get("cost", 0))
	var reason: String = "" if available else "Requires §%d." % int(changes.get("cost", 0))
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
	return result


func _story_effects_text(changes: Dictionary) -> String:
	var parts: PackedStringArray = []
	if int(changes.get("cost", 0)) > 0:
		parts.append("Pay §%d" % int(changes.cost))
	if int(changes.get("income", 0)) > 0:
		parts.append("Earn §%d" % int(changes.income))
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
				career.performance = minf(1000.0, float(career.performance) + float(effects.performance))
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


func get_clock_text() -> String:
	var hour: int = int(minutes) / 60
	var minute: int = int(minutes) % 60
	return "Day %d · %02d:%02d" % [day, hour, minute]


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
		var colors:Dictionary={"Happy":"65a68b","Energized":"c8aa5d","Confident":"6b9ac0","Focused":"629db3","Inspired":"9a85b3","Playful":"cf8aaa","Tense":"cf8669"}
		return {"label":strongest.emotion,"description":strongest.description,"color":Color(colors.get(strongest.emotion,"7aaf89"))}
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
	return {"version": SAVE_VERSION, "character": character.duplicate(true), "lifecycle": lifecycle.duplicate(true), "education": education.duplicate(true), "needs": needs.duplicate(true), "skills": skills.duplicate(true), "relationships": relationships.duplicate(true), "career": career.duplicate(true), "wants": wants.duplicate(true), "funds": funds, "day": day, "minutes": minutes, "speed": speed, "autonomy": autonomy, "action_queue": action_queue.duplicate(true), "satisfaction": satisfaction, "bills_paid": bills_paid, "last_bill_day": last_bill_day,"moodlets":moodlets.duplicate(true),"memories":memories.duplicate(true), "aspiration_stage":aspiration_stage, "aspiration_next_day":aspiration_next_day, "aspiration_history":aspiration_history.duplicate(true), "story_events":story_events.duplicate(true), "story_history":story_history.duplicate(true), "story_generated_day":_story_generated_day, "romantic_partner":romantic_partner, "social_history":social_history.duplicate(true)}


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
	if state.get("skills") is Dictionary and not state.skills.has("parenting"):
		state.skills.parenting = {"level":1,"xp":0.0}
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
	lifecycle = state.get("lifecycle", LifeLifecycle.fresh()).duplicate(true)
	lifecycle.progress = float(lifecycle.progress)
	for birthday: Dictionary in lifecycle.history: birthday.day = int(birthday.day)
	needs = state["needs"].duplicate(true)
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
	funds = int(state["funds"])
	day = int(state["day"])
	minutes = float(state["minutes"])
	var school_state: Dictionary = state.get("education",LifeEducation.fresh(str(character.age_stage),day))
	education = LifeEducation.advance(school_state,str(character.age_stage),day).state
	speed = int(state.get("speed", 1))
	autonomy = bool(state.get("autonomy", true))
	satisfaction = int(state.get("satisfaction", 0))
	bills_paid = int(state.get("bills_paid", 0))
	last_bill_day = int(state.get("last_bill_day", 0))
	action_queue.clear()
	for stored: Dictionary in state.get("action_queue", []):
		var action: Dictionary = _actions[str(stored["id"])].duplicate(true)
		action["target_id"] = str(stored.get("target_id", ""))
		action["target_position"] = _as_vector3(stored.get("target_position", [0.0, 0.0, 0.0]))
		action["elapsed"] = clampf(float(stored.get("elapsed", 0.0)), 0.0, float(action["duration"]))
		action["duration"] = float(stored.get("duration", action["duration"]))
		action["progress"] = clampf(float(action["elapsed"]) / float(action["duration"]), 0.0, 1.0)
		action["phase"] = "queued"
		action["paid"] = bool(stored.get("paid", false))
		action["autonomous"] = bool(stored.get("autonomous", false))
		action["started_day"] = int(stored.get("started_day", day))
		if stored.has("started_minutes"): action["started_minutes"] = float(stored.started_minutes)
		if stored.has("target_kind"): action["target_kind"] = str(stored.target_kind)
		for key: String in ["cooperation_id","cooperation_role"]:
			if stored.has(key): action[key] = str(stored[key])
		if str(action.id) == "birthday": action["birthday_from_stage"] = str(stored.get("birthday_from_stage",character.age_stage))
		action_queue.append(action)
	_idle_minutes = 0.0
	_warned_needs.clear()
	_start_front()
	_emit_changed()
	_emit_notice("Welcome home, %s." % character["name"])
	return {"ok": true, "world": state.get("world", []).duplicate(true)}


func _validate_state(state: Dictionary) -> String:
	if int(state.get("version", -1)) != SAVE_VERSION:
		return "This save uses an unsupported version."
	for key: String in ["character", "needs", "skills", "relationships", "career"]:
		if not state.get(key) is Dictionary:
			return "Save is missing valid %s data." % key
	if not state.get("wants") is Array or not state.get("action_queue", []) is Array or not state.get("world", []) is Array:
		return "Save contains invalid lists."
	var profile: Dictionary = state["character"]
	var age_error: String = LifeLifecycle.validate(profile, state.get("lifecycle", LifeLifecycle.fresh()))
	if not age_error.is_empty(): return age_error
	for birthday: Dictionary in state.get("lifecycle", LifeLifecycle.fresh()).history:
		if int(birthday.day) > int(state.get("day", 0)): return "Save contains a future birthday."
	if not profile.get("name") is String or not profile.get("traits") is Array or str(profile.get("aspiration", "")) not in ASPIRATION_NAMES:
		return "Save contains an invalid character."
	for trait_name: Variant in profile["traits"]:
		if not trait_name is String or str(trait_name) not in TRAIT_NAMES:
			return "Save contains an invalid trait."
	for need_name: String in NEED_NAMES:
		if not _number_in_range(state["needs"].get(need_name), 0.0, 100.0):
			return "Save contains an invalid need."
	for skill_name: String in SKILL_NAMES:
		var skill: Variant = state["skills"].get(skill_name)
		if not skill is Dictionary or not _number_in_range(skill.get("level"), 1.0, 10.0) or not _number_in_range(skill.get("xp"), 0.0, 10000.0):
			return "Save contains an invalid skill."
	for required_id:String in ["maya","leo"]:
		if not state["relationships"].has(required_id):return "Save is missing a relationship."
	for person_id: String in state["relationships"]:
		var person: Variant = state["relationships"].get(person_id)
		if not person is Dictionary or not person.get("name") is String or not person.get("status") is String or not _number_in_range(person.get("friendship"), -100.0, 100.0) or not _number_in_range(person.get("romance"), 0.0, 100.0):
			return "Save contains an invalid relationship."
	var job: Dictionary = state["career"]
	if not job.get("title") is String or not _number_in_range(job.get("level"), 1.0, 5.0) or not _number_in_range(job.get("performance"), 0.0, 1000.0) or not _number_in_range(job.get("salary"), 0.0, 1000000.0) or not _number_in_range(job.get("worked_day"), 0.0, 1000000.0):
		return "Save contains an invalid career."
	if not _number_in_range(state.get("funds"), 0.0, 1000000000.0) or not _number_in_range(state.get("day"), 1.0, 1000000.0) or not _number_in_range(state.get("minutes"), 0.0, 1439.99999):
		return "Save contains an invalid clock or funds."
	var school_error: String = _validate_school_state(state)
	if not school_error.is_empty(): return school_error
	if not _number_in_range(state.get("speed", 1), 0.0, 8.0) or int(state.get("speed", 1)) not in [0, 1, 3, 8] or not state.get("autonomy", true) is bool:
		return "Save contains invalid simulation settings."
	for key: String in ["satisfaction", "bills_paid", "last_bill_day"]:
		if not _number_in_range(state.get(key, 0), 0.0, 1000000000.0):
			return "Save contains invalid progress."
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
		if action.has("cooperation_id") or action.has("cooperation_role") or action_id == "help_homework":
			if not action.get("cooperation_id") is String or str(action.cooperation_id).is_empty() or str(action.get("cooperation_role","")) != ("helper" if action_id == "help_homework" else "learner") or action_id not in ["homework","help_homework"]:
				return "Save contains an invalid cooperative action."
			if action_id == "help_homework" and str(profile.get("life_stage","adult")) != "adult": return "Save contains a non-adult homework helper."
		if action_id in ["job","work"] and str(profile.get("life_stage","adult")) != "adult": return "Save contains adult work queued for a non-adult Lifelet."
		if action_id == "cook" and LifeLifecycle.stage_for(profile) == "child": return "Save contains stove cooking queued for a child."
		if action_id == "birthday":
			if LifeLifecycle.next_stage(LifeLifecycle.stage_for(profile)).is_empty(): return "Save contains a birthday beyond the supported age stages."
			if str(action.get("birthday_from_stage",LifeLifecycle.stage_for(profile))) != LifeLifecycle.stage_for(profile): return "Save contains a birthday for an age stage that has already passed."
		if not _number_in_range(action.get("elapsed", 0), 0.0, 10000.0) or not _number_in_range(action.get("duration", 1), 1.0, 10000.0):
			return "Save contains invalid action progress."
		var position: Variant = action.get("target_position", [0, 0, 0])
		if not position is Vector3:
			if not position is Array or position.size() != 3:
				return "Save contains an invalid action position."
			for component: Variant in position:
				if not _number_in_range(component, -100000.0, 100000.0):
					return "Save contains an invalid action position."
	return ""


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
		if str(context.get("neighbor", "")) not in ["maya", "leo"] or str(context.get("skill", "")) not in SKILL_NAMES or not _number_in_range(context.get("career_level"), 1, 5) or not _number_in_range(context.get("creativity_level"), 1, 10):
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
			if str(queued.id) == id: return "That school activity is already queued."
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
	var front_removed: bool = not action_queue.is_empty() and str(action_queue[0].id) in ["school","homework"]
	var cancelled: bool = false
	for index: int in range(action_queue.size()-1,-1,-1):
		if str(action_queue[index].id) in ["school","homework"]:
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
		var invalid: bool = str(action.id) in ["school","homework"]
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
	if not bool(lifecycle.auto_age) or str(character.age_stage) == "unknown": return
	var duration: float = LifeLifecycle.duration(str(character.age_stage), str(lifecycle.lifespan)) * 1440.0
	lifecycle.progress = minf(1.0, float(lifecycle.progress) + game_minutes / duration)
	if float(lifecycle.progress) >= 1.0 - .0000001 and not LifeLifecycle.next_stage(str(character.age_stage)).is_empty():
		celebrate_birthday()

func celebrate_birthday(start_next_action: bool = true) -> bool:
	var previous: String = str(character.age_stage)
	var next: String = LifeLifecycle.next_stage(previous)
	if next.is_empty(): return false
	var school_result: Dictionary = LifeEducation.advance(education,next,day,minutes)
	if not bool(school_result.ok):
		_emit_notice(str(school_result.error))
		return false
	character.age_stage = next
	character.life_stage = LifeLifecycle.eligibility(next)
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

func _emit_changed() -> void: _publish("changed")
func _emit_notice(message: String) -> void: _publish("notice",[message])
func _emit_action_started(action: Dictionary) -> void: _publish("action_started",[action])
func _emit_action_finished(action: Dictionary) -> void: _publish("action_finished",[action])
func _emit_age_changed(previous: String, current: String) -> void: _publish("age_changed",[previous,current])
