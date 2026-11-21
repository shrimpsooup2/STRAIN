extends Control
## Night. A memory returned by clearing THE ARCHIVE. One fragment per dream, in order:
##   1 seven coat hooks, the decon cycle that keeps counting
##   2 FORM 12-L: two signature lines, one signature
##   3 03:14: every stock sterilized, the printout
##   4 03:20: the palm opened over the last dish, seen from CAM 04
## After dreams 1-3 the matching torn notebook page comes back (Lore page_N).

const Juice := preload("res://scripts/fx/juice.gd")

const DURATION := 16.0
const FADE := 1.8
const BAR := 16
const CPS := 22.0
const THINK_HOLD := 4.2

## Think lines per dream: [start time, text]. Typed into the bottom bar.
const THINK := {
	1: [[2.5, "Seven hooks. Mine was already empty."], [8.5, "I held the button down."],
		[12.8, "It is still counting."]],
	2: [[2.0, "Forty-one trials. Forty-one grey pots."], [7.5, "Nobody else would sign it."],
		[12.3, "It only ever checked for one."]],
	3: [[1.5, "03:14. My code. My hands."], [6.5, "Every rack. Every backup."],
		[12.6, "Nearly every one."]],
	4: [[1.5, "The last dish."], [7.0, "My hand didn't shake."], [12.0, "Nobody slipped."]],
}

# Dream 1 timings.
const D1_COAT0 := 1.5
const D1_COAT_GAP := 1.1
const D1_CYCLE := 8.0
const D1_PRINT := 12.0
# Dream 2.
const D2_SIGN := 3.0
const D2_SIGN_END := 6.0
const D2_PHONE := 5.0
const D2_STAMP := 11.5
# Dream 3.
const D3_STER := 3.0
const D3_VIAL_GAP := 0.25
const D3_PRINT := [[2.0, "AUTH 0001"], [2.6, "STERILIZE ALL"], [4.5, "S-7/A   VOID"], [6.5, "S-7/B   VOID"],
	[8.5, "S-7/C   VOID"], [10.5, "S-7/D   VOID"], [11.5, "OFFSITE NONE"], [12.3, "VIABLE  0"]]
# Dream 4.
const D4_CUT := 5.0
const D4_DROP0 := 5.8
const D4_DROP_GAP := 0.7
const D4_CAM := 11.0

var _n := 1
var _t := 0.0
var _prev := 0.0
var _done := false
var _rng := RandomNumberGenerator.new()
var _line := -1
var _typed := 0
var _over := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(UI.W, UI.H)
	UI.set_post(0.0, 0.0)
	_n = clampi(Game.pending_dream, 1, 4)
	var args := Game._user_args()
	if args.has("dream"):
		_n = clampi(int(args["dream"]), 1, 4)
	Sfx.drone("dream")


func _process(dt: float) -> void:
	_prev = _t
	_t += dt
	_cues()
	_type_blips()
	queue_redraw()
	if _t >= DURATION:
		_finish()


func _input(e: InputEvent) -> void:
	if _done or UI.busy:
		return
	if (e.is_action_pressed("interact") or e.is_action_pressed("back")) and _t > 2.0:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	# Hold on black while the page comes back.
	_t = maxf(_t, DURATION)
	queue_redraw()
	Sfx.heartbeat(0.0)
	UI.set_post(0.0, 0.0)
	Game.pending_dream = 0
	if _n <= 3:
		var id := "page_%d" % _n
		await Lore.show(id)
	Game.save_game()
	Sfx.drone("")
	Game.goto("lab")


# ------------------------------------------------------------------ timeline

## True exactly once, on the frame the clock crosses t0.
func _at(t0: float) -> bool:
	return _prev < t0 and _t >= t0


