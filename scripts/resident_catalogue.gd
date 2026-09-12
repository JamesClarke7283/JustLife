extends RefCounted
class_name LifeResidentCatalogue
## Identity metadata shared by save validation and live resident controllers.
const IDS: Array[String] = ["maya", "leo", "priya", "tom"]
const PEOPLE={
 "maya":{"name":"Maya Chen","home":"maya_home","frame":0,"hair":2,"skin_color":"b77e58","hair_color":"2a2420","top_color":"417a71","bottom_color":"eadfc9","traits":["Creative","Geek"],"fun":{"work":35,"off":78},"lane":8.0,"side":-1,"walk_wait":0.0,"rest_wait":24.0,"visit_wait":3.0,"home_wait":48.0},
 "leo":{"name":"Leo Morgan","home":"leo_home","frame":1,"hair":0,"skin_color":"e7b98f","hair_color":"89563a","top_color":"7195b3","bottom_color":"493e37","traits":["Active","Cheerful"],"fun":{"work":42,"off":82},"lane":8.8,"side":1,"walk_wait":24.0,"rest_wait":72.0,"visit_wait":7.0,"home_wait":72.0},
 "priya":{"name":"Priya Sharma","home":"priya_home","frame":0,"hair":6,"skin_color":"9c6b47","hair_color":"1d1712","top_color":"a3554f","bottom_color":"3c4a3a","traits":["Bookworm","Creative"],"fun":{"work":38,"off":80},"lane":9.6,"side":-1,"walk_wait":48.0,"rest_wait":36.0,"visit_wait":5.0,"home_wait":60.0,"routine":{"place":"the library","from":10.0,"to":16.0}},
 "tom":{"name":"Tom Alvarez","home":"tom_home","frame":1,"hair":3,"skin_color":"c98d5f","hair_color":"2e2620","top_color":"5b6d8f","bottom_color":"6e5a44","traits":["Outgoing","Loves the outdoors"],"fun":{"work":30,"off":74},"lane":10.4,"side":1,"walk_wait":36.0,"rest_wait":54.0,"visit_wait":6.0,"home_wait":66.0,"routine":{"place":"his garden plot","from":13.0,"to":17.0}}}

static func routine_active(person: Dictionary, weekday: bool, minutes: float) -> bool:
	# A resident keeps an off-lot routine on weekdays: Priya reads at the
	# library, Tom tends his garden plot. Outside the window they are home or
	# out walking as usual.
	var routine: Dictionary = person.get("routine", {})
	if routine.is_empty() or not weekday:return false
	return minutes >= float(routine["from"]) * 60.0 and minutes < float(routine["to"]) * 60.0

static func routine_until(person: Dictionary, minutes: float) -> float:
	var routine: Dictionary = person.get("routine", {})
	return float(routine["to"]) * 60.0
