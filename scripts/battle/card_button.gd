extends Control
## One gene card in the Reader window (or a reward offer / the END button).
## Drawn entirely by hand so it stays crisp at 384x216.

signal pressed
signal hovered

const GeneArt := preload("res://scripts/run/gene_art.gd")

var id := ""            ## gene id; "" = empty slot (or caption button)
var caption := ""       ## non-empty → plain button with this text (END, SKIP)
var selected := false
var spent := false
var affordable := true
var cost_now := -1      ## shown cost (-1 = card cost)
var tag := ""           ## overrides the bottom line (e.g. "SILENCED")


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


func set_selected(v: bool) -> void:
	if v != selected:
		selected = v
		queue_redraw()


func _draw() -> void:
	var lift := Vector2(0, -3) if selected else Vector2.ZERO
	var r := Rect2(lift, size)
	if caption != "":
		var bg := UI.C_FOCUS if selected else UI.C_PAPER
		var bd := UI.C_ACCENT if selected else UI.C_BORDER
		draw_style_box(UI.box_style(bg, bd, 2 if selected else 1, 2, Vector4.ZERO), r)
		var tw := GeneArt.text_w(caption)
		GeneArt.text(self, lift + Vector2(roundf((size.x - tw) / 2.0), roundf(size.y / 2.0 - 4)), caption,
			UI.C_INK if affordable else UI.C_DIM)
		return
	if id == "":
		draw_rect(Rect2(Vector2(0, 0), size), Color(0.05, 0.07, 0.09, 0.6))
		draw_rect(Rect2(Vector2(0, 0), size), UI.C_BORDER.darkened(0.3), false, 1.0)
		GeneArt.text(self, Vector2(roundf(size.x / 2.0 - 12), roundf(size.y / 2.0 - 4)), "---", UI.C_DIM)
		return
	var c: Dictionary = Cards.card(id)
	var green := Cards.is_green(id)
	var passive: bool = c["kind"] == "passive"
	var tcol := GeneArt.gene_color(id)
	var bg := UI.C_FOCUS if selected else UI.C_PAPER
	if spent or passive:
		bg = Color("8a9298") if not selected else Color("a8b0b8")
	var bd := UI.C_BORDER
	if green:
		bd = UI.C_GREEN
	if selected:
		bd = UI.C_ACCENT if not green else UI.C_GREEN.lightened(0.3)
	var bw := 2 if (selected or green) else 1
	draw_style_box(UI.box_style(bg, bd, bw, 2, Vector4.ZERO), r)
	# Type band.
	draw_rect(Rect2(lift + Vector2(bw, bw), Vector2(size.x - bw * 2, 3)), tcol)
	var ink := UI.C_INK if affordable and not spent else Color("404850")
	if green and not spent:
		ink = Color("185018")
	var nm: String = c["name"]
	GeneArt.text(self, lift + Vector2(roundf((size.x - GeneArt.text_w(nm)) / 2.0), 7), nm, ink)
	# Cost pips / passive tag.
	var cy := lift.y + 19.0
	if passive:
		GeneArt.text(self, Vector2(roundf((size.x - 56) / 2.0), lift.y + 18), "PASSIVE", Color("383c58"))
	else:
		var cost := int(c["cost"]) if cost_now < 0 else cost_now
		if cost == 0:
			GeneArt.text(self, Vector2(roundf((size.x - 32) / 2.0), lift.y + 18), "FREE", Color("306848"))
		else:
			var total_w := cost * 7 - 2
			var x0 := roundf((size.x - total_w) / 2.0)
			var pc := UI.C_WARN if affordable else UI.C_BAD
			for i in cost:
				draw_rect(Rect2(x0 + i * 7, cy, 5, 5), UI.C_INK)
				draw_rect(Rect2(x0 + i * 7 + 1, cy + 1, 3, 3), pc)
	var bottom: String = c["short"] if tag == "" else tag
	if spent:
		bottom = "SPENT"
	var bc := ink if not spent else Color("303438")
	GeneArt.text(self, lift + Vector2(roundf((size.x - GeneArt.text_w(bottom)) / 2.0), 31), bottom, bc)
