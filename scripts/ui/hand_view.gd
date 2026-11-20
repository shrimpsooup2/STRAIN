extends Control
## Your left hand, drawn in chunky pixels. Green lines grow out of the palm
## cut with infection stage + progress. Used by the HAND menu and the medbay scan.
##   var hv = preload("res://scripts/ui/hand_view.gd").new()
##   hv.stage = Game.stage; hv.progress = Game.stage_progress

const PX := 2  ## logical pixel size
const SKIN := Color("d8a888")
const SKIN_SHADE := Color("b88468")
const LINE := Color("70d850")
const LINE_DIM := Color("3c8a30")
const BG := Color("141c24")

var stage := 0
var progress := 0.0
var clean := false  ## endings: draw the hand with no lines at all

var _branches: Array = []  ## each: {"pts": PackedVector2Array, "start": float}
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(96, 112)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build_branches()


func _process(dt: float) -> void:
	_t += dt
	if stage >= 2:
		queue_redraw()


## Growth 0..6 (stage + progress fraction) mapped to how far along each branch is drawn.
func _growth() -> float:
	return clampf(float(stage) + progress / 100.0, 0.0, 6.0)


func _build_branches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_branches.clear()
	var cut := Vector2(48, 50)
	# Trunk lines head down the wrist and forearm; side lines curl into fingers.
	var targets := [
		{"dir": Vector2(0, 1), "len": 60, "start": 0.0},
		{"dir": Vector2(-0.3, 1), "len": 55, "start": 0.6},
		{"dir": Vector2(0.35, 1), "len": 50, "start": 1.2},
		{"dir": Vector2(-0.5, -1), "len": 26, "start": 2.0},
		{"dir": Vector2(0.1, -1), "len": 30, "start": 2.4},
		{"dir": Vector2(0.6, -1), "len": 24, "start": 3.0},
		{"dir": Vector2(-1, 0.4), "len": 22, "start": 3.5},
		{"dir": Vector2(1, 0.6), "len": 22, "start": 4.0},
		{"dir": Vector2(-0.1, 1), "len": 62, "start": 4.5},
		{"dir": Vector2(0.15, 1), "len": 62, "start": 5.0},
	]
	for t in targets:
		var pts := PackedVector2Array()
		var p := cut
		var d: Vector2 = (t["dir"] as Vector2).normalized()
		pts.append(p)
		var steps := int(t["len"]) / 4
		for i in steps:
			d = d.rotated(rng.randf_range(-0.5, 0.5)).lerp(t["dir"].normalized(), 0.35).normalized()
			p += d * 4.0
			pts.append(p)
		_branches.append({"pts": pts, "start": t["start"]})


func _snap(v: Vector2) -> Vector2:
	return (v / PX).floor() * PX


func _r(x: int, y: int, w: int, h: int, c: Color, off: Vector2) -> void:
	draw_rect(Rect2(Vector2(x, y) + off, Vector2(w, h)), c)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var off := Vector2((size.x - 96) / 2.0, 0).floor()
	if stage >= 2 and not clean:
		# Tremor: 1px shudder.
		if fmod(_t * 9.0, 1.0) < 0.3 + 0.1 * stage:
			off.x += PX * (1 if int(_t * 31.0) % 2 == 0 else -1)
	# Forearm, wrist, palm, fingers, thumb. Blocky on a 2px grid.
	_r(34, 76, 28, 36, SKIN_SHADE, off)
	_r(36, 76, 24, 36, SKIN, off)
	_r(30, 40, 36, 38, SKIN, off)
	_r(30, 72, 36, 6, SKIN_SHADE, off)
	_r(30, 14, 8, 28, SKIN, off)
	_r(40, 8, 8, 34, SKIN, off)
	_r(50, 10, 8, 32, SKIN, off)
	_r(60, 18, 6, 24, SKIN, off)
	_r(18, 44, 12, 8, SKIN, off)
	_r(14, 38, 8, 10, SKIN, off)
	for x in [38, 48, 58]:
		_r(x, 14, 2, 26, SKIN_SHADE, off)
	# The cut.
	_r(42, 48, 12, 2, Color("8a2a2a"), off)
	if clean:
		return
	var g := _growth()
	for b in _branches:
		var start: float = b["start"]
		if g <= start:
			continue
		var frac := clampf((g - start) / 1.2, 0.0, 1.0)
		var pts: PackedVector2Array = b["pts"]
		var n := maxi(2, int(pts.size() * frac))
		for i in n - 1:
			var a := _snap(pts[i]) + off
			var c := _snap(pts[i + 1]) + off
			var col := LINE if i < n - 3 or stage >= 4 else LINE_DIM
			draw_line(a, c, col, PX)
	# Stage 0 still shows a faint ring around the cut.
	if g < 0.4:
		_r(40, 46, 16, 2, LINE_DIM, off)
		_r(40, 50, 16, 2, LINE_DIM, off)
