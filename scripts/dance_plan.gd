extends RefCounted
class_name LifeDancePlan
## A shared dance at one music player: pure rules only.
##
## The household owns the session, the clock and the save; this module names
## the action, the token, the cap and the ring of standing spots around the
## record player. No nodes, no signals, no global randomness. The shape mirrors
## scripts/baby_plan.gd, which is the pair form of the same idea.

const ACTION_ID: String = "dance_together"
const SESSION_KIND: String = "dance"
const ROLE: String = "dancer"
const TOKEN_PREFIX: String = "dance_"
## The activity lasts exactly as long as the solo record, and each dancer gains
## the solo dance's own numbers through the same action definition.
const DURATION: float = 35.0
const MAX_DANCERS: int = 5
## Two dancers closer than this would stand in one body.
const MIN_SPACING: float = .5

## The ring of local offsets a group dance stands on: one spot in front of the
## player for the first dancer, then the rest spread around it at an increasing
## radius. The caller snaps each to real clear floor and refuses a spot that
## another furnishing already occupies.
static func ring_offsets(count: int) -> Array[Vector3]:
	if count <= 0: return []
	if count == 1: return [Vector3(0,.16,.86)]
	var offsets: Array[Vector3] = []
	var radius: float = .86 + .22 * float(count - 1)
	for index: int in count:
		var angle: float = -PI * .5 + TAU * float(index) / float(count)
		offsets.append(Vector3(cos(angle) * radius,.16,sin(angle) * radius))
	return offsets

## Whether these ids name a legal group: at least one, at most MAX_DANCERS,
## no duplicates, and every id a real household member.
static func group_error(member_ids: Array, known_ids: Array) -> String:
	if member_ids.is_empty(): return "Choose at least one Lifelet to dance with."
	var unique: Array = []
	for id: Variant in member_ids:
		var member_id: String = str(id)
		if unique.has(member_id): continue
		if not known_ids.has(member_id): return "That Lifelet is not part of this household."
		unique.append(member_id)
	if unique.size() > MAX_DANCERS: return "Only five Lifelets fit around the record player. Start the dance with fewer."
	return ""

static func session_kind(session: Dictionary) -> String:
	return str(session.get("kind",""))
