extends RefCounted
## Shared look for genes: type colours, pixel-text drawing helpers.

const C_DMG := Color("e06048")
const C_FILM := Color("58a8e8")
const C_HEAL := Color("e888b0")
const C_CHORUS := Color("e8c840")
const C_UTIL := Color("b0b8c8")
const C_PASSIVE := Color("9888c0")
const C_JUNK := Color("6a7a30")


static func gene_color(id: String) -> Color:
	var c: Dictionary = Cards.card(id)
	if c.get("green", false):
		return UI.C_GREEN
	match String(c.get("kind", "gene")):
		"junk":
			return C_JUNK
		"passive":
			return C_PASSIVE
	var fx: Array = c.get("fx", [])
	if fx.is_empty():
		return C_UTIL
	match String(fx[0]["t"]):
		"dmg", "dmg_chorus", "drain", "drifter", "rot":
			return C_DMG
		"film":
			return C_FILM
		"heal":
			return C_HEAL
		"chorus", "if_chorus":
			return C_CHORUS
	return C_UTIL


## Draw 8px pixel text with its top-left corner at `pos`.
static func text(ci: CanvasItem, pos: Vector2, s: String, color: Color, max_w := -1) -> void:
	ci.draw_string(UI.font, pos + Vector2(0, 8), s, HORIZONTAL_ALIGNMENT_LEFT, max_w, 8, color)


static func text_w(s: String) -> float:
	return s.length() * 8.0


static var _styles: Dictionary = {}


## Dark HUD box in the theme's style.
static func box(ci: CanvasItem, r: Rect2, dark := true, border := Color(0, 0, 0, 0)) -> void:
	var bg := UI.C_THINK_BG if dark else UI.C_PAPER
	var bd := border if border.a > 0.0 else (UI.C_ACCENT.darkened(0.3) if dark else UI.C_BORDER)
	var key := bg.to_html() + bd.to_html()
	if not _styles.has(key):
		_styles[key] = UI.box_style(bg, bd)
	ci.draw_style_box(_styles[key], r)


## Draws a pixel bitmap (rows of '#' / '.') scaled by `px`.
static func bitmap(ci: CanvasItem, pos: Vector2, rows: Array, color: Color, px := 2) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				ci.draw_rect(Rect2(pos + Vector2(x * px, y * px), Vector2(px, px)), color)
