extends CanvasLayer
## Wordless monitor playback.
##   kind  "cctv"       CAM 04, 03:12: lockdown from inside, six into decon
##         "cctv_palm"  CAM 02, 03:20: the palm over the last dish
##         "comms"      satellite composite timelapse
##         "voicemail"  waveform playback; `level` 0 clean .. 3 not quite her
##   var mon = preload("res://scripts/ui/monitor.gd").new()
##   mon.set("kind", "voicemail"); mon.set("level", 2); mon.set("label", "MSG 3")
##   add_child(mon)
##   await mon.finished      # frees itself
## Interact skips after 1.5s.

signal finished

const SCR := Rect2(52, 22, 280, 156)  ## screen area inside the bezel
const PX := 2

var kind := "cctv"
var level := 0          ## voicemail degradation 0..3
var label := ""         ## voicemail header, e.g. "MSG 2  04:12"
var _t := 0.0
var _canvas: Control
var _done := false
var _beeped := {}

# A 40x14 blocky world map: '#' land, '.' sea.
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

const FG := Color("a8c8a0")
const DIM := Color("4c604c")
const COAT := Color("e0e8d0")
const RED := Color("e04040")


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
	Sfx.play("blip", 0.8)


func _duration() -> float:
	match kind:
		"cctv":
			return 12.0
		"cctv_palm":
			return 11.0
		"voicemail":
			return 8.0
	return 9.0


func _process(dt: float) -> void:
	_t += dt
	_canvas.queue_redraw()
	_cues()
	if _t >= _duration():
		_finish()


## One-shot sounds keyed to the playback clock.
func _cue(key: String, at: float, sfx: String, pitch := 1.0) -> void:
	if _t >= at and not _beeped.has(key):
		_beeped[key] = true
		Sfx.play(sfx, pitch, -6.0)


func _cues() -> void:
	match kind:
		"cctv":
			_cue("red", 1.0, "error", 0.7)
			_cue("door", 7.0, "door", 0.6)
			_cue("thud", 7.8, "thud", 0.8)
		"cctv_palm":
			_cue("cut", 3.2, "glitch", 0.6)
		"voicemail":
			if level >= 2:
				_cue("static", 2.0, "glitch", 0.5)
			if level >= 3:
				_cue("whisper", 5.0, "whisper", 0.9)


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


func _draw_screen() -> void:
	match kind:
		"cctv":
			_draw_cctv()
		"cctv_palm":
			_draw_palm()
		"voicemail":
			_draw_voicemail()
		_:
			_draw_comms()
	# Scanlines.
	for y in range(0, int(SCR.size.y), 4):
		_canvas.draw_rect(Rect2(0, y, SCR.size.x, 1), Color(0, 0, 0, 0.25))


## A walking figure, front-on (face pixels) or from behind (no face).
func _figure(x: float, y: float, c: Color, frame: int, back := false) -> void:
	var p := Vector2(x, y).floor()
	_canvas.draw_rect(Rect2(p + Vector2(2, 0), Vector2(4, 4)), c)        # head
	if not back:
		_canvas.draw_rect(Rect2(p + Vector2(3, 1), Vector2(1, 1)), c.darkened(0.5))
		_canvas.draw_rect(Rect2(p + Vector2(5, 1), Vector2(1, 1)), c.darkened(0.5))
	_canvas.draw_rect(Rect2(p + Vector2(0, 4), Vector2(8, 8)), c)        # coat
	var leg := 2 if frame % 2 == 0 else 0
	_canvas.draw_rect(Rect2(p + Vector2(1 + leg, 12), Vector2(2, 4)), c.darkened(0.3))
	_canvas.draw_rect(Rect2(p + Vector2(5 - leg, 12), Vector2(2, 4)), c.darkened(0.3))


func _stamp(cam: String, start_secs: int, rate: float) -> void:
	var secs := start_secs + int(_t * rate)
	_txt(Vector2(6, 14), "%s  03:%02d:%02d" % [cam, secs / 60 % 60, secs % 60], FG)
	if fmod(_t, 1.0) < 0.5:
		_canvas.draw_rect(Rect2(SCR.size.x - 14, 6, 6, 6), RED)


# ------------------------------------------------------------------ CCTV 03:12
# Corridor seen side-on. Wall panel at x=56. Decon door at x=200.
# The coat stands at the panel, back to the lens, the whole time.

