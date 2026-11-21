extends "res://scripts/battle/creatures/creature_base.gd"
## THE SCAB (boss): a raw flesh dome armoured in overlapping crust plates,
## a low toothed head, two raking claw arms, four pillar legs, a bone crest.
## Damage sloughs the crust off in random order, baring red meat.

var _body: Node3D
var _head: Node3D
var _jaw: Node3D
var _arms: Array = []   ## [shoulder, side, forearm]
var _legs: Array = []   ## [pivot, phase]
var _rake := 0.0
var _chomp := 0.0


func _build() -> void:
	_rng.seed = 404
	_native_boss = true
	_height = 2.85
	var raw := _m(c_accent.darkened(0.08))
	var meat := _m(c_floor.lightened(0.15))
	var crust_a := _m(c_dark.lerp(Color("3a1a10"), 0.5))
	var crust_b := _m(c_floor.darkened(0.25).lerp(Color("5a3020"), 0.4))
	var crust_c := _m(c_dark.darkened(0.3))
	var bone := _m(c_bone)
	var void_m := _m(c_void, {"unlit": true})
	var eye := _m(Color("ffe070"), {"unlit": true})
	_body = _pivot(_root, Vector3(0, 1.45, -0.1))
	var dome := _ball(1.0, raw, _body, Vector3.ZERO, 10, 7)
	dome.scale = Vector3(1.0, 0.92, 0.9)
	var belly := _ball(0.85, meat, _body, Vector3(0, -0.45, 0.05), 8, 4)
	belly.scale = Vector3(1.05, 0.5, 1.0)
	# crest of bone spikes along the spine
	for i in 5:
		var e := lerpf(1.2, 0.35, float(i) / 4.0)
		var p := Vector3(0, sin(e) * 0.92, -cos(e) * 0.9)
		var sp := _cyl(0.0, 0.09, 0.42 - 0.05 * absf(float(i) - 1.5), bone, _body, p)
		_align_up(sp, p.normalized())
		sp.position = p * 1.12
	# legs
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var sz := -1.0 if i < 2 else 1.0
		var lp := _pivot(_root, Vector3(0.62 * sx, 0.95, 0.4 * sz - 0.1))
		var leg := _cyl(0.16, 0.24, 1.0, crust_a, lp, Vector3(0.08 * sx, -0.48, 0.05 * sz), 6)
		leg.rotation.z = 0.16 * sx
		_box(Vector3(0.5, 0.12, 0.55), crust_c, lp, Vector3(0.16 * sx, -0.92, 0.12 * sz + 0.08))
		_legs.append([lp, float(i) * 1.3])
	# head and maw
	_head = _pivot(_root, Vector3(0, 1.3, 0.85))
	var skull := _ball(0.42, crust_b, _head, Vector3.ZERO, 7, 5)
	skull.scale = Vector3(1.2, 0.75, 1.0)
	_box(Vector3(0.7, 0.1, 0.42), void_m, _head, Vector3(0, -0.14, 0.2))
	for i in 3:
		var ex := (float(i) - 1.0) * 0.17
		_ball(0.05, eye, _head, Vector3(ex, 0.14 - absf(ex) * 0.3, 0.38), 4, 3)
	for i in 6:
		var tx := (float(i) - 2.5) * 0.11
		var t := _cyl(0.0, 0.04, 0.16, bone, _head, Vector3(tx, -0.14, 0.36), 4)
		t.rotation.x = PI
	_jaw = _pivot(_head, Vector3(0, -0.18, -0.05))
	_box(Vector3(0.72, 0.12, 0.5), crust_a, _jaw, Vector3(0, -0.06, 0.25))
	for i in 5:
		var tx := (float(i) - 2.0) * 0.12
		_cyl(0.0, 0.04, 0.15, bone, _jaw, Vector3(tx, 0.06, 0.44), 4)
	# raking arms
	for side in [-1.0, 1.0]:
		var sd: float = side
		var sh := _pivot(_root, Vector3(0.92 * sd, 1.7, 0.3))
		_ball(0.26, crust_b, sh, Vector3.ZERO, 6, 4)
		var up := _cyl(0.1, 0.14, 0.75, meat, sh, Vector3(0.2 * sd, -0.3, 0.05), 5)
		up.rotation.z = 0.6 * sd
		var fa := _pivot(sh, Vector3(0.38 * sd, -0.6, 0.1), Vector3(-0.9, 0, 0))
		var fore := _cyl(0.08, 0.12, 0.7, crust_a, fa, Vector3(0, -0.33, 0), 5)
		fore.rotation.x = 0.0
		for c in 3:
			var cl := _cyl(0.0, 0.045, 0.32, bone, fa, Vector3((float(c) - 1.0) * 0.08, -0.74, 0.04), 4)
			cl.rotation.x = PI - 0.5
			cl.rotation.z = (float(c) - 1.0) * 0.25
		_arms.append([sh, sd, fa])
	# crust plates in latitude rings; shuffled so they slough at random
	var plates: Array = []
	var rings := [[0.12, 13], [0.5, 12], [0.88, 9], [1.22, 5], [1.5, 1]]
	var mats := [crust_a, crust_b, crust_c]
	for ri in rings.size():
		var ring: Array = rings[ri]
		var el: float = ring[0]
		var cnt: int = ring[1]
		for k in cnt:
			var a := TAU * (float(k) + 0.5 * float(ri % 2)) / float(cnt) + _rng.randf_range(-0.1, 0.1)
			var p := Vector3(cos(el) * cos(a) * 1.0, sin(el) * 0.92, cos(el) * sin(a) * 0.9)
			var nrm := Vector3(p.x, p.y / 0.85, p.z / 0.81).normalized()
			var w := lerpf(0.55, 0.32, el / 1.5)
			var pl := _box(Vector3(w, 0.07, w * 0.8), mats[_rng.randi() % 3] as Material, _body, p + nrm * 0.03)
			_align_up(pl, nrm)
			pl.rotate_object_local(Vector3.UP, _rng.randf() * TAU)
			pl.rotate_object_local(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2))
			plates.append(pl)
	for i in range(plates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Node3D = plates[i]
		plates[i] = plates[j]
		plates[j] = tmp
	for pl in plates:
		_part(pl as Node3D, FALL)


func _idle(t: float, _dt: float) -> void:
	var br := sin(t * 1.2)
	_body.scale = Vector3(1.0 + br * 0.02, 1.0 + br * 0.03, 1.0 + br * 0.02)
	_body.position.y = 1.45 + br * 0.03
	_head.rotation = Vector3(sin(t * 0.8) * 0.05 - _rake * 0.15, sin(t * 0.55) * 0.18, 0)
	_jaw.rotation.x = 0.12 + maxf(sin(t * 1.7), 0.0) * 0.12 + _chomp * 0.55 + _wind * 0.35
	for e in _arms:
		var sh: Node3D = e[0]
		var sd: float = e[1]
		var fa: Node3D = e[2]
		sh.rotation = Vector3(sin(t * 1.1 + sd) * 0.08 - _rake * 1.1 - _wind * 0.5, 0, sd * (0.05 + _wind * 0.25))
		fa.rotation.x = -0.9 + sin(t * 1.4 + sd) * 0.1 + _rake * 0.5
	for e in _legs:
		var lp: Node3D = e[0]
		var ph: float = e[1]
		lp.position.y = 0.95 + sin(t * 1.2 + ph) * 0.01


func _attack(kind: String) -> void:
	var tw := create_tween()
	if kind == "gnaw" or kind == "drain":
		for _i in (3 if kind == "gnaw" else 1):
			tw.tween_property(self, "_chomp", 1.0, 0.08)
			tw.tween_property(self, "_chomp", 0.0, 0.1)
	else:
		tw.tween_property(self, "_rake", -0.5, 0.12)
		tw.tween_property(self, "_rake", 1.0, 0.1)
		tw.tween_property(self, "_rake", 0.0, 0.3)
