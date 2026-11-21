extends "res://scripts/battle/creatures/creature_base.gd"
## TENDRIL KNOT: a hovering snarl of fibrin loops around a dark clot,
## tethered to the floor by four threads. Loops writhe; damage unravels them.

var _core: Node3D
var _loops: Array = []    ## [pivot, axis, speed, phase]
var _strands: Array = []  ## [pivot, base rot, phase]
var _tight := 0.0


func _build() -> void:
	_rng.seed = 202
	_height = 1.8
	var clot := _m(c_dark.lerp(Color("180404"), 0.4))
	var fib_a := _m(c_bone.lerp(c_accent, 0.35))
	var fib_b := _m(c_accent.darkened(0.15))
	var fib_c := _m(c_flesh.lightened(0.1))
	var bead := _m(c_accent.lightened(0.2))
	_core = _pivot(_root, Vector3(0, 1.05, 0))
	var c := _ball(0.34, clot, _core, Vector3.ZERO, 7, 5)
	c.scale = Vector3(1.0, 0.9, 1.0)
	var mats := [fib_a, fib_b, fib_c]
	var n := 12
	for i in n:
		var k := float(i) / float(n - 1)
		var r := lerpf(0.36, 0.72, k) * _rng.randf_range(0.9, 1.05)
		var th := _rng.randf_range(0.035, 0.065)
		var piv := _pivot(_core, Vector3(_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06)),
			Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		var tor := _torus(r - th, r + th, mats[i % 3] as Material, piv, Vector3.ZERO, 9, 4)
		tor.scale = Vector3(1.0, 1.0, _rng.randf_range(0.6, 1.0))
		_ball(th * 1.9, bead, tor, Vector3(r, 0, 0), 4, 3)
		_loops.append([piv, _rand_dir(), _rng.randf_range(0.25, 0.8) * (1.0 if i % 2 == 0 else -1.0), _rng.randf() * TAU])
		_part(tor, POP)
	for i in 4:
		var ang := TAU * float(i) / 4.0 + 0.4
		var sp := _pivot(_root, Vector3(cos(ang) * 0.28, 0.82, sin(ang) * 0.28))
		var base := Vector3(PI + sin(ang) * 0.5, 0, -cos(ang) * 0.5)
		sp.rotation = base
		var parent: Node3D = sp
		for s in 3:
			var seg_len := 0.32
			_cyl(0.03 - 0.006 * s, 0.035 - 0.006 * s, seg_len, fib_b, parent, Vector3(0, seg_len * 0.5, 0), 4)
			var j := _pivot(parent, Vector3(0, seg_len, 0), Vector3(0.25, 0, 0))
			parent = j
		_strands.append([sp, base, _rng.randf() * TAU])


func _idle(t: float, dt: float) -> void:
	_core.position.y = 1.05 + sin(t * 1.4) * 0.05
	var breathe := 1.0 + sin(t * 2.2) * 0.04 - _tight * 0.18 + _wind * 0.05
	for e in _loops:
		var piv: Node3D = e[0]
		var ax: Vector3 = e[1]
		var spd: float = e[2]
		var ph: float = e[3]
		piv.rotate(ax, spd * dt * (1.0 + _wind * 3.0 + _tight * 4.0))
		piv.scale = Vector3.ONE * (breathe + sin(t * 3.1 + ph) * 0.03)
	for e in _strands:
		var sp: Node3D = e[0]
		var base: Vector3 = e[1]
		var ph: float = e[2]
		sp.rotation = base + Vector3(sin(t * 1.6 + ph) * 0.12, 0, cos(t * 1.3 + ph) * 0.12)


func _attack(kind: String) -> void:
	var tw := create_tween()
	if kind == "buff":
		tw.tween_property(self, "_tight", -0.6, 0.2)
	else:
		tw.tween_property(self, "_tight", 1.0, 0.1)
	tw.tween_property(self, "_tight", 0.0, 0.35)
