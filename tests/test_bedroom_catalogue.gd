extends SceneTree
## Bedroom, bath and picture catalogue entries the Build panel can actually sell.

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
	var bed: Dictionary = LifeCatalog.get_item("bed")
	check(LifeCatalogVariants.sizes(bed) == ["double", "single"], "The bed is sold as a double and a single.")
	check(LifeCatalogVariants.price(bed, "double") == 840 and LifeCatalogVariants.price(bed, "single") == 520, "Double and single beds keep their own prices.")
	check(LifeCatalogVariants.footprint(bed, "single").x < LifeCatalogVariants.footprint(bed, "double").x, "A single bed takes less floor than a double.")
	for kind: String in ["nightstand", "bedside_lamp", "bookshelf", "dressing_table", "wardrobe", "desk_chair", "study_desk", "office_desk"]:
		var data: Dictionary = LifeCatalog.get_item(kind)
		check(not data.is_empty() and str(data.category) == "Bedroom", "%s is in the Bedroom catalogue." % kind)
		check(ResourceLoader.exists(LifeCatalogVariants.model_path(kind, "")), "%s has a model to place." % kind)
	var mat: Dictionary = LifeCatalog.get_item("bath_mat")
	check(int(mat.price) == 15 and mat.styles.size() == 3 and mat.colors.size() == 10, "Bath mats are £15 in 3 styles and 10 colours.")
	check(LifeCatalog.passable("bath_mat"), "A bath mat does not block the room.")
	var art: Dictionary = LifeCatalog.get_item("framed_picture")
	check(int(art.price) == 35 and art.styles.size() == 3 and art.colors.size() == 4, "Pictures are £35 in 3 themes and 4 frames.")
	check(LifeCatalog.wall_mounted("framed_picture") and float(art.hang) >= 1.4, "Pictures hang on the wall, up off the skirting.")
	check(float(LifeCatalog.get_item("painting").hang) >= 1.4, "The existing painting hangs higher by default.")
	check(float(LifeCatalog.get_item("garden_light_wall").hang) >= 1.4, "Outdoor wall lights hang higher by default.")
	print("BEDROOM_CATALOGUE ", checks, " assertions; ", failures, " failures")
	quit(1 if failures else 0)
