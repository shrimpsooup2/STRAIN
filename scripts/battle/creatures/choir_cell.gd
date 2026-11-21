extends "res://scripts/battle/creatures/creature_base.gd"
## CHOIR CELL: a hovering flesh bell. Rows of small dark mouths open and close
## around its waist; a tongue-clapper swings beneath. Frills and nodules fall
## away with damage.

var _bell: Node3D
var _clapper: Node3D
var _mouths: Array = []  ## [pivot, phase]
var _ring := 0.0


func _build() -> void:
	_rng.seed = 909
	_height = 2.1
	var flesh := _m(c_flesh)
	var pale := _m(c_pale.lerp(c_flesh, 0.5))
	var rim := _m(c_accent.darkened(0.1))
	var dark := _m(c_dark)
	var void_m := _m(c_void, {"unlit": true})
	var tongue := _m(c_accent.lerp(Color("ff8090"), 0.3))
	var shadow_m := Retro.mat(Color(0, 0, 0), {"alpha": 0.3})
	_cyl(0.5, 0.5, 0.01, shadow_m, _root, Vector3(0, 0.02, 0), 10)
	_bell = _pivot(_root, Vector3(0, 1.5, 0))
	# bell body: flared cone + dome cap + lip torus
	_cyl(0.42, 0.72, 0.85, flesh, _bell, Vector3(0, -0.15, 0), 10)
	var dome := _ball(0.43, pale, _bell, Vector3(0, 0.27, 0), 10, 5)
	dome.scale = Vector3(1.0, 0.7, 1.0)
	_torus(0.62, 0.8, rim, _bell, Vector3(0, -0.58, 0), 14, 4)
	var inner := _cyl(0.66, 0.66, 0.04, void_m, _bell, Vector3(0, -0.56, 0), 10)
	inner.rotation.x = PI
	_cyl(0.06, 0.1, 0.25, dark, _bell, Vector3(0, 0.55, 0), 5)
	var collar := _torus(0.05, 0.11, dark, _bell, Vector3(0, 0.7, 0), 8, 3)
	collar.rotation.x = PI * 0.5
	# mouths around the waist
	for i in 7:
		var a := TAU * float(i) / 7.0
		var r := 0.6
		var mp := _pivot(_bell, Vector3(sin(a) * r, -0.22, cos(a) * r), Vector3(0, a, 0))
		mp.rotate_object_local(Vector3.RIGHT, -0.33)
		var lipm := _ball(0.11, rim, mp, Vector3(0, 0, 0.02), 6, 3)
		lipm.scale = Vector3(1.2, 0.5, 0.5)
		_ball(0.08, void_m, mp, Vector3(0, 0, 0.06), 5, 3)
		_mouths.append([mp, float(i) * 0.9])
	# clapper / tongue swinging under the bell
	_clapper = _pivot(_bell, Vector3(0, -0.25, 0))
	_cyl(0.03, 0.05, 0.75, dark, _clapper, Vector3(0, -0.4, 0), 4)
	var tip := _ball(0.16, tongue, _clapper, Vector3(0, -0.82, 0), 6, 4)
	tip.scale = Vector3(0.9, 1.3, 0.9)
	# parts: rim frills (lost last), then nodules on the dome (lost first)
	for i in 12:
		var a := TAU * (float(i) + 0.5) / 12.0
		var fp := _pivot(_bell, Vector3(sin(a) * 0.78, -0.62, cos(a) * 0.78), Vector3(0, a, 0))
		var fr := _box(Vector3(0.14, 0.24, 0.04), rim if i % 2 == 0 else flesh, fp, Vector3(0, -0.1, 0))
		fr.rotation.x = 0.3
		_part(fp, FALL)
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.3
		var el := 0.35 + 0.35 * float(i % 2)
		var d := Vector3(sin(a) * cos(el), sin(el) * 0.7, cos(a) * cos(el))
		var n := _ball(0.07 + 0.03 * float(i % 3), pale, _bell, Vector3(0, 0.27, 0) + d * 0.43, 5, 3)
		_part(n, POP)


func _idle(t: float, _dt: float) -> void:
	_bell.position.y = 1.5 + sin(t * 1.4) * 0.07
	var sw := sin(t * 1.1) * 0.06 + sin(t * 9.0) * 0.03 * _ring
	_bell.rotation = Vector3(sw, t * 0.2, cos(t * 0.9) * 0.05)
	_clapper.rotation = Vector3(sin(t * 1.1 + 0.8) * 0.35 + sin(t * 14.0) * 0.4 * _ring, 0, cos(t * 1.3) * 0.25)
	for e in _mouths:
		var mp: Node3D = e[0]
		var ph: float = e[1]
		var o := 0.35 + maxf(sin(t * 2.2 + ph), 0.0) * 0.8 + _ring * 0.8 + _wind * 0.6
		mp.scale = Vector3(1.0, o, 1.0)


func _attack(_kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_ring", 1.0, 0.08)
	tw.tween_interval(0.2)
	tw.tween_property(self, "_ring", 0.0, 0.4)
