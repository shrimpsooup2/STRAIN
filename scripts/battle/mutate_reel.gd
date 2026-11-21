extends Control
## MUTATE reel: three rows of gene names spin, ticking and slowing. Interact /
## click stops it (it eases onto the next name); it auto-stops after 2.5s.
##   var reel := MutateReel.new()
##   var new_id: String = await reel.run(host, pool, current_id)

const GeneArt := preload("res://scripts/run/gene_art.gd")

signal finished(id: String)

const W := 132.0
const ROW_H := 12.0
const AUTO_STOP := 2.5

var reel: Array = []
var offset := 0.0
var speed := 16.0
var t := 0.0
var stopping := false
var stopped := false
var _last_tick := -1
var _layer: CanvasLayer
var _host: Node


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, ROW_H * 3 + 28)


func run(host: Node, pool: Array, cur: String) -> String:
	_host = host
	var src: Array = []
	for v in pool:
		var s := String(v)
		if s != cur and s != "":
			src.append(s)
	if src.is_empty():
		src = pool.duplicate()
	if src.is_empty():
		return cur
	while reel.size() < 24:
		var batch := src.duplicate()
		batch.shuffle()
		reel.append_array(batch)
	offset = randf() * reel.size()
	speed = randf_range(14.0, 18.0)
	_layer = CanvasLayer.new()
	_layer.layer = 30
	host.add_child(_layer)
	position = Vector2(roundf((384 - W) / 2.0), 70)
	_layer.add_child(self)
	while not stopped:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		if t >= AUTO_STOP:
			stopping = true
		# Natural slow-down; much faster once a stop is requested.
		speed *= pow(0.12 if stopping else 0.62, dt)
		if stopping and speed < 3.0:
			speed = 3.0
		var prev := offset
		offset += speed * dt
		var cell := int(floor(offset))
		if cell != _last_tick:
			_last_tick = cell
			_sfx("tick", 0.8 + minf(speed, 18.0) * 0.03)
		if stopping and speed <= 3.0 and floor(prev) != floor(offset):
			offset = floor(offset)
			stopped = true
		queue_redraw()
	var idx := posmod(int(round(offset)), reel.size())
	var out: String = String(reel[idx])
	_sfx("mutate", 1.0)
	var hold := 0.0
	while hold < 0.45:
		await get_tree().process_frame
		hold += get_process_delta_time()
		queue_redraw()
	finished.emit(out)
	_layer.queue_free()
	return out


func _sfx(n: String, p: float) -> void:
	var sfx: Node = _host.get_node_or_null("/root/Sfx") if _host != null else null
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", n, p)


func _input(e: InputEvent) -> void:
	if stopped or stopping or t < 0.15:
		return
	var hit := e.is_action_pressed("interact") or e.is_action_pressed("ui_accept")
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		hit = true
	if hit:
		get_viewport().set_input_as_handled()
		stopping = true


func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, Color(0.02, 0.03, 0.04, 0.94))
	draw_rect(frame, GeneArt.C_JUNK.lightened(0.3), false, 2.0)
	var title := "MUTATING" if not stopped else "TAKES"
	GeneArt.text(self, Vector2(roundf((W - GeneArt.text_w(title)) / 2.0), 3), title, UI.C_WARN)
	var top := 15.0
	var frac := offset - floorf(offset)
	# Rows: index-1, index, index+1 around the centre, scrolled by frac.
	for k in range(-2, 3):
		var y := top + ROW_H + (k - frac) * ROW_H
		if y < top - 2 or y > top + ROW_H * 2 + 2:
			continue
		var idx := posmod(int(floorf(offset)) + k, reel.size())
		var gid: String = String(reel[idx])
		var nm: String = String(Cards.card(gid).get("name", gid))
		var centre := absf(y - (top + ROW_H)) < ROW_H * 0.5
		var col := GeneArt.gene_color(gid) if centre else UI.C_DIM
		GeneArt.text(self, Vector2(roundf((W - GeneArt.text_w(nm)) / 2.0), roundf(y + 2)), nm, col)
	var sel := Rect2(Vector2(4, top + ROW_H), Vector2(W - 8, ROW_H))
	draw_rect(sel, UI.C_WARN if stopped else UI.C_PAPER, false, 1.0)
	if not stopped:
		GeneArt.text(self, Vector2(roundf((W - GeneArt.text_w("Z STOP")) / 2.0), top + ROW_H * 3), "Z STOP", UI.C_DIM)
