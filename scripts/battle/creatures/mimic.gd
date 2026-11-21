extends "res://scripts/battle/creatures/creature_base.gd"
## MIMIC: a pale, wrong copy of your own colony. A heap of cubes where your
## cells are spheres, swept by translucent scan slabs, glitching in place.
## Cubes chip away with damage.

var _heap: Node3D
var _cubes: Array = []    ## [holder, home, phase]
var _scans: Array = []    ## [mesh, phase]
var _eye: Node3D
var _glitch := 0.0
var _jump_t := 0.0


func _build() -> void:
	_rng.seed = 1313
	_height = 1.75
	var c_a := _m(Color("88b878").lerp(c_pale, 0.3))
	var c_b := _m(Color("6a9a5a").lerp(c_floor, 0.25))
	var c_c := _m(Color("b8d8a8"))
	var dark := _m(Color("2c4a24").lerp(c_dark, 0.3))
	var eye_m := _m(Color("f0f0ff"), {"unlit": true})
	var pupil := _m(c_void, {"unlit": true})
	var scan_m := Retro.mat(c_pale.lerp(Color("c0ffc0"), 0.4), {"alpha": 0.28})
	_heap = _pivot(_root)
	# core blob of cubes: a rough dome
	var mats := [c_a, c_b, c_c]
	var spots: Array = []
	for i in 30:
		var d := _rand_dir(-0.05)
		var rr := _rng.randf_range(0.25, 0.95)
		var p := Vector3(d.x * rr * 0.95, 0.15 + absf(d.y) * rr * 1.25, d.z * rr * 0.8)
		spots.append(p)
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	for i in spots.size():
		var p: Vector3 = spots[i]
		var h := _pivot(_heap, p)
		var s := _rng.randf_range(0.2, 0.36) * (1.15 - p.y * 0.25)
		var cube := _box(Vector3(s, s, s), mats[i % 3] as Material, h)
		cube.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))
		_cubes.append([h, p, _rng.randf() * TAU])
		_part(cube, POP)
	# inner dark mass so lost cubes leave holes, not daylight
	var inner := _box(Vector3(1.2, 0.9, 0.9), dark, _heap, Vector3(0, 0.5, 0))
	inner.rotation.y = 0.4
	var inner2 := _box(Vector3(0.7, 0.6, 0.6), dark, _heap, Vector3(0.05, 1.05, 0))
	inner2.rotation.y = -0.3
	# one copied "eye": a square stare
	_eye = _pivot(_heap, Vector3(0.05, 1.05, 0.38))
	_box(Vector3(0.28, 0.2, 0.04), eye_m, _eye)
	_box(Vector3(0.09, 0.12, 0.04), pupil, _eye, Vector3(0, 0, 0.02))
	# scan slabs
	for i in 3:
		var sl := _box(Vector3(1.9, 0.035, 1.5), scan_m, _root, Vector3(0, 0.3, 0))
		_scans.append([sl, float(i) / 3.0])


func _idle(t: float, dt: float) -> void:
	_jump_t -= dt
	var g := _glitch + _wind * 0.5
	if _jump_t <= 0.0:
		_jump_t = _rng.randf_range(0.15, 0.9) * (1.0 - g * 0.6)
		for e in _cubes:
			var h: Node3D = e[0]
			var p: Vector3 = e[1]
			if _rng.randf() < 0.18 + g * 0.5:
				h.position = p + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)) * (0.06 + g * 0.18)
			else:
				h.position = p
		_heap.position.x = _rng.randf_range(-0.04, 0.04) * (1.0 + g * 3.0)
	var br := 1.0 + sin(t * 1.9) * 0.03
	_heap.scale = Vector3(br, 2.0 - br, br)
	for e in _scans:
		var sl: MeshInstance3D = e[0]
		var ph: float = e[1]
		var u := fposmod(t * 0.35 + ph, 1.0)
		sl.position.y = 0.05 + u * 1.75
		sl.scale = Vector3(1.0 - absf(u - 0.5) * 0.6, 1.0, 1.0 - absf(u - 0.5) * 0.6)
		sl.visible = u > 0.05 and u < 0.95
	_eye.position.x = 0.05 + sin(t * 0.5) * 0.08
	_eye.scale = Vector3(1.0, 1.0 if fposmod(t, 3.7) > 0.12 else 0.1, 1.0)


func _attack(_kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_glitch", 1.0, 0.05)
	tw.tween_interval(0.3)
	tw.tween_property(self, "_glitch", 0.0, 0.3)
	_jump_t = 0.0
