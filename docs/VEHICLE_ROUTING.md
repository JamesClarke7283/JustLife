# Vehicle routing and animation

Cars used to move in a straight line along their own axis with their heading never
changing: the commute car slid 22 m out of its spot (through a hedge, over the lot's
edge or across the road onto the far verge) and played the same line backwards to
come home; the household trip car drove 21 m the same way, through the house when the
car faced it; the birth car slid 2.16 m sideways. Nothing knew where the road was,
nothing turned, no wheel moved and two cars drove straight through each other.

Now a car leaves its spot forward (or in reverse when it must), joins the lane that
matches its heading in a smooth turn, and drives out of the view along it. Coming home
is the mirror image: along the road, a turn off it, and onto the spot exactly as it was
parked. Cars sweep their real body against the house, furniture, fences, gate posts,
hedges, trees and parked cars, and queue for one another.

## Files

| File | Role |
| --- | --- |
| `scripts/road.gd` (`LifeRoad`) | The street's numbers, read by the ground drawing in `world.gd` and by the planner. |
| `scripts/vehicle_path.gd` (`LifeVehiclePath`) | A route as saveable data, Dubins words, the pace table, `state_at(path, t)`, validation. Pure. |
| `scripts/vehicle_planner.gd` (`LifeVehiclePlanner`) | Scenes, collision sweeps, `plan_departure`, `plan_arrival`, `hold_seconds`. Pure apart from `scene_from_world`. |
| `scripts/vehicle_rig.gd` (`LifeVehicleRig`) | Steering, rolling wheels and brake lights on a car node. |
| `scripts/vehicle_drive.gd` (`LifeVehicleDrive`) | The glue: plans from the world, keeps routes on the saved commute, places cars, queues, trip and birth-car drives. |

New scripts are referenced by `preload` constants, not by their `class_name`.

## The street

Traffic keeps left, as the car doors already implied (they open on the kerb side, so a
car facing +x has the kerb on its left): the **near lane**, beside the kerb, carries
traffic towards +x and the **far lane** towards -x. A car leaving a driveway turns left
onto the near lane (a short turn) or right across it onto the far lane.

The road was one lane wide (3.7 m, z 9.15 to 12.85): a car leaving a garage flush with
the frontage had no room to turn. It is now two proper lanes, **6.6 m** (z 9.15 to
15.75), growing away from the lot; the sidewalk and the lot's bounds are untouched.

| Constant | Value | Notes |
| --- | --- | --- |
| `SIDEWALK_Z`, `SIDEWALK_WIDTH` | 8.5, 1.25 | covers z 7.875 to 9.125, as before |
| `ROAD_NEAR_EDGE`, `ROAD_WIDTH`, `ROAD_FAR_EDGE` | 9.15, 6.6, 15.75 | the kerb edge does not move |
| `ROAD_CENTER_Z` | 12.45 | the centre dashes |
| `LANE_NEAR_Z`, `LANE_FAR_Z`, `LANE_WIDTH` | 10.8, 14.1, 3.3 | near lane towards +x, far lane towards -x |
| `KERB_PARK_Z` | 10.25 | the venue, birth and shared-car kerb spot, unchanged, inside the near lane |
| `VAN_Z` | 10.6 | the delivery van, unchanged, inside the near lane |
| `EXIT_X` | 26 | cars leave and enter the view at this distance from the lot's centre line |
| `MAILBOX` | Rect2(1.75, 7.6, .5, .4) | a car body cannot drive through the post |

Every older constant stays valid: the venue/birth kerb spot z 10.25, the van z 10.6, the
pedestrians' lanes (8.3 and 8.8), the sidewalk, the lot (x -18..18, z -12..9), the
police kerb stop (z 10.1) and the school bus line (z 8.55, on the sidewalk). The ground
drawing in `LifeWorld.draw_ground` reads `LifeRoad`, and `tests/test_road_geometry.gd`
pins the drawn boxes to the constants and the old street constants to their places.

## Routes

