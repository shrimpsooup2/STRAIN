extends RefCounted
## Shared look for genes: type colours, pixel-text drawing helpers.

const C_DMG := Color("e06048")
const C_FILM := Color("58a8e8")
const C_HEAL := Color("e888b0")
const C_ORDER := Color("e8c840")   ## genes that care where they sit (LINK / DEEP / ALONE / REACH)
const C_SEVER := Color("d05050")
const C_UTIL := Color("b0b8c8")
const C_PASSIVE := Color("9888c0")
const C_JUNK := Color("6a7a30")


## Gene category by base id: "dmg" | "film" | "heal" | "order" | "util" | "passive" | "junk".
const CAT := {
	"lyse": "dmg", "swarm": "dmg", "spike": "dmg", "siphon": "dmg", "rot": "dmg",
	"needle": "dmg", "lance": "dmg", "cascade": "dmg", "fever": "dmg", "bloom": "dmg",
	"drifter": "dmg", "hopper": "dmg",
	"film": "film", "membrane": "film", "sporewall": "film", "clot": "film", "cyst": "film",
	"mirror": "film", "terminator": "film",
	"divide": "heal",
	"signal": "order", "hymn": "order", "drone": "order", "chant": "order",
	"whisper": "order", "lullaby": "order", "hush": "order", "quorum": "order",
	"crescendo": "order",
	"promoter": "util", "catalyst": "util", "splicer": "util", "invert": "util",
	"pull": "util", "spore": "util", "primer": "util", "echo": "util", "proofread": "util",
	"ledger": "util", "tripwire": "util", "relay": "util",
	"pact_coil": "passive", "thick_wall": "passive",
	"g_lash": "dmg", "g_root": "film", "g_chorus": "order", "g_bloom": "heal", "g_weave": "util",
	"overgrowth": "junk", "scab_plate": "junk",
}


## Category of a gene id ("+" upgrades share their base's category).
static func gene_cat(id: String) -> String:
	var b: String = Cards.base_id(id)
	if CAT.has(b):
		var cat: String = CAT[b]
		return cat
	var c: Dictionary = Cards.card(b)
	var kind: String = String(c.get("kind", "gene"))
	if kind == "junk" or kind == "passive":
		return kind
	var fx: Array = c.get("fx", [])
	if fx.is_empty():
		return "util"
	var first: Dictionary = fx[0]
	match String(first.get("t", "")):
		"dmg", "drain", "drifter", "rot", "stagger_dmg", "latent":
			return "dmg"
		"film":
			return "film"
		"heal":
			return "heal"
		"chain", "dmg_count", "prime":
			return "order"
	return "util"


static func cat_color(cat: String) -> Color:
	match cat:
		"dmg":
			return C_DMG
		"film":
			return C_FILM
		"heal":
			return C_HEAL
		"order":
			return C_ORDER
		"passive":
			return C_PASSIVE
		"junk":
			return C_JUNK
	return C_UTIL


static func gene_color(id: String) -> Color:
	if Cards.is_green(id):
		return UI.C_GREEN
	return cat_color(gene_cat(id))


## 7x7 glyphs for gene modes / enemy marks, drawn with bitmap().
const GLYPH_DEEP := ["#.....#", ".#...#.", "..#.#..", "#..#..#", ".#...#.", "..#.#..", "...#..."]
const GLYPH_LONE := ["..###..", ".#...#.", "#.....#", "#..#..#", "#.....#", ".#...#.", "..###.."]
const GLYPH_SEVER := ["......#", ".....#.", "###.#..", "...#...", "..#.###", ".#.....", "#......"]
const GLYPH_TEETH := ["#######", "#.#.#.#", ".......", ".......", ".......", "#.#.#.#", "#######"]
const GLYPH_KNOT := ["#.....#", "##...##", "###.###", "...#...", "###.###", "##...##", "#.....#"]


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
