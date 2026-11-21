extends "res://scripts/battle/creatures/creature_base.gd"
## CURRENT: a blood-eel rearing out of a coiled tail, body a chain of
## tapering segments riding a travelling sine. Fins are torn off by damage.

const SEGS := 14

var _segs: Array = []   ## Node3D holders, tail (0) -> head (SEGS-1)
var _head: Node3D
var _jaw: Node3D
var _strike := 0.0
var _gape := 0.0


func _build() -> void:
	_rng.seed = 606
	_height = 2.0
	var skin := _m(c_accent.darkened(0.2))
	var back := _m(c_dark)
	var belly := _m(c_pale.lerp(c_flesh, 0.5))
	var fin := _m(c_accent.lightened(0.15))
	var bone := _m(c_bone)
	var eye := _m(Color("fff0a0"), {"unlit": true})
	var void_m := _m(c_void, {"unlit": true})
	var fins: Array = []
	for i in SEGS:
		var k := float(i) / float(SEGS - 1)
		var h := _pivot(_root)
		var r := lerpf(0.1, 0.25, sin(minf(k * 1.25, 1.0) * PI * 0.5)) * (1.0 - 0.25 * k * k)
		var seg := _ball(r, skin if i % 2 == 0 else back, h, Vector3.ZERO, 6, 4)
		seg.scale = Vector3(1.0, 1.0, 1.6)
		var bel := _ball(r * 0.75, belly, h, Vector3(0, -r * 0.35, 0), 5, 3)
		bel.scale = Vector3(1.0, 0.6, 1.8)
		_segs.append(h)
		if i >= 2 and i < SEGS - 1 and i % 2 == 0:
			var f := _box(Vector3(0.03, r * 1.3, r * 1.6), fin, h, Vector3(0, r * 1.25, 0))
			f.rotation.x = -0.35
			fins.append(f)
		if i >= 3 and i < SEGS - 2 and i % 3 == 0:
			for sd in [-1.0, 1.0]:
				var s: float = sd
				var pf := _box(Vector3(r * 1.4, 0.03, r * 1.0), fin, h, Vector3(s * r * 1.3, -r * 0.2, 0))
				pf.rotation.z = -0.35 * s
				fins.append(pf)
	# head on the last holder
	_head = _segs[SEGS - 1]
	var skull := _ball(0.22, skin, _head, Vector3(0, 0.03, 0.15), 6, 4)
	skull.scale = Vector3(1.0, 0.8, 1.5)
	_box(Vector3(0.26, 0.05, 0.3), void_m, _head, Vector3(0, -0.06, 0.28))
	for i in 5:
		var t := _cyl(0.0, 0.025, 0.09, bone, _head, Vector3((float(i) - 2.0) * 0.05, -0.05, 0.4), 4)
		t.rotation.x = PI
	_jaw = _pivot(_head, Vector3(0, -0.07, 0.05))
	var jw := _box(Vector3(0.24, 0.06, 0.38), back, _jaw, Vector3(0, -0.03, 0.2))
	jw.rotation.x = 0.0
	for i in 4:
		_cyl(0.0, 0.022, 0.08, bone, _jaw, Vector3((float(i) - 1.5) * 0.05, 0.03, 0.36), 4)
	for sd in [-1.0, 1.0]:
		var s: float = sd
		_ball(0.045, eye, _head, Vector3(0.14 * s, 0.1, 0.22), 4, 3)
		var barb := _cyl(0.0, 0.02, 0.35, fin, _head, Vector3(0.12 * s, -0.08, 0.3), 3)
		barb.rotation = Vector3(-1.2, 0, 0.5 * s)
	for f in fins:
		_part(f as Node3D, FLING)
	_place(0.0)


func _path(k: float, t: float) -> Vector3:
	var rear := 0.15 + _wind * 0.15 - _strike * 0.15
	var x := sin(k * 5.0 - t * 2.2) * 0.32 * (1.0 - k * 0.55)
	if k < 0.5:
		# coiled tail on the floor
		var a := k * 2.0 * PI * 1.1
		var rr := 0.55 - k * 0.5
		return Vector3(cos(a + PI) * rr + x * 0.3, 0.2 + k * 0.1, sin(a + PI) * rr - 0.15)
	var u := (k - 0.5) * 2.0
	var y := 0.3 + u * (1.25 + rear) + sin(u * 3.0 - t * 1.8) * 0.06
	var z := -0.15 + u * (0.35 + _strike * 0.9) - sin(u * PI) * 0.15
	return Vector3(x, y, z)


func _place(t: float) -> void:
	var pts: Array = []
	for i in SEGS:
		pts.append(_path(float(i) / float(SEGS - 1), t))
	for i in SEGS:
		var h: Node3D = _segs[i]
		var p: Vector3 = pts[i]
		var nxt: Vector3
		if i < SEGS - 1:
			nxt = pts[i + 1]
		else:
			var prev: Vector3 = pts[i - 1]
			nxt = p + (p - prev) + Vector3(0, -0.06 - _strike * 0.1, 0.12 + _strike * 0.1)
		h.position = p
		var fwd := nxt - p
		if fwd.length() > 0.001:
			var up := Vector3.UP
			if absf(fwd.normalized().dot(up)) > 0.98:
				up = Vector3.BACK
			h.basis = Basis.looking_at(fwd, up, true)


func _idle(t: float, _dt: float) -> void:
	_place(t)
	_jaw.rotation.x = 0.15 + maxf(sin(t * 1.3), 0.0) * 0.2 + _gape * 0.7 + _wind * 0.3


func _attack(kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_strike", -0.3, 0.1)
	tw.tween_property(self, "_strike", 1.0, 0.08)
	tw.parallel().tween_property(self, "_gape", 1.0, 0.08)
	tw.tween_interval(0.06 if kind != "drain" else 0.3)
	tw.tween_property(self, "_strike", 0.0, 0.3)
	tw.parallel().tween_property(self, "_gape", 0.0, 0.3)