func _cues() -> void:
	match _n:
		1:
			for i in range(1, 7):
				if _at(_coat_gone(i)):
					Sfx.play("door", 0.7 + i * 0.03, -14.0)
			if _at(D1_CYCLE):
				Sfx.play("power_on", 0.6, -10.0)
			if not _over and _cycle_secs() > 45:
				_over = true
				Sfx.play("error", 0.7, -8.0)
			if _over and int(_t) != int(_prev):
				Sfx.play("tick", 0.5, -16.0)
			if _at(D1_PRINT):
				Sfx.play("thud", 0.55, -6.0)
				Juice.shake(self, 2.0, 0.3)
		2:
			if _t > D2_SIGN and _t < D2_SIGN_END and int(_t * 7.0) != int(_prev * 7.0):
				Sfx.play("type", _rng.randf_range(0.45, 0.6), -12.0)
			if _at(D2_PHONE):
				Sfx.play("blip", 0.6, -14.0)
			if _at(D2_STAMP):
				Sfx.play("thud", 0.7, -4.0)
				Juice.shake(self, 3.0, 0.25)
		3:
			if _at(D3_STER):
				Sfx.play("power_on", 0.5, -6.0)
				Juice.shake(self, 1.5, 0.3)
			for k in 32:
				if _at(_vial_dies(k)):
					Sfx.play("tick", 1.2 - floorf(k / 8.0) * 0.12, -14.0)
			for row in D3_PRINT:
				if _at(float(row[0])):
					Sfx.play("type", 0.7, -8.0)
			if _at(11.0):
				Sfx.play("error", 0.55, -10.0)
		4:
			if _at(0.5):
				Sfx.heartbeat(0.9)
			if _at(D4_CUT):
				Sfx.play("vein", 0.8, -4.0)
				Sfx.heartbeat(1.4)
				Juice.shake(self, 3.0, 0.35)
				Juice.flash(self, Color(1.0, 0.45, 0.45), 0.2)
			for k in 6:
				if _at(_drop_at(k) + 0.35):
					Sfx.play("bubble", 0.8 + k * 0.05, -12.0)
			if _at(D4_CAM):
				UI.set_post(0.85, 0.0)
				Sfx.play("glitch", 1.0, -6.0)
				Juice.shake(self, 2.0, 0.2)
			if _at(12.5):
				Sfx.heartbeat(0.55)


func _think_index() -> int:
	var lines: Array = THINK.get(_n, [])
	var idx := -1
	for i in lines.size():
		var row: Array = lines[i]
		var start: float = row[0]
		if _t >= start:
			idx = i
	if idx < 0:
		return -1
	var last: Array = lines[idx]
	var s0: float = last[0]
	return idx if _t < s0 + THINK_HOLD else -1


func _type_blips() -> void:
	var i := _think_index()
	if i < 0:
		return
	var lines: Array = THINK[_n]
	var row: Array = lines[i]
	var start: float = row[0]
	var text: String = row[1]
	if i != _line:
		_line = i
		_typed = 0
	var shown := mini(int((_t - start) * CPS), text.length())
	if shown > _typed:
		_typed = shown
		if shown % 2 == 0 and text[shown - 1] != " ":
			Sfx.play("type", _rng.randf_range(0.8, 1.0), -12.0)


# ------------------------------------------------------------------ drawing helpers

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(Vector2(x, y).floor(), Vector2(w, h).floor()), c)


## 8px text with its top-left corner at x, y.
func _txt(x: float, y: float, s: String, c: Color) -> void:
	draw_string(UI.font, Vector2(x, y + 8).floor(), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	draw_circle(Vector2.ZERO, rx, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _fade_alpha() -> float:
	return clampf(minf(_t / FADE, (DURATION - _t) / FADE), 0.0, 1.0)


func _draw() -> void:
	match _n:
		1: _dream_hooks()
		2: _dream_form()
		3: _dream_stocks()
		4: _dream_palm()
	# The think line, typed into the bottom bar.
	_r(0, 0, UI.W, BAR, Color.BLACK)
	_r(0, UI.H - BAR, UI.W, BAR, Color.BLACK)
	var i := _think_index()
	if i >= 0:
		var lines: Array = THINK[_n]
		var row: Array = lines[i]
		var start: float = row[0]
		var text: String = row[1]
		var shown := mini(int((_t - start) * CPS), text.length())
		var a := clampf((start + THINK_HOLD - _t) / 0.6, 0.0, 1.0)
		_txt((UI.W - text.length() * 8) / 2.0, UI.H - 12, text.substr(0, shown), Color(UI.C_THINK_FG, a))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1.0 - _fade_alpha()))