func _draw_cctv() -> void:
	var red_on := _t >= 1.0
	var bg := Color("2a1c1c") if red_on and fmod(_t, 0.8) < 0.4 else Color("1c2620")
	_canvas.draw_rect(Rect2(Vector2.ZERO, SCR.size), bg)
	for x in range(0, int(SCR.size.x), 20):
		_canvas.draw_rect(Rect2(x, 60, 1, 80), Color("26322a"))
	_canvas.draw_rect(Rect2(0, 56, SCR.size.x, 4), DIM)
	_canvas.draw_rect(Rect2(0, 140, SCR.size.x, 4), DIM)
	# Wall panel.
	_canvas.draw_rect(Rect2(56, 66, 14, 12), Color("6a8a8a"))
	_canvas.draw_rect(Rect2(59, 69, 8, 3), RED if red_on else Color("60c060"))
	# Decon door frame + slab.
	var door_x := 200.0
	_canvas.draw_rect(Rect2(door_x - 2, 62, 2, 78), Color("6a8a8a"))
	_canvas.draw_rect(Rect2(door_x + 26, 62, 2, 78), Color("6a8a8a"))
	_txt(Vector2(door_x - 4, 54), "DECON", DIM)
	var close := clampf((_t - 7.0) / 0.8, 0.0, 1.0)
	# Six file in, one at a time; they vanish past the doorway.
	for i in 6:
		var start := 1.4 + i * 0.85
		if _t < start:
			continue
		var x := 90.0 + (_t - start) * 55.0
		if x > door_x + 6:
			continue
		var y := 96.0 + (i % 2) * 10.0
		_figure(x, y, FG, int(_t * 8.0) + i)
	_canvas.draw_rect(Rect2(door_x, 62, 26, 78 * close), Color("8a3030"))
	# The coat at the panel. Hand up. It does not turn.
	_figure(52, 84, COAT, 0, true)
	_canvas.draw_rect(Rect2(60, 80, 2, 6), COAT)
	if close >= 1.0:
		var cyc := int((_t - 7.8) * 160.0)
		_txt(Vector2(150, 152), "CYCLE %02d:%02d" % [cyc / 60, cyc % 60], RED)
		if fmod(_t, 0.6) < 0.3:
			_canvas.draw_rect(Rect2(door_x + 4, 48, 18, 6), RED)
	if red_on and _t < 3.0:
		_txt(Vector2(6, 30), "LOCKDOWN - INTERNAL", RED)
	_stamp("CAM 04", 12 * 60, 1.2)


# ------------------------------------------------------------------ CCTV 03:20
# The splice lab from above the door. A lamp, one dish, the coat behind it.

func _draw_palm() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, SCR.size), Color("141a16"))
	var lamp := Vector2(140, 92)
	# Light pool.
	for r in [44.0, 32.0, 20.0]:
		_canvas.draw_circle(lamp, r, Color(0.66, 0.78, 0.62, 0.08))
	# Bench.
	_canvas.draw_rect(Rect2(60, 96, 160, 22), Color("3a4a40"))
	_canvas.draw_rect(Rect2(60, 118, 160, 3), DIM)
	# Dish: tints green as it takes.
	var take := clampf((_t - 4.0) / 6.0, 0.0, 1.0)
	_canvas.draw_rect(Rect2(128, 100, 24, 6), Color("8a9a94"))
	_canvas.draw_rect(Rect2(130, 101, 20, 4), Color("1a2a1e").lerp(Color("4c9a3c"), take))
	# The coat, behind the bench, back to the lens.
	var p := Vector2(132, 70)
	_figure(p.x, p.y, COAT, 0, true)
	# Right arm out over the dish.
	var reach := clampf((_t - 1.0) / 1.2, 0.0, 1.0)
	_canvas.draw_rect(Rect2(p.x + 8, p.y + 8, 2 + 10 * reach, 3), COAT)
	var hand := Vector2(p.x + 10 + 10 * reach, p.y + 10)
	# The blade: a glint across the palm.
	if _t > 2.8 and _t < 3.6:
		var g := (_t - 2.8) / 0.8
		_canvas.draw_rect(Rect2(hand.x - 6 + 12 * g, hand.y - 2, 6, 1), Color("f0f0f0"))
	# Drops, after the cut. Slow, then steady. Held there.
	if _t > 3.4:
		var n := int((_t - 3.4) * 3.0)
		for i in n:
			var age := _t - 3.4 - i / 3.0
			var fy := minf(hand.y + 2 + age * 40.0, 101.0)
			if fy < 101.0:
				_canvas.draw_rect(Rect2(hand.x, fy, 1, 2), Color("6a1c1c").lerp(Color("4c9a3c"), take))
	_stamp("CAM 02", 20 * 60, 1.0)


