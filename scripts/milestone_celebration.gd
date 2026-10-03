extends CanvasLayer
class_name LifeMilestoneCelebration
## The big moment: a card in the middle of the screen with a loud fanfare and
## streamers bursting up from both bottom corners. A birthday, a retirement and a
## driving licence all use it, so they feel the same.
##
## `style` is "grand" (card, streamers and fanfare) or "card" (the card alone, for
## news that is welcome but not a party). Nothing here takes the mouse, so the
## game stays playable underneath, and the whole thing removes itself.
##
## The wedding has its own smaller burst (wedding_celebration.gd); this does not
## change it.

const P = preload("res://scripts/palette.gd")
const GRAND_SECONDS: float = 7.0
const CARD_SECONDS: float = 5.5
## Ribbons and confetti together. Every piece is at least this many pixels on its
## shortest side, so they read as large paper streamers and not as dust.
const PIECE_COUNT: int = 240
const RIBBON_COUNT: int = 160
const MIN_SIDE: float = 30.0
## Paper falls slowly: a light pull down and a good deal of air resistance.
const GRAVITY: float = 500.0
const DRAG: float = 0.3
const COLORS: Array[Color] = [Color("efaa54"), Color("ed739b"), Color("75bda8"), Color("9586d6"), Color("f7d969"), Color("6fa8dc"), Color("e06666")]

var title: String = ""
var subtitle: String = ""
var style: String = "grand"
## Whether the fanfare plays. The caller passes the game's Sound switch.
var sound: bool = true
## How long the celebration lasts, or a negative number for the style's own.
var duration: float = -1.0
var elapsed: float = 0.0
var pieces: Array = []
var canvas: Control
var banner: Panel
var title_label: Label
var subtitle_label: Label
var fanfare_player: AudioStreamPlayer


## Put a celebration on the screen and return it.
static func present(app: Node, headline: String, detail: String = "", look: String = "grand", with_sound: bool = true) -> Node:
	var celebration: LifeMilestoneCelebration = LifeMilestoneCelebration.new()
	celebration.title = headline
	celebration.subtitle = detail
	celebration.style = look
	celebration.sound = with_sound
	app.add_child(celebration)
	return celebration


func _ready() -> void:
	layer = 61
	if duration < 0.0: duration = GRAND_SECONDS if style == "grand" else CARD_SECONDS
	canvas = Control.new()
	canvas.name = "MilestoneCanvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	var size: Vector2 = get_viewport().get_visible_rect().size
	if style == "grand": _build_streamers(size)
	_build_banner(size)
	if style == "grand" and sound:
		fanfare_player = AudioStreamPlayer.new()
		fanfare_player.name = "MilestoneFanfare"
		fanfare_player.stream = CelebrationAudio.fanfare()
		fanfare_player.volume_db = 0.0
		add_child(fanfare_player)
		fanfare_player.play()
	advance(0.0)


func _process(delta: float) -> void: advance(delta)

## Move the celebration on by `delta` real seconds: the card grows in and fades
## out, the streamers fly and fall, and at the end the whole layer goes.
func advance(delta: float) -> void:
	elapsed += delta
	var grow: float = clampf(elapsed / 0.35, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - grow, 3.0)
	if is_instance_valid(banner):
		banner.scale = Vector2.ONE * lerpf(0.85, 1.0, eased)
		banner.modulate.a = eased * clampf((duration - elapsed) / 0.8, 0.0, 1.0)
	var fade: float = clampf((duration - elapsed) / 1.5, 0.0, 1.0)
	for piece: Dictionary in pieces:
		var node: ColorRect = piece.node
		var age: float = elapsed - float(piece.delay)
		if age < 0.0:
			node.visible = false
			continue
		node.visible = true
		# Position is worked out from the start each frame, so a long frame cannot
		# throw a piece off its arc: a burst velocity, a little drag, then gravity.
		var travelled: float = (1.0 - exp(-DRAG * age)) / DRAG
		var start: Vector2 = piece.start
		var velocity: Vector2 = piece.velocity
		node.position = start + velocity * travelled + Vector2(sin(age * 3.0 + float(piece.sway)) * 36.0, 0.5 * GRAVITY * age * age)
		node.rotation = float(piece.spin) * age
		node.modulate.a = fade
	if elapsed >= duration: queue_free()

