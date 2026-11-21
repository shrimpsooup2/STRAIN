extends "res://scripts/battle/creatures/creature_base.gd"
## SHROUD: a hovering crown of gristle trailing a curtain of translucent
## membrane strips. Faces press out through the veil from behind and sink
## back. Knotted tatters hang below. Faces and tatters are lost with damage.

var _crown: Node3D
var _veils: Array = []  ## [pivot, base rot, phase]
var _faces: Array = []  ## [holder, phase]
var _billow := 0.0


func _build() -> void:
	_rng.seed = 1111
	_native_elite = true
	_height = 2.15
	var gristle := _m(c_bone.lerp(c_floor, 0.35))
	var dark := _m(c_dark)
	var skin := _m(c_pale.lerp(c_bone, 0.4))
	var void_m := _m(c_void, {"unlit": true})
	var veil_a := _m(c_pale, {"alpha": 0.42})
	var veil_b := _m(c_accent.lightened(0.2), {"alpha": 0.32})
	_crown = _pivot(_root, Vector3(0, 1.95, 0))
	var ring := _torus(0.42, 0.56, gristle, _crown, Vector3.ZERO, 14, 4)
	ring.scale = Vector3(1.0, 1.4, 1.0)
	for i in 7:
		var a := TAU * float(i) / 7.0
		var sp := _cyl(0.0, 0.06, 0.26, gristle, _crown, Vector3(cos(a) * 0.5, 0.15, sin(a) * 0.5), 4)
		sp.rotation = Vector3(0, -a, 0)
		sp.rotate_object_local(Vector3.FORWARD, -0.2)
	var lid := _ball(0.42, dark, _crown, Vector3(0, -0.02, 0), 8, 3)
	lid.scale = Vector3(1.0, 0.35, 1.0)
	# veil strips hanging from the ring, a full curtain (thin boxes, cull safe)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var vp := _pivot(_crown, Vector3(cos(a) * 0.5, -0.05, sin(a) * 0.5))
		var base := Vector3(0, -a + PI * 0.5, 0)
		vp.rotation = base
		var l := _rng.randf_range(1.25, 1.6)
		var strip := _box(Vector3(0.3, l, 0.02), veil_a if i % 2 == 0 else veil_b, vp, Vector3(0, -l * 0.5, 0))
		strip.rotation.z = _rng.randf_range(-0.06, 0.06)
		_veils.append([vp, base, float(i) * 0.6])
	# faces pressing out of the front of the veil
	var faces: Array = []
	var spots := [Vector3(-0.22, 1.35, 0.4), Vector3(0.26, 1.15, 0.38), Vector3(0.0, 0.85, 0.45), Vector3(-0.3, 0.7, 0.32), Vector3(0.32, 0.55, 0.3)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var h := _pivot(_root, p)
		var f := _pivot(h)
		var head := _ball(0.17, skin, f, Vector3.ZERO, 6, 4)
		head.scale = Vector3(0.85, 1.1, 0.6)
		for sd in [-1.0, 1.0]:
			var s: float = sd
			var eye := _ball(0.04, void_m, f, Vector3(0.06 * s, 0.04, 0.09), 4, 3)
			eye.scale = Vector3(1.0, 0.6, 0.5)
		var mouth := _box(Vector3(0.07, 0.05, 0.02), void_m, f, Vector3(0, -0.08, 0.095))
		mouth.rotation.z = 0.0
		_faces.append([h, float(i) * 1.7])
		faces.append(f)
	# tatters under the curtain, knotted ends
	var tatters: Array = []
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.25
		var tp := _pivot(_root, Vector3(cos(a) * 0.4, 0.45, sin(a) * 0.4))
		_box(Vector3(0.06, 0.35, 0.02), dark, tp, Vector3(0, -0.15, 0))
		_ball(0.05, gristle, tp, Vector3(0, -0.33, 0), 4, 3)
		tatters.append(tp)
	for f in faces:
		_part(f as Node3D, POP)
	for tp in tatters:
		_part(tp as Node3D, FALL)


func _idle(t: float, _dt: float) -> void:
	_crown.position.y = 1.95 + sin(t * 1.2) * 0.06
	_crown.rotation = Vector3(sin(t * 0.7) * 0.05, t * 0.12, cos(t * 0.8) * 0.05)
	for e in _veils:
		var vp: Node3D = e[0]
		var base: Vector3 = e[1]
		var ph: float = e[2]
		vp.rotation = base + Vector3(sin(t * 1.5 + ph) * 0.1 - _billow * 0.4 - _wind * 0.15, 0, 0)
	for e in _faces:
		var h: Node3D = e[0]
		var ph: float = e[1]
		var push := maxf(sin(t * 0.9 + ph), 0.0)
		var k := 0.35 + push * 0.75 + _wind * 0.4 + _billow * 0.3
		h.scale = Vector3(k, k, k)


func _attack(_kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_billow", 1.0, 0.15)
	tw.tween_property(self, "_billow", 0.0, 0.5)
