extends "res://scripts/battle/creatures/creature_base.gd"
## CREEPER: a low clot crawler. Lumpy clot abdomen, eight high-kneed legs,
## bone mandibles. Loses back nodules, then leg tips.

var _body: Node3D
var _legs: Array = []   ## [hip pivot, base z rot, phase, knee pivot, knee base z]
var _mand: Array = []   ## [pivot, side]
var _snap := 0.0


func _build() -> void:
	_rng.seed = 101
	_height = 1.65
	var flesh := _m(c_flesh.darkened(0.1))
	var clot := _m(c_dark.lerp(Color("200404"), 0.3))
	var raw := _m(c_accent.darkened(0.1))
	var bone := _m(c_bone)
	var eye := _m(Color("f0d870"), {"unlit": true})
	_body = _pivot(_root, Vector3(0, 0.78, 0))
	var abd := _ball(0.55, clot, _body, Vector3(0, 0.22, -0.58), 7, 5)
	abd.scale = Vector3(1.0, 0.82, 1.15)
	var thx := _ball(0.34, flesh, _body, Vector3(0, 0.04, 0.02), 6, 4)
	thx.scale = Vector3(1.1, 0.8, 1.0)
	var head := _ball(0.26, flesh, _body, Vector3(0, -0.02, 0.4), 6, 4)
	head.scale = Vector3(1.15, 0.75, 1.0)
	_box(Vector3(0.5, 0.06, 0.3), raw, _body, Vector3(0, -0.2, 0.02))
	for i in 4:
		var ex := -0.12 + 0.08 * float(i)
		_ball(0.035, eye, _body, Vector3(ex, 0.12 - absf(ex) * 0.4, 0.6), 4, 3)
	for side in [-1.0, 1.0]:
		var sd: float = side
		var mp := _pivot(_body, Vector3(0.11 * sd, -0.08, 0.6))
		_box(Vector3(0.06, 0.06, 0.26), bone, mp, Vector3(0.03 * sd, 0, 0.12))
		var tip := _box(Vector3(0.05, 0.05, 0.2), bone, mp, Vector3(-0.02 * sd, 0, 0.3))
		tip.rotation.y = -0.7 * sd
		_mand.append([mp, sd])
	# legs: 4 per side, hip pivots yawed outward, knee bent down to the floor
	var knees: Array = []
	for side in [-1.0, 1.0]:
		var sd: float = side
		for i in 4:
			var a := lerpf(0.65, -0.7, float(i) / 3.0)
			var yaw := -a if sd > 0.0 else PI + a
			var frame := _pivot(_body, Vector3(0.24 * sd, 0.0, 0.25 - 0.2 * float(i)), Vector3(0, yaw, 0))
			var hip := _pivot(frame, Vector3.ZERO, Vector3(0, 0, 0.9))
			var l1 := 0.58
			_box(Vector3(l1, 0.08, 0.08), flesh, hip, Vector3(l1 * 0.5, 0, 0))
			var knee := _pivot(hip, Vector3(l1, 0, 0), Vector3(0, 0, -2.15))
			var l2 := 1.22
			_box(Vector3(l2, 0.06, 0.06), clot, knee, Vector3(l2 * 0.5, 0, 0))
			_ball(0.05, raw, knee, Vector3(0, 0, 0), 4, 3)
			_legs.append([hip, 0.9, float(i) * 1.7 + (0.0 if sd > 0.0 else PI), knee, -2.15])
			if i % 2 == 1:
				knees.append(knee)
	for k in knees:
		_part(k as Node3D, POP)
	# clot nodules on the abdomen, lost first
	var nod := _m(c_accent.lerp(Color("401010"), 0.45))
	for i in 10:
		var d := _rand_dir(0.1)
		var r := _rng.randf_range(0.08, 0.15)
		var n := _ball(r, nod if i % 3 != 0 else raw, _body, Vector3(0, 0.22, -0.58) + Vector3(d.x * 0.55, d.y * 0.45, d.z * 0.63), 5, 3)
		_part(n, POP)


func _idle(t: float, _dt: float) -> void:
	_body.position.y = 0.78 + sin(t * 3.0) * 0.025
	_body.rotation.z = sin(t * 1.5) * 0.04
	for e in _legs:
		var hip: Node3D = e[0]
		var bz: float = e[1]
		var ph: float = e[2]
		var knee: Node3D = e[3]
		var kz: float = e[4]
		var w := sin(t * 4.0 + ph)
		hip.rotation.z = bz + maxf(w, 0.0) * 0.18
		hip.rotation.y = w * 0.1
		knee.rotation.z = kz - maxf(w, 0.0) * 0.12
	var open := 0.15 + sin(t * 2.3) * 0.12 + _snap * 0.6
	for e in _mand:
		var mp: Node3D = e[0]
		var sd: float = e[1]
		mp.rotation.y = open * sd


func _attack(kind: String) -> void:
	if kind == "dmg" or kind == "gnaw":
		var tw := create_tween()
		var reps := 3 if kind == "gnaw" else 1
		for _i in reps:
			tw.tween_property(self, "_snap", 1.0, 0.06)
			tw.tween_property(self, "_snap", -0.4, 0.06)
		tw.tween_property(self, "_snap", 0.0, 0.12)


func _on_windup(on: bool) -> void:
	_snap = 0.6 if on else 0.0
