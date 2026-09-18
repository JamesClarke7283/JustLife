extends RefCounted
class_name LifePets
## Original household pets: purchase policy, the authored appearance contract and
## save validation. Pure static policy — the household owns the live record,
## money and clocks, exactly as it does for adoptions.
##
## A pet's coat is two natural colours blended into one continuous gradient, so
## a cat or dog can be solid, softly shaded, or a mixed two-tone. The same
## colour list serves both species so any natural pairing is reachable.

const VERSION: int = 1
const MAX_PETS: int = 6

## Species. The keys are also the model file stems and the save values.
const SPECIES: Array[String] = ["cat", "dog"]
const SPECIES_LABELS: Dictionary = {"cat": "Cat", "dog": "Dog"}
## A cat or a dog costs its own price; the accessories are sold separately.
const PRICES: Dictionary = {"cat": 320, "dog": 480}

## Sex is presentation and naming only.
const SEXES: Array[String] = ["female", "male"]
const SEX_LABELS: Dictionary = {"female": "Female", "male": "Male"}

## Natural coat colours, shared by both species so a mixed gradient can pair any
## two of them. These are authored coat tones rather than skin tones: black
## through cream, a grey family and two warm coat families.
const COAT_COLORS: Array[String] = [
	"211e1c", "3a2b23", "54382a", "6f4a31", "89563a", "a06b43",
	"c08a58", "d7b483", "ead6b8", "f2ece0",
	"8c7f70", "6b6f73", "b9b3a6", "c9c2b4",
	"b8794a", "8f5334", "c8a06a", "e0c39a",
]
## Coat lengths change the silhouette: short reads sleek, long reads fluffy.
const COAT_LENGTHS: Array[String] = ["short", "medium", "long"]
const COAT_LENGTH_LABELS: Dictionary = {"short": "Short", "medium": "Medium", "long": "Long"}

## Distinctive markings offered beyond a plain graded coat.
const MARKINGS: Array[String] = ["none", "bicolour", "tuxedo", "tabby", "points", "mask"]
const MARKING_LABELS: Dictionary = {"none": "Plain", "bicolour": "Bicolour", "tuxedo": "Tuxedo", "tabby": "Tabby", "points": "Points", "mask": "Mask"}

## Accessories. The bowl suits any pet; a cat tree, a cat bed and a cat toy box
## each need a cat, and a kennel, a dog bed and a dog toy box each need a dog,
## so the shop only offers what the household can actually use. The two toys are
## the single pieces a toy box already holds six of.
const ACCESSORY_KINDS: Array[String] = ["pet_bowl", "cat_tree", "kennel", "pet_bed_cat", "pet_bed_dog", "pet_toy_cat", "pet_toy_dog", "cat_toy_box", "dog_toy_box"]
const ACCESSORY_SPECIES: Dictionary = {
	"pet_bowl": "", "cat_tree": "cat", "kennel": "dog",
	"pet_bed_cat": "cat", "pet_bed_dog": "dog",
	"pet_toy_cat": "cat", "pet_toy_dog": "dog",
	"cat_toy_box": "cat", "dog_toy_box": "dog",
}
const ACCESSORY_LABELS: Dictionary = {
	"pet_bowl": "Food & water bowl", "cat_tree": "Cat tree", "kennel": "Dog kennel",
	"pet_bed_cat": "Cosy cat bed", "pet_bed_dog": "Cushioned dog bed",
	"pet_toy_cat": "Feather mouse toy", "pet_toy_dog": "Knotted rope bone",
	"cat_toy_box": "Cat Toy Box", "dog_toy_box": "Dog Toy Box",
}
const ACCESSORY_PRICES: Dictionary = {
	"pet_bowl": 60, "cat_tree": 240, "kennel": 320,
	"pet_bed_cat": 120, "pet_bed_dog": 160,
	"pet_toy_cat": 25, "pet_toy_dog": 30,
	"cat_toy_box": 50, "dog_toy_box": 50,
}
## The six toys a toy box comes with, and where they sit inside it. Each box is
## sold full, and buying one places the box and its six toys as a set.
const TOY_BOX_TOYS: Dictionary = {"cat_toy_box": "cat", "dog_toy_box": "dog"}
const TOYS_PER_BOX: int = 6

