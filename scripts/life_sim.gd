extends Node
class_name LifeSim
## Deterministic single-household simulation. The world owns movement and calls tick.

signal changed()
signal action_started(action: Dictionary)
signal action_finished(action: Dictionary)
signal notice(text: String)

const SAVE_PATH: String = "user://justlife_save.json"
const SAVE_VERSION: int = 1
const GAME_MINUTES_PER_SECOND: float = 6.0
const MAX_QUEUE: int = 8
const NEED_NAMES: Array[String] = ["hunger", "energy", "hygiene", "bladder", "fun", "social"]
const TRAIT_NAMES: Array[String] = ["Creative", "Outgoing", "Active", "Bookworm", "Foodie", "Neat"]
const ASPIRATION_NAMES: Array[String] = ["Maker", "Connected", "Successful", "Balanced"]
const NEED_DECAY: Dictionary = {"hunger": 3.5, "energy": 3.0, "hygiene": 2.1, "bladder": 4.0, "fun": 2.5, "social": 2.0}
const SKILL_NAMES: Array[String] = ["cooking", "creativity", "charisma", "logic", "gardening"]
const CAREER_TRACKS: Dictionary = {
	"studio":{"label":"Creative studio","skill":"creativity","base_salary":180,"titles":["Studio assistant","Project coordinator","Creative specialist","Studio lead","Creative director"]},
	"culinary":{"label":"Culinary arts","skill":"cooking","base_salary":160,"titles":["Kitchen assistant","Prep cook","Line chef","Sous chef","Head chef"]},
	"technology":{"label":"Technology","skill":"logic","base_salary":200,"titles":["Support specialist","Junior developer","Software engineer","Technical lead","Principal engineer"]},
	"community":{"label":"Community work","skill":"charisma","base_salary":150,"titles":["Community assistant","Event organizer","Outreach specialist","Program manager","Community director"]}
}

var needs: Dictionary = {}
var character: Dictionary = {}
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


func _init() -> void:
	_build_actions()
	new_household({})


func new_household(profile: Dictionary) -> void:
	character = profile.duplicate(true)
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
	career = {"track":"studio","title": "Studio assistant", "level": 1, "performance": 0.0, "salary": 180, "worked_day": 0}
	moodlets.clear();memories.clear()
	funds = 2500
	day = 1
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
	changed.emit()


func _build_actions() -> void:
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
	_define("friendly", "Friendly introduction", 25.0, {"social": 28.0, "fun": 6.0}, 0, "charisma", 18.0, "Say hello and get to know your neighbor.")
	_define("joke", "Tell a joke", 20.0, {"social": 22.0, "fun": 16.0}, 0, "charisma", 16.0, "Share a laugh and strengthen your friendship.")
	_define("deep_talk", "Have a heartfelt talk", 45.0, {"social": 45.0, "fun": 8.0}, 0, "charisma", 28.0, "A deeper conversation works best with someone you know.")
	_define("flirt", "Flirt", 25.0, {"social": 26.0, "fun": 10.0}, 0, "charisma", 20.0, "Express interest. Friendship helps your advances land well.")
	_define("argue", "Argue", 20.0, {"social": 8.0, "fun": -12.0}, 0, "charisma", 8.0, "Vent your frustration, at a cost to the relationship.")


func _define(id: String, label: String, duration: float, changes: Dictionary, cost: int, skill: String, xp: float, description: String) -> void:
	_actions[id] = {"id": id, "label": label, "duration": duration, "changes": changes, "cost": cost, "skill": skill, "xp": xp, "description": description}