A route is JSON-safe data: `{"v": 1, "start": [x, z, yaw], "segs": [[curvature, length,
gear], ...], "v0", "v1"}` (at most ten segments, at most 320 m). A car faces
(sin yaw, cos yaw); curvature above 0 turns it left; gear is +1 forward or -1 reverse;
`v0` and `v1` are the speeds at the ends (0 means standing still: a car leaving ends
the route at lane speed, a car coming home starts it at lane speed). Integrating a
segment is exact, so the pose after any distance is a pure function of the numbers.

`state_at(path, t)` turns a route and a time into the car's pose, the front wheels'
steering angle, how far a wheel has rolled (signed), and whether it is braking. The
pace is a table built from the segments (never saved): at most 8.5 m/s, 2.2 m/s in
reverse, speed in a bend at most sqrt(3 / |k|) (about 3.2 m/s in the 3.7 m turn),
acceleration 3 m/s2, braking 3.6 m/s2, standing still at every cusp for 0.4 s. The
heading shown is the heading averaged over 0.9 m of road (tapering to nothing at the
ends so the parked pose is exact), so a bend begins without a kink; steering is the
angle for the curvature averaged over 2 m, so the wheels turn smoothly. Tests bound the
yaw rate (under 60 degrees a second) and per-frame heading change (under 2.6 degrees
at 30 fps).

## The planner

A scene is plain data made once from the world (`scene_from_world`): level-0 walls,
solid furnishings (including other parked cars and a car garage's walls), fences, the
posts of every gate, the mailbox, a far-kerb limit, extra obstacles (the food truck),
the delivery van and the school bus (street obstacles: tried with, then without, since
they move), and planting (trees as their trunks, bushes, hedges; flower beds are driven
over). The lot's back and side hedge lines are closed rectangles, so no route leaves
through a hedge; planting the car was already parked in is driven out of.

The car's body is swept every 0.4 m (every 1.6 m first, to throw out blocked routes
cheaply) as an oriented box 0.91 x 2.10 m times the size scale, plus 0.10 m of slack.
Candidates are built cheaply and tried in order of length:

* **Forward out**: a straight stub (0 to 8 m), then the shortest drivable curve (a
  straight and two arcs of the tightest turn the car can make, 3.7 m times the size
  scale) onto a pose on a lane with the nose along it, then a straight along the lane
  to the edge of the view. Both lanes are tried; the far lane costs 6 m more.
  Starting or ending a turn at once costs 2.5 m more than a short straight.
* **Reverse out**: the same, all in reverse, to a lane pose with the nose along the lane,
  one stop (the cusp), then forward. Used only when no forward route exists.
* **Gate chains**: for each gate, the route is squared up 2 or 3 m before the gate and
  held straight through it, then continues to the lane.

Arrival is the departure played backwards: a forward way in is a reverse way out
reversed (and the other way round), preceded by a straight run along the lane from the
edge of the view. It prefers coming in forward, except where that needs a loop round
the yard (more than 132 degrees of turning, or a spot whose nose points at the street):
then the car drives past the entrance, stops and reverses in. The route ends exactly on
the parked pose (position error under 1 cm, yaw under 0.5 degrees; the commute also
snaps the car to the parked transform when the route ends).

A plan costs milliseconds (typically 5 to 60 ms in headless GDScript; up to a few
hundred ms when nothing works and every candidate is tried), is deterministic, and is
computed once and kept.

### Gates

Gates are passable furnishings, so the planner adds the two posts as obstacles and lets
a body overlap the leaf only when its heading is within about 35 degrees of the leaf's
normal. A car therefore crosses a fence line only inside a gate's gap and nearly square
to it. `GateFlow` is unchanged: a car in the `driving_vehicle` group (only while it is
actually moving, never while it waits) swings the gate open before its nose arrives and
the gate shuts behind it. A car well off a gate's line (more lateral offset than a 3.7 m
turn can recover in 2 to 3 m) has no route; see the placements below.

### Queues

When a driver's boarding finishes, `LifeVehicleDrive.queue` asks `hold_seconds` how
long this car must wait, parked (or, coming home, out of sight at the edge of the view),
so that its swept body never touches a car already on the move, whose own route and
time are known. The hold is in quarter-seconds, at most 12, saved on the commute as
`depart_hold` or `return_hold`. The driver whose boarding finishes first goes first
(first in, first out); a car waiting shows "Waiting for the car ahead" and joins the
`driving_vehicle` group only when it moves. The same rule serves a car coming home while
another leaves and cars arriving together.