## Collar and leash colours. A pet's collar and leash are its own, chosen when
## the pet is shaped and kept in the save, so a household can tell two animals
## apart at a glance. These are authored accessory tones rather than coat tones.
const COLLAR_COLORS: Array[String] = [
	"be5a4b", "d94f4f", "e0803a", "e8b74a", "6fae5a",
	"3f9b8e", "4a8fd0", "6b5fbe", "a9559b", "e07fae",
	"8a5a3c", "4a4f55", "2e3438", "8c8f94", "e6e2d8", "f2f0ea",
]
## A leash is usually the plainer of the two, so it gets a shorter, calmer set
## that always contrasts with the collar it hangs beside.
const LEASH_COLORS: Array[String] = [
	"4a4f55", "2e3438", "8a5a3c", "3f9b8e", "4a8fd0", "6b5fbe",
	"be5a4b", "6fae5a", "8c8f94", "e6e2d8",
]
const DEFAULT_COLLAR: String = "be5a4b"
const DEFAULT_LEASH: String = "4a4f55"

const NAMES: Dictionary = {
	"female": ["Willow", "Hazel", "Clover", "Poppy", "Nala", "Sable", "Juniper", "Pip", "Mabel", "Fern", "Daisy", "Winnie"],
	"male": ["Basil", "Rufus", "Milo", "Otto", "Bramble", "Scout", "Jasper", "Alder", "Biscuit", "Rook", "Toby", "Pebble"],
}


static func fresh() -> Dictionary:
	return {"version": VERSION, "next_serial": 1, "pets": []}


static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high


static func species_label(species: String) -> String:
	return str(SPECIES_LABELS.get(species, species.capitalize()))


static func price_for(species: String) -> int:
	return int(PRICES.get(species, 0))


static func candidate_count() -> int:
	# Both species and both sexes are always on show, so a shop visit offers a
	# cat and a dog and never hides one species behind a reroll.
	return 6


static func colour(value: Variant) -> bool:
	if not value is String:
		return false
	var hex: String = str(value).trim_prefix("#").to_lower()
	if hex.length() != 6:
		return false
	for character: String in hex:
		if character not in "0123456789abcdef":
			return false
	return true


static func normalised_colour(value: Variant, fallback: String) -> String:
	return str(value).trim_prefix("#").to_lower() if colour(value) else fallback


