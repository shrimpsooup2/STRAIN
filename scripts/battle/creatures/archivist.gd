extends "res://scripts/battle/creatures/creature_base.gd"
## THE ARCHIVIST (boss): a leaning tower of filing cabinets grown into flesh,
## walking on drawer-legs, with flat plate arms and one great eye on top that
## tracks you. Drawers slide in and out as it breathes; with damage they fall
## out and spill.

var _tower: Node3D
var _tiers: Array = []    ## [pivot, base rot, phase]
var _sliders: Array = []  ## [holder, base z, phase]
var _eye: Node3D
var _pupil: Node3D
var _arms: Array = []     ## [pivot, side]
var _legs: Array = []     ## [pivot, phase]
var _file := 0.0


func _build() -> void:
	_rng.seed = 1616
	_native_boss = true
	_height = 2.95
	var wood := _m(Color("3a2c48").lerp(c_floor, 0.35))
	var wood_l := _m(Color("5a4870").lerp(c_floor, 0.3))
	var metal := _m(Color("8c8498").lerp(c_pale, 0.2))
	var flesh := _m(c_accent.darkened(0.35).lerp(Color("803848"), 0.4))
	var paper := _m(Color("d8ccb8"))
	var dark := _m(c_void, {"unlit": true})
	var eye_w := _m(Color("f0e8d8"))
	var iris := _m(c_accent.lightened(0.2), {"unlit": true})
	# legs: two drawer-legs
	for sd in [-1.0, 1.0]:
		var s: float = sd
		var lp := _pivot(_root, Vector3(0.38 * s, 0.75, 0))
		_box(Vector3(0.3, 0.75, 0.38), wood, lp, Vector3(0, -0.36, 0))
		_box(Vector3(0.4, 0.1, 0.5), metal, lp, Vector3(0, -0.72, 0.05))
		_box(Vector3(0.12, 0.04, 0.03), metal, lp, Vector3(0, -0.3, 0.2))
		_legs.append([lp, 0.0 if s < 0 else PI])
	_tower = _pivot(_root, Vector3(0, 0.72, 0))
	var drawers: Array = []
	var tiers := [
		[Vector3(1.25, 0.55, 0.75), 0.0, 3],
		[Vector3(1.05, 0.45, 0.7), 0.12, 2],
		[Vector3(0.9, 0.42, 0.65), -0.1, 2],
		[Vector3(0.62, 0.36, 0.55), 0.18, 1],
	]
	var parent: Node3D = _tower
	for ti in tiers.size():
		var spec: Array = tiers[ti]
		var sz: Vector3 = spec[0]
		var lean: float = spec[1]
		var nd: int = spec[2]
		var tp := _pivot(parent, Vector3(0, 0, 0), Vector3(0, lean, lean * 0.25))
		_box(sz, wood if ti % 2 == 0 else wood_l, tp, Vector3(0, sz.y * 0.5, 0))
		_box(Vector3(sz.x + 0.06, 0.05, sz.z + 0.06), metal, tp, Vector3(0, sz.y, 0))
		# flesh seam where tiers grew together
		var seam := _box(Vector3(sz.x * 0.9, 0.07, sz.z * 0.9), flesh, tp, Vector3(0, 0.0, 0))
		seam.scale = Vector3(1.0, 1.0, 1.0)
		var dw := (sz.x - 0.1) / float(nd)
		for d in nd:
			var hx := -sz.x * 0.5 + 0.05 + dw * (float(d) + 0.5)
			var hold := _pivot(tp, Vector3(hx, sz.y * 0.48, sz.z * 0.5 - 0.1))
			var dr := _pivot(hold)
			_box(Vector3(dw - 0.05, sz.y * 0.78, 0.28), wood_l if ti % 2 == 0 else wood, dr, Vector3(0, 0, 0))
			_box(Vector3(dw * 0.4, 0.05, 0.04), metal, dr, Vector3(0, sz.y * 0.15, 0.15))
			_box(Vector3(dw * 0.7, 0.06, 0.2), paper, dr, Vector3(0, sz.y * 0.4, 0.0))
			_sliders.append([hold, sz.z * 0.5 - 0.1, _rng.randf() * TAU])
			drawers.append(dr)
		# dark gaps behind drawers
		_box(Vector3(sz.x - 0.1, sz.y * 0.8, 0.02), dark, tp, Vector3(0, sz.y * 0.48, sz.z * 0.5 - 0.13))
		_tiers.append([tp, Vector3(0, lean, lean * 0.25), float(ti) * 1.1])
		var nxt := _pivot(tp, Vector3(0, sz.y + 0.03, 0))
		parent = nxt
	# eye on top
	_eye = _pivot(parent, Vector3(0, 0.14, 0))
	var lid := _ball(0.28, flesh, _eye, Vector3.ZERO, 8, 5)
	lid.scale = Vector3(1.05, 0.85, 1.0)
	_pupil = _pivot(_eye)
	var ball := _ball(0.23, eye_w, _pupil, Vector3(0, 0, 0.08), 8, 5)
	ball.scale = Vector3(1.0, 1.0, 0.9)
	_ball(0.1, iris, _pupil, Vector3(0, 0, 0.28), 6, 4)
	var pp := _ball(0.05, dark, _pupil, Vector3(0, 0, 0.36), 4, 3)
	pp.scale = Vector3(0.6, 1.4, 0.5)
	# plate arms from the second tier
	var t1: Node3D = (_tiers[1] as Array)[0]
	for sd in [-1.0, 1.0]:
		var s: float = sd
		var ap := _pivot(t1, Vector3(0.58 * s, 0.38, 0.0))
		_box(Vector3(0.12, 0.7, 0.12), metal, ap, Vector3(0.06 * s, -0.32, 0))
		var plate := _box(Vector3(0.08, 0.6, 0.48), wood_l, ap, Vector3(0.12 * s, -0.78, 0.12))
		plate.rotation.y = 0.0
		_box(Vector3(0.1, 0.5, 0.06), paper, ap, Vector3(0.12 * s, -0.78, 0.38))
		_arms.append([ap, s])
	# parts: drawers. Top drawers fall first.
	for dr in drawers:
		_part(dr as Node3D, FALL)


