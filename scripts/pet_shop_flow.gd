extends RefCounted
class_name LifePetShopFlow
## Pet-shop presentation and physical arrival. The household owns the saved pet
## record, the fee and the arrival policy; this view only builds the shop, the
## pet picker and the arrival walk, exactly as the adoption flow does.
##
## The picker is the person-picker pattern applied to a pet: choose the species,
## the sex, then the coat as two natural colours mixed into one gradient, with
## coat length and markings on top.
const P = preload("res://scripts/palette.gd")

var app: Node
var request: Dictionary = {}
var confirming: bool = false
## The pet the player is currently shaping, before it is bought.
var draft: Dictionary = {}
var primary: String = ""
var serial_preview: int = 1


func _init(owner_app: Node) -> void:
	app = owner_app


func _panel(title: String, subtitle: String) -> void:
	app._begin_pause_overlay()
	app.menus.shade()
	app.card(Vector2(265, 118), Vector2(910, 668), P.WHITE, 24, app.overlay)
	app.small_caps("Phone · Juniper Pet Shop", Vector2(300, 140), Vector2(780, 26), app.overlay)
	app.text_label(title, Vector2(298, 181), Vector2(805, 57), 38, P.INK, true, app.overlay)
	app.paragraph(subtitle, Vector2(302, 249), Vector2(822, 62), 18, P.MUTED, app.overlay)


func context_error() -> String:
	if app.mode != "live" or app.current_venue != "home" or not app.pending_move.is_empty():
		return "Return to Live mode at home to visit the pet shop."
	return ""


## The shop is a phone service, so a household can adopt a pet without leaving
## home — the animal then walks in from the street like an adopted child.
func show_shop() -> void:
	request.clear()
	primary = app.household.selected_id()
	_panel("A new friend for the household.", "Cats and dogs, shaped how you like them. Nothing is charged until you confirm.")
	var pets: Array = app.household.pets.get("pets", [])
	var reason: String = context_error()
	app.paragraph("Your household keeps %d of %d pets." % [pets.size(), LifePets.MAX_PETS], Vector2(307, 322), Vector2(820, 27), 16, P.MUTED, app.overlay)
	var choose: Button = app.button("Adopt a cat or dog", Vector2(302, 366), Vector2(820, 55), show_species, true, app.overlay)
	choose.name = "PetShopAdopt"
	choose.disabled = not reason.is_empty()
	choose.tooltip_text = reason
	app.paragraph("Choose the species, the sex, and a coat built from two natural colours. A cat costs §%d and a dog §%d." % [LifePets.price_for("cat"), LifePets.price_for("dog")], Vector2(307, 433), Vector2(806, 44), 16, P.INK, app.overlay)
	if not pets.is_empty():
		show_household_pets(pets, Vector2(302, 482))
		show_accessories(Vector2(302, 560))
	else:
		show_accessories(Vector2(302, 482))
	app.paragraph(reason, Vector2(307, 702), Vector2(806, 40), 14, P.TEAL, app.overlay)
	app.button("Back to life", Vector2(302, 742), Vector2(820, 40), app.close_overlay, false, app.overlay)


## Buying an accessory is an ordinary furnishing purchase: it opens the normal
## placement, so reach, support and doorway checks all still apply.
func show_accessories(at: Vector2) -> void:
	app.small_caps("Accessories", at, Vector2(400, 23), app.overlay)
	var kinds: Array = LifePets.available_accessories(app.household.pets.get("pets", []))
	if kinds.is_empty():
		app.paragraph("Adopt a pet first, then a bowl, a cat tree or a kennel can come home with them.", at + Vector2(2, 30), Vector2(806, 34), 15, P.MUTED, app.overlay)
		return
	for index: int in range(kinds.size()):
		var kind: String = str(kinds[index])
		var price: int = int(LifeCatalog.ITEMS[kind].price)
		var reason: String = app.household.accessory_availability(kind)
		var button: Button = app.button("%s  ·  §%d" % [LifePets.ACCESSORY_LABELS[kind], price], at + Vector2(index * 268, 30), Vector2(258, 44), func(): buy_accessory(kind), false, app.overlay)
		button.name = "PetAccessory_" + kind
		button.disabled = app.mode != "live" or not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else "Places the %s through the ordinary furnishing placement." % str(LifePets.ACCESSORY_LABELS[kind]).to_lower()


func show_household_pets(pets: Array, at: Vector2) -> void:
	app.small_caps("Living here", at, Vector2(400, 23), app.overlay)
	var names: Array = []
	for pet: Dictionary in pets:
		names.append("%s · %s %s" % [str(pet.name), str(LifePets.SEX_LABELS[pet.sex]), LifePets.species_label(str(pet.species)).to_lower()])
	app.paragraph(", ".join(PackedStringArray(names)), at + Vector2(2, 30), Vector2(806, 40), 15, P.INK, app.overlay)


