extends SceneTree
## The family tree can set parent, child, and sibling, including a child's
## mother, father, or both. Shared parents make the children siblings.

var checks: int = 0
var failures: int = 0

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func _initialize() -> void:
	var home := LifeHousehold.new()
	home.new_household([
		{"name": "Ada Vale", "age_stage": "adult"},
		{"name": "Ben Vale", "age_stage": "adult"},
		{"name": "Cora Vale", "age_stage": "child"},
		{"name": "Drew Vale", "age_stage": "child"},
	])
	home.minutes = 600.0
	for member: Dictionary in home.members:
		member.sim.minutes = 600.0
	var mother := "player"
	var father := "housemate_1"
	var cora := "housemate_2"
	var drew := "housemate_3"
	var sibling: Dictionary = home.edit_family_link(cora, drew, "sibling")
	check(bool(sibling.ok), "A sibling link can be set after the day has started (%s)." % str(sibling.get("error", "")))
	check(LifeFamilyGraph.relationship(home.family_graph, cora, drew) == "siblings", "The two children are siblings.")
	var parent: Dictionary = home.edit_family_link(cora, mother, "parent")
	check(bool(parent.ok) and LifeFamilyGraph.relationship(home.family_graph, cora, mother) == "parent", "The viewed child can be given a parent.")
	var child_link: Dictionary = home.edit_family_link(mother, drew, "child")
	check(bool(child_link.ok) and LifeFamilyGraph.relationship(home.family_graph, mother, drew) == "child", "A parent can be given a child.")
	var both: Dictionary = home.assign_child_parents(cora, mother, father)
	check(bool(both.ok), "A child can have both a mother and a father (%s)." % str(both.get("error", "")))
	home.assign_child_parents(drew, mother, father)
	check(LifeFamilyGraph.relationship(home.family_graph, cora, mother) == "parent", "The mother is Cora's parent.")
	check(LifeFamilyGraph.relationship(home.family_graph, cora, father) == "parent", "The father is Cora's parent.")
	check(LifeFamilyGraph.relationship(home.family_graph, cora, drew) == "siblings", "Children who share parents are siblings.")
	var only_mother: Dictionary = home.assign_child_parents(drew, mother, "")
	check(bool(only_mother.ok) and LifeFamilyGraph.relationship(home.family_graph, drew, father) != "parent", "A father can be cleared while the mother stays.")
	home.free()
	print("FAMILY_EDIT %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
