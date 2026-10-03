extends RefCounted
class_name LifeRoad
## The street in front of every lot, in one place. The ground drawing in
## world.gd and the vehicle planner both read these numbers, so the tarmac a
## player sees and the lanes a car drives can never drift apart; the road
## geometry test pins one to the other.
##
## Traffic keeps left, which the car doors already imply (they open on the kerb
## side, so a car facing +x has the kerb on its left): the near lane, beside the
## kerb, carries traffic towards +x and the far lane towards -x.

const SIDEWALK_Z: float = 8.5
const SIDEWALK_WIDTH: float = 1.25
const SIDEWALK_LENGTH: float = 75.0
const ROAD_LENGTH: float = 100.0
## The kerb edge of the tarmac is fixed against the lot; the road grows away from it.
const ROAD_NEAR_EDGE: float = 9.15
const ROAD_WIDTH: float = 6.6
const ROAD_CENTER_Z: float = 12.45
const ROAD_FAR_EDGE: float = 15.75
const LANE_WIDTH: float = 3.3
const LANE_NEAR_Z: float = 10.8
const LANE_FAR_Z: float = 14.1
## Where a car stands at the kerb: the venue and birth arrivals park here.
const KERB_PARK_X: float = 0.0
const KERB_PARK_Z: float = 10.25
const VAN_Z: float = 10.6
## Cars leave the view, and come into it, at this distance from the lot's centre line.
const EXIT_X: float = 26.0
## The post of the mailbox at the frontage: a car body must not drive through it.
const MAILBOX: Rect2 = Rect2(1.75, 7.6, .5, .4)


## The lane for a car heading along x: +1 the near lane, -1 the far lane.
static func lane_z(heading_sign: float) -> float:
	return LANE_NEAR_Z if heading_sign >= 0.0 else LANE_FAR_Z


## The yaw of a car driving along a lane (facing +x is +90 degrees).
static func lane_yaw(heading_sign: float) -> float:
	return PI * .5 if heading_sign >= 0.0 else -PI * .5


## Which lane a heading belongs to: +1 for eastbound (+x), -1 for westbound, 0 when
## the yaw is not along the street.
static func lane_sign_for_yaw(yaw: float) -> float:
	var along: float = sin(yaw)
	if absf(along) < .94: return 0.0
	return 1.0 if along > 0.0 else -1.0


## Whether a z lies on the tarmac.
static func on_road(z: float) -> bool:
	return z >= ROAD_NEAR_EDGE and z <= ROAD_FAR_EDGE
