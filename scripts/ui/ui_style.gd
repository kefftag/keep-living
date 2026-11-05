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

# Emergency / feedback
const ALERT_DARK := Color("#8E0009")   # EEW banner flash low point
const WHITE := Color("#FFFFFF")
const HURT := Color("#B0000C")         # hurt vignette edge
const PROMPT_BG := Color(0.06, 0.07, 0.08, 0.72)  # sign plate under the crosshair
const KEYCAP_TEXT := INK
const RING_TRACK := Color(1, 1, 1, 0.16)
const OVERLAY_DIM := Color(0.02, 0.02, 0.04, 0.82)
const OVERLAY_BG := Color(0.11, 0.12, 0.13, 0.98)

# --- Type sizes (1600x900 canvas; nothing under 16) -----------------------------
const FS_SMALL := 16     # controls chips, fine print
const FS_HUD := 18       # stat labels, inventory, entrances
const FS_PROMPT := 21
const FS_FEED := 20
const FS_BODY := 20      # overlay body text
const FS_NOTE := 18      # overlay captions / dim notes
const FS_BUTTON := 20
const FS_HEADING := 34
const FS_TITLE := 52
const FS_CLOCK := 32

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
	t.default_font_size = FS_HUD

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
	t.set_font_size("font_size", "Button", FS_BUTTON)
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


## Key cap: a small square sign-yellow plate with the key letter in ink.
static func keycap_box() -> StyleBoxFlat:
	var s := box(SIGN_YELLOW, Color(0, 0, 0, 0), 0, 4)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	s.border_width_bottom = 3   # a little depth, like a real key
	s.border_color = SIGN_YELLOW.darkened(0.45)
	return s


## Controls-hint chip around a key cap and its label.
static func chip_box() -> StyleBoxFlat:
	var s := box(Color(0.06, 0.07, 0.08, 0.6), Color(1, 1, 1, 0.1), 0, 4)
	s.content_margin_left = 6
	s.content_margin_right = 10
	return s


## NHK-style emergency strips (EEW banner, danger ticker).
static func alert_box(pad: int = 10) -> StyleBoxFlat:
	var s := box(ALERT_RED, Color(0, 0, 0, 0), 0, pad)
	s.border_width_bottom = 3
	s.border_color = WHITE
	return s


## The little white "速報" tag at the left of a ticker strip.
static func tag_box() -> StyleBoxFlat:
	var s := box(WHITE, Color(0, 0, 0, 0), 0, 4)
	s.content_margin_left = 8
	s.content_margin_right = 8
	return s


## Full-screen hurt vignette + low-health desaturation (canvas_item, reads the
## screen behind it). `hurt` 0..1 is the bite flash, `low` 0..1 how far below
## 30% health the player is.
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float hurt = 0.0;
uniform float low = 0.0;
uniform vec4 hurt_color : source_color = vec4(0.69, 0.0, 0.05, 1.0);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec2 d = SCREEN_UV - vec2(0.5);
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(d);
	float edge = smoothstep(0.32, 0.95, r);
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey), low * 0.8);
	c *= 1.0 - edge * (0.25 + 0.45 * low) * low;
	float flash = edge * hurt;
	c = mix(c, hurt_color.rgb, clamp(flash * 0.8 + edge * low * 0.18, 0.0, 0.85));
	COLOR = vec4(c, 1.0);
}
"""


static func vignette_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("hurt_color", HURT)
	return m


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)
