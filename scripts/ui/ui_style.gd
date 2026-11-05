extends RefCounted
## The "Office hours" look (docs/UI_PLAN.md): Tokyo signage, office greys and
## paper, sign yellow and hanko red. One Theme, built in code, set on the HUD
## root. Everything that picks a colour or font goes through here.

# --- Palette ------------------------------------------------------------------
const PAPER := Color("#F2EFE6")        # text on dark, documents
const INK := Color("#1E2226")          # text on paper
const DIM := Color("#9BA1A6")          # secondary text
const OFFICE := Color(0.169, 0.184, 0.2, 0.88)  # #2B2F33, fluorescent-office grey panels
const NAVY := Color("#1F2A44")         # suit navy: buttons, headers
const LINE_GREEN := Color("#80C241")   # Yamanote line green: good / safe
const SIGN_YELLOW := Color("#F5C400")  # station-sign yellow: warnings, keys
const HANKO := Color("#C8102E")        # seal red: stamps, accents (fills, borders)
const HANKO_TEXT := Color("#E8475A")   # hanko red lifted for text on dark panels
const ALERT_RED := Color("#D7000F")    # emergency banners
const ALERT_TEXT := Color("#FF5A4F")   # danger text on dark panels
const LCD := Color("#CFE8E3")          # phone / LCD glow

# Bars
const BAR_HEALTH := Color("#D8433F")
const BAR_HUNGER := Color("#E0A23A")
const BAR_THIRST := Color("#3D8FD6")
const BAR_NOISE := Color("#C9CCCF")
const BAR_TRACK := Color(1, 1, 1, 0.09)

# --- Fonts --------------------------------------------------------------------
const FONT_UI := "res://assets/fonts/BIZUDPGothic-Regular.ttf"       # Morisawa BIZ UD, OFL
const FONT_UI_BOLD := "res://assets/fonts/BIZUDPGothic-Bold.ttf"
const FONT_CLOCK := "res://assets/fonts/DSEG7Classic-Bold.ttf"       # 7-segment, OFL

const RADIUS := 2   # signs and forms are square
const PAD := 12


static func font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font:
			return f
	return ThemeDB.fallback_font


static func ui_font() -> Font:
	return font(FONT_UI)


static func bold_font() -> Font:
	return font(FONT_UI_BOLD)


static func clock_font() -> Font:
	return font(FONT_CLOCK)


## A flat box. `stripe` > 0 draws only a top rule in `border` (station-sign
## colour bar); otherwise `border` is a 1 px outline when it's visible.
static func box(bg: Color, border: Color = Color(0, 0, 0, 0), stripe: int = 0, pad: int = PAD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(RADIUS)
	s.set_content_margin_all(pad)
	if stripe > 0:
		s.border_width_top = stripe
		s.border_color = border
	elif border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	return s


## HUD panel: office grey with a coloured top rule (green by day, red by night).
static func panel_box(stripe_color: Color = LINE_GREEN) -> StyleBoxFlat:
	return box(OFFICE, stripe_color, 3)


static func bar_box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(1)
	return s


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = ui_font()
	t.default_font_size = 16

	t.set_color("font_color", "Label", PAPER)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("outline_size", "Label", 3)
	t.set_constant("line_spacing", "Label", 2)

	t.set_font("normal_font", "RichTextLabel", ui_font())
	t.set_font("bold_font", "RichTextLabel", bold_font())
	t.set_color("default_color", "RichTextLabel", PAPER)
	t.set_color("font_outline_color", "RichTextLabel", Color(0, 0, 0, 0.75))
	t.set_constant("outline_size", "RichTextLabel", 3)

	t.set_stylebox("panel", "PanelContainer", panel_box())

	t.set_stylebox("background", "ProgressBar", bar_box(BAR_TRACK))
	t.set_stylebox("fill", "ProgressBar", bar_box(PAPER))

	# Buttons: navy plates like a station's information board. Hover and focus
	# light the yellow sign edge; pressing stamps it red.
	t.set_font("font", "Button", ui_font())
	t.set_font_size("font_size", "Button", 17)
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_hover_color", "Button", PAPER)
	t.set_color("font_focus_color", "Button", PAPER)
	t.set_color("font_pressed_color", "Button", PAPER)
	t.set_stylebox("normal", "Button", box(NAVY, Color(1, 1, 1, 0.14)))
	t.set_stylebox("hover", "Button", box(NAVY.lightened(0.12), SIGN_YELLOW))
	t.set_stylebox("focus", "Button", box(NAVY.lightened(0.12), SIGN_YELLOW))
	t.set_stylebox("pressed", "Button", box(HANKO, HANKO.lightened(0.3)))

	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)