# ------------------------------------------------------------------ 1: hooks and decon

func _coat_gone(i: int) -> float:
	return D1_COAT0 + (i - 1) * D1_COAT_GAP


## Seconds on the decon counter. Nominal is 45; it keeps going.
func _cycle_secs() -> int:
	if _t < D1_CYCLE:
		return 0
	var k := _t - D1_CYCLE
	return int(k * k * 50.0 + k * 20.0)


func _dream_hooks() -> void:
	_r(0, 0, UI.W, UI.H, Color("0b1014"))
	_r(0, 162, UI.W, 54, Color("06080a"))
	_r(0, 160, UI.W, 2, Color("1a2228"))
	# One strip light, buzzing.
	var buzz := 0.06 if fmod(_t, 3.7) > 0.1 else 0.02
	_r(60, 18, 96, 2, Color(0.8, 0.85, 0.8, 0.5))
	draw_colored_polygon(PackedVector2Array([Vector2(60, 20), Vector2(156, 20), Vector2(196, 160), Vector2(20, 160)]),
		Color(0.7, 0.8, 0.75, buzz))
	# Rail and seven hooks. Hook 1 was empty before anyone else left.
	_r(20, 48, 168, 3, Color("3a444a"))
	for i in 7:
		var x := 28 + i * 22
		_r(x + 3, 51, 2, 5, Color("5a646a"))
		_r(x + 3, 55, 5, 2, Color("5a646a"))
		if i == 0:
			continue
		var a := 1.0 - clampf((_t - _coat_gone(i)) / 0.5, 0.0, 1.0)
		if a <= 0.0:
			continue
		var lift := (1.0 - a) * 6.0
		var sway := sin(_t * 1.3 + i) * 0.6
		var c := Color(0.62, 0.64, 0.62, a)
		_r(x - 2 + sway, 57 - lift, 14, 6, c)
		_r(x + sway, 62 - lift, 10, 52, c)
		_r(x + 4 + sway, 62 - lift, 2, 30, Color(0.45, 0.47, 0.45, a))
		_r(x + 1 + sway, 72 - lift, 4, 2, Color(0.22, 0.28, 0.32, a))
	# The chair nobody picked up.
	_r(128, 150, 26, 4, Color("2a3036"))
	_r(150, 132, 4, 22, Color("2a3036"))
	_r(126, 154, 3, 6, Color("2a3036"))
	# Decon door.
	var dx := 236.0
	_r(dx - 6, 26, 112, 136, Color("1c2428"))
	_r(dx, 32, 100, 128, Color("323c42"))
	for i in 6:
		_r(dx + 2 + i * 17, 150, 9, 10, Color("6a5418"))
	_txt(dx + 22, 36, "DECON B", Color("8a969c"))
	# Porthole: each passing body throws light; then fog; then a hand.
	var cx := dx + 50.0
	var cy := 76.0
	draw_circle(Vector2(cx, cy), 20, Color("1a2024"))
	var inner := Color("0e1416")
	var pass_flash := 0.0
	for i in range(1, 7):
		pass_flash = maxf(pass_flash, 1.0 - absf(_t - _coat_gone(i) - 0.3) / 0.3)
	inner = inner.lerp(Color("c8d8e0"), clampf(pass_flash, 0.0, 1.0))
	if _t >= D1_CYCLE:
		var fog := clampf((_t - D1_CYCLE) / 1.5, 0.0, 1.0) * (0.75 + sin(_t * 2.3) * 0.1)
		inner = inner.lerp(Color("7a948e"), fog)
	draw_circle(Vector2(cx, cy), 17, inner)
	if _t >= D1_PRINT:
		var slide := maxf(0.0, _t - D1_PRINT - 0.5) * 2.2
		var pa := 0.7 * (1.0 - clampf((_t - 14.5) / 1.2, 0.0, 1.0))
		var pc := Color(0.88, 0.95, 0.92, pa)
		_r(cx - 5, cy - 1 + slide, 10, 9, pc)
		for k in 4:
			_r(cx - 5 + k * 2.7, cy - 9 + slide + absf(k - 1.5), 2, 8, pc)
		_r(cx - 8, cy + 1 + slide, 3, 5, pc)
	# Counter panel.
	_r(dx + 12, 104, 76, 30, Color("0a0e10"))
	_txt(dx + 14, 107, "NOM 00:45", Color("5a8070"))
	var run := "RUN --:--"
	var rc := Color("70d0a0")
	if _t >= D1_CYCLE:
		var s := _cycle_secs()
		run = "RUN %02d:%02d" % [mini(floori(s / 60.0), 99), s % 60]
		if s > 45:
			rc = UI.C_BAD
	_txt(dx + 14, 120, run, rc)
	# Lamp over the door.
	var lamp := Color("3a2020")
	if _over and fmod(_t, 1.0) < 0.5:
		lamp = Color("e04040")
		draw_circle(Vector2(dx + 50, 30), 14, Color(0.9, 0.2, 0.2, 0.08))
	_r(dx + 44, 28, 12, 4, lamp)
	# Light under the door.
	if _t >= D1_CYCLE:
		_r(dx + 4, 159, 92, 1, Color(0.75, 0.85, 0.8, 0.25 + sin(_t * 4.0) * 0.1))


