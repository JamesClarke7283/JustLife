extends RefCounted
class_name LifeCatalogVariants
## Styles, colours and sizes for the buy catalogue.
##
## A catalogue entry may declare any of three independent variant axes:
##
##   "styles":  an Array of style ids. Each style is its own authored model at
##              `assets/models/<kind>_<style>.glb`, so a different style is a
##              different silhouette rather than a recolour.
##   "colors":  an Array of hex strings, recoloured at runtime on the model's
##              `Tint` surface. The authored mesh is shared across colours.
##   "sizes":   an Array of size ids, each scaling the authored model uniformly
##              and replacing the declared footprint.
##
## A player's choice is stored per placed furnishing, so a save resumes the same
## object. An entry with no variants behaves exactly as it did before this file
## existed: no style suffix, no tint and one fixed footprint.
##
## Pure static policy: no Nodes, no renderer, no wallet.

## The uniform scale each size applies to the authored mesh. `small` is the
## authored size, so it scales by exactly 1 and an unsized kind therefore builds
## the same model as its own `small` choice.
const SIZE_SCALES: Dictionary = {
	"small": 1.0,
	"medium": 1.45,
	"large": 2.0,
}

const SIZES: Array[String] = ["small", "medium", "large"]

## The authored mesh name a colour variant recolours. Every colour-variant model
## authors exactly one such surface; see the art contract in
## `tools/create_outdoor_water.py` and its siblings.
##
## Matched by prefix rather than exactly, because a model that reuses one mesh for
## several parts exports it several times and Godot's importer then suffixes the
## duplicates — `Tint_001`, `Tint_010`. A prefix match paints every one of them,
## which is what a recoloured part actually needs.
const TINT_SURFACE: String = "Tint"


static func is_tint(node_name: String) -> bool:
	return node_name.begins_with(TINT_SURFACE)

## The colour choices offered when an entry asks to be tintable but names no
## palette: ten garden-appropriate tones, so any family that wants "10 colour
## choices" gets the same reviewed set.
const DEFAULT_COLORS: Array[String] = [
	"8faf9f", "6f8fa8", "c9a05a", "a8674f", "7d6b93",
	"c9c3a8", "5b7c6a", "d9a0a0", "4a4f55", "e6d8c5",
]

## A kind with no styles has exactly one authored model, which carries no style
## suffix. This is the id that means "the file without a suffix".
const BASE_STYLE: String = ""

## How many authored colours a multi-colour family should offer, so a kind that
## simply says "colours" reaches the reviewed set without listing it.
static func _listed(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key, [])
	return (value as Array).duplicate() if value is Array else []


static func styles(data: Dictionary) -> Array:
	var listed: Array = _listed(data, "styles")
	return listed if not listed.is_empty() else [BASE_STYLE]


static func colors(data: Dictionary) -> Array:
	var listed: Array = _listed(data, "colors")
	if not listed.is_empty(): return listed
	return DEFAULT_COLORS.duplicate() if bool(data.get("tint", false)) else []


static func sizes(data: Dictionary) -> Array:
	return _listed(data, "sizes")


## Whether this entry offers the player a choice at all. A variant kind is one
## whose choice is made inside the buy flow, so the catalogue cell opens a picker
## rather than beginning a placement straight away.
static func has_variants(data: Dictionary) -> bool:
	return styles(data).size() > 1 or colors(data).size() > 1 or sizes(data).size() > 1


## The model path for one style. An empty or unknown style falls back to the
## unsuffixed file, so a save written before a style existed still loads.
static func model_path(kind: String, style: String) -> String:
	var suffix: String = "_" + style if not style.is_empty() and style != BASE_STYLE else ""
	return "res://assets/models/%s%s.glb" % [kind, suffix]


