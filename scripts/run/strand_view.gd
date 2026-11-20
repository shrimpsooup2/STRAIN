extends CanvasLayer
## Full-screen ordered list of a Strand, in read order.
##   "view"   browse; interact / back / menu closes → -1
##   "pick"   choose a gene → its index; back → -1
##   "place"  slide `moving` into a slot → insertion index (0..size); back → -1 if cancel allowed
## Usage: var i: int = await StrandView.new().run(self, strand, "pick", {"title": "..."})

signal done(result: int)

const GeneArt := preload("res://scripts/run/gene_art.gd")
const ROW_H := 10
const ROWS := 13
const LIST := Rect2(6, 4, 372, 158)
const DESC := Rect2(6, 164, 372, 48)

var strand: Array = []
var mode := "view"
var moving := ""
var title := ""
var allow_cancel := true
var cursor := 0
var _top := 0
var _canvas: Control
var _desc: Label
var _blink := 0.0
var _closed := false


## opts: title, moving (place), cancel (bool), cursor (int)
func run(parent: Node, p_strand: Array, p_mode: String, opts: Dictionary = {}) -> int:
	strand = p_strand.duplicate()
	mode = p_mode
	moving = String(opts.get("moving", ""))
	title = String(opts.get("title", "STRAND"))
	allow_cancel = bool(opts.get("cancel", true))
	var start: int = opts.get("cursor", strand.size() if mode == "place" else 0)
	cursor = clampi(start, 0, maxi(0, _count() - 1))
	layer = 50
	parent.add_child(self)
	_build()
	var r: int = await done
	queue_free()
	return r


func _count() -> int:
	return strand.size() + 1 if mode == "place" else strand.size()


## Item shown at display row i (in place mode the moving gene sits at the cursor).
func _item(i: int) -> String:
	if mode != "place":
		return strand[i]
	if i == cursor:
		return moving
	return strand[i if i < cursor else i - 1]


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_list)
	_canvas.gui_input.connect(_on_gui)
	add_child(_canvas)
	var dp := UI.panel(DESC, true)
	dp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dp)
	_desc = UI.label("", UI.C_THINK_FG)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(DESC.size.x - 14, 36)
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dp.add_child(_desc)
	_refresh()


func _process(dt: float) -> void:
	if mode == "place":
		_blink += dt
		_canvas.queue_redraw()


func _refresh() -> void:
	if cursor < _top:
		_top = cursor
	elif cursor >= _top + ROWS:
		_top = cursor - ROWS + 1
	_top = clampi(_top, 0, maxi(0, _count() - ROWS))
	if _count() == 0:
		_desc.text = "Nothing left in the Strand."
	else:
		var id := _item(cursor)
		var c: Dictionary = Cards.card(id)
		var head := "%s  COST %d. " % [c["name"], int(c["cost"])]
		if c["kind"] == "passive":
			head = "%s. " % c["name"]
		_desc.text = head + String(c["desc"])
	_canvas.queue_redraw()


