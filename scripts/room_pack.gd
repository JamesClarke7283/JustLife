extends RefCounted
## Turns a room pack's room-relative layout (`LifeCatalog.room_pack_layout`) into
## lot positions for the room that was actually built: its size, where it
## stands and which wall carries the doorway. Pure policy: no Nodes, no wallet.

const WALL_HALF: float = .07
const CLEARANCE: float = .06

## The yaw that turns "walking in, toward the back wall" into the lot's axes.
static func back_yaw(door: String) -> float:
	match door:
		"south": return PI
		"west": return PI * .5
		"east": return -PI * .5
	return 0.0

static func to_world(area: Rect2, door: String, local: Vector2) -> Vector2:
	var yaw: float = back_yaw(door)
	return area.get_center() + Vector2(local.x * cos(yaw) + local.y * sin(yaw), -local.x * sin(yaw) + local.y * cos(yaw))

## Half the room's inside extent across (x) and deep (y), as seen walking in.
static func half_extents(area: Rect2, door: String) -> Vector2:
	var across: bool = door in ["north", "south"]
	return Vector2(area.size.x if across else area.size.y, area.size.y if across else area.size.x) * .5

const FACING: Dictionary = {"door": Vector2(0, -1), "back": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}

## The catalogue rotation, in degrees, that turns a piece's front toward `facing`.
static func facing_degrees(door: String, facing: String) -> float:
	var local: Vector2 = FACING.get(facing, Vector2(0, -1))
	var world: Vector2 = to_world(Rect2(Vector2.ZERO, Vector2.ZERO), door, local)
	return snappedf(rad_to_deg(atan2(world.x, world.y)), 90.0)

## Every piece of the pack as a placement request. Floor pieces carry their lot
## position and rotation; wall pieces carry a point just inside the wall they
## hang on, for the world's own wall and window snapping to finish.
static func plan(kind: String, area: Rect2, door: String) -> Array:
	var half: Vector2 = half_extents(area, door)
	var out: Array = []
	for row: Dictionary in LifeCatalog.room_pack_layout(kind):
		var piece: String = str(row.kind)
		if not LifeCatalog.ITEMS.has(piece): continue
		var data: Dictionary = LifeCatalog.get_item(piece)
		var request: Dictionary = {"kind": piece, "style": str(row.get("style", "")), "color": str(row.get("color", "")), "size": str(row.get("size", ""))}
		if row.has("wall"):
			var along: float = float(row.get("along", 0.0))
			var local: Vector2
			match str(row.wall):
				"left": local = Vector2(-(half.x - .3), along * (half.y - .6))
				"right": local = Vector2(half.x - .3, along * (half.y - .6))
				"door": local = Vector2(along * (half.x - .6), -(half.y - .3))
				_: local = Vector2(along * (half.x - .6), half.y - .3)
			request["wall"] = str(row.wall)
			request["point"] = to_world(area, door, local)
		else:
			var footprint: Vector2 = LifeCatalogVariants.footprint(data, request.size)
			var facing: String = str(row.get("facing", "door"))
			var extent: Vector2 = footprint if facing in ["door", "back"] else Vector2(footprint.y, footprint.x)
			var reach: Vector2 = half - Vector2.ONE * WALL_HALF - extent * .5 - Vector2.ONE * CLEARANCE
			var local := Vector2(float(row.get("x", 0.0)) * maxf(0.0, reach.x), float(row.get("z", 0.0)) * maxf(0.0, reach.y))
			request["point"] = to_world(area, door, local)
			request["rotation"] = facing_degrees(door, facing)
		out.append(request)
	return out