## A stable, reproducible reviewed pet. The same serial and choice always give
## the same animal, so a shop reopened out of order never changes what is shown.
static func candidate(serial: int, choice: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91100 + (serial - 1) * candidate_count() + choice
	var species: String = SPECIES[choice % SPECIES.size()]
	var sex: String = "female" if (serial + choice) % 2 == 0 else "male"
	var coat: String = COAT_COLORS[rng.randi_range(0, COAT_COLORS.size() - 1)]
	var second: String = COAT_COLORS[rng.randi_range(0, COAT_COLORS.size() - 1)]
	# Roughly half the candidates are a genuine mixed gradient; the rest are
	# solid or only lightly shaded, so the shop shows both extremes.
	var mixed: bool = rng.randf() < 0.5
	var blend: float = rng.randf_range(0.45, 0.95) if mixed else rng.randf_range(0.0, 0.22)
	var pool: Array = NAMES.get(sex, NAMES["female"])
	return {
		"serial": serial, "choice": choice, "species": species, "sex": sex,
		"name": str(pool[rng.randi_range(0, pool.size() - 1)]),
		"coat_color": coat, "mark_color": second,
		"gradient": snappedf(blend, 0.01),
		"coat_length": COAT_LENGTHS[rng.randi_range(0, COAT_LENGTHS.size() - 1)],
		"marking": MARKINGS[rng.randi_range(0, MARKINGS.size() - 1)],
		"collar_color": COLLAR_COLORS[rng.randi_range(0, COLLAR_COLORS.size() - 1)],
		"leash_color": LEASH_COLORS[rng.randi_range(0, LEASH_COLORS.size() - 1)],
	}


## The appearance fields the actor reads, normalised and clamped.
static func appearance(pet: Dictionary) -> Dictionary:
	return {
		"species": str(pet.get("species", "cat")) if SPECIES.has(str(pet.get("species", ""))) else "cat",
		"coat_color": normalised_colour(pet.get("coat_color", ""), "89563a"),
		"mark_color": normalised_colour(pet.get("mark_color", ""), "ead6b8"),
		"gradient": clampf(float(pet.get("gradient", 0.0)), 0.0, 1.0),
		"coat_length": str(pet.get("coat_length", "medium")) if COAT_LENGTHS.has(str(pet.get("coat_length", ""))) else "medium",
		"marking": str(pet.get("marking", "none")) if MARKINGS.has(str(pet.get("marking", ""))) else "none",
		"collar_color": normalised_colour(pet.get("collar_color", ""), DEFAULT_COLLAR),
		"leash_color": normalised_colour(pet.get("leash_color", ""), DEFAULT_LEASH),
	}


## Validate a reviewed pet before the household takes it in. Never charges: the
## household commits the fee only once this and the arrival path both pass.
static func profile_error(value: Variant) -> String:
	if not value is Dictionary:
		return "Choose a pet first."
	var pet: Dictionary = value
	if not SPECIES.has(str(pet.get("species", ""))):
		return "Choose a cat or a dog."
	if not SEXES.has(str(pet.get("sex", ""))):
		return "Choose the pet's sex."
	var name: String = str(pet.get("name", "")).strip_edges()
	if name.is_empty():
		return "Give your new pet a name."
	if name.length() > 24:
		return "That name is too long for a pet tag."
	if not colour(pet.get("coat_color", "")):
		return "Choose a valid coat colour."
	if not colour(pet.get("mark_color", "")):
		return "Choose a valid marking colour."
	if not integer(pet.get("serial", 0), 1, 64) or not integer(pet.get("choice", 0), 0, candidate_count() - 1):
		return "This pet review is no longer valid. Open the shop again."
	if not is_finite(float(pet.get("gradient", -1.0))) or float(pet.get("gradient", -1.0)) < 0.0 or float(pet.get("gradient", -1.0)) > 1.0:
		return "The coat gradient must be between solid and fully mixed."
	if not COAT_LENGTHS.has(str(pet.get("coat_length", ""))):
		return "Choose a coat length."
	if not MARKINGS.has(str(pet.get("marking", ""))):
		return "Choose a marking."
	if not colour(pet.get("collar_color", "")):
		return "Choose a valid collar colour."
	if not colour(pet.get("leash_color", "")):
		return "Choose a valid leash colour."
	return ""


## The shop request: the reviewed pet plus the household size and price it was
## quoted at. Re-checking both refuses a review prepared before the household
## changed, exactly as an adoption request does.
static func request_error(value: Variant) -> String:
	if not value is Dictionary:
		return "This pet review is no longer valid. Open the shop again."
	var request: Dictionary = value
	if request.size() != 14:
		return "This pet review is no longer valid. Open the shop again."
	if not integer(request.get("member_count", 0), 1, 8):
		return "This pet review is no longer valid. Open the shop again."
	if not integer(request.get("fee", 0), 1, 1000000) or int(request.fee) != price_for(str(request.get("species", ""))):
		return "This pet review is no longer valid. Open the shop again."
	return profile_error(request)


## Build the stored record from an accepted review. The identity is the
## household's serial, so pets are numbered in the order they came home.
static func record_from(review: Dictionary, id: String, day: int) -> Dictionary:
	return {
		"id": id,
		"serial": int(review.serial),
		"species": str(review.species),
		"sex": str(review.sex),
		"name": str(review.name).strip_edges(),
		"coat_color": normalised_colour(review.coat_color, "89563a"),
		"mark_color": normalised_colour(review.mark_color, "ead6b8"),
		"gradient": snappedf(clampf(float(review.gradient), 0.0, 1.0), 0.01),
		"coat_length": str(review.coat_length),
		"marking": str(review.marking),
		"collar_color": normalised_colour(review.get("collar_color", ""), DEFAULT_COLLAR),
		"leash_color": normalised_colour(review.get("leash_color", ""), DEFAULT_LEASH),
		"day": day,
		"fee": price_for(str(review.species)),
	}


## Validate one stored pet record. `index` fixes the serial so a save cannot
## reorder or duplicate its pet history.
static func pet_error(value: Variant, index: int, known: Dictionary) -> String:
	if not value is Dictionary:
		return "Save contains an invalid pet."
	var pet: Dictionary = value
	if pet.size() != 14:
		return "Save contains a pet with unexpected fields."
	var id: String = str(pet.get("id", ""))
	if id.is_empty() or known.has(id):
		return "Save contains a duplicate pet identity."
	if not integer(pet.get("serial", 0), 1, 64) or int(pet.serial) != index + 1:
		return "Save contains an out-of-order pet serial."
	if not SPECIES.has(str(pet.get("species", ""))):
		return "Save contains an unknown pet species."
	if not SEXES.has(str(pet.get("sex", ""))):
		return "Save contains an unknown pet sex."
	var name: String = str(pet.get("name", "")).strip_edges()
	if name.is_empty() or name.length() > 24:
		return "Save contains an invalid pet name."
	if not colour(pet.get("coat_color", "")) or not colour(pet.get("mark_color", "")):
		return "Save contains an invalid pet coat colour."
	if not is_finite(float(pet.get("gradient", -1.0))) or float(pet.gradient) < 0.0 or float(pet.gradient) > 1.0:
		return "Save contains an impossible coat gradient."
	if not COAT_LENGTHS.has(str(pet.get("coat_length", ""))):
		return "Save contains an unknown coat length."
	if not MARKINGS.has(str(pet.get("marking", ""))):
		return "Save contains an unknown marking."
	if not colour(pet.get("collar_color", "")) or not colour(pet.get("leash_color", "")):
		return "Save contains an invalid collar or leash colour."
	if not integer(pet.get("day", 0), 1, 1000000) or not integer(pet.get("fee", 0), 0, 1000000):
		return "Save contains an invalid pet purchase record."
	if int(pet.fee) != price_for(str(pet.species)):
		return "A saved pet price does not match the shop price."
	return ""


static func validate(value: Variant, data: Dictionary) -> String:
	# Additive optional record: absent means a household that owns no pets yet.
	if value == null:
		return ""
	if not value is Dictionary:
		return "The saved pets are invalid."
	var record: Dictionary = value
	if record.size() != 3:
		return "The saved pets have unexpected fields."
	if not integer(record.get("version", 0), VERSION, VERSION):
		return "The saved pets use an unsupported version."
	if not record.get("pets") is Array or record.pets.size() > MAX_PETS:
		return "The saved pets are invalid."
	if not integer(record.get("next_serial", 1), 1, MAX_PETS + 1) or int(record.next_serial) != record.pets.size() + 1:
		return "Save contains an invalid pet serial."
	var known: Dictionary = {}
	for index: int in range(record.pets.size()):
		var error: String = pet_error(record.pets[index], index, known)
		if not error.is_empty():
			return error
		known[str(record.pets[index].id)] = true
	return ""


## The arrival route a pet walks in on. The same finite-point contract the
## adoption arrival uses, so a blocked front garden is refused before any money
## changes hands.
static func point(value: Variant) -> bool:
	if value is Vector3:
		return value.is_finite() and absf(value.x) <= 30 and absf(value.z) <= 30 and absf(value.y - 0.16) < 0.001
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)):
			return false
	return absf(float(value[0])) <= 30 and absf(float(value[2])) <= 30 and absf(float(value[1]) - 0.16) < 0.001