func get_actions_for(kind: String) -> Array:
	var ids: Array = []
	match kind:
		"fridge": ids = ["cook", "snack"]
		"stove", "kitchen": ids = ["cook"]
		"bed": ids = ["sleep", "nap"]
		"shower", "bath": ids = ["shower"]
		"toilet": ids = ["toilet"]
		"sofa", "chair": ids = ["relax", "nap"]
		"tv": ids = ["watch"]
		"bookshelf": ids = ["read", "study"]
		"easel": ids = ["paint"]
		"desk", "computer": ids = ["work", "study", "job"]
		"plant": ids = ["water"]
		"neighbor", "maya", "leo": ids = ["friendly", "joke", "deep_talk", "flirt", "argue"]
	var result: Array = []
	for id: String in ids:
		var data: Dictionary = _actions[id].duplicate(true)
		data["available"] = funds >= int(data["cost"]) and (id != "job" or int(career["worked_day"]) != day)
		result.append(data)
	return result


func get_action_definition(id: String) -> Dictionary:
	return _actions.get(id, {}).duplicate(true)


func queue_action(id: String, target_id: String = "", target_position: Vector3 = Vector3.ZERO) -> bool:
	if not _actions.has(id):
		return false
	if action_queue.size() >= MAX_QUEUE:
		notice.emit("Your action queue is full. Finish or cancel an activity first.")
		return false
	var definition: Dictionary = _actions[id]
	if funds < int(definition["cost"]):
		notice.emit("You need §%d for %s." % [int(definition["cost"]), str(definition["label"]).to_lower()])
		return false
	if id == "job" and int(career["worked_day"]) == day:
		notice.emit("Today's shift is complete. You can work again tomorrow.")
		return false
	var action: Dictionary = definition.duplicate(true)
	action.merge({"target_id": target_id, "target_position": target_position, "phase": "queued", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false}, true)
	if _has_trait("Active") and id == "nap":
		action["duration"] = 60.0
	action_queue.append(action)
	_idle_minutes = 0.0
	if action_queue.size() == 1:
		_start_front()
	changed.emit()
	return true


func get_current_action() -> Dictionary:
	return {} if action_queue.is_empty() else action_queue[0]


func begin_current_action() -> void:
	if action_queue.is_empty() or str(action_queue[0]["phase"]) != "approach":
		return
	var action: Dictionary = action_queue[0]
	var cost: int = int(action["cost"])
	if not bool(action["paid"]):
		if funds < cost:
			notice.emit("There isn't enough money for that activity anymore.")
			cancel_action()
			return
		if str(action["id"]) == "job" and int(career["worked_day"]) == day:
			notice.emit("You have already worked today's shift.")
			cancel_action()
			return
		funds -= cost
		action["paid"] = true
		action["started_day"] = day
	action["phase"] = "active"
	changed.emit()


func cancel_action(index: int = 0) -> void:
	if index < 0 or index >= action_queue.size():
		return
	action_queue.remove_at(index)
	if index == 0:
		_start_front()
	_idle_minutes = 0.0
	changed.emit()


func _start_front() -> void:
	if action_queue.is_empty():
		return
	action_queue[0]["phase"] = "approach"
	action_started.emit(action_queue[0])


func set_speed(value: int) -> void:
	if value not in [0, 1, 3, 8]:
		return
	speed = value
	changed.emit()


func register_targets(targets: Array) -> void:
	_targets.clear()
	for entry: Variant in targets:
		if entry is Dictionary and entry.has("id") and entry.has("kind") and entry.get("position") is Vector3:
			_targets.append(entry.duplicate(true))


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
		changed.emit()


func _step(game_minutes: float) -> void:
	for i in range(moodlets.size()-1,-1,-1):
		moodlets[i].remaining=maxf(0,float(moodlets[i].remaining)-game_minutes)
		if float(moodlets[i].remaining)<=0:moodlets.remove_at(i)
	minutes += game_minutes
	while minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
		_new_day()
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
	if not action_queue.is_empty() and str(action_queue[0]["phase"]) == "active":
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
	var skill: Dictionary = skills[skill_name]
	if int(skill["level"]) >= 10:
		return
	skill["xp"] = float(skill["xp"]) + amount
	var required: float = float(int(skill["level"]) * 50)
	while float(skill["xp"]) >= required and int(skill["level"]) < 10:
		skill["xp"] = float(skill["xp"]) - required
		skill["level"] = int(skill["level"]) + 1
		notice.emit("%s reached %s level %d!" % [character["name"], skill_name.capitalize(), int(skill["level"])])
		required = float(int(skill["level"]) * 50)


