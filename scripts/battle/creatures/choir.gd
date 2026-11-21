extends "res://scripts/battle/creatures/creature_base.gd"
## THE CHOIR (boss): a heaving flesh mound sprouting seven long segmented
## necks, each ending in a bell-head with a hinged singing jaw. They sway out
## of time with each other; on attack they all gape at once. Heads drop off
## with damage, interleaved with nodules on the mound.

var _mound: Node3D
var _necks: Array = []   ## [base pivot, base rot, phase, [joint pivots]]
var _jaws: Array = []    ## [jaw pivot, phase]
var _sing := 0.0


func _build() -> void:
	_rng.seed = 1212
	_native_boss = true
	_height = 2.9
	var flesh := _m(c_flesh)
	var dark := _m(c_dark)
	var pale := _m(c_pale.lerp(c_bone, 0.3))
	var rim := _m(c_accent.darkened(0.1))
	var void_m := _m(c_void, {"unlit": true})
	var nod_m := _m(c_accent.lerp(c_flesh, 0.5))
	var eye := _m(Color("fff0c0"), {"unlit": true})
	_mound = _pivot(_root, Vector3(0, 0.0, 0))
	var m := _ball(1.0, flesh, _mound, Vector3(0, 0.25, -0.05), 10, 6)
	m.scale = Vector3(1.15, 0.6, 0.95)
	var m2 := _ball(0.7, dark, _mound, Vector3(0, 0.08, 0), 8, 4)
	m2.scale = Vector3(1.55, 0.35, 1.35)
	var heads: Array = []
	var nods: Array = []
	var specs := [
		[Vector3(0.0, 0.72, -0.15), 1.85, Vector3(-0.05, 0, 0.0)],
		[Vector3(-0.45, 0.6, -0.1), 1.6, Vector3(0.0, 0, 0.22)],
		[Vector3(0.45, 0.6, -0.1), 1.7, Vector3(0.0, 0, -0.22)],
		[Vector3(-0.7, 0.38, 0.2), 1.2, Vector3(0.2, 0, 0.35)],
		[Vector3(0.72, 0.38, 0.18), 1.3, Vector3(0.2, 0, -0.35)],
		[Vector3(-0.25, 0.55, 0.35), 1.0, Vector3(0.35, 0, 0.15)],
		[Vector3(0.28, 0.55, 0.38), 0.9, Vector3(0.4, 0, -0.2)],
	]
	for i in specs.size():
		var sp: Array = specs[i]
		var p: Vector3 = sp[0]
		var l: float = sp[1]
		var r0: Vector3 = sp[2]
		var bp := _pivot(_mound, p, r0)
		var joints: Array = []
		var parent: Node3D = bp
		var segs := 4
		var sl := l / float(segs)
		for s in segs:
			var rr := lerpf(0.11, 0.06, float(s) / float(segs))
			_cyl(rr * 0.85, rr, sl, flesh if s % 2 == 0 else dark, parent, Vector3(0, sl * 0.5, 0), 5)
			_torus(rr * 0.7, rr * 1.35, pale, parent, Vector3(0, sl * 0.95, 0), 8, 3)
			var j := _pivot(parent, Vector3(0, sl, 0))
			joints.append(j)
			parent = j
		# head: a bell that faces forward; FALL part
		var hd := _pivot(parent, Vector3(0, 0.05, 0))
		var hz := 0.18 if i < 3 else 0.14
		var bell := _cyl(hz * 1.25, hz * 0.6, hz * 2.0, pale, hd, Vector3(0, hz * 0.6, hz * 0.4), 7)
		bell.rotation.x = 1.25
		var crown := _ball(hz * 0.62, pale, hd, Vector3(0, hz * 0.35, -hz * 0.5), 6, 3)
		crown.scale = Vector3(1.0, 0.8, 1.0)
		var throat := _cyl(hz * 1.1, hz * 1.1, 0.03, void_m, hd, Vector3(0, hz * 0.88, hz * 1.3), 7)
		throat.rotation.x = 1.25
		_ball(0.03, eye, hd, Vector3(-hz * 0.4, hz * 1.15, hz * 0.45), 4, 3)
		_ball(0.03, eye, hd, Vector3(hz * 0.4, hz * 1.15, hz * 0.45), 4, 3)
		var jw := _pivot(hd, Vector3(0, -hz * 0.2, hz * 0.9))
		_box(Vector3(hz * 1.6, 0.05, hz * 1.2), rim, jw, Vector3(0, -0.02, hz * 0.5))
		_jaws.append([jw, float(i) * 0.9])
		_necks.append([bp, r0, float(i) * 1.37, joints])
		heads.append(hd)
	for i in 9:
		var d := _rand_dir(0.25)
		var n := _ball(_rng.randf_range(0.09, 0.16), nod_m, _mound, Vector3(0, 0.25, -0.05) + Vector3(d.x * 1.12, d.y * 0.58, d.z * 0.93), 5, 3)
		nods.append(n)
	# interleave: heads last-in-list lose first; small necks first
	var order: Array = []
	for i in 9:
		if i < heads.size():
			order.append(heads[i])
		order.append(nods[i])
	for p in order:
		_part(p as Node3D, FALL)


func _idle(t: float, _dt: float) -> void:
	var br := sin(t * 1.1)
	_mound.scale = Vector3(1.0 + br * 0.02, 1.0 + br * 0.04, 1.0 + br * 0.02)
	for e in _necks:
		var bp: Node3D = e[0]
		var r0: Vector3 = e[1]
		var ph: float = e[2]
		var joints: Array = e[3]
		var rear := -_sing * 0.25 - _wind * 0.15
		bp.rotation = r0 + Vector3(sin(t * 0.8 + ph) * 0.1 + rear, 0, cos(t * 0.7 + ph) * 0.12)
		for ji in joints.size():
			var j: Node3D = joints[ji]
			var k := float(ji + 1)
			j.rotation = Vector3(sin(t * 1.1 + ph - k * 0.6) * 0.09 + _sing * 0.08, 0, sin(t * 0.9 + ph - k * 0.5) * 0.1)
	for e in _jaws:
		var jw: Node3D = e[0]
		var ph: float = e[1]
		jw.rotation.x = 0.1 + maxf(sin(t * 1.7 + ph), 0.0) * 0.35 + _sing * 0.7 + _wind * 0.4


func _attack(kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_sing", 1.0, 0.15)
	tw.tween_interval(0.25 if kind != "buff" else 0.5)
	tw.tween_property(self, "_sing", 0.0, 0.4)
