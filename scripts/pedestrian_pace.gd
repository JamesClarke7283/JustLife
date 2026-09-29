extends RefCounted
class_name LifePedestrianPace
## One natural walking pace for everybody who strolls the sidewalk: the four
## resident neighbours, the children, teens, adults, elders and dogs who pass the
## home. Speeds are metres per real second at Normal speed; the gait clock and
## the distance walked share one factor, so a walker's feet always land where
## their body has moved instead of skating.
##
## Fast speeds keep that agreement. The gait clock in `LifeActor.animate` stops
## at three times its authored rate, so a pedestrian's ground speed stops there
## too: at 8x the world's dwell and rest timers still run eight times faster,
## but a walker covers ground at the fastest pace the legs can actually
## animate. Pure policy: no nodes, no clock.

## Comfortable strolling speeds. A child's short legs and an elder's careful
## steps are slower than a teenager's brisk walk; dogs trot beside their people.
## Adults keep the pace the resident neighbours have always walked.
const SPEED: Dictionary = {
	"baby": 0.0, "child": 0.95, "teen": 1.2, "young_adult": 1.1, "adult": 1.1,
	"elder": 0.75, "dog": 1.25, "cat": 1.0,
	# A neighbour wandering the front rooms of a home at a slower, indoor pace.
	"indoor": 0.75,
}
## Fraction of an adult's body size, from the authored heights (1.18, 1.55, 1.76
## and 1.72 m). Step length follows leg length, so the same joint swing covers
## proportionally less ground on a smaller body.
const BODY_SCALE: Dictionary = {"child": 0.67, "teen": 0.88, "young_adult": 1.0, "adult": 1.0, "elder": 0.98, "indoor": 1.0}
## The ground speed one authored gait cycle covers on an adult body, and on a
## dog. `LifeTraversal.WALK_SPEED` and `LifePetBehavior.WALK_SPEED` are the same
## numbers: those are the paces the gait clocks were tuned against.
const HUMAN_GAIT_SPEED: float = 1.6
const DOG_GAIT_SPEED: float = 1.4
## `LifeActor.animate` and `LifePetActor.animate` clamp their clocks to this.
const FASTEST_CLOCK: float = 3.0


## Walking speed in metres per real second at Normal speed.
static func metres_per_second(kind: String) -> float:
	return float(SPEED.get(kind, SPEED.adult))


## How much of the game-speed multiplier a walker's movement and gait clock can
## follow. Paused stays paused; 1x, 3x and 8x walk at 1x, 3x and 3x.
static func clock_scale(game_speed: float) -> float:
	if not is_finite(game_speed):
		return 0.0
	return clampf(game_speed, 0.0, FASTEST_CLOCK)


## Distance a walker of this kind covers in `delta` real seconds.
static func distance(kind: String, delta: float, game_speed: float) -> float:
	return metres_per_second(kind) * maxf(0.0, delta) * clock_scale(game_speed)


## The `speed_factor` to hand `LifeActor.animate` (or the `speed` of
## `LifePetActor.animate`) so its gait cycle covers exactly the ground the walker
## moves: the walker's speed over the pace one cycle was authored for, times
## the clock scale.
static func gait_factor(kind: String, game_speed: float) -> float:
	var reference: float = DOG_GAIT_SPEED if kind in ["dog", "cat"] else HUMAN_GAIT_SPEED * float(BODY_SCALE.get(kind, 1.0))
	return metres_per_second(kind) / reference * clock_scale(game_speed)


## The gait factor for a body of this kind that is really being moved at
## `speed` metres a second at game speed 1 (a dog on a lead moves at its walker's
## pace, not its own), so its feet cover the ground it does.
static func gait_factor_at(kind: String, speed: float, game_speed: float) -> float:
	var reference: float = DOG_GAIT_SPEED if kind in ["dog", "cat"] else HUMAN_GAIT_SPEED * float(BODY_SCALE.get(kind, 1.0))
	return speed / reference * clock_scale(game_speed)


## Ground covered by one full gait cycle of a walker of this kind, in metres.
## It depends only on the body, never on speed or age pace: that is what keeps
## the feet planted, and what a no-skating check compares against.
static func stride_length(kind: String) -> float:
	# LifeActor's cycle advances 7.6 rad per second at factor 1; a dog's legs
	# advance 0.9 (clock) x 0.85 (species length) x 6 rad per second.
	if kind in ["dog", "cat"]:
		return DOG_GAIT_SPEED * TAU / (0.9 * 0.85 * 6.0)
	return HUMAN_GAIT_SPEED * float(BODY_SCALE.get(kind, 1.0)) * TAU / 7.6