func _finish_front() -> void:
	var action: Dictionary = action_queue.pop_front()
	var id: String = str(action["id"])
	if id == "paint":
		var sale: int = 55 + int(skills["creativity"]["level"]) * 35
		funds += sale
		notice.emit("Canvas sold for §%d. A little creativity goes a long way." % sale)
	elif id == "work":
		var income: int = 55 + int(skills["logic"]["level"]) * 20
		funds += income
		career["performance"] = minf(100.0, float(career["performance"]) + 8.0)
		notice.emit("Freelance project complete. Earned §%d." % income)
	elif id == "job":
		var income: int = int(career["salary"])
		funds += income
		career["worked_day"] = day
		var comfort: float = (float(needs["hunger"]) + float(needs["energy"]) + float(needs["fun"])) / 3.0
		career["performance"] = float(career["performance"]) + 18.0 + comfort * 0.15 + float(skills["logic"]["level"]) * 2.0
		notice.emit("Shift finished. Earned §%d." % income)
		_check_promotion()
	elif id in ["friendly", "joke", "deep_talk", "flirt", "argue"]:
		_apply_social(action)
	elif id == "water":
		notice.emit("The plants look happier. Gardening skill improved.")
	elif id == "cook" and _has_trait("Foodie"):
		notice.emit("A delicious homemade meal! Your Foodie trait made it extra satisfying.")
	_activity_memory(id)
	for want: Dictionary in wants:
		if str(want["id"]) == "first_meal" and id == "cook":
			want["progress"] = 1.0
		elif str(want["id"]) == "create" and id == "paint":
			want["progress"] = float(want["progress"]) + 1.0
		elif str(want["id"]) == "earn" and id in ["work", "job", "paint"]:
			want["progress"] = float(want["progress"]) + 1.0
	action["phase"] = "finished"
	action_finished.emit(action)
	_idle_minutes = 0.0
	_update_wants()
	_start_front()
	changed.emit()


func _apply_social(action: Dictionary) -> void:
	var target: String = str(action["target_id"])
	if not relationships.has(target):
		# World objects may prefix their unique IDs (e.g. neighbor_maya).
		for person_id: String in relationships:
			if target.contains(person_id):
				target = person_id
				break
	if not relationships.has(target):
		target = "maya"
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
				notice.emit("%s appreciates the chat, but needs time to open up." % person["name"])
		"flirt":
			if float(person["friendship"]) >= 30.0:
				person["romance"] = minf(100.0, float(person["romance"]) + 16.0)
				change = 5.0
				notice.emit("There is a spark between you and %s." % person["name"])
			else:
				change = -7.0
				notice.emit("%s seems uncomfortable. Try building a friendship first." % person["name"])
		"argue":
			change = -22.0
			person["romance"] = maxf(0.0, float(person["romance"]) - 12.0)
	if _has_trait("Outgoing") and change > 0.0:
		change *= 1.2
	person["friendship"] = clampf(float(person["friendship"]) + change, -100.0, 100.0)
	_update_relationship_status(person)


func _update_relationship_status(person: Dictionary) -> void:
	if float(person["romance"]) >= 50.0:
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
	notice.emit("Promotion! You are now a %s. §200 bonus and a higher daily salary." % str(career["title"]).to_lower())
	add_moodlet("A step forward","Confident","Your hard work is paying off.",360,4)
	remember("A promotion",str(career.title))