# ------------------------------------------------------------------ 2: the single signature

func _sig_point(k: int) -> Vector2:
	return Vector2(124 + k * 1.8, 124 + sin(k * 0.9) * 3.0 + sin(k * 0.37) * 2.0 - (2.0 if k % 11 == 0 else 0.0))


func _pen_tip() -> Vector2:
	if _t < D2_SIGN:
		return Vector2(300, 60).lerp(Vector2(124, 124), clampf((_t - 1.0) / 2.0, 0.0, 1.0))
	if _t < D2_SIGN_END:
		return _sig_point(int((_t - D2_SIGN) / (D2_SIGN_END - D2_SIGN) * 60.0))
	if _t < 7.0:
		return _sig_point(60).lerp(Vector2(124, 148), (_t - D2_SIGN_END))
	if _t < 10.5:
		return Vector2(124 + sin(_t * 23.0) * 0.8, 148 + sin(_t * 17.0) * 0.6 - clampf(_t - 9.5, 0.0, 1.0) * 4.0)
	return Vector2(124, 144).lerp(Vector2(420, 40), clampf((_t - 10.5) / 1.2, 0.0, 1.0))


func _dream_form() -> void:
	_r(0, 0, UI.W, UI.H, Color("120e0a"))
	var flick := 0.09 if fmod(_t * 1.7, 5.3) > 0.12 else 0.03
	draw_circle(Vector2(192, 104), 150, Color(0.9, 0.75, 0.45, flick * 0.5))
	draw_circle(Vector2(192, 104), 100, Color(0.9, 0.75, 0.45, flick))
	# Forty-one pots along the shelf edge, all grey.
	for i in 41:
		var x := 8 + i * 9
		_r(x, 18, 6, 6, Color("4a4a46"))
		_r(x + 1, 18, 4, 2, Color("6a6a66"))
	# The form.
	var ink := Color("2a2a2a")
	_r(98, 32, 192, 156, Color(0, 0, 0, 0.4))
	_r(96, 30, 192, 156, Color("cbc6b4"))
	_txt(104, 36, "HALDEN AGRITECH", ink)
	_txt(104, 48, "FORM 12-L", ink)
	_r(104, 58, 176, 1, ink)
	_txt(104, 64, "S-7 LEASH REMOVAL", ink)
	_txt(104, 80, "TWO SIGNATURES", ink)
	_txt(104, 90, "REQUIRED.", ink)
	_txt(104, 124, "1", ink)
	_r(120, 133, 120, 1, ink)
	_txt(104, 148, "2", ink)
	_r(120, 157, 120, 1, ink)
	# One signature, scratched in.
	var blue := Color("1c2a5a")
	var n := 0
	if _t >= D2_SIGN:
		n = int(clampf((_t - D2_SIGN) / (D2_SIGN_END - D2_SIGN), 0.0, 1.0) * 60.0)
	for k in n:
		draw_line(_sig_point(k), _sig_point(k + 1), blue, 1.0)
	if _t >= D2_SIGN_END:
		_txt(248, 124, "0001", ink)
	# The stamp lands across the empty line.
	if _t >= D2_STAMP:
		var k2 := clampf((_t - D2_STAMP) / 0.12, 0.0, 1.0)
		var sc := lerpf(1.6, 1.0, k2)
		var red := Color(0.7, 0.12, 0.12, 0.85 * k2)
		draw_set_transform(Vector2(186, 152), -0.14, Vector2(sc, sc))
		draw_rect(Rect2(-34, -10, 68, 20), red, false, 2.0)
		draw_string(UI.font, Vector2(-20, 4), "FILED", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, red)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The hand and pen.
	var tip := _pen_tip()
	draw_line(tip, tip + Vector2(14, -18), Color("101010"), 2.0)
	_r(tip.x + 10, tip.y - 32, 30, 20, Color("8a6a52"))
	_r(tip.x + 36, tip.y - 36, 40, 22, Color("9a9c98"))
	# The phone, face up. It lights; nobody picks it up.
	_r(306, 122, 46, 56, Color("0c0c0e"))
	_r(308, 126, 42, 44, Color("16181c"))
	if _t >= D2_PHONE:
		var on := fmod(_t - D2_PHONE, 1.6) < 1.0
		if on:
			_r(308, 126, 42, 44, Color("1c3a32"))
			draw_circle(Vector2(329, 148), 30, Color(0.4, 0.8, 0.65, 0.05))
		_txt(309, 142, "1 MSG", Color("70d0a0") if on else Color("2a4a40"))


