extends Control
## The CLEAN read bar. A cursor sweeps once across a track (~0.55s). Pressing
## interact (or clicking) while it is inside the band = CLEAN read.
##   var rb := ReadBar.new()
##   var clean: bool = await rb.run(host, 0.30, "READ", Vector2(132, 124))
## `auto_clean` skips the sweep and returns true (green genes).

const GeneArt := preload("res://scripts/run/gene_art.gd")

signal finished(clean: bool)

const TRACK_W := 120.0
const TRACK_H := 8.0
const SWEEP := 0.55

var band_frac := 0.3
var band_start := 0.5
var label_text := "READ"
var t := 0.0
var cursor := 0.0
var done := false
var result := false
var _layer: CanvasLayer
var _flash := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(TRACK_W + 8, 26)


func run(host: Node, p_band: float, p_label := "READ", at := Vector2(-1, -1)) -> bool:
	band_frac = clampf(p_band, 0.05, 0.9)
	# The band sits in the back half so there is a beat to react.
	band_start = randf_range(0.35, maxf(0.36, 1.0 - band_frac - 0.04))
	label_text = p_label
	_layer = CanvasLayer.new()
	_layer.layer = 30
	host.add_child(_layer)
	if at.x < 0:
		at = Vector2(roundf((384 - size.x) / 2.0), 120)
	position = at
	_layer.add_child(self)
	var sfx := host.get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", "tick", 0.8)
	while not done:
		await get_tree().process_frame
		t += get_process_delta_time()
		cursor = clampf(t / SWEEP, 0.0, 1.0)
		queue_redraw()
		if t >= SWEEP + 0.06:
			done = true
			result = false
	# Brief hold so the player sees where it stopped.
	var hold := 0.0
	while hold < 0.16:
		await get_tree().process_frame
		hold += get_process_delta_time()
		_flash = maxf(0.0, 1.0 - hold / 0.16)
		queue_redraw()
	finished.emit(result)
	_layer.queue_free()
	return result


func _input(e: InputEvent) -> void:
	if done or t <= 0.0:
		return
	var hit := false
	if e.is_action_pressed("interact") or e.is_action_pressed("ui_accept"):
		hit = true
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		hit = true
	if not hit:
		return
	get_viewport().set_input_as_handled()
	done = true
	result = cursor >= band_start and cursor <= band_start + band_frac
	_flash = 1.0
	queue_redraw()


func _draw() -> void:
	var track := Rect2(Vector2(4, 12), Vector2(TRACK_W, TRACK_H))
	GeneArt.text(self, Vector2(4, 0), label_text, UI.C_THINK_FG)
	if not done:
		var hint := "Z/CLICK"
		GeneArt.text(self, Vector2(size.x - 4 - GeneArt.text_w(hint), 0), hint, UI.C_DIM)
	draw_rect(track.grow(2), Color(0.02, 0.03, 0.04, 0.92))
	draw_rect(track, Color("1c2630"))
	var band := Rect2(track.position + Vector2(band_start * TRACK_W, 0), Vector2(band_frac * TRACK_W, TRACK_H))
	var bcol := UI.C_GREEN
	if done and not result:
		bcol = bcol.darkened(0.5)
	draw_rect(band, bcol)
	var cx := track.position.x + cursor * TRACK_W
	var ccol := UI.C_PAPER
	if done:
		ccol = UI.C_GREEN.lightened(0.4) if result else UI.C_BAD
	draw_rect(Rect2(Vector2(cx - 1, track.position.y - 3), Vector2(3, TRACK_H + 6)), ccol)
	if done and _flash > 0.0:
		var word := "CLEAN" if result else "LOOSE"
		draw_rect(track.grow(2), Color(ccol, 0.25 * _flash), false, 1.0)
		GeneArt.text(self, Vector2(roundf((size.x - GeneArt.text_w(word)) / 2.0), 0), word, ccol)
