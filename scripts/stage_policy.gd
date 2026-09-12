extends RefCounted
class_name LifeStagePolicy
## Age-stage gating for the shared action menu.
##
## Only the baby stage is filtered here: a baby is driven by a caregiver and
## cannot work, study, cook or hold a conversation. Every other stage keeps the
## behaviour it already had, so this file adds one refusal path and nothing else.
## Callers pass the raw values so the decision stays a pure function of them.

## The recovery and play set a baby keeps: sleep, eat, wash, play, be fussed over.
## The baby family authors only the casual romper, so the other wear actions are
## refused rather than offered and then rendered identically.
const BABY_ACTIONS: Array[String] = [
	"sleep", "nap", "snack", "eat_meal", "shower", "bath", "toilet", "relax",
	"play_toys", "birthday", "change_outfit",
	"wear_casual",
]

const BABY_SOCIAL_REASON: String = "A baby cannot hold a conversation yet."
const BABY_WORK_REASON: String = "Work and study come with age. A baby needs a caregiver."

static func action_error(age_stage: String, life_stage: String, action_id: String) -> String:
	if age_stage != "baby":
		return ""
	if action_id in BABY_ACTIONS:
		return ""
	if action_id in ["job", "work", "career_day", "study", "school", "school_day", "homework", "help_homework"]:
		return BABY_WORK_REASON
	if action_id in ["friendly", "joke", "deep_talk", "hug", "share_interests", "sympathize",
			"gossip", "flirt", "argue", "ask_partner", "commit", "break_up", "practice_speech"]:
		return BABY_SOCIAL_REASON
	return "A baby cannot do that yet."

static func can_use(age_stage: String, life_stage: String, action_id: String) -> bool:
	return action_error(age_stage, life_stage, action_id).is_empty()