# ------------------------------------------------------------------ 3: 03:14

func _vial_dies(k: int) -> float:
	return D3_STER + k * D3_VIAL_GAP


func _dream_stocks() -> void:
	_r(0, 0, UI.W, UI.H, Color("070b10"))
	# The freezer, open.
	_r(36, 24, 208, 148, Color("1c242c"))
	_r(42, 30, 196, 136, Color("0a1016"))
	for row in 4:
		var y := 36 + row * 32
		_r(44, y + 26, 192, 2, Color("2a343c"))
		for c in 8:
			var k := row * 8 + c
			var x := 54 + c * 23
			var alive := _t < _vial_dies(k)
			var dying := clampf((_t - _vial_dies(k)) / 0.3, 0.0, 1.0)
			if alive:
				draw_circle(Vector2(x + 4, y + 16), 9, Color(0.44, 0.85, 0.31, 0.1 + sin(_t * 2.0 + k) * 0.03))
			_r(x, y + 4, 8, 22, Color(0.6, 0.7, 0.7, 0.25))
			var liquid := Color("70d850").lerp(Color("1e2a22"), dying)
			if not alive and dying < 1.0:
				liquid = liquid.lerp(Color("e04040"), 1.0 - dying)
			_r(x + 1, y + 11, 6, 14, liquid)
			_r(x - 1, y + 2, 10, 3, Color("3a4a54"))
	# The sweep.
	if _t >= D3_STER and _t < 11.0:
		var sy := 36.0 + (_t - D3_STER) / (8.0 * D3_VIAL_GAP) * 32.0
		_r(42, sy, 196, 2, Color(1.0, 0.25, 0.25, 0.7))
		_r(42, sy - 6, 196, 6, Color(1.0, 0.25, 0.25, 0.12))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.1, 0.1, 0.05 + sin(_t * 6.0) * 0.03))
	# Clock.
	_r(282, 22, 72, 22, Color("0a0c0e"))
	var clock := "03:14" if fmod(_t, 1.0) < 0.5 else "03 14"
	_txt(298, 29, clock, Color("e04040"))
	# Printout, feeding down.
	var count := 0
	for row in D3_PRINT:
		if _t >= float(row[0]):
			count += 1
	if count > 0:
		_r(258, 54, 120, 8 + count * 12, Color("c4c0b0"))
		_r(254, 50, 128, 6, Color("2a3036"))
		for i in count:
			var row: Array = D3_PRINT[i]
			_txt(262, 60 + i * 12, String(row[1]), Color("2a2a2a"))
	# Below the frame: one dish nobody listed.
	if _t >= 12.8:
		var g := clampf((_t - 12.8) / 1.5, 0.0, 1.0) * (0.12 + sin(_t * 3.0) * 0.04)
		draw_circle(Vector2(150, 196), 26, Color(0.44, 0.85, 0.31, g))


