extends RefCounted
class_name LifeWantsManager

## Manages moment-to-moment whims (desires) and psychological fears,
## mirroring the Sims 4 Wants & Fears / Whims system.
## Lifelets have 3 active whims:
## 1. Need-driven / Well-being whim (left)
## 2. Trait / Personality whim (middle)
## 3. Emotional whim (right, driven by current emotion)
## Plus optional active fears developed from severe stress or grief.

const VERSION := 1
const MAX_WHIMS := 3

const WHIMS := {
	# Need-based whims
	"satisfy_hunger": {
		"id": "satisfy_hunger",
		"label": "Satisfy hunger",
		"description": "Grab a quick snack or cook a warm meal.",
		"type": "need",
		"action_tags": ["cook", "snack", "eat_meal"],
		"reward": 25
	},
	"soothing_shower": {
		"id": "soothing_shower",
		"label": "Take a warm shower",
		"description": "Clean up and freshen your hygiene.",
		"type": "need",
		"action_tags": ["shower", "wash_hands"],
		"reward": 25
	},
	"restful_sleep": {
		"id": "restful_sleep",
		"label": "Get some rest",
		"description": "Sleep in a cozy bed or take a restoring nap.",
		"type": "need",
		"action_tags": ["sleep", "nap"],
		"reward": 30
	},
	"have_fun": {
		"id": "have_fun",
		"label": "Have some fun",
		"description": "Unwind with painting, dancing, games, or music.",
		"type": "need",
		"action_tags": ["paint", "dance", "play_chess", "play_piano", "watch", "play_games"],
		"reward": 25
	},
	"social_chat": {
		"id": "social_chat",
		"label": "Talk with someone",
		"description": "Share a warm conversation with a housemate or friend.",
		"type": "need",
		"action_tags": ["chat", "friendly", "joke", "deep_talk", "compliment", "host_a_chat"],
		"reward": 30
	},
	
	# Trait-based whims
	"creative_painting": {
		"id": "creative_painting",
		"label": "Paint a canvas",
		"description": "Channel creative energy onto a fresh canvas.",
		"type": "trait",
		"trait": "Creative",
		"action_tags": ["paint", "sketch_for_fun"],
		"reward": 45
	},
	"culinary_creation": {
		"id": "culinary_creation",
		"label": "Cook a fresh meal",
		"description": "Step up to the stove and prepare a delicious recipe.",
		"type": "trait",
		"trait": "Foodie",
		"action_tags": ["cook", "experiment_recipe"],
		"reward": 45
	},
	"active_workout": {
		"id": "active_workout",
		"label": "Work up a sweat",
		"description": "Energize your body with a jog, run or stretch.",
		"type": "trait",
		"trait": "Active",
		"action_tags": ["jog", "morning_run", "stretch", "warm_up", "push_through"],
		"reward": 40
	},
	"neat_cleaning": {
		"id": "neat_cleaning",
		"label": "Tidy up",
		"description": "Mop puddles or wash plates to keep the home spotless.",
		"type": "trait",
		"trait": "Neat",
		"action_tags": ["mop_puddle", "clean_plate", "deep_clean", "plant_wee"],
		"reward": 35
	},
	"outgoing_mingle": {
		"id": "outgoing_mingle",
		"label": "Connect with others",
		"description": "Spend quality social time sharing stories and laughs.",
		"type": "trait",
		"trait": "Outgoing",
		"action_tags": ["host_a_chat", "chat", "deep_talk", "hug", "friendly"],
		"reward": 45
	},
	"bookworm_reading": {
		"id": "bookworm_reading",
		"label": "Read deeply",
		"description": "Immerse yourself in literature and study.",
		"type": "trait",
		"trait": "Bookworm",
		"action_tags": ["read", "deep_read", "study"],
		"reward": 40
	},
	
	# Emotion-based whims
	"inspired_expression": {
		"id": "inspired_expression",
		"label": "Create while Inspired",
		"description": "Ride the wave of inspiration to paint, sketch, or play piano.",
		"type": "emotion",
		"emotion": "Inspired",
		"action_tags": ["paint", "play_piano", "sketch_for_fun"],
		"reward": 50
	},
	"energized_exercise": {
		"id": "energized_exercise",
		"label": "Burn off energy",
		"description": "Put that high energy into athletic action.",
		"type": "emotion",
		"emotion": "Energized",
		"action_tags": ["jog", "morning_run", "stretch", "dance"],
		"reward": 40
	},
	"playful_laughter": {
		"id": "playful_laughter",
		"label": "Spread some joy",
		"description": "Tell a funny joke or play a lively game.",
		"type": "emotion",
		"emotion": "Playful",
		"action_tags": ["joke", "play_games", "play_toys"],
		"reward": 35
	},
	"focused_intellect": {
		"id": "focused_intellect",
		"label": "Sharpen your mind",
		"description": "Play chess, study, or research with deep focus.",
		"type": "emotion",
		"emotion": "Focused",
		"action_tags": ["play_chess", "study", "read"],
		"reward": 45
	},
	"flirty_romance": {
		"id": "flirty_romance",
		"label": "Share romantic warmth",
		"description": "Flirt, hug, or embrace your partner.",
		"type": "emotion",
		"emotion": "Flirty",
		"action_tags": ["flirt", "hug", "kiss", "deep_talk", "try_for_baby"],
		"reward": 50
	},
	"sad_comfort": {
		"id": "sad_comfort",
		"label": "Seek comfort & remember",
		"description": "Mourn at a memorial, leave flowers, or share memories with loved ones.",
		"type": "emotion",
		"emotion": "Sad",
		"action_tags": ["mourn", "leave_flowers", "remember_passed", "comfort_loss", "share_memories", "cry_in_bed"],
		"reward": 60
	}
}