func choose_career(track_id:String) -> bool:
	if not CAREER_TRACKS.has(track_id):return false
	if career.get("track","studio")==track_id:return true
	for action in action_queue:
		if action.id=="job":notice.emit("Finish or cancel your shift before changing careers.");return false
	var track:Dictionary=CAREER_TRACKS[track_id]
	career={"track":track_id,"title":track.titles[0],"level":1,"performance":0.0,"salary":track.base_salary,"worked_day":int(career.worked_day)}
	remember("A new direction","Joined "+str(track.label))
	add_moodlet("New possibilities","Inspired","A new career is a chance to grow.",240,2)
	notice.emit("Your new job: %s. §%d per shift." % [career.title,career.salary])
	changed.emit()
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
		notice.emit("Day %d: household bills used your remaining §%d. Earn money with work or painting." % [day, charged])
	else:
		notice.emit("A new day. §%d paid for household bills." % charged)
	for person: Dictionary in relationships.values():
		if float(person["friendship"]) > 0.0:
			person["friendship"] = maxf(0.0, float(person["friendship"]) - 1.5)
		_update_relationship_status(person)


func _check_need_notices() -> void:
	for need_name: String in NEED_NAMES:
		if float(needs[need_name]) < 15.0 and not _warned_needs.has(need_name):
			_warned_needs[need_name] = true
			var messages: Dictionary = {"hunger": "is very hungry. A meal would help.", "energy": "is exhausted. Time for some sleep.", "hygiene": "needs a shower to feel fresh again.", "bladder": "really needs the bathroom.", "fun": "feels bored. Make time for something enjoyable.", "social": "feels lonely. Try talking to a neighbor."}
			notice.emit("%s %s" % [character["name"], messages[need_name]])
		elif float(needs[need_name]) >= 35.0:
			_warned_needs.erase(need_name)


func _choose_autonomous_action() -> void:
	_idle_minutes = 0.0
	if _targets.is_empty():
		return
	var lowest: String = ""
	var value: float = 52.0
	for need_name: String in NEED_NAMES:
		if float(needs[need_name]) < value:
			value = float(needs[need_name])
			lowest = need_name
	var candidates: Array[String] = []
	match lowest:
		"hunger": candidates = ["snack", "cook"]
		"energy": candidates = ["sleep", "nap"]
		"hygiene": candidates = ["shower"]
		"bladder": candidates = ["toilet"]
		"fun": candidates = ["paint", "read", "watch", "relax"]
		"social": candidates = ["friendly", "joke"]
	if candidates.is_empty():
		return
	if lowest == "fun" and _has_trait("Bookworm"):
		candidates = ["read", "watch", "relax"]
	for id: String in candidates:
		for target: Dictionary in _targets:
			for definition: Dictionary in get_actions_for(str(target["kind"])):
				if str(definition["id"]) == id and bool(definition["available"]):
					if queue_action(id, str(target["id"]), target["position"]):
						action_queue.back()["autonomous"] = true
					return


func _has_trait(trait_name: String) -> bool:
	return character.get("traits", []).has(trait_name)


func _create_wants() -> void:
	wants = [
		{"id": "first_meal", "label": "A taste of home", "description": "Cook your first fresh meal.", "progress": 0.0, "target": 1.0, "reward": 60, "complete": false},
		{"id": "friend", "label": "A familiar face", "description": "Build a friendship to 35.", "progress": 0.0, "target": 35.0, "reward": 80, "complete": false}
	]
	match str(character["aspiration"]):
		"Maker": wants.append({"id": "create", "label": "Make your mark", "description": "Complete and sell three paintings.", "progress": 0.0, "target": 3.0, "reward": 180, "complete": false})
		"Connected": wants.append({"id": "close_friend", "label": "Better together", "description": "Make a close friend with 65 friendship.", "progress": 0.0, "target": 65.0, "reward": 180, "complete": false})
		"Successful": wants.append({"id": "earn", "label": "On the way up", "description": "Finish three money-making activities.", "progress": 0.0, "target": 3.0, "reward": 180, "complete": false})
		_: wants.append({"id": "balanced", "label": "A little balance", "description": "Bring every need above 65.", "progress": 0.0, "target": 6.0, "reward": 180, "complete": false})


