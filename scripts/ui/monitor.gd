extends CanvasLayer
## Wordless monitor playback: "cctv" (lockdown night) or "comms" (satellite timelapse).
##   var mon = preload("res://scripts/ui/monitor.gd").new()
##   mon.kind = "cctv"
##   add_child(mon)
##   await mon.finished      # frees itself
## Interact skips after 1.5s.

signal finished

const SCR := Rect2(52, 22, 280, 156)  ## screen area inside the bezel
const PX := 2

var kind := "cctv"
var _t := 0.0
var _canvas: Control
var _done := false

# A 40x18 blocky world map: '#' land, '.' sea.
const MAP := [
	"........................................",
	"...######.........#####.................",
	"..#########.....##########.....######...",
	"...########....############..#########..",
	"....######......##########...##########.",
	".....####........#######.....#########..",
	"......###.........#####........######...",
	"......####........######.........###....",
	".......####........####...........#.....",
	"........###........###..................",
	"........##.........##.........####......",
	".........#...................######.....",
	"..............................####......",
	"........................................",
]
const STATION := Vector2i(22, 4)
const HOME := Vector2i(27, 6)


func _ready() -> void:
	layer = 65
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var bezel := UI.panel(Rect2(SCR.position - Vector2(8, 8), SCR.size + Vector2(16, 16)), true)
	add_child(bezel)
	_canvas = Control.new()
	_canvas.position = SCR.position
	_canvas.size = SCR.size
	_canvas.clip_contents = true
	_canvas.draw.connect(_draw_screen)
	add_child(_canvas)


func _duration() -> float:
	return 11.0 if kind == "cctv" else 9.0


func _process(dt: float) -> void:
	_t += dt
	_canvas.queue_redraw()
	if _t >= _duration():
		_finish()


func _input(e: InputEvent) -> void:
	if e.is_action_pressed("interact") or e.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		if _t > 1.5:
			_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


func _txt(pos: Vector2, s: String, c: Color) -> void:
	_canvas.draw_string(UI.font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)


# ------------------------------------------------------------------ CCTV

func _draw_screen() -> void:
	if kind == "cctv":
		_draw_cctv()
	else:
		_draw_comms()
	# Scanlines.
	for y in range(0, int(SCR.size.y), 4):
		_canvas.draw_rect(Rect2(0, y, SCR.size.x, 1), Color(0, 0, 0, 0.25))


func _figure(x: float, y: float, c: Color, frame: int) -> void:
	var p := Vector2(x, y).floor()
	_canvas.draw_rect(Rect2(p + Vector2(2, 0), Vector2(4, 4)), c)        # head
	_canvas.draw_rect(Rect2(p + Vector2(0, 4), Vector2(8, 8)), c)        # coat
	var leg := 2 if frame % 2 == 0 else 0
	_canvas.draw_rect(Rect2(p + Vector2(1 + leg, 12), Vector2(2, 4)), c.darkened(0.3))
	_canvas.draw_rect(Rect2(p + Vector2(5 - leg, 12), Vector2(2, 4)), c.darkened(0.3))


func _draw_cctv() -> void:
	var bg := Color("1c2620")
	var fg := Color("a8c8a0")
	var dim := Color("4c604c")
	_canvas.draw_rect(Rect2(Vector2.ZERO, SCR.size), bg)
	# Floor grid, walls, the airlock glass at x=150.
	for x in range(0, int(SCR.size.x), 20):
		_canvas.draw_rect(Rect2(x, 60, 1, 80), Color("26322a"))
	_canvas.draw_rect(Rect2(0, 56, SCR.size.x, 4), dim)
	_canvas.draw_rect(Rect2(0, 140, SCR.size.x, 4), dim)
	var glass_x := 150.0
	var door_close := clampf((_t - 8.0) / 0.8, 0.0, 1.0)
	_canvas.draw_rect(Rect2(glass_x, 60, 3, 80), Color("6a8a8a"))
	# Airlock door slab drops when lockdown completes.
	_canvas.draw_rect(Rect2(glass_x + 4, 60, 10, 80 * door_close), Color("8a3030"))
	# Six leave, one stays.
	for i in 6:
		var start := 0.6 + i * 0.9
		var x := 20.0 + (_t - start) * 60.0
		if _t < start:
			x = 20.0
		var y := 84.0 + (i % 3) * 14.0
		if x < SCR.size.x + 10:
			_figure(x, y, fg, int(_t * 8.0) + i)
	# The one who stays: walks to the glass and stops, hand on it.
	var sx := minf(30.0 + _t * 30.0, glass_x - 10.0)
	_figure(sx, 100, Color("e0e8d0"), int(_t * 8.0) if sx < glass_x - 10.0 else 0)
	if sx >= glass_x - 10.0:
		_canvas.draw_rect(Rect2(glass_x - 2, 104, 2, 2), Color("e0e8d0"))
	# Lights: red blink once sealed.
	if door_close >= 1.0 and fmod(_t, 0.6) < 0.3:
		_canvas.draw_rect(Rect2(glass_x - 2, 48, 18, 6), Color("e04040"))
	var secs := 11 * 60 + 58 + int(_t * 1.5)
	var stamp := "CAM 04  03:%02d:%02d" % [secs / 60 % 60, secs % 60]
	_txt(Vector2(6, 14), stamp, fg)
	if fmod(_t, 1.0) < 0.5:
		_canvas.draw_rect(Rect2(SCR.size.x - 14, 6, 6, 6), Color("e04040"))


# ------------------------------------------------------------------ COMMS

func _draw_comms() -> void:
	var sea := Color("0c1420")
	var land := Color("4a8a3c")
	var grey := Color("8a8a84")
	_canvas.draw_rect(Rect2(Vector2.ZERO, SCR.size), sea)
	var month := clampi(int(_t / 0.55) + 1, 1, 14)
	var radius := month * 1.35
	var cell := Vector2(6, 8)
	var origin := Vector2(20, 20)
	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			if row[x] != "#":
				continue
			var d := Vector2(x - STATION.x, (y - STATION.y) * 1.6).length()
			var c := grey if d <= radius else land
			_canvas.draw_rect(Rect2(origin + Vector2(x, y) * cell, cell - Vector2(1, 1)), c)
	var st := origin + Vector2(STATION) * cell
	if fmod(_t, 0.5) < 0.3:
		_canvas.draw_rect(Rect2(st + Vector2(1, 2), Vector2(4, 4)), Color("e04040"))
	if Game.lore.has("photo") and _t > 4.0:
		# Crosshair on the photo's coordinates.
		var hp := origin + Vector2(HOME) * cell + Vector2(2, 3)
		var c := Color("f0e070")
		_canvas.draw_rect(Rect2(hp + Vector2(-6, 0), Vector2(4, 1)), c)
		_canvas.draw_rect(Rect2(hp + Vector2(3, 0), Vector2(4, 1)), c)
		_canvas.draw_rect(Rect2(hp + Vector2(0, -6), Vector2(1, 4)), c)
		_canvas.draw_rect(Rect2(hp + Vector2(0, 3), Vector2(1, 4)), c)
	_txt(Vector2(6, 14), "COMPOSITE  M%02d / 14" % month, Color("a8c8d8"))