## The accessory kinds a household may buy, in catalogue order: a bowl suits any
## pet, a cat tree needs a cat and a kennel needs a dog.
static func available_accessories(pets: Array) -> Array:
	var species_present: Dictionary = {}
	for pet: Variant in pets:
		if pet is Dictionary:
			species_present[str(pet.get("species", ""))] = true
	var result: Array = []
	for kind: String in ACCESSORY_KINDS:
		var required: String = str(ACCESSORY_SPECIES[kind])
		if required.is_empty():
			if not species_present.is_empty():
				result.append(kind)
		elif species_present.has(required):
			result.append(kind)
	return result


## A pet accessory is refused unless the household owns a pet that can use it:
## the bowl suits any pet, a cat tree needs a cat and a kennel needs a dog.
static func accessory_kind_error(kind: String, pets: Array) -> String:
	if not ACCESSORY_KINDS.has(kind):
		return "Choose a valid pet accessory."
	var required: String = str(ACCESSORY_SPECIES[kind])
	if required.is_empty():
		if pets.is_empty():
			return "Adopt a pet before buying %s." % str(ACCESSORY_LABELS[kind]).to_lower()
		return ""
	for pet: Variant in pets:
		if pet is Dictionary and str(pet.get("species", "")) == required:
			return ""
	return "%s needs a %s in the household." % [ACCESSORY_LABELS[kind], species_label(required).to_lower()]