func _update_wants() -> void:
	var friendship: float = 0.0
	for person: Dictionary in relationships.values():
		friendship = maxf(friendship, float(person["friendship"]))
	for want: Dictionary in wants:
		if bool(want["complete"]):
			continue
		if str(want["id"]) in ["friend", "close_friend"]:
			want["progress"] = friendship
		elif str(want["id"]) == "balanced":
			var count: int = 0
			for need_name: String in NEED_NAMES:
				if float(needs[need_name]) >= 65.0:
					count += 1
			want["progress"] = float(count)
		if float(want["progress"]) >= float(want["target"]):
			want["complete"] = true
			want["progress"] = float(want["target"])
			satisfaction += int(want["reward"])
			funds += int(want["reward"])
			notice.emit("Want fulfilled: %s! +%d satisfaction and §%d." % [want["label"], int(want["reward"]), int(want["reward"])])


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
	return {"version": SAVE_VERSION, "character": character.duplicate(true), "needs": needs.duplicate(true), "skills": skills.duplicate(true), "relationships": relationships.duplicate(true), "career": career.duplicate(true), "wants": wants.duplicate(true), "funds": funds, "day": day, "minutes": minutes, "speed": speed, "autonomy": autonomy, "action_queue": action_queue.duplicate(true), "satisfaction": satisfaction, "bills_paid": bills_paid, "last_bill_day": last_bill_day,"moodlets":moodlets.duplicate(true),"memories":memories.duplicate(true)}


func save_game(world_data: Array = []) -> bool:
	var state: Dictionary = get_state()
	state["world"] = world_data.duplicate(true)
	var file: FileAccess = FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		notice.emit("Could not save your household. Please check available disk space.")
		return false
	file.store_string(JSON.stringify(_json_safe(state), "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		notice.emit("Saving failed. Your previous save is still available.")
		return false
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH))
	if rename_error != OK:
		notice.emit("Could not replace the save file.")
		return false
	notice.emit("Household saved. Your story will be here when you return.")
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


func restore_state(state: Dictionary) -> Dictionary:
	# Validate everything before touching the live household.
	var error: String = _validate_state(state)
	if not error.is_empty():
		return {"ok": false, "error": error}
	character = state["character"].duplicate(true)
	needs = state["needs"].duplicate(true)
	skills = state["skills"].duplicate(true)
	relationships = state["relationships"].duplicate(true)
	career = state["career"].duplicate(true)
	wants = state["wants"].duplicate(true)
	moodlets=state.get("moodlets",[]).duplicate(true)
	memories=state.get("memories",[]).duplicate(true)
	funds = int(state["funds"])
	day = int(state["day"])
	minutes = float(state["minutes"])
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
		action_queue.append(action)
	_idle_minutes = 0.0
	_warned_needs.clear()
	_start_front()
	changed.emit()
	notice.emit("Welcome home, %s." % character["name"])
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
	for person_id: String in ["maya", "leo"]:
		var person: Variant = state["relationships"].get(person_id)
		if not person is Dictionary or not person.get("name") is String or not person.get("status") is String or not _number_in_range(person.get("friendship"), -100.0, 100.0) or not _number_in_range(person.get("romance"), 0.0, 100.0):
			return "Save contains an invalid relationship."
	var job: Dictionary = state["career"]
	if not job.get("title") is String or not _number_in_range(job.get("level"), 1.0, 5.0) or not _number_in_range(job.get("performance"), 0.0, 1000.0) or not _number_in_range(job.get("salary"), 0.0, 1000000.0) or not _number_in_range(job.get("worked_day"), 0.0, 1000000.0):
		return "Save contains an invalid career."
	if not _number_in_range(state.get("funds"), 0.0, 1000000000.0) or not _number_in_range(state.get("day"), 1.0, 1000000.0) or not _number_in_range(state.get("minutes"), 0.0, 1439.99999):
		return "Save contains an invalid clock or funds."
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
	if state.get("action_queue", []).size() > MAX_QUEUE:
		return "Save contains too many queued actions."
	for action: Variant in state.get("action_queue", []):
		if not action is Dictionary or not _actions.has(str(action.get("id", ""))):
			return "Save contains an invalid action."
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