const FEARS := {
	"fear_of_failure": {
		"id": "fear_of_failure",
		"label": "Fear of Failure",
		"description": "Haunted by doubts about performance. Conquered by completing a work shift or mastering a creative work.",
		"cure_tags": ["career_day", "job", "paint", "work"],
		"reward": 150
	},
	"fear_of_loss": {
		"id": "fear_of_loss",
		"label": "Fear of Being Left Alone",
		"description": "Deeply affected by loss in the household. Conquered by comforting a loved one or having a heart-to-heart talk.",
		"cure_tags": ["comfort_loss", "share_memories", "deep_talk", "hug"],
		"reward": 150
	},
	"fear_of_exhaustion": {
		"id": "fear_of_exhaustion",
		"label": "Fear of Burnout",
		"description": "Exhausted from constant demands. Conquered by taking a full night of peaceful sleep.",
		"cure_tags": ["sleep"],
		"reward": 120
	}
}

static func fresh_state(character: Dictionary = {}, mood_label: String = "Fine", needs: Dictionary = {}, enabled: bool = true) -> Dictionary:
	var state: Dictionary = {
		"version": VERSION,
		"enabled": enabled,
		"whims": [],
		"fears": [],
		"stats": {"fulfilled": 0, "conquered_fears": 0, "total_satisfaction": 0}
	}
	if enabled:
		refresh_whims(state, character, needs, mood_label, true)
	return state

static func refresh_whims(state: Dictionary, character: Dictionary, needs: Dictionary, mood_label: String, force: bool = false) -> void:
	var current_whims: Array = state.get("whims", [])
	while current_whims.size() < MAX_WHIMS:
		current_whims.append({})
	
	# Slot 0: Need-based whim
	if force or current_whims[0].is_empty() or (not bool(current_whims[0].get("pinned", false)) and bool(current_whims[0].get("completed", false))):
		current_whims[0] = _pick_need_whim(needs)
	
	# Slot 1: Trait-based whim
	if force or current_whims[1].is_empty() or (not bool(current_whims[1].get("pinned", false)) and bool(current_whims[1].get("completed", false))):
		current_whims[1] = _pick_trait_whim(character)
	
	# Slot 2: Emotion-based whim
	if force or current_whims[2].is_empty() or (not bool(current_whims[2].get("pinned", false)) and bool(current_whims[2].get("completed", false))):
		current_whims[2] = _pick_emotion_whim(mood_label)
		
	state.whims = current_whims

