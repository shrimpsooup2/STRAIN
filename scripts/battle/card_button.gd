extends Control
## One gene tile in the Reader window, or a plain caption button (END / MUT / SHOT).
## Drawn by hand so it stays crisp at 384x216.
## Tile states: spent, marked (teeth / knot / sever), knotted (+1 cost), faded "???",
## SKIP ghost, lit mode glyph (DEEP / ALONE), link target arrow (double when HELD), READ/NEXT zone.

signal pressed
signal hovered

const GeneArt := preload("res://scripts/run/gene_art.gd")

var id := ""            ## gene id; "" = empty slot (or caption button)
var caption := ""       ## non-empty → plain button with this text
var hotkey := ""        ## tiny key hint drawn under a caption ("E")
var selected := false
var spent := false
var affordable := true
var cost_now := -1      ## shown cost (-1 = card cost)
var tag := ""           ## overrides the bottom line
var marked := ""        ## "" | "gnaw" | "knot" | "sever" — enemy intends to eat / knot / cut this
var knotted := false    ## knotted this turn: costs +1
var faded := false      ## FADING medium: shows "???"
var ghost := ""         ## overlay word while animating out ("SKIP")
var mode := ""          ## "" | "deep" | "lone" — lit mode glyph
var link_target := false ## expressing this would LINK
var held := false       ## the link target is a HELD chain from last turn
var next_zone := false  ## tile sits in the NEXT zone (dimmer)
var pulse := 0.0        ## 0..1 highlight pulse (set by the battle each frame)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	mouse_entered.connect(func(): hovered.emit())


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()


func set_card(p_id: String, p_spent := false, p_afford := true, p_cost := -1) -> void:
	id = p_id
	spent = p_spent
	affordable = p_afford
	cost_now = p_cost
	queue_redraw()


## Sets every per-turn state flag at once (the battle calls this on refresh).
func set_state(st: Dictionary) -> void:
	marked = String(st.get("marked", ""))
	knotted = bool(st.get("knotted", false))
	faded = bool(st.get("faded", false))
	mode = String(st.get("mode", ""))
	link_target = bool(st.get("link", false))
	held = bool(st.get("held", false))
	next_zone = bool(st.get("next", false))
	ghost = String(st.get("ghost", ""))
	queue_redraw()


func set_selected(v: bool) -> void:
	if v != selected:
		selected = v
		queue_redraw()


