extends RefCounted
class_name LifeWetness
## Being wet: what a swim or a soak leaves on a Lifelet and how it comes off.
##
## Coming out of a pool or hot tub a Lifelet is soaked (1.0). It drips for a short
## while, then merely damp, and dries on its own clock — slowly in the air, faster
## wrapped in a towel, faster still while rubbing down with it. A Lifelet who sits
## on padded furniture while still damp for too long leaves a puddle under the
## seat, which somebody has to mop.
##
## Pure static policy: no Nodes, no clock, no world. `LifeSim` owns the number,
## `LifeWaterFlow` owns the towels and puddles that follow from it.

const SOAKED: float = 1.0
## Game minutes for a soaked Lifelet to air dry, to dry wrapped in a towel, and
## to dry while actively rubbing down with one.
const AIR_DRY_MINUTES: float = 45.0
const TOWEL_DRY_MINUTES: float = 8.0
const RUB_DRY_MINUTES: float = 4.0
## Above this wetness the body still drips. Air drying gets below it in about
## twenty game minutes, which is a short, visible shedding of water.
const DRIP_ABOVE: float = 0.55
## A damp seat: still this wet after sitting this long on a padded seat leaves a puddle.
const PUDDLE_ABOVE: float = 0.2
const PUDDLE_AFTER_MINUTES: float = 6.0

## The furnishings a swim or a soak happens at. All of them leave a Lifelet wet.
const WATER_KINDS: Array[String] = ["pool", "hot_tub", "pool_ring", "pool_noodle", "pool_slide", "pool_ladder", "pool_light"]
## Indoor padded furniture and the garden's own seats. Sitting on any of these while wet
## soaks the cushion, which is what the puddle stands for.
const SOFT_SEATS: Array[String] = ["sofa", "loveseat", "armchair", "bench", "garden_table", "outdoor_swing"]
## What a towel is fetched from: a rack holds some, a loose beach towel is one.
const TOWEL_SOURCES: Array[String] = ["towel_rack", "beach_towel"]
const DRY_OFF_ID: String = "dry_off"
const DRY_SIT_ID: String = "dry_sit"


static func is_water_kind(kind: String) -> bool:
	return kind in WATER_KINDS


static func is_soft_seat(kind: String) -> bool:
	return kind in SOFT_SEATS


static func is_towel_source(kind: String) -> bool:
	return kind in TOWEL_SOURCES


## How much wetness a game minute removes.
static func dry_rate(towel_wrapped: bool, rubbing: bool = false) -> float:
	if rubbing: return SOAKED / RUB_DRY_MINUTES
	return SOAKED / (TOWEL_DRY_MINUTES if towel_wrapped else AIR_DRY_MINUTES)


static func drips(wetness: float) -> bool:
	return wetness > DRIP_ABOVE


static func damp(wetness: float) -> bool:
	return wetness > 0.0


## Game minutes a Lifelet still needs, wrapped in a towel, before they are dry.
static func minutes_to_dry(wetness: float) -> float:
	return maxf(0.0, wetness) * TOWEL_DRY_MINUTES