static func _pick_need_whim(needs: Dictionary) -> Dictionary:
	var lowest_need: String = "hunger"
	var lowest_val: float = 100.0
	for need: String in ["hunger", "energy", "hygiene", "fun", "social"]:
		var val: float = float(needs.get(need, 75.0))
		if val < lowest_val:
			lowest_val = val
			lowest_need = need
	
	var whim_id: String = "satisfy_hunger"
	match lowest_need:
		"hunger": whim_id = "satisfy_hunger"
		"energy": whim_id = "restful_sleep"
		"hygiene": whim_id = "soothing_shower"
		"fun": whim_id = "have_fun"
		"social": whim_id = "social_chat"
	
	var def: Dictionary = WHIMS.get(whim_id, WHIMS.satisfy_hunger).duplicate(true)
	def["pinned"] = false
	def["completed"] = false
	return def

static func _pick_trait_whim(character: Dictionary) -> Dictionary:
	var traits: Array = character.get("traits", [])
	var candidate_ids: Array[String] = []
	for tid: String in WHIMS:
		var w: Dictionary = WHIMS[tid]
		if str(w.get("type", "")) == "trait" and traits.has(str(w.get("trait", ""))):
			candidate_ids.append(tid)
	
	var chosen_id: String = "creative_painting"
	if not candidate_ids.is_empty():
		chosen_id = candidate_ids[0]
	else:
		chosen_id = "culinary_creation"
	
	var def: Dictionary = WHIMS.get(chosen_id, WHIMS.culinary_creation).duplicate(true)
	def["pinned"] = false
	def["completed"] = false
	return def

static func _pick_emotion_whim(mood_label: String) -> Dictionary:
	var candidate_id: String = "playful_laughter"
	for tid: String in WHIMS:
		var w: Dictionary = WHIMS[tid]
		if str(w.get("type", "")) == "emotion" and str(w.get("emotion", "")).to_lower() == mood_label.to_lower():
			candidate_id = tid
			break
	if candidate_id == "playful_laughter" and mood_label.to_lower() != "playful":
		match mood_label.to_lower():
			"inspired": candidate_id = "inspired_expression"
			"energized": candidate_id = "energized_exercise"
			"focused": candidate_id = "focused_intellect"
			"flirty": candidate_id = "flirty_romance"
			"sad": candidate_id = "sad_comfort"
			_: candidate_id = "inspired_expression"
			
	var def: Dictionary = WHIMS.get(candidate_id, WHIMS.inspired_expression).duplicate(true)
	def["pinned"] = false
	def["completed"] = false
	return def

static func evaluate_action(state: Dictionary, action_id: String) -> Dictionary:
	var result: Dictionary = {"fulfilled": false, "reward": 0, "cured_fear": false, "fear_reward": 0}
	if not bool(state.get("enabled", false)): return result
	
	# Check active whims
	var whims: Array = state.get("whims", [])
	for i in range(whims.size()):
		var w: Dictionary = whims[i]
		if w.is_empty() or bool(w.get("completed", false)): continue
		var tags: Array = w.get("action_tags", [])
		if tags.has(action_id):
			w["completed"] = true
			var rew: int = int(w.get("reward", 25))
			result["fulfilled"] = true
			result["whim"] = w
			result["reward"] = rew
			result["moodlet"] = {
				"label": "Fulfilled Desire",
				"emotion": "Happy",
				"description": "Fulfilling your personal daydreams brings a steady sense of happiness.",
				"duration": 240.0,
				"strength": 1
			}
			state["stats"]["fulfilled"] = int(state.get("stats", {}).get("fulfilled", 0)) + 1
			state["stats"]["total_satisfaction"] = int(state.get("stats", {}).get("total_satisfaction", 0)) + rew
			break
			
	# Check active fears
	var fears: Array = state.get("fears", [])
	for i in range(fears.size()):
		var fid: String = str(fears[i])
		if FEARS.has(fid):
			var fdef: Dictionary = FEARS[fid]
			var cure_tags: Array = fdef.get("cure_tags", [])
			if cure_tags.has(action_id):
				fears.remove_at(i)
				var frew: int = int(fdef.get("reward", 150))
				result["cured_fear"] = true
				result["fear"] = fdef
				result["fear_reward"] = frew
				result["fear_moodlet"] = {
					"label": "Conquered Fear",
					"emotion": "Confident",
					"description": "Stood tall and overcame the inner doubt! You feel stronger than ever.",
					"duration": 360.0,
					"strength": 2
				}
				state["stats"]["conquered_fears"] = int(state.get("stats", {}).get("conquered_fears", 0)) + 1
				state["stats"]["total_satisfaction"] = int(state.get("stats", {}).get("total_satisfaction", 0)) + frew
				break
				
	return result