func _draw_list() -> void:
	var ci := _canvas
	GeneArt.box(ci, LIST, false)
	var hint := "Z CLOSE"
	match mode:
		"pick":
			hint = "Z PICK  X BACK" if allow_cancel else "Z PICK"
		"place":
			hint = "UP/DN MOVE  Z SET"
	GeneArt.text(ci, LIST.position + Vector2(8, 5), title, UI.C_INK)
	GeneArt.text(ci, Vector2(LIST.end.x - 8 - GeneArt.text_w(hint), LIST.position.y + 5), hint, UI.C_BORDER)
	ci.draw_rect(Rect2(LIST.position.x + 6, LIST.position.y + 16, LIST.size.x - 12, 1), UI.C_BORDER)
	var n := _count()
	if n == 0:
		GeneArt.text(ci, LIST.position + Vector2(10, 22), "(EMPTY)", UI.C_DIM)
		return
	for row in mini(ROWS, n - _top):
		var i := _top + row
		var id := _item(i)
		var c: Dictionary = Cards.card(id)
		var y := LIST.position.y + 20 + row * ROW_H
		var x := LIST.position.x + 8
		var is_cur := i == cursor
		var is_moving := mode == "place" and is_cur
		if is_cur:
			var hl := UI.C_FOCUS
			if is_moving:
				hl = UI.C_WARN.lightened(0.5) if fmod(_blink, 0.6) < 0.4 else UI.C_FOCUS
			ci.draw_rect(Rect2(x - 2, y - 1, LIST.size.x - 12, ROW_H), hl)
			ci.draw_rect(Rect2(x - 2, y - 1, 3, ROW_H), UI.C_ACCENT)
		var ink := UI.C_INK
		if Cards.is_green(id):
			ink = UI.C_GREEN.darkened(0.45)
		elif Cards.is_junk(id):
			ink = GeneArt.C_JUNK.darkened(0.2)
		GeneArt.text(ci, Vector2(x + 4, y), ("+" if is_moving else "%02d" % (i + 1)), UI.C_BORDER)
		ci.draw_rect(Rect2(x + 24, y + 1, 6, 6), GeneArt.gene_color(id))
		ci.draw_rect(Rect2(x + 24, y + 1, 6, 1), GeneArt.gene_color(id).lightened(0.4))
		GeneArt.text(ci, Vector2(x + 34, y), String(c["name"]), ink)
		var cost := "P" if c["kind"] == "passive" else str(int(c["cost"]))
		GeneArt.text(ci, Vector2(x + 120, y), cost, UI.C_BORDER)
		GeneArt.text(ci, Vector2(x + 136, y), String(c["short"]), ink)
		var tag := ""
		if c.has("pact"):
			tag = "PACT %d" % int(c["pact"])
		elif Cards.is_green(id):
			tag = "GREEN"
		elif c["kind"] == "junk":
			tag = "JUNK"
		elif c["kind"] == "passive":
			tag = "PASSIVE"
		if tag != "":
			GeneArt.text(ci, Vector2(x + 228, y), tag, UI.C_GREEN.darkened(0.3) if tag == "GREEN" else UI.C_DIM)
	# Scroll arrows.
	if _top > 0:
		GeneArt.text(ci, Vector2(LIST.end.x - 16, LIST.position.y + 20), "^", UI.C_BORDER)
	if _top + ROWS < n:
		GeneArt.text(ci, Vector2(LIST.end.x - 16, LIST.end.y - 12), "v", UI.C_BORDER)


func _row_at(p: Vector2) -> int:
	if not LIST.has_point(p):
		return -1
	var row := int((p.y - (LIST.position.y + 19)) / ROW_H)
	if row < 0 or row >= ROWS:
		return -1
	var i := _top + row
	return i if i < _count() else -1


func _on_gui(e: InputEvent) -> void:
	if _closed or UI.busy:
		return
	if e is InputEventMouseMotion and mode != "place":
		var i := _row_at(e.position)
		if i >= 0 and i != cursor:
			cursor = i
			_refresh()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_move(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_move(1)
			MOUSE_BUTTON_LEFT:
				var i := _row_at(e.position)
				if i < 0:
					return
				if i == cursor or mode == "view":
					_finish(cursor)
				else:
					cursor = i
					_refresh()
			MOUSE_BUTTON_RIGHT:
				_cancel()


func _move(d: int) -> void:
	var n := _count()
	if n == 0:
		return
	cursor = clampi(cursor + d, 0, n - 1)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if _closed or UI.busy:
		return
	if e.is_action_pressed("move_up"):
		_move(-1)
	elif e.is_action_pressed("move_down"):
		_move(1)
	elif e.is_action_pressed("interact"):
		_finish(cursor)
	elif e.is_action_pressed("back") or (mode == "view" and e.is_action_pressed("menu")):
		_cancel()
	else:
		return
	get_viewport().set_input_as_handled()


func _cancel() -> void:
	if mode == "view" or allow_cancel:
		_closed = true
		done.emit(-1)


func _finish(i: int) -> void:
	if mode == "view":
		_cancel()
		return
	if _count() == 0:
		_cancel()
		return
	_closed = true
	done.emit(i)