# ------------------------------------------------------------------ VOICEMAIL
# A waveform. 0 clean speech; 1 gaps; 2 wind and static; 3 the same words,
# exactly the same, again and again.

func _draw_voicemail() -> void:
	var bg := Color("10161a")
	var wave := Color("a8c8d8")
	_canvas.draw_rect(Rect2(Vector2.ZERO, SCR.size), bg)
	_txt(Vector2(6, 14), label if label != "" else "VOICEMAIL", wave)
	var mid := 84.0
	_canvas.draw_rect(Rect2(8, mid, SCR.size.x - 16, 1), Color("26323a"))
	var rng := RandomNumberGenerator.new()
	var cols := int((SCR.size.x - 16) / 2)
	var head := int(clampf(_t / (_duration() - 0.5), 0.0, 1.0) * cols)
	for i in cols:
		var amp := 0.0
		match level:
			0:
				rng.seed = i * 7 + 3
				var word := sin(i * 0.21) * 0.5 + 0.5
				amp = word * rng.randf_range(6.0, 26.0) if fmod(i, 23.0) > 3.0 else 1.0
			1:
				rng.seed = i * 7 + 3
				var gap := fmod(i, 31.0) > 18.0
				amp = 0.0 if gap else rng.randf_range(4.0, 22.0)
			2:
				rng.seed = i * 13 + int(_t * 12.0)
				amp = rng.randf_range(2.0, 30.0) if i % 9 != 0 else 0.0
			_:
				# One phrase, cloned. Too regular.
				var k := i % 24
				amp = absf(sin(k * 0.4)) * 22.0 + 2.0
		var c := wave if i <= head else Color("34444c")
		_canvas.draw_rect(Rect2(8 + i * 2, mid - amp, 1, amp * 2.0 + 1.0), c)
	_canvas.draw_rect(Rect2(8 + head * 2, 40, 1, 90), Color("f0e070"))
	if level >= 2:
		rng.seed = int(_t * 30.0)
		for s in 40:
			_canvas.draw_rect(Rect2(rng.randf() * SCR.size.x, rng.randf() * SCR.size.y, 2, 1), Color(1, 1, 1, 0.15))
	var dur := [31, 48, 130, 58]
	var total: int = dur[clampi(level, 0, 3)]
	var now := int(clampf(_t / (_duration() - 0.5), 0.0, 1.0) * total)
	_txt(Vector2(6, 148), "%d:%02d / %d:%02d" % [now / 60, now % 60, total / 60, total % 60], DIM)
	if level >= 3 and fmod(_t, 2.0) < 1.0:
		_txt(Vector2(150, 148), "SRC: LOCAL", RED)


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
		_canvas.draw_rect(Rect2(st + Vector2(1, 2), Vector2(4, 4)), RED)
	if Game.lore.has("photo") and _t > 4.0:
		# Crosshair on the photo's coordinates.
		var hp := origin + Vector2(HOME) * cell + Vector2(2, 3)
		var c := Color("f0e070")
		_canvas.draw_rect(Rect2(hp + Vector2(-6, 0), Vector2(4, 1)), c)
		_canvas.draw_rect(Rect2(hp + Vector2(3, 0), Vector2(4, 1)), c)
		_canvas.draw_rect(Rect2(hp + Vector2(0, -6), Vector2(1, 4)), c)
		_canvas.draw_rect(Rect2(hp + Vector2(0, 3), Vector2(1, 4)), c)
	_txt(Vector2(6, 14), "COMPOSITE  M%02d / 14" % month, Color("a8c8d8"))
	if Lore.next_vm() != "" and fmod(_t, 1.0) < 0.6:
		_txt(Vector2(6, 148), "1 MESSAGE", Color("f0e070"))
