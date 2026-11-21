extends "res://scripts/battle/creatures/creature_base.gd"
## TENDRIL: a gnarled root-ball with five tapering, jointed whips that coil
## and lash. Rootlets claw the floor. Whip tips and rootlets snap off with
## damage.

var _ball_n: Node3D
var _whips: Array = []   ## [base pivot, base rot, phase, [joints]]
var _lash := 0.0


func _build() -> void:
	_rng.seed = 1717
	_height = 2.0
	var bark := _m(c_dark.lerp(Color("2a1c10"), 0.35))
	var bark_l := _m(c_floor.lerp(Color("5a4028"), 0.35))
	var green := _m(c_accent.darkened(0.2))
	var tip_m := _m(c_accent.lightened(0.2), {"unlit": true})
	var knot := _m(c_floor.darkened(0.2))
	_ball_n = _pivot(_root, Vector3(0, 0.45, 0))
	var b := _ball(0.48, bark, _ball_n, Vector3.ZERO, 8, 5)
	b.scale = Vector3(1.1, 0.85, 1.0)
	for i in 6:
		var d := _rand_dir(-0.2)
		var k := _ball(_rng.randf_range(0.13, 0.22), knot if i % 2 == 0 else bark_l, _ball_n, d * 0.42, 5, 3)
		k.scale = Vector3(1.0, 0.8, 1.0)
	var tips: Array = []
	var specs := [
		[Vector3(0.0, 0.3, 0.1), Vector3(0.15, 0, 0.0), 1.65],
		[Vector3(-0.3, 0.2, 0.0), Vector3(0.05, 0, 0.45), 1.35],
		[Vector3(0.32, 0.22, -0.05), Vector3(0.0, 0, -0.45), 1.4],
		[Vector3(-0.15, 0.25, -0.3), Vector3(-0.35, 0, 0.2), 1.2],
		[Vector3(0.2, 0.2, 0.3), Vector3(0.55, 0, -0.15), 1.1],
	]
	for i in specs.size():
		var sp: Array = specs[i]
		var p: Vector3 = sp[0]
		var r0: Vector3 = sp[1]
		var l: float = sp[2]
		var bp := _pivot(_ball_n, p, r0)
		var joints: Array = []
		var parent: Node3D = bp
		var segs := 5
		var sl := l / float(segs)
		for s in segs:
			var k := float(s) / float(segs)
			var r := lerpf(0.11, 0.025, k)
			_cyl(r * 0.78, r, sl, bark if s % 2 == 0 else bark_l, parent, Vector3(0, sl * 0.5, 0), 5)
			if s == 1 or s == 3:
				var th := _cyl(0.0, r * 0.5, 0.12, green, parent, Vector3(r * 0.9, sl * 0.5, 0), 3)
				th.rotation.z = -1.0
			var j := _pivot(parent, Vector3(0, sl, 0))
			joints.append(j)
			parent = j
		# the last joint carries the barbed tip (POP part)
		var tip := _pivot(parent)
		_cyl(0.0, 0.03, 0.18, green, tip, Vector3(0, 0.09, 0), 4)
		_ball(0.035, tip_m, tip, Vector3(0, 0.02, 0), 4, 3)
		tips.append(tip)
		_whips.append([bp, r0, float(i) * 1.23, joints])
	# rootlets on the floor
	var roots: Array = []
	for i in 7:
		var a := TAU * float(i) / 7.0 + _rng.randf_range(-0.2, 0.2)
		var rp := _pivot(_root, Vector3(cos(a) * 0.35, 0.12, sin(a) * 0.35), Vector3(0, -a, 0))
		var rl := _rng.randf_range(0.4, 0.65)
		var rc := _cyl(0.05, 0.015, rl, bark, rp, Vector3(rl * 0.45, -0.04, 0), 4)
		rc.rotation.z = PI * 0.5 - 0.2
		roots.append(rp)
	for i in maxi(tips.size(), roots.size()):
		if i < roots.size():
			_part(roots[i] as Node3D, FALL)
		if i < tips.size():
			_part(tips[i] as Node3D, POP)


func _idle(t: float, _dt: float) -> void:
	_ball_n.scale = Vector3.ONE * (1.0 + sin(t * 1.5) * 0.03)
	_ball_n.rotation.y = sin(t * 0.3) * 0.15
	for e in _whips:
		var bp: Node3D = e[0]
		var r0: Vector3 = e[1]
		var ph: float = e[2]
		var joints: Array = e[3]
		var coil := 0.1 + _wind * 0.25 - _lash * 0.2
		bp.rotation = r0 + Vector3(sin(t * 0.9 + ph) * 0.12 - _lash * 0.4, 0, cos(t * 0.7 + ph) * 0.1)
		for ji in joints.size():
			var j: Node3D = joints[ji]
			var k := float(ji + 1)
			var w := sin(t * 1.8 + ph - k * 0.7)
			j.rotation = Vector3(coil * (0.5 + k * 0.25) + w * 0.14 + _lash * 0.35 * sin(k * 1.3), 0, cos(t * 1.4 + ph - k * 0.6) * 0.16)


func _attack(kind: String) -> void:
	var tw := create_tween()
	var reps := 3 if kind == "gnaw" else 1
	for _i in reps:
		tw.tween_property(self, "_lash", -0.5, 0.1)
		tw.tween_property(self, "_lash", 1.0, 0.07)
	tw.tween_property(self, "_lash", 0.0, 0.3)