## Every model file this entry can build from, so a validator or a test can
## check the authored art really exists for each choice it offers.
static func model_paths(kind: String, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for style: String in styles(data):
		out.append(model_path(kind, style))
	return out


## The uniform scale one size applies. An unknown or absent size is the authored
## size.
static func size_scale(size: String) -> float:
	return float(SIZE_SCALES.get(size, 1.0))


## The price one size costs. Three families are possible, in this order:
##   `rate_per_square_metre`  priced from the footprint it really occupies, which
##                            is how a fence is sold by the square metre;
##   `size_prices`            a stated price per size;
##   `price`                  one price, which is also the price of `small`.
static func price(data: Dictionary, size: String) -> int:
	if data.has("rate_per_square_metre"):
		return maxi(1, roundi(face_area(data, size) * float(data.rate_per_square_metre)))
	var per_size: Dictionary = data.get("size_prices", {})
	if per_size.has(size): return int(per_size[size])
	return int(data.get("price", 0))


## The square metres of face one size presents: its width times its height. A
## fence is sold this way, so a longer or taller run costs proportionally more
## without a second price table to keep in step.
static func face_area(data: Dictionary, size: String) -> float:
	var span: Vector2 = footprint(data, size)
	return maxf(0.01, span.x * height(data, size))


## How many people, or cars, one size seats or holds. Reading a capacity here
## rather than in the placement code keeps the size and the capacity one fact.
static func seats(data: Dictionary, size: String) -> int:
	var per_size: Dictionary = data.get("seats", {})
	if per_size.has(size): return int(per_size[size])
	return int(data.get("seat_count", 0))


## The colour a variant record actually paints. An unnamed colour falls back to
## the entry's authored colour, and a colour outside the offered palette is
## refused rather than silently painted.
static func color_or_default(color: String, data: Dictionary) -> String:
	var wanted: String = str(color).strip_edges().to_lower()
	if not wanted.is_empty() and colors(data).has(wanted): return wanted
	return str(data.get("color", "ffffff"))


static func color_offered(color: String, data: Dictionary) -> bool:
	return colors(data).has(str(color).strip_edges().to_lower())


## The style a variant record actually builds. An unnamed style falls back to
## the first authored one.
static func style_or_default(style: String, data: Dictionary) -> String:
	var offered: Array = styles(data)
	return style if offered.has(style) else (str(offered.front()) if not offered.is_empty() else BASE_STYLE)


## The size a variant record actually reports. An entry with no sizes reports
## none, so it carries no `size` key at all.
static func size_or_default(size: String, data: Dictionary) -> String:
	var offered: Array = sizes(data)
	if offered.is_empty(): return ""
	return size if offered.has(size) else str(offered.front())


## A variant record as it is stored on a placed furnishing. Only the axes the
## entry actually offers are written, so two saves describing the same object
## compare equal.
static func record(data: Dictionary, style: String, color: String, size: String) -> Dictionary:
	var out: Dictionary = {}
	if styles(data).size() > 1: out["style"] = style_or_default(style, data)
	if colors(data).size() > 1: out["color"] = color_or_default(color, data)
	if sizes(data).size() > 1: out["size"] = size_or_default(size, data)
	return out


## The record a purchase stores when the picker was never opened.
static func default_record(data: Dictionary) -> Dictionary:
	return record(data, "", "", "")


## Read the variant record off a placed furnishing, folded over the entry's own
## defaults so a caller never has to ask whether a key is present.
static func from_entry(entry: Dictionary) -> Dictionary:
	return record(LifeCatalog.ITEMS.get(str(entry.get("kind", "")), {}),
		str(entry.get("style", "")), str(entry.get("color", "")), str(entry.get("size", "")))


## The style, colour and size a variant record actually resolves to, which is
## what a caller needs to build or draw the object.
static func resolve(data: Dictionary, value: Dictionary) -> Dictionary:
	return {
		"style": style_or_default(str(value.get("style", "")), data),
		"color": color_or_default(str(value.get("color", "")), data),
		"size": size_or_default(str(value.get("size", "")), data),
	}


## The footprint an entry occupies at one size: the authored footprint scaled.
## Callers that place, support, draw or thumbnail the object read this, so a
## size choice is one fact rather than a scale applied in each caller.
static func footprint(data: Dictionary, size: String) -> Vector2:
	return (data.get("size", Vector2.ONE) as Vector2) * size_scale(size)


static func height(data: Dictionary, size: String) -> float:
	return float(data.get("height", 1.0)) * size_scale(size)


## Labels for the picker.
## A family with numbered styles names them in its own `style_labels`, so the
## picker says "Tied back" rather than "03".
static func style_label(style: String, data: Dictionary = {}) -> String:
	var named: Variant = data.get("style_labels", {})
	if named is Dictionary and named.has(style): return str(named[style])
	return "Classic" if style.is_empty() else style.capitalize()


static func size_label(size: String) -> String:
	return "One size" if size.is_empty() else size.capitalize()
