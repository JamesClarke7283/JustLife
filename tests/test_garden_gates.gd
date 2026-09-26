extends SceneTree
## Gates sit on the same edge as a fence panel, and the wide gate is a double.

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var single: Dictionary = LifeCatalog.get_item("garden_gate")
	var wide: Dictionary = LifeCatalog.get_item("garden_gate_double")
	check(int(single.price) == 40 and single.size.x == 1.0, "A single gate is one metre wide and costs £40.")
	check(int(wide.price) == 70 and wide.size.x == 2.0, "A double gate is two metres wide and costs £70.")
	check(is_equal_approx(single.size.y, LifeCatalog.get_item("fence").size.y), "A gate is as thick as the fence it meets.")
	check(LifeCatalog.passable("garden_gate") and LifeCatalog.passable("garden_gate_double"), "People can walk through a gate.")
	var fence := Rect2(0, 0, 2, .12)
	var against := Rect2(2, 0, 1, .12)
	var overlapping := Rect2(1.5, 0, 1, .12)
	check(not LifeCatalog.blocks_neighbor(against, fence, "garden_gate", "fence"), "A gate may sit flush against the end of a fence.")
	check(LifeCatalog.blocks_neighbor(overlapping, fence, "garden_gate", "fence"), "A gate may not stand inside a fence panel.")
	check(LifeCatalog.blocks_neighbor(against, fence, "chair", "fence"), "An ordinary furnishing still keeps a gap.")
	print("GARDEN_GATES ", checks, " assertions; ", failures, " failures")
	quit(1 if failures else 0)
