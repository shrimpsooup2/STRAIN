extends Control
## Night: a wordless memory, returned by clearing THE ARCHIVE.
##   1 the farmhouse   2 the field goes grey   3 seven desks, one lamp   4 the vial
## After dreams 1-3 the matching torn notebook page comes back (Lore page_N).

const PX := 2
const DURATION := 11.0

var _n := 1
var _t := 0.0
var _done := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(UI.W, UI.H)
	UI.set_post(0.0, 0.0)
	_n = clampi(Game.pending_dream, 1, 4)
	var args := Game._user_args()
	if args.has("dream"):
		_n = int(args["dream"])


func _process(dt: float) -> void:
	_t += dt
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
	Game.pending_dream = 0
	if _n <= 3:
		var id := "page_%d" % _n
		await Lore.show(id)
	Game.save_game()
	Game.goto("lab")


# ------------------------------------------------------------------ drawing helpers

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(Vector2(x, y).floor(), Vector2(w, h).floor()), c)


func _fade_alpha() -> float:
	return clampf(minf(_t / 1.2, (DURATION - _t) / 1.2), 0.0, 1.0)


func _draw() -> void:
	match _n:
		1: _dream_farm(0.0)
		2: _dream_farm(clampf((_t - 1.0) / 7.0, 0.0, 1.0))
		3: _dream_desks()
		4: _dream_vial()
	# Vignette bars and fade.
	_r(0, 0, UI.W, 10, Color.BLACK)
	_r(0, UI.H - 10, UI.W, 10, Color.BLACK)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1.0 - _fade_alpha()))


## Farmhouse on a green field. grey_t 0..1 creeps grey in from the horizon edges.
func _dream_farm(grey_t: float) -> void:
	var sky := Color("88b8d8").lerp(Color("9a9a98"), grey_t)
	_r(0, 0, UI.W, 120, sky)
	# Sun.
	var sun := Color("f8e8a0").lerp(Color("c8c8c0"), grey_t)
	_r(300, 26, 22, 22, sun)
	_r(296, 30, 30, 14, sun)
	# Clouds drift.
	for i in 3:
		var cx := fmod(40.0 + i * 130.0 + _t * 6.0, UI.W + 60.0) - 40.0
		_r(cx, 40 + i * 9, 36, 8, Color(1, 1, 1, 0.8))
		_r(cx + 8, 34 + i * 9, 20, 6, Color(1, 1, 1, 0.8))
	# Field rows: green, swaying; grey eats inward from both sides.
	_rng.seed = 11
	for row in 12:
		var y := 120 + row * 8
		for col in 48:
			var x := col * 8
			var edge := minf(col, 47 - col) / 24.0  # 0 at edges, 1 at centre
			var is_grey := grey_t > 0.0 and edge < grey_t * 1.15 - (row / 40.0)
			var base := Color("4a9a3c") if (col + row) % 2 == 0 else Color("3c8a30")
			if is_grey:
				base = Color("8a8a84") if (col + row) % 2 == 0 else Color("7c7c78")
			_r(x, y, 8, 8, base)
			if not is_grey and _rng.randf() < 0.3:
				var sway := 1.0 if sin(_t * 3.0 + col * 0.7) > 0.0 else 0.0
				_r(x + 2 + sway, y - 2, 1, 3, Color("6ac050"))
	# Farmhouse.
	_r(70, 82, 64, 40, Color("e8e0d0"))
	_r(64, 70, 76, 14, Color("a03c30"))
	_r(72, 62, 60, 10, Color("a03c30"))
	_r(96, 98, 14, 24, Color("5a3a28"))
	_r(76, 90, 12, 10, Color("406880"))
	_r(116, 90, 12, 10, Color("406880"))
	# Fence.
	for i in 8:
		_r(170 + i * 16, 110, 3, 14, Color("c8b090"))
	_r(170, 113, 116, 2, Color("c8b090"))
	_r(170, 119, 116, 2, Color("c8b090"))
	# The small figure on the fence (gone once the grey comes).
	if grey_t < 0.05:
		var swing := 1.0 if fmod(_t, 1.2) < 0.6 else 0.0
		_r(222, 98, 6, 6, Color("d8a888"))
		_r(221, 104, 8, 8, Color("e0c040"))
		_r(222, 112, 2, 5 + swing, Color("405880"))
		_r(226, 112, 2, 6 - swing, Color("405880"))


## Seven desks at night. Lamps go out one by one; one stays.
func _dream_desks() -> void:
	_r(0, 0, UI.W, UI.H, Color("0a0e14"))
	_r(0, 150, UI.W, 66, Color("141a22"))
	for i in 7:
		var x := 22 + i * 50
		var out_at := 1.5 + i * 1.1
		var stays := i == 3
		var lit := stays or _t < out_at
		if lit:
			# Lamp pool.
			draw_circle(Vector2(x + 18, 150), 22, Color(0.95, 0.85, 0.55, 0.12))
		_r(x, 140, 36, 6, Color("3a4048"))
		_r(x + 2, 146, 3, 14, Color("2a3038"))
		_r(x + 31, 146, 3, 14, Color("2a3038"))
		_r(x + 26, 120, 2, 20, Color("4a525a"))
		_r(x + 18, 118, 12, 4, Color("f0d890") if lit else Color("3a4048"))
		# A figure at each lit desk; the one who stays slumps lower over time.
		if lit:
			var slump := 0.0 if not stays else clampf((_t - 8.0) * 2.0, 0.0, 6.0)
			_r(x + 10, 124 + slump, 8, 8, Color("d8a888"))
			_r(x + 8, 132 + slump, 12, 10 - slump * 0.5, Color("e8ecec"))


## A hand, a vial, the crack, the spill.
func _dream_vial() -> void:
	var crack := clampf((_t - 4.0) / 0.4, 0.0, 1.0)
	var spill := clampf((_t - 4.4) / 2.5, 0.0, 1.0)
	_r(0, 0, UI.W, UI.H, Color("10161c"))
	# Bench edge.
	_r(0, 160, UI.W, 56, Color("8c9294"))
	_r(0, 158, UI.W, 2, Color("b8bcbc"))
	# Hand (blocky) closing around the vial.
	var squeeze := clampf((_t - 2.0) / 2.0, 0.0, 1.0) * 4.0
	_r(150 + squeeze, 90, 80, 46, Color("d8a888"))
	_r(140 + squeeze, 96, 14, 32, Color("c89878"))
	_r(226 - squeeze, 100, 24, 30, Color("d8a888"))
	# Vial.
	var vx := 186.0
	_r(vx, 60, 18, 90, Color(0.82, 0.92, 0.9, 0.55))
	_r(vx + 3, 100 - spill * 10.0, 12, 46, Color("70d850"))
	_r(vx - 2, 56, 22, 6, Color("405060"))
	if crack > 0.0:
		for i in 6:
			_r(vx + 4 + (i % 2) * 6, 70 + i * 12, 4, 6 * crack, Color("e8f8f0"))
	if spill > 0.0:
		# Green runs down the hand and spreads across the bench.
		_r(vx + 4, 136, 10, 24 * spill, Color("70d850"))
		_r(vx - 60 * spill, 160, 120 * spill + 18, 6, Color("4a9a3c"))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.44, 0.85, 0.31, spill * 0.35))
	if _t > 8.5:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, clampf((_t - 8.5) / 1.5, 0.0, 1.0)))
