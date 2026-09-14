extends RefCounted
class_name LifeResidentCatalogue
## Identity metadata shared by save validation and live resident controllers.
const IDS: Array[String] = ["maya", "leo", "priya", "tom"]
const PEOPLE = {
	# Compact silhouette, curls and a teal jacket with warm cream trousers.
	"maya": {
		"name":"Maya Chen", "home":"maya_home", "frame":0, "hair":2,
		"face_round":.24, "jaw_strong":.18, "nose_wide":.26, "eye_spacing":.61,
		"nose_length":-.42, "lip_fullness":.24, "brow_arch":.48, "chin_length":-.32,
		"face_length":-.48, "mouth_width":.32, "nose_bridge":-.38,
		"body_scale":.91, "height_scale":.95, "outfit":1, "bottom":0,
		"skin_color":"b77e58", "hair_color":"2a2420", "eye_color":"65452e",
		"top_color":"417a71", "bottom_color":"eadfc9", "shoe_color":"573c37",
		"traits":["Creative","Geek"], "fun":{"work":35,"off":78},
		"lane":7.8, "side":-1, "walk_wait":0.0, "rest_wait":24.0, "visit_wait":3.0, "home_wait":48.0,
	},
	# The tallest neighbor: angular face, cropped auburn hair and sporty separates.
	"leo": {
		"name":"Leo Morgan", "home":"leo_home", "frame":1, "hair":0,
		"face_round":.12, "jaw_strong":.82, "nose_wide":.31, "eye_spacing":.24,
		"nose_length":.52, "lip_fullness":-.36, "brow_arch":-.28, "chin_length":.58,
		"face_length":.65, "mouth_width":-.28, "nose_bridge":.62,
		"body_scale":1.12, "height_scale":1.07, "outfit":3, "bottom":1,
		"skin_color":"e7b98f", "hair_color":"89563a", "eye_color":"58758c",
		"top_color":"7195b3", "bottom_color":"39444f", "shoe_color":"ece4d5",
		"traits":["Active","Cheerful"], "fun":{"work":42,"off":82},
		"lane":8.2, "side":1, "walk_wait":24.0, "rest_wait":72.0, "visit_wait":7.0, "home_wait":72.0,
	},
	# A soft, fuller silhouette, long waves and a red cardigan over olive trousers.
	"priya": {
		"name":"Priya Sharma", "home":"priya_home", "frame":0, "hair":6,
		"face_round":.62, "jaw_strong":.12, "nose_wide":.68, "eye_spacing":.30,
		"nose_length":.16, "lip_fullness":.62, "brow_arch":.28, "chin_length":-.48,
		"face_length":.20, "mouth_width":.55, "nose_bridge":.16,
		"body_scale":1.07, "height_scale":1.01, "outfit":2, "bottom":0,
		"skin_color":"9c6b47", "hair_color":"1d1712", "eye_color":"49342b",
		"top_color":"a3554f", "bottom_color":"3c4a3a", "shoe_color":"3b302c",
		"traits":["Bookworm","Creative"], "fun":{"work":38,"off":80},
		"lane":8.5, "side":-1, "walk_wait":48.0, "rest_wait":36.0, "visit_wait":5.0, "home_wait":60.0,
		"routine":{"place":"the library","venue":"library","from":10.0,"to":16.0,"anchor_kind":"bookshelf"},
	},
	# A shorter broad frame, rounded face, tied hair and an outdoor hoodie palette.
	"tom": {
		"name":"Tom Alvarez", "home":"tom_home", "frame":1, "hair":3,
		"face_round":.76, "jaw_strong":.40, "nose_wide":.82, "eye_spacing":.72,
		"nose_length":-.28, "lip_fullness":.36, "brow_arch":-.44, "chin_length":.12,
		"face_length":-.62, "mouth_width":-.48, "nose_bridge":-.52,
		"body_scale":.98, "height_scale":.97, "outfit":4, "bottom":0,
		"skin_color":"c98d5f", "hair_color":"2e2620", "eye_color":"77805b",
		"top_color":"5b6d8f", "bottom_color":"a48b6b", "shoe_color":"45362c",
		"traits":["Outgoing","Loves the outdoors"], "fun":{"work":30,"off":74},
		"lane":8.8, "side":1, "walk_wait":36.0, "rest_wait":54.0, "visit_wait":6.0, "home_wait":66.0,
		"routine":{"place":"the community garden","venue":"park","from":13.0,"to":17.0,"anchor_kind":"plant"},
		"morning":{"from":7.0,"to":9.0},
	},
}

static func routine_active(person: Dictionary, weekday: bool, minutes: float) -> bool:
	# A resident keeps an off-lot routine on weekdays: Priya reads at the
	# library, Tom tends his garden plot. Outside the window they are home or
	# out walking as usual.
	var routine: Dictionary = person.get("routine", {})
	if routine.is_empty() or not weekday:return false
	return minutes >= float(routine["from"]) * 60.0 and minutes < float(routine["to"]) * 60.0

static func routine_until(person: Dictionary) -> float:
	var routine: Dictionary = person.get("routine", {})
	return float(routine["to"]) * 60.0

static func routine_morning_active(person: Dictionary, weekday: bool, minutes: float) -> bool:
	# A resident's second beat: a morning window spent out on the lane.
	var morning: Dictionary = person.get("morning", {})
	if morning.is_empty() or not weekday:return false
	return minutes >= float(morning["from"]) * 60.0 and minutes < float(morning["to"]) * 60.0
