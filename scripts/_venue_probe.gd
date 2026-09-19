extends SceneTree
# Throwaway probe for the venues module: exercises the real API, cross-checks
# every kind against the live catalogue, and computes real footprints against
# the canonical lot and the public-venue standing spot. Deleted after the run.

const STAND := Vector2(2.5, 2.75)

func _init() -> void:
	var venues = load("res://scripts/venues.gd")
	var catalog = load("res://scripts/catalog.gd")
	var variants = load("res://scripts/catalog_variants.gd")
	var land = load("res://scripts/land.gd")
	var failures: Array[String] = []
	var kinds: Dictionary = {}
	var lot: Rect2 = land.rect({})
	for place: String in venues.ids():
		var layout: Array = venues.layout(place)
		var offers: Array = venues.offers(place)
		var problem: String = venues.validate(place)
		if not problem.is_empty(): failures.append("%s: validate -> %s" % [place, problem])
		var rects: Array[Rect2] = []
		var blocked_stand := false
		var service_ids: Array[String] = []
		for service: Dictionary in offers: service_ids.append(str(service.id))
		var kinds_here: Array[String] = []
		for entry: Dictionary in layout:
			var kind: String = str(entry.kind)
			if not catalog.ITEMS.has(kind): failures.append("%s: missing catalogue kind %s" % [place, kind])
			kinds[kind] = true
			if not kinds_here.has(kind): kinds_here.append(kind)
			if not str(entry.id).begins_with(place + "_"): failures.append("%s: bad id %s" % [place, entry.id])
			if entry.keys().size() != 5: failures.append("%s: %s unexpected keys" % [place, entry.id])
			var data: Dictionary = catalog.ITEMS[kind]
			var size: Vector2 = variants.footprint(data, "")
			var half: Vector2 = Vector2(absf(size.x), absf(size.y)) * .5
			if int(roundf(float(entry.rotation) / 90.0)) % 2: half = Vector2(half.y, half.x)
			var area := Rect2(Vector2(float(entry.x), float(entry.z)) - half, half * 2)
			if not lot.encloses(area): failures.append("%s: %s outside the lot %s" % [place, entry.id, area])
			if not catalog.passable(kind):
				for other: Rect2 in rects:
					if other.grow(.05).intersects(area): failures.append("%s: %s overlaps another furnishing" % [place, entry.id])
				if area.grow(-.2).has_point(STAND): blocked_stand = true
				rects.append(area)
		if blocked_stand: failures.append("%s: blocks the public-venue standing spot" % place)
		print("%-16s %-3d furnishings  %s" % [place, layout.size(), ", ".join(PackedStringArray(kinds_here))])
	# The services the brief names, by id.
	var required: Dictionary = {
		"petrol_station": ["fill_petrol", "charge_car"],
		"shopping_centre": ["weekly_shop"],
		"cafe": ["coffee_and_cake", "light_lunch"],
		"hairdresser": ["haircut", "colour_and_restyle"],
		"gymnasium": ["workout"],
		"school": ["enrol_child", "enrol_teen"],
		"university": ["study_bachelors", "study_masters", "study_phd"],
		"prison": ["visit_family"],
	}
	if venues.ids().size() != 8: failures.append("expected eight venues, found %d" % venues.ids().size())
	for place: String in required:
		var have: Array[String] = []
		for service: Dictionary in venues.offers(place): have.append(str(service.id))
		for wanted: String in required[place]:
			if not have.has(wanted): failures.append("%s: missing service %s" % [place, wanted])
	# Unknown ids must be refused rather than answered.
	if venues.has("home") or venues.has("library"): failures.append("has() claims a neighborhood place")
	if venues.validate("library").is_empty(): failures.append("validate() accepted a foreign venue")
	if not venues.info("library").is_empty(): failures.append("info() invented a foreign venue")
	if not venues.offers("library").is_empty(): failures.append("offers() invented services")
	if not venues.layout("library").is_empty(): failures.append("layout() invented furnishings")
	for place: String in venues.ids():
		if not venues.has(place): failures.append("%s: has() disagrees with ids()" % place)
		if venues.info(place).get("name", "") == "": failures.append("%s: empty info" % place)
	# A venue that is complete but whose kind left the catalogue must be caught.
	var catalog_script = load("res://scripts/catalog.gd")
	if not catalog_script.ITEMS.has("treadmill"): failures.append("treadmill left the catalogue")
	print("venue ids: ", ", ".join(PackedStringArray(venues.ids())))
	print("kinds used: ", ", ".join(PackedStringArray(kinds.keys())))
	if failures.is_empty():
		print("PROBE OK")
	else:
		print("PROBE FAILURES:")
		for failure: String in failures: print("  ", failure)
	quit(0 if failures.is_empty() else 1)