## Leave the shop for the ordinary build placement. The shop closes first so the
## placement owns the cursor, exactly as a catalogue purchase does.
func buy_accessory(kind: String) -> void:
	var reason: String = app.household.accessory_availability(kind)
	if not reason.is_empty():
		app.show_notice(reason)
		return
	app.close_overlay()
	app.set_build_mode(true)
	app.begin_purchase(kind)


func show_species() -> void:
	draft = LifePets.candidate(serial_preview, 0)
	draw_picker()


## The pet picker: species, sex, coat colours and the gradient between them.
func draw_picker() -> void:
	_panel("Shape your new pet.", "Every feature here is yours to choose. Mixed coats blend two natural colours across the body.")
	var species: String = str(draft.get("species", "cat"))
	app.small_caps("Species", Vector2(302, 322), Vector2(388, 23), app.overlay)
	for index: int in range(LifePets.SPECIES.size()):
		var option: String = LifePets.SPECIES[index]
		var label_text: String = "%s  ·  §%d" % [LifePets.species_label(option), LifePets.price_for(option)]
		var reason: String = app.household.pet_availability(option)
		var button: Button = app.button(label_text, Vector2(302 + index * 200, 350), Vector2(190, 46), func(): set_species(option), option == species, app.overlay)
		button.name = "PetSpecies_" + option
		button.tooltip_text = reason
	app.small_caps("Sex", Vector2(302, 406), Vector2(180, 23), app.overlay)
	for index: int in range(LifePets.SEXES.size()):
		var option: String = LifePets.SEXES[index]
		var button: Button = app.button(LifePets.SEX_LABELS[option], Vector2(302 + index * 94, 434), Vector2(88, 40), func(): set_sex(option), option == str(draft.sex), app.overlay)
		button.name = "PetSex_" + option
	app.small_caps("Name", Vector2(506, 406), Vector2(184, 23), app.overlay)
	var edit := LineEdit.new()
	edit.name = "PetName"
	edit.text = str(draft.name)
	edit.max_length = 24
	edit.placeholder_text = "Your pet's name"
	app.rect(edit, Vector2(506, 434), Vector2(184, 40), app.overlay)
	edit.text_changed.connect(func(value: String): draft.name = value)
	app.small_caps("Base coat", Vector2(302, 484), Vector2(388, 23), app.overlay)
	_swatch_row("coat_color", Vector2(302, 504))
	app.small_caps("Second colour", Vector2(302, 582), Vector2(388, 23), app.overlay)
	_swatch_row("mark_color", Vector2(302, 602))
	# The panel ends at y=759. The preview card and its thumbnail are sized to
	# finish inside it, so the live coat is never half-clipped by the panel edge.
	app.small_caps("Live preview", Vector2(302, 680), Vector2(388, 23), app.overlay)
	app.card(Vector2(302, 702), Vector2(388, 48), P.PALE, 14, app.overlay)
	var holder := Control.new()
	holder.name = "PetPreviewHolder"
	app.rect(holder, Vector2(392, 704), Vector2(208, 44), app.overlay)
	app.pet_thumbnail(Vector2.ZERO, Vector2(208, 44), draft, holder)
	app.small_caps("Coat length", Vector2(726, 322), Vector2(412, 23), app.overlay)
	for index: int in range(LifePets.COAT_LENGTHS.size()):
		var option: String = LifePets.COAT_LENGTHS[index]
		var button: Button = app.button(LifePets.COAT_LENGTH_LABELS[option], Vector2(726 + index * 94, 350), Vector2(86, 38), func(): draft.coat_length = option; draw_picker(), option == str(draft.coat_length), app.overlay)
		button.name = "PetCoatLength_" + option
	app.small_caps("Markings", Vector2(726, 402), Vector2(412, 23), app.overlay)
	for index: int in range(LifePets.MARKINGS.size()):
		var option: String = LifePets.MARKINGS[index]
		var button: Button = app.button(LifePets.MARKING_LABELS[option], Vector2(726 + (index % 3) * 94, 428 + (index / 3) * 42), Vector2(86, 38), func(): draft.marking = option; draw_picker(), option == str(draft.marking), app.overlay)
		button.name = "PetMarking_" + option
	app.small_caps("Mixed gradient", Vector2(726, 518), Vector2(412, 23), app.overlay)
	var slider := HSlider.new()
	slider.name = "PetGradient"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(draft.gradient)
	app.rect(slider, Vector2(729, 546), Vector2(300, 30), app.overlay)
	slider.value_changed.connect(func(value: float):
		draft.gradient = value
		app.preview_pet(draft))
	app.text_label("Solid", Vector2(726, 577), Vector2(150, 25), 12, P.MUTED, false, app.overlay)
	var right: Label = app.text_label("Fully mixed", Vector2(900, 577), Vector2(160, 25), 12, P.MUTED, false, app.overlay)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	app.button("Surprise me", Vector2(726, 614), Vector2(190, 42), surprise_pet, false, app.overlay)
	app.button("Back to shop", Vector2(926, 614), Vector2(212, 42), show_shop, false, app.overlay)
	var reason: String = app.household.pet_availability(str(draft.species))
	var confirm: Button = app.button("Take %s home  ·  §%d" % [str(draft.name).strip_edges(), LifePets.price_for(str(draft.species))], Vector2(726, 672), Vector2(412, 44), confirm_pet, true, app.overlay)
	confirm.name = "PetShopConfirm"
	confirm.disabled = not reason.is_empty()
	confirm.tooltip_text = reason