## Text that is squeezed horizontally to fit `w` (keeps 8-char names legible).
func _fit_text(pos: Vector2, s: String, col: Color, w: float) -> void:
	var tw := GeneArt.text_w(s)
	if tw <= w:
		GeneArt.text(self, pos + Vector2(roundf((w - tw) / 2.0), 0), s, col)
		return
	var sx := w / tw
	draw_set_transform(pos, 0.0, Vector2(sx, 1.0))
	GeneArt.text(self, Vector2.ZERO, s, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var lift := Vector2(0, -3) if selected else Vector2.ZERO
	var r := Rect2(lift, size)
	if caption != "":
		var bg := UI.C_FOCUS if selected else UI.C_PAPER
		if not affordable:
			bg = Color("8a9298")
		var bd := UI.C_ACCENT if selected else UI.C_BORDER
		draw_style_box(UI.box_style(bg, bd, 2 if selected else 1, 2, Vector4.ZERO), r)
		var ty := roundf(size.y / 2.0 - 4)
		_fit_text(lift + Vector2(2, ty), caption, UI.C_INK if affordable else Color("404850"), size.x - 4)
		return
	if id == "":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.09, 0.6))
		draw_rect(Rect2(Vector2.ZERO, size), UI.C_BORDER.darkened(0.3), false, 1.0)
		_fit_text(Vector2(0, roundf(size.y / 2.0 - 4)), "---", UI.C_DIM, size.x)
		return
	var c: Dictionary = Cards.card(id)
	var green := Cards.is_green(id)
	var kind: String = String(c.get("kind", "gene"))
	var passive := kind == "passive"
	var junk := kind == "junk"
	var tcol := GeneArt.gene_color(id)
	if faded and not spent:
		tcol = UI.C_DIM
	var bg := UI.C_FOCUS if selected else UI.C_PAPER
	if spent or passive or (faded and not selected):
		bg = Color("8a9298") if not selected else Color("a8b0b8")
	if junk and not spent:
		bg = bg.lerp(GeneArt.C_JUNK, 0.35)
	if next_zone and not selected:
		bg = bg.darkened(0.18)
	var bd := UI.C_BORDER
	if green:
		bd = UI.C_GREEN
	if link_target and not spent:
		bd = GeneArt.C_ORDER.lerp(UI.C_PAPER, pulse * 0.5)
	if selected:
		bd = UI.C_ACCENT if not green else UI.C_GREEN.lightened(0.3)
	var bw := 2 if (selected or green or (link_target and not spent)) else 1
	draw_style_box(UI.box_style(bg, bd, bw, 2, Vector4.ZERO), r)
	draw_rect(Rect2(lift + Vector2(bw, bw), Vector2(size.x - bw * 2, 3)), tcol)
	var ink := UI.C_INK if affordable and not spent else Color("404850")
	if green and not spent:
		ink = Color("185018")
	var nm: String = String(c.get("name", id))
	if faded and not spent:
		nm = "???"
	_fit_text(lift + Vector2(3, 7), nm, ink, size.x - 6)
	# Cost pips / passive tag.
	var cy := lift.y + 19.0
	if faded and not spent:
		pass
	elif passive:
		_fit_text(Vector2(2, lift.y + 18), "PASSIVE", Color("383c58"), size.x - 4)
	elif junk and bool(c.get("unplayable", false)):
		_fit_text(Vector2(2, lift.y + 18), "INERT", Color("404828"), size.x - 4)
	else:
		var cost := int(c.get("cost", 0)) if cost_now < 0 else cost_now
		if cost == 0:
			_fit_text(Vector2(2, lift.y + 18), "FREE", Color("306848"), size.x - 4)
		else:
			var total_w := cost * 7 - 2
			var x0 := roundf((size.x - total_w) / 2.0)
			var pc := UI.C_WARN if affordable else UI.C_BAD
			if knotted:
				pc = Color("b070e0")
			for i in cost:
				draw_rect(Rect2(x0 + i * 7, cy, 5, 5), UI.C_INK)
				draw_rect(Rect2(x0 + i * 7 + 1, cy + 1, 3, 3), pc)
	var bottom: String = String(c.get("short", "")) if tag == "" else tag
	if faded and not spent:
		bottom = "FADED"
	if spent:
		bottom = "SPENT"
	var bc := ink if not spent else Color("303438")
	_fit_text(lift + Vector2(2, size.y - 12), bottom, bc, size.x - 4)
	# Mode glyph (top-right): the mode this gene would fire in right now.
	if mode != "" and not (faded and not spent):
		var g: Array = GeneArt.GLYPH_DEEP if mode == "deep" else GeneArt.GLYPH_LONE
		GeneArt.bitmap(self, lift + Vector2(size.x - 10, 5), g, GeneArt.C_ORDER if mode == "deep" else Color("80a8e8"), 1)
	# Enemy marks (top-left).
	if marked == "gnaw":
		GeneArt.bitmap(self, lift + Vector2(3, 5), GeneArt.GLYPH_TEETH, UI.C_BAD, 1)
		draw_rect(Rect2(lift, size), Color(UI.C_BAD, 0.12 + 0.12 * pulse))
	elif marked == "knot":
		GeneArt.bitmap(self, lift + Vector2(3, 5), GeneArt.GLYPH_KNOT, Color("b070e0"), 1)
		draw_rect(Rect2(lift, size), Color(0.69, 0.44, 0.88, 0.1 + 0.1 * pulse))
	elif marked == "sever":
		GeneArt.bitmap(self, lift + Vector2(3, 5), GeneArt.GLYPH_SEVER, GeneArt.C_SEVER, 1)
		draw_rect(Rect2(lift, size), Color(GeneArt.C_SEVER, 0.1 + 0.1 * pulse))
	if knotted and not spent:
		GeneArt.bitmap(self, lift + Vector2(3, size.y - 20), GeneArt.GLYPH_KNOT, Color("b070e0"), 1)
	# Link arrow: a small chevron on the left edge (two when it resumes a HELD chain).
	if link_target and not spent:
		var ax := lift.x - 1.0
		var ay := lift.y + size.y / 2.0
		var ac := GeneArt.C_ORDER
		draw_colored_polygon(PackedVector2Array([Vector2(ax - 3, ay - 4), Vector2(ax + 2, ay), Vector2(ax - 3, ay + 4)]), ac)
		if held:
			draw_colored_polygon(PackedVector2Array([Vector2(ax - 3, ay - 13), Vector2(ax + 2, ay - 9), Vector2(ax - 3, ay - 5)]), ac)
	if ghost != "":
		draw_rect(Rect2(lift, size), Color(0.02, 0.03, 0.04, 0.55))
		_fit_text(lift + Vector2(2, roundf(size.y / 2.0 - 4)), ghost, UI.C_BAD.lightened(0.2), size.x - 4)