static func pin_whim(state: Dictionary, index: int, pinned: bool) -> bool:
	var whims: Array = state.get("whims", [])
	if index < 0 or index >= whims.size(): return false
	whims[index]["pinned"] = pinned
	return true

static func dismiss_whim(state: Dictionary, index: int, character: Dictionary, needs: Dictionary, mood_label: String) -> bool:
	var whims: Array = state.get("whims", [])
	if index < 0 or index >= whims.size(): return false
	if bool(whims[index].get("pinned", false)): return false # Pinned whims cannot be dismissed
	
	if index == 0:
		whims[0] = _pick_need_whim(needs)
	elif index == 1:
		whims[1] = _pick_trait_whim(character)
	else:
		whims[2] = _pick_emotion_whim(mood_label)
	return true

static func add_fear(state: Dictionary, fear_id: String) -> bool:
	if not FEARS.has(fear_id): return false
	var fears: Array = state.get("fears", [])
	if fears.has(fear_id): return false
	fears.append(fear_id)
	state["fears"] = fears
	return true

static func validate_save(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not _valid_counter(data.get("version")) or data.version != VERSION: return false
	if not data.get("enabled") is bool: return false
	if not data.get("whims") is Array or not data.get("fears") is Array: return false
	if data.whims.size() != (MAX_WHIMS if data.enabled else 0): return false
	var slot_types: Array[String] = ["need", "trait", "emotion"]
	for index: int in range(data.whims.size()):
		var whim: Variant = data.whims[index]
		if not whim is Dictionary or not whim.get("id") is String: return false
		if not WHIMS.has(whim.id): return false
		var definition: Dictionary = WHIMS[whim.id]
		if str(definition.type) != slot_types[index]: return false
		if not whim.get("pinned") is bool or not whim.get("completed") is bool: return false
		# Action matching, labels and rewards come from the catalogue; accepting
		# arbitrary saved definitions could crash completion or invent rewards.
		for key: String in definition:
			if not whim.has(key): return false
			var saved: Variant = whim[key]
			var expected: Variant = definition[key]
			if expected is Array:
				if not saved is Array or saved.size() != expected.size(): return false
				for tag_index: int in range(expected.size()):
					if not saved[tag_index] is String or saved[tag_index] != str(expected[tag_index]): return false
			elif expected is int:
				if not _valid_counter(saved) or saved != expected: return false
			elif not saved is String or saved != str(expected): return false
	var seen_fears: Array[String] = []
	for fear: Variant in data.fears:
		if not fear is String or not FEARS.has(fear) or seen_fears.has(fear): return false
		seen_fears.append(fear)
	if not data.get("stats") is Dictionary: return false
	for key: String in ["fulfilled", "conquered_fears", "total_satisfaction"]:
		if not _valid_counter(data.stats.get(key)): return false
	return true

static func _valid_counter(value: Variant) -> bool:
	if not (value is int or value is float): return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= 9007199254740991.0 and number == floorf(number)
