extends RefCounted
class_name TestFurnishing
## The UI-faithful path for driving a member's furnishing interaction in a
## probe or suite: queue through queue_interaction with the live item node, so
## the action carries the real approach position. A bare
## sim.queue_action(id, target) without a position plans a zero-destination
## route and is correctly refused by the traversal planner.

static func live_item(app: Node, item_id: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.id) == item_id:
			return item
	return {}

## member_id defaults to the player: queue_interaction always queues for the
## bound member, so housemate-driven interactions need their own flow.
static func queue_member_action(app: Node, item: Dictionary, action_id: String, member_id: String = "player") -> bool:
	var node: Node3D = item.get("node")
	if node == null:
		return false
	var size: Vector2 = item.get("size") if item.get("size") is Vector2 else Vector2(1, 1)
	app.queue_interaction({"id": str(item.id), "kind": str(item.kind), "node": node, "size": size}, action_id)
	return not app.household.member_sim("player").get_current_action().is_empty()
