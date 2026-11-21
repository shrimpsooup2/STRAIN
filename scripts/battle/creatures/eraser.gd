extends "res://scripts/battle/creatures/creature_base.gd"
## ERASER: an upright grey slab of stacked blocks on stubby legs, a single
## eye-slit, two scrubbing arms. Smeared ghost copies of it jitter beside it.
## Damage knocks blocks out from the top corners inward.

var _slab: Node3D
var _arms: Array = []    ## [pivot, side]
var _ghosts: Array = []  ## [mesh, side, phase]
var _slit: Node3D
var _scrub := 0.0


func _build() -> void:
	_rng.seed = 1414
	_height = 1.85
	var grey := _m(Color("a8a4a8").lerp(c_pale, 0.15))
	var grey_d := _m(Color("787478").lerp(c_floor, 0.2))
	var grey_l := _m(Color("d0ccd0"))
	var dark := _m(Color("302c34"))
	var slit_m := _m(c_accent.lightened(0.35), {"unlit": true})
	var ghost_m := Retro.mat(Color("c8c4cc"), {"alpha": 0.22})
	_slab = _pivot(_root, Vector3(0, 0.38, 0))
	# core plate behind the blocks
	_box(Vector3(1.15, 1.4, 0.3), dark, _slab, Vector3(0, 0.7, -0.08))
	# 3 x 4 grid of blocks; order: bottom rows first so top corners go first
	var bw := 0.38
	var bh := 0.36
	var cells: Array = []
	for row in 4:
		for col in 3:
			var p := Vector3((float(col) - 1.0) * (bw + 0.02), 0.2 + float(row) * (bh + 0.02), 0.04)
			var mm: Material = [grey, grey_d, grey_l][(row + col) % 3]
			var b := _box(Vector3(bw, bh, 0.36), mm, _slab, p)
			b.rotation.z = _rng.randf_range(-0.04, 0.04)
			# score lines / wear
			_box(Vector3(bw * 0.7, 0.025, 0.02), dark, b, Vector3(0, _rng.randf_range(-0.1, 0.1), 0.18))
			var pri := float(row) * 10.0 + absf(float(col) - 1.0) * 5.0
			cells.append([pri, b, row, col])
	cells.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var center: Node3D = null
	for e in cells:
		var r: int = e[2]
		var c: int = e[3]
		if r == 2 and c == 1:
			center = e[1]
	for e in cells:
		var b: Node3D = e[1]
		_part(b, FALL)
	# eye slit on the central block of row 2
	_slit = _pivot(center, Vector3(0, 0.02, 0.185))
	_box(Vector3(0.3, 0.05, 0.02), slit_m, _slit)
	# legs
	for sd in [-1.0, 1.0]:
		var s: float = sd
		_box(Vector3(0.28, 0.38, 0.3), grey_d, _root, Vector3(0.3 * s, 0.19, 0))
		_box(Vector3(0.36, 0.08, 0.42), dark, _root, Vector3(0.3 * s, 0.04, 0.04))
	# scrubbing arms with flat pads
	for sd in [-1.0, 1.0]:
		var s: float = sd
		var ap := _pivot(_slab, Vector3(0.66 * s, 1.15, 0.05))
		_box(Vector3(0.14, 0.7, 0.14), grey_d, ap, Vector3(0.04 * s, -0.33, 0.0))
		var pad := _box(Vector3(0.26, 0.12, 0.34), grey_l, ap, Vector3(0.06 * s, -0.72, 0.06))
		pad.rotation.x = 0.15
		_arms.append([ap, s])
	# smear ghosts: translucent offset slabs
	for i in 3:
		var sd := -1.0 if i % 2 == 0 else 1.0
		var gh := _box(Vector3(1.1, 1.45, 0.25), ghost_m, _root, Vector3(0.0, 1.1, -0.05))
		_ghosts.append([gh, sd, float(i) * 1.9])


func _idle(t: float, _dt: float) -> void:
	_slab.position.y = 0.38 + absf(sin(t * 1.4)) * 0.03
	_slab.rotation.z = sin(t * 0.8) * 0.025
	for e in _arms:
		var ap: Node3D = e[0]
		var s: float = e[1]
		var w := sin(t * 3.0 + s * 1.5)
		ap.rotation = Vector3(-0.25 + w * 0.25 - _scrub * 1.1 - _wind * 0.4, 0, s * (0.12 + w * 0.08 + _scrub * 0.2))
	for e in _ghosts:
		var gh: MeshInstance3D = e[0]
		var s: float = e[1]
		var ph: float = e[2]
		var j := sin(t * 2.3 + ph) * 0.5 + 0.5
		var off := (0.12 + j * 0.22 + _scrub * 0.3 + _wind * 0.15) * s
		if randf() < 0.04:
			off += randf_range(-0.2, 0.2)
		gh.position = Vector3(off, 1.1 + sin(t * 1.7 + ph) * 0.04, -0.05 - absf(off) * 0.3)
		gh.scale = Vector3(1.0 + j * 0.1, 1.0 - j * 0.05, 1.0)
	var blink := 1.0 if fposmod(t, 4.3) > 0.15 else 0.1
	_slit.scale = Vector3(1.0 + _wind * 0.4, blink * (1.0 + _wind * 1.5), 1.0)


func _attack(_kind: String) -> void:
	var tw := create_tween()
	for _i in 2:
		tw.tween_property(self, "_scrub", 1.0, 0.08)
		tw.tween_property(self, "_scrub", 0.2, 0.08)
	tw.tween_property(self, "_scrub", 0.0, 0.2)