func _idle(t: float, _dt: float) -> void:
	_tower.position.y = 0.72 + absf(sin(t * 1.0)) * 0.03
	_tower.rotation.z = sin(t * 0.6) * 0.03
	for e in _tiers:
		var tp: Node3D = e[0]
		var r0: Vector3 = e[1]
		var ph: float = e[2]
		tp.rotation = r0 + Vector3(sin(t * 0.7 + ph) * 0.02, sin(t * 0.5 + ph) * 0.05, sin(t * 0.8 + ph) * 0.025)
	for e in _sliders:
		var hold: Node3D = e[0]
		var z0: float = e[1]
		var ph: float = e[2]
		var out := maxf(sin(t * 0.9 + ph), 0.0) * 0.12 + _file * 0.3 * (0.5 + 0.5 * sin(ph * 3.0)) + _wind * 0.08
		hold.position.z = z0 + out
	# the eye tracks the player: player is along local +Z, slightly left
	var look := Vector3(sin(t * 0.37) * 0.25 - 0.1, -0.12 + sin(t * 0.53) * 0.08, 1.0)
	_pupil.basis = Basis.looking_at(look, Vector3.UP, true)
	var blink := 1.0 if fposmod(t, 5.1) > 0.14 else 0.15
	_eye.scale = Vector3(1.0 + _wind * 0.25, blink * (1.0 + _wind * 0.25), 1.0 + _wind * 0.25)
	for e in _arms:
		var ap: Node3D = e[0]
		var s: float = e[1]
		ap.rotation = Vector3(sin(t * 0.9 + s) * 0.1 - _file * 1.2, 0, s * (0.08 + _wind * 0.3))
	for e in _legs:
		var lp: Node3D = e[0]
		var ph: float = e[1]
		lp.rotation.x = sin(t * 1.0 + ph) * 0.04


func _attack(_kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_file", 1.0, 0.12)
	tw.tween_interval(0.15)
	tw.tween_property(self, "_file", 0.0, 0.35)