## Seconds left before the celebration removes itself.
func remaining() -> float: return maxf(0.0, duration - elapsed)


func _build_banner(viewport: Vector2) -> void:
	var title_font: Font = P.display_font()
	var size_px: int = 56
	var wanted: float = title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x if title_font != null else 600.0
	var room: float = maxf(320.0, viewport.x - 80.0)
	if wanted + 120.0 > room: size_px = 48
	wanted = title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x if title_font != null else 600.0
	var width: float = clampf(wanted + 140.0, 560.0, room)
	var wraps: bool = wanted + 140.0 > room
	var height: float = 190.0 + (60.0 if wraps else 0.0)
	banner = Panel.new()
	banner.name = "MilestoneBanner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = P.panel(P.WHITE, 28, P.GOLD, 3)
	box.shadow_color = Color(0, 0, 0, 0.28)
	box.shadow_size = 20
	banner.add_theme_stylebox_override("panel", box)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -width * 0.5
	banner.offset_right = width * 0.5
	banner.offset_top = -height * 0.5
	banner.offset_bottom = height * 0.5
	banner.pivot_offset = Vector2(width, height) * 0.5
	canvas.add_child(banner)
	title_label = Label.new()
	title_label.name = "MilestoneTitle"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if title_font != null: title_label.add_theme_font_override("font", title_font)
	title_label.add_theme_font_size_override("font_size", size_px)
	title_label.add_theme_color_override("font_color", P.INK)
	title_label.position = Vector2(30.0, 30.0)
	title_label.size = Vector2(width - 60.0, 80.0 + (60.0 if wraps else 0.0))
	banner.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.name = "MilestoneSubtitle"
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label.text = subtitle
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.add_theme_font_size_override("font_size", 22)
	subtitle_label.add_theme_color_override("font_color", P.MUTED)
	subtitle_label.position = Vector2(40.0, 126.0 + (60.0 if wraps else 0.0))
	subtitle_label.size = Vector2(width - 80.0, 44.0)
	banner.add_child(subtitle_label)

func _build_streamers(viewport: Vector2) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for index: int in PIECE_COUNT:
		var ribbon: bool = index < RIBBON_COUNT
		var node: ColorRect = ColorRect.new()
		node.name = "Ribbon%d" % index if ribbon else "Confetti%d" % index
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.color = COLORS[index % COLORS.size()]
		if ribbon: node.size = Vector2(rng.randf_range(MIN_SIDE, MIN_SIDE + 8.0), rng.randf_range(110.0, 210.0))
		else:
			var side: float = rng.randf_range(MIN_SIDE, MIN_SIDE + 14.0)
			node.size = Vector2(side, side)
		node.pivot_offset = node.size * 0.5
		node.visible = false
		canvas.add_child(node)
		# Half burst up from the bottom-left corner and half from the bottom-right,
		# in three waves: most at once, some a moment later, a few as a trailing shower.
		var from_left: bool = index % 2 == 0
		var start: Vector2 = Vector2(rng.randf_range(-20.0, 40.0) if from_left else viewport.x - rng.randf_range(-20.0, 40.0), viewport.y + 10.0)
		var velocity: Vector2 = Vector2(rng.randf_range(300.0, 900.0) * (1.0 if from_left else -1.0), -rng.randf_range(700.0, 1200.0))
		pieces.append({"node": node, "start": start - node.size * 0.5, "velocity": velocity, "spin": rng.randf_range(-4.0, 4.0), "sway": rng.randf_range(0.0, TAU), "delay": [0.0, 0.0, rng.randf_range(0.35, 0.6), rng.randf_range(1.2, 2.0)][index % 4]})