# ------------------------------------------------------------------ 4: 03:20

func _drop_at(k: int) -> float:
	return D4_DROP0 + k * D4_DROP_GAP


func _blade_tip() -> Vector2:
	if _t < 3.0:
		return Vector2(330, 60)
	if _t < D4_CUT:
		return Vector2(330, 60).lerp(Vector2(136, 103), (_t - 3.0) / (D4_CUT - 3.0))
	if _t < D4_CUT + 0.6:
		return Vector2(136, 103).lerp(Vector2(166, 105), (_t - D4_CUT) / 0.6)
	return Vector2(166, 105).lerp(Vector2(420, 40), clampf((_t - D4_CUT - 1.0) / 1.5, 0.0, 1.0))


func _dream_palm() -> void:
	var grey_k := clampf(_t / 14.0, 0.0, 1.0)
	_r(0, 0, UI.W, 130, Color("0c1014"))
	_r(0, 128, UI.W, 2, Color("6a7074"))
	_r(0, 130, UI.W, 86, Color("3a4044"))
	draw_circle(Vector2(170, 120), 110, Color(0.85, 0.9, 0.95, 0.04))
	# A child's drawing, pinned. It loses its colour.
	var gr := Color("8a8a86")
	_r(28, 26, 62, 50, Color("d8d4c8").lerp(Color("9a9a96"), grey_k))
	_r(28, 64, 62, 12, Color("5ab048").lerp(gr, grey_k))
	_r(40, 46, 20, 18, Color("e8e0d0").lerp(gr, grey_k))
	_r(37, 40, 26, 6, Color("c04030").lerp(gr, grey_k))
	_r(47, 54, 6, 10, Color("6a4a30").lerp(gr, grey_k))
	_r(74, 30, 8, 8, Color("f0d040").lerp(gr, grey_k))
	_r(68, 54, 3, 3, Color("d8a888").lerp(gr, grey_k))
	_r(67, 57, 5, 6, Color("f0d040").lerp(gr, grey_k))
	_r(58, 27, 3, 3, Color("c03030"))
	# Clock.
	_r(290, 22, 64, 22, Color("0a0c0e"))
	_txt(302, 29, "03:20" if fmod(_t, 1.0) < 0.5 else "03 20", Color("e04040"))
	# The last dish.
	var dc := Vector2(172, 152)
	_ellipse(dc, 44, 13, Color(0.8, 0.9, 0.9, 0.35))
	_ellipse(dc, 40, 11, Color("8a8460"))
	var green := clampf((_t - (_drop_at(0) + 1.5)) * 5.0, 0.0, 36.0)
	if green > 0.0:
		_ellipse(dc + Vector2(-14, 0), green, green * 0.27, Color("4a9a3c"))
		_ellipse(dc + Vector2(-14, 0), green * 0.6, green * 0.16, Color("70d850"))
	# The open hand, palm up, over the dish.
	_r(40, 96, 84, 22, Color("a8aca8"))
	_r(118, 94, 6, 26, Color("8a8e8a"))
	var skin := Color("b08468")
	_r(124, 92, 46, 24, skin)
	for k in 4:
		_r(170, 93 + k * 6, 18 - absf(k - 1.5) * 2.0, 5, skin)
	_r(132, 86, 22, 6, Color("a07858"))
	# The cut, and what comes out of it.
	if _t >= D4_CUT:
		var cut_x := lerpf(136.0, 166.0, clampf((_t - D4_CUT) / 0.6, 0.0, 1.0))
		var well := 1.0 + clampf(_t - D4_CUT - 0.6, 0.0, 1.0)
		draw_line(Vector2(136, 103), Vector2(cut_x, 105), Color("9a1818"), well)
		for k in 6:
			var t0 := _drop_at(k)
			if _t < t0:
				continue
			var f := clampf((_t - t0) / 0.35, 0.0, 1.0)
			var dy := lerpf(116.0, 150.0, f * f)
			if f < 1.0:
				_r(150 + k % 3, dy, 2, 3, Color("a01c1c"))
			else:
				_ellipse(Vector2(158 - k * 3, 152), 3, 1, Color("6a1414"))
	# It takes the hand back: green along the cut, then up the wrist.
	if _t >= 9.5:
		var v := clampf((_t - 9.5) / 3.0, 0.0, 1.0)
		var gc := Color(0.44, 0.85, 0.31, 0.8 * v)
		draw_line(Vector2(136, 103), Vector2(166, 105), gc, 1.0)
		draw_line(Vector2(136, 103), Vector2(136 - 40 * v, 101 - 2 * v), Color(gc, 0.5 * v), 1.0)
		draw_line(Vector2(140, 104), Vector2(140 - 36 * v, 110), Color(gc, 0.4 * v), 1.0)
	# The blade.
	var tip := _blade_tip()
	draw_line(tip, tip + Vector2(12, -6), Color("c8d0d4"), 1.0)
	draw_line(tip + Vector2(12, -6), tip + Vector2(30, -14), Color("2a3036"), 3.0)
	_r(tip.x + 28, tip.y - 26, 28, 22, skin)
	_r(tip.x + 52, tip.y - 30, 50, 24, Color("a8aca8"))
	# CAM 04.
	if _t >= D4_CAM:
		for y in range(BAR, UI.H - BAR, 2):
			_r(0, y, UI.W, 1, Color(0, 0, 0, 0.22))
		_txt(8, 20, "CAM 04  WING B", Color("c8d8c8"))
		var secs := 11 + int(_t - D4_CAM)
		_txt(UI.W - 8 - 64, 20, "03:20:%02d" % secs, Color("c8d8c8"))
		if fmod(_t, 1.0) < 0.5:
			draw_circle(Vector2(UI.W - 84, 24), 3, UI.C_BAD)
		var gl := _t - D4_CAM
		if gl < 0.4 or fmod(_t, 2.9) < 0.07:
			_rng.seed = int(_t * 30.0)
			for i in 5:
				_r(0, _rng.randi_range(BAR, UI.H - BAR), UI.W, _rng.randi_range(1, 4),
					Color(0.8, 0.85, 0.8, _rng.randf_range(0.05, 0.25)))
