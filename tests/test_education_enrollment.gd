extends SceneTree
const Education = preload("res://scripts/education.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var result: Dictionary = Education.advance(Education.fresh("child",1),"teen",1,1080.0)
	check(result.ok and result.state.first_class_day == 2,"A birthday after class enrollment closes begins classes tomorrow.")
	var state: Dictionary = result.state
	check(Education.validate(state,"teen",1).is_empty(),"The evening enrollment state remains valid before its first class day.")
	check(not Education.actions(state,"teen",1,1080.0)[0].available and Education.actions(state,"teen",1,1080.0)[1].available,"The birthday evening still allows homework, while class begins tomorrow.")
	result = Education.complete(state,"teen",1,1125.0,"homework")
	check(result.ok and result.state.homework == 1,"Homework can be completed on the enrollment evening.")
	state = result.state
	result = Education.advance(state,"teen",2)
	check(result.ok and result.state.missed == 0,"Midnight must not mark a class missed before enrollment opened.")
	state = result.state
	check(Education.validate(JSON.parse_string(JSON.stringify(state)),"teen",2).is_empty(),"Enrollment and evening homework survive JSON round-trip.")
	result = Education.complete(state,"teen",2,660.0,"school")
	check(result.ok and result.state.attended == 1 and result.state.prepared == 1,"The first class consumes the homework prepared the previous evening.")
	state = result.state
	result = Education.advance(state,"young_adult",2,1080.0)
	check(result.ok and result.state.records[1].first_class_day == 2,"Graduation history preserves the first eligible class date.")
	check(Education.validate(JSON.parse_string(JSON.stringify(result.state)),"young_adult",2).is_empty(),"Historical first-class dates and assignments remain loadable.")
	var skipped: Dictionary = Education.advance(Education.advance(Education.fresh("child",1),"teen",1,1080.0).state,"teen",3)
	check(skipped.ok and skipped.state.missed == 1,"The first eligible class day still counts as an absence if skipped.")
	var early: Dictionary = Education.advance(Education.fresh("child",1),"teen",1,840.0)
	check(early.ok and early.state.first_class_day == 1 and Education.actions(early.state,"teen",1,840.0)[0].available,"A birthday at the final class-start time can attend that day.")
	check(Education.advance(early.state,"teen",2).state.missed == 1,"An eligible birthday class remains accountable at midnight.")
	var weekend: Dictionary = Education.advance(Education.fresh("child",5),"teen",5,1080.0)
	check(Education.advance(weekend.state,"teen",8).state.missed == 0,"Late Friday enrollment must not invent a weekend absence.")
	check(Education.advance(weekend.state,"teen",9).state.missed == 1,"The first actual school weekday is counted after a weekend.")
	var legacy: Dictionary = Education.fresh("child",1)
	legacy.erase("first_class_day")
	check(Education.validate(legacy,"child",1).is_empty() and Education.advance(legacy,"child",1).state.first_class_day == 1,"Existing saves without first-class metadata retain their original enrollment date.")
	legacy = Education.advance(Education.fresh("child",1),"teen",2).state
	legacy.erase("first_class_day")
	legacy.records[0].erase("first_class_day")
	check(Education.validate(legacy,"teen",2).is_empty() and Education.advance(legacy,"teen",2).state.records[0].first_class_day == 1,"Legacy school history is normalized without changing attendance.")
	var malformed: Dictionary = state.duplicate(true)
	malformed.first_class_day = 3
	check(not Education.validate(malformed,"teen",2).is_empty(),"A save cannot defer enrollment beyond the following calendar day.")
	malformed = state.duplicate(true)
	malformed.first_class_day = 0
	check(not Education.validate(malformed,"teen",2).is_empty(),"Classes cannot begin before enrollment.")
	for invalid: float in [-1.0,1440.0,INF,NAN]:
		check(not Education.advance(Education.fresh("child",1),"teen",1,invalid).ok,"Invalid enrollment times must fail without producing state.")
	print("ENROLLMENT TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
