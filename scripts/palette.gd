extends RefCounted
class_name LifePalette

const INK = Color("263f3d")
const MUTED = Color("778783")
const PAPER = Color("f8f6ef")
const WHITE = Color("fffdf7")
const TEAL = Color("397e70")
const PALE = Color("e4ede3")
const LINE = Color("dbe2d7")
const CORAL = Color("cd8069")
const GOLD = Color("bf9757")

## The household's money, and what it is called. The body face carries no script
## L, so the displayed symbol falls back to the display face, which does — the
## same fallback the engine applies inside a Label is set up here once, on the
## shared fonts, so every screen renders the symbol instead of a blank box.
const CURRENCY_NAME: String = "Lifeons"
const CURRENCY_SYMBOL: String = "ℒ"

static func body_font() -> FontFile:
	var body: FontFile = load("res://assets/fonts/Body.ttf")
	var display: FontFile = load("res://assets/fonts/Display.otf")
	if not display.get_rids().is_empty() and body.fallbacks.is_empty():
		body.fallbacks = [display]
	return body

static func display_font() -> FontFile:
	return load("res://assets/fonts/Display.otf")

static func panel(color: Color = WHITE, radius: int = 18, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(width)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

static func theme() -> Theme:
	var t = Theme.new()
	t.default_font = body_font()
	t.default_font_size = 16
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", WHITE)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_stylebox("normal", "Button", panel(WHITE, 10, LINE, 1))
	t.set_stylebox("hover", "Button", panel(PALE, 10, TEAL, 1))
	t.set_stylebox("pressed", "Button", panel(TEAL, 10, TEAL, 1))
	t.set_stylebox("focus", "Button", panel(Color.TRANSPARENT, 10, GOLD, 2))
	t.set_stylebox("disabled", "Button", panel(Color("ebece5"), 10))
	t.set_stylebox("normal", "LineEdit", panel(PAPER, 9, LINE, 1))
	t.set_stylebox("focus", "LineEdit", panel(WHITE, 9, TEAL, 2))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", TEAL)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	var bar_bg = panel(LINE, 5)
	var bar_fill = panel(TEAL, 5)
	for b in [bar_bg, bar_fill]:
		b.content_margin_top=0
		b.content_margin_bottom=0
		b.content_margin_left=0
		b.content_margin_right=0
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_stylebox("panel", "PopupPanel", panel(WHITE, 12, LINE, 1))
	t.set_stylebox("panel", "PopupMenu", panel(WHITE, 12, LINE, 1))
	t.set_color("font_color", "PopupMenu", INK)
	return t