## Wheels

`LifeVehicleRig.attach` finds tyres by name (`tyre`, `rubber`, `Wheel...`) and hubs
(`hub`) in every car model, remembers their rest transforms, and takes the front axle
from the tyre positions. `apply(rig, steer, rolled)` steers the front pair about
each tyre's own centre and spins every wheel about the car's X axis by distance over its
radius (negative when reversing, less on a scaled car). Hubs share the pivot of the tyre
they sit on; doors (`car_entry.gd`) are children of the car node and follow. Brake and
reverse lights glow on the tail-light surfaces.

Models rigged: the ten `car_*` saloons, hatchback, estate, coupe, van, minibus, SUV,
off-roader and pickup, `juniper_car` (the shared and police car), `electric_car` and
`delivery_van`. **`car_electric.glb` is declared unrigged**: it is authored lying on its
side (its length runs along the model's Y axis, 4.2 m tall by 1.38 m long), so its wheels
have no front or rear along Z. It is driven without wheel animation; fixing the model is
a separate art task (`tests/test_vehicle_rig.gd` records the defect). The Juniper car is
2.18 m wide by 3.78 m long, a little wider and shorter than the 1.82 x 4.20 m
catalogue cars the planner sweeps; it only ever drives the kerb run, which has no
obstacles to sweep.

## Work commute

`work_commute.gd` keeps its phases (`walk`, `board`, `depart`, `away`, `return`, `exit`,
`back`). At the end of the walk it plans the way out and stores it as
`commute.drive_path`; `drive_sign` is kept (+1 when the first gear is forward). When
boarding ends it records `depart_hold` if the car must wait. The car's pose in `depart`
is `state_at(drive_path, time - depart_hold)`, so a paused or loaded game places it
exactly. When the worker's absence ends it plans the way home, `return_path` (and
`return_hold`); if that plan fails it falls back to the departure route driven back,
then to the old straight run. The `return` phase ends with the car on the parked
transform exactly, then `exit` runs as before. The hidden driver is not moved: only the
car node moves, so `cabin_position_matches` is unchanged.

### Saving

New optional keys on the saved commute: `drive_path`, `return_path` (routes) and
`depart_hold`, `return_hold` (0 to 60 s). `save_error` validates every number (finite,
bounded, at most ten segments, gear exactly +1 or -1) and lets a `depart` or `return`
phase run for its wait plus its route's time, instead of the old four seconds. A record
with no route (every save made before this change) plays the old straight run exactly:
22 m along the car's axis, eased over four seconds. A save made now and loaded by an
older build is refused if it was taken more than four seconds into a drive.

When the plan fails (nothing clear exists) the commute falls back to the old straight
run if `drive_direction` finds that corridor clear, and otherwise refuses with the old
"Clear the driveway so the car can reach the road." The old corridor test ignores
hedges, so such a car can still drive through one: see the placements below.

## Trips

`begin_trip` plans the household car's way out before anything changes. A boxed-in car
refuses the trip with the same driveway notice and changes no state (a hand-built trip
with no route still plays the old straight run, so older probes keep working). The trip's
departure follows the route with the camera easing after the car (it stays within 3 m of
the car on screen and never jumps); the fifteen simulated minutes are paced across the
route's own time instead of a fixed six seconds, in exact sixty-fourths of a minute so
the household clock lands on the quarter hour exactly however long the route is. Leaving a venue, or leaving home in the
shared car, is a smooth run along the near lane from the kerb spot. A venue arrival
comes in along the near lane and is eased onto the kerb spot (no slide); the camera pans
to its usual framing as the car stops instead of cutting. A trip home with the household
car plans the way onto the car's own parked spot, hides the parked body while its twin
drives in, ends on the spot exactly, shows the body again, and the party steps out
beside the car. The car keeps its size scale on the trip (it used to lose it).