## A row of authored coat swatches. Choosing one redraws the picker so the
## selection mark and the live preview both follow immediately. Each swatch is
## compacted to its own square, because the shared button theme's 18 px content
## margin would otherwise stretch it into an oval.
func _swatch_row(key: String, at: Vector2) -> void:
	var chosen: String = str(draft.get(key, ""))
	for index: int in range(LifePets.COAT_COLORS.size()):
		var colour: String = LifePets.COAT_COLORS[index]
		var column: int = index % 9
		var row: int = index / 9
		var swatch: Button = app.button("", at + Vector2(column * 40, row * 40), Vector2(34, 34), func(): draft[key] = colour; draw_picker(), false, app.overlay)
		swatch.name = "PetSwatch_%s_%d" % [key, index]
		swatch.custom_minimum_size = Vector2.ZERO
		# The shared panel style sets 18 px content margins, which would force a
		# 34 px chip to 36 px and overlap its neighbour; a swatch carries no text.
		swatch.add_theme_stylebox_override("normal", app.swatch_panel(Color(colour), 17, P.TEAL if colour == chosen else Color("ffffff"), 3))
		swatch.add_theme_stylebox_override("hover", app.swatch_panel(Color(colour).lightened(.1), 17, P.TEAL, 3))
		swatch.add_theme_stylebox_override("pressed", app.swatch_panel(Color(colour).darkened(.1), 17, P.TEAL, 3))
		swatch.add_theme_stylebox_override("focus", app.swatch_panel(Color.TRANSPARENT, 17, P.GOLD, 2))
		swatch.size = Vector2(34, 34)
		if colour == chosen:
			swatch.text = "•"
			swatch.add_theme_color_override("font_color", Color.WHITE if Color(colour).get_luminance() < 0.55 else P.INK)


func set_species(value: String) -> void:
	if not LifePets.SPECIES.has(value):
		return
	draft.species = value
	draw_picker()


func set_sex(value: String) -> void:
	if not LifePets.SEXES.has(value):
		return
	draft.sex = value
	# A rolled name belongs to the sex it was rolled for; a name the player has
	# typed over is always left alone.
	if bool(draft.get("rolled_name", false)):
		var pool: Array = LifePets.NAMES[value]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(draft.get("serial", 1)) * 31 + value.hash()
		draft.name = str(pool[rng.randi_range(0, pool.size() - 1)])
	draw_picker()


func surprise_pet() -> void:
	# Roll a fresh candidate, keeping the species and sex the player has chosen
	# so a reroll never silently becomes the other animal.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rolled: Dictionary = LifePets.candidate(serial_preview, rng.randi_range(0, LifePets.candidate_count() - 1))
	rolled.species = str(draft.species)
	rolled.sex = str(draft.sex)
	var pool: Array = LifePets.NAMES[str(draft.sex)]
	rolled.name = str(pool[rng.randi_range(0, pool.size() - 1)])
	rolled.rolled_name = true
	draft = rolled
	draw_picker()


func confirm_pet() -> void:
	if confirming or not app.overlay_open or app.overlay.get_node_or_null("PetShopConfirm") == null:
		return
	confirming = true
	var reason: String = context_error()
	var prepared: Dictionary = app.household.prepare_pet(draft)
	request = prepared.get("request", {}).duplicate(true)
	if reason.is_empty() and not bool(prepared.get("ok", false)):
		reason = str(prepared.get("error", ""))
	var spawn: Vector3 = app.world.lot_exit_position(app.household.members.size())
	var destination: Vector3 = app.pet_arrival_destination(spawn)
	var result: Dictionary = {"ok": false, "error": reason}
	if reason.is_empty() and not destination.is_finite():
		reason = "The arrival path is blocked. Clear the front garden, then try again."
		result = {"ok": false, "error": reason}
	if reason.is_empty():
		result = app.household.commit_pet(request, spawn)
	if bool(result.ok):
		if not bool(result.get("duplicate", false)):
			app.spawn_pet(str(result.pet.id), result.pet, spawn, destination)
			app.show_notice("%s the %s has come home. −§%d" % [str(result.pet.name), LifePets.species_label(str(result.pet.species)).to_lower(), int(result.pet.fee)])
		else:
			app.show_notice("%s is already part of the household." % str(result.pet.name))
		request.clear()
		serial_preview += 1
		app.close_overlay()
		app.draw_live()
	else:
		app.show_notice(str(result.get("error", "The pet could not come home.")))
	confirming = false