The **birth car** now enters at the edge of the view along the near lane and is eased
onto the kerb spot like a venue arrival, removing the 2.16 m sideways slide.

## Which placements get which result

Measured on the real starter lot (`tests/test_vehicle_routes.gd`; "leaves / comes home"):

| Placement | Result |
| --- | --- |
| Yard car facing the street (south), e.g. (-12, 3) | forward out (left onto the near lane); backs in |
| Car parallel to the street in the front yard, e.g. (-9, 7) west, (12, 6) east | forward out by an S-curve; comes home forward, or backs in when a tree trunk is in the way |
| East-facing (-9, 6) (a tree trunk 1.4 m ahead) | backs out; comes home forward |
| Car facing away from the street (north), e.g. (-12, 4) | backs out in one curve (one cusp); drives in forward |
| Car facing the house wall, e.g. (10, 2) west | backs out; drives in forward |
| Front-corner car facing the street, e.g. (-13, 6.9) | forward out; backs in |
| Four-bay street-facing garage, every bay taken | every bay drives forward out onto the road (the outer bays across to the far lane) and backs in |
| Garage opening away from the street | refused by the planner (legacy run decides) |
| Medium (x1.45) and large (x2.0) cars | routed where the geometry allows (3 of the 4 sample placements each), otherwise cleanly refused; a large car is 3.64 m wide, wider than a lane |
| Fenced frontage with a drive gate, car in line with it | through the gate, square to it |
| Delivery van parked at the kerb | driven around, in and out |
| Back-garden car facing the open west or east yard, e.g. (-11, -9) west | forward out down the side yard (one long manoeuvre); backs in |
| Car directly behind the house, or parallel to the street in a side yard | no planned route (a one-turn route cannot get past the house); legacy straight run if its corridor is clear, otherwise the old refusal |
| Car parked tight against the side hedge | leaves or comes home if its turn does not swing the tail into the hedge; the hedge gives 0.3 m to a passing body, never more; otherwise no planned route |

On the grid test, 34 of 76 legal parking poses lack a planned route both ways, the
poses behind the house, parked along a side yard, or tight against the hedge. The listing is
printed as `GRID_NO_ROUTE`.

## Known limits

* A route is a single manoeuvre (at most one cusp). Cars directly behind the house, in a
  side yard facing along it, tight against the hedge, or in a garage that opens away from
  the street have no planned route and use the old straight run (which ignores hedges)
  or the old refusal.
* Gates need the car roughly in line with them.
* The police car now turns at the station with a bounded yaw rate and parks square, but
  it still arrives from the east along the near lane facing west (against the lane
  convention) because the station is to the west and the car would need a U-turn road
  to arrive the other way; the school bus still runs along the sidewalk line, and the
  delivery van and food truck still appear parked.
* The camera is orthographic: a zoomed-out camera can see a car appear and vanish at
  26 m from the lot's centre line.
* `car_electric.glb` has no wheel animation (see Wheels).
* A route is planned once, when the walk to the car ends (and the way home when the absence
  ends). A fence, wall or piece of furniture built across it while the car is boarding,
  driving off or coming home is not swept again, so the car clips it; build in the quiet
  between drives.
* The food truck (the whole of every seventh day) and a grocery van waiting to be unloaded
  are avoided when any route goes round them. When none does (a car parked parallel to the
  street in front of their pitch) the plan is made as though they were not there and the
  car drives through them; only the school bus is really gone by the time the car reaches
  its place.

## Verification

`tests/test_vehicle_path.gd`, `test_vehicle_planner.gd`, `test_vehicle_routes.gd`,
`test_road_geometry.gd`, `test_commute_drive.gd`, `test_vehicle_convoy.gd`,
`test_trip_drive.gd`, `test_vehicle_rig.gd`, `test_vehicle_extras.gd`, and the older
`test_work_commute.gd -- --versioned`, `test_commute_return.gd`,
`test_commute_build_protection.gd`, `test_trip_boarding.gd`, `test_car_garage.gd`,
`test_gate_vehicles.gd` (re-authored: a drive gate in a fenced frontage), and
`test_vehicle_drive_probe.gd` (a hand-built trip still plays the straight run).
