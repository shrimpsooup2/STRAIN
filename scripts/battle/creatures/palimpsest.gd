extends "res://scripts/battle/creatures/creature_base.gd"
## PALIMPSEST: a slow storm of skin-pages orbiting a dripping ink core, each
## page scrawled over and over. On buffs the pages reshuffle. Pages tear loose
## and drift to the floor with damage.

var _core: Node3D
var _drips: Array = []  ## [mesh, phase]
var _pages: Array = []  ## [holder, radius, base angle, height, phase, tilt]
var _spin := 0.0
var _shuffle := 0.0


func _build() -> void:
	_rng.seed = 1515
	_native_elite = true
	_height = 2.2
	var ink := _m(Color("140c20").lerp(c_dark, 0.3))
	var ink_hi := _m(c_accent.darkened(0.2), {"unlit": true})
	var page_a := _m(Color("d8c8b0").lerp(c_pale, 0.2))
	var page_b := _m(Color("c0a890").lerp(c_floor, 0.2))
	var scrawl := _m(Color("2a1830").lerp(c_accent, 0.15))
	var scrawl_r := _m(c_accent.darkened(0.1))
	# pedestal of dried ink
	var ped := _cyl(0.25, 0.5, 0.35, ink, _root, Vector3(0, 0.17, 0), 7)
	ped.rotation.y = 0.2
	_core = _pivot(_root, Vector3(0, 1.15, 0))
	var orb := _ball(0.32, ink, _core, Vector3.ZERO, 7, 5)
	orb.scale = Vector3(1.0, 1.2, 1.0)
	_ball(0.12, ink_hi, _core, Vector3(0, 0.05, 0.25), 5, 3)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		var dr := _cyl(0.0, 0.05, 0.45, ink, _core, Vector3(cos(a) * 0.15, -0.5, sin(a) * 0.15), 4)
		dr.rotation.x = PI
		_drips.append([dr, float(i) * 1.3])
	# pages in orbit holders
	for i in 10:
		var hp := _pivot(_root)
		var r := _rng.randf_range(0.6, 0.95)
		var ang := TAU * float(i) / 10.0 + _rng.randf_range(-0.2, 0.2)
		var y := _rng.randf_range(0.55, 1.75)
		var pw := _rng.randf_range(0.34, 0.46)
		var ph := pw * 1.3
		var pg := _box(Vector3(pw, ph, 0.025), page_a if i % 2 == 0 else page_b, hp)
		pg.rotation = Vector3(0, 0, _rng.randf_range(-0.25, 0.25))
		for l in 3:
			var ln := _box(Vector3(pw * _rng.randf_range(0.5, 0.8), 0.025, 0.02), scrawl if l != 1 else scrawl_r, pg,
				Vector3(_rng.randf_range(-0.04, 0.04), ph * (0.25 - 0.22 * float(l)), 0.018))
			ln.rotation.z = _rng.randf_range(-0.18, 0.18)
		var corner := _box(Vector3(pw * 0.3, ph * 0.25, 0.03), ink, pg, Vector3(pw * 0.35, -ph * 0.38, 0.0))
		corner.rotation.z = 0.785
		_pages.append([hp, r, ang, y, _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)])
		_part(pg, FALL)


func _idle(t: float, dt: float) -> void:
	_spin += dt * (0.35 + _wind * 1.4 + _shuffle * 4.0)
	_core.position.y = 1.15 + sin(t * 1.3) * 0.05
	_core.rotation.y = t * 0.4
	for e in _drips:
		var dr: MeshInstance3D = e[0]
		var ph: float = e[1]
		var u := fposmod(t * 0.5 + ph, 1.0)
		dr.scale = Vector3(1.0, 0.5 + u * 0.9, 1.0)
	for i in _pages.size():
		var e: Array = _pages[i]
		var hp: Node3D = e[0]
		var r: float = e[1]
		var a0: float = e[2]
		var y: float = e[3]
		var ph: float = e[4]
		var tilt: float = e[5]
		var dirn := 1.0 if i % 3 != 0 else -0.7
		var a := a0 + _spin * dirn
		var rr := r * (1.0 + _wind * 0.15 + _shuffle * 0.3 * sin(float(i) * 2.1))
		hp.position = Vector3(cos(a) * rr, y + sin(t * 0.9 + ph) * 0.08 + _shuffle * 0.2 * sin(float(i) * 1.7), sin(a) * rr)
		# face outward from the core, flutter
		hp.rotation = Vector3(tilt + sin(t * 2.0 + ph) * 0.12, -a + PI * 0.5, sin(t * 1.4 + ph) * 0.1)


func _attack(kind: String) -> void:
	var tw := create_tween()
	if kind == "buff":
		tw.tween_property(self, "_shuffle", 1.0, 0.25)
		tw.tween_property(self, "_shuffle", 0.0, 0.6)
	else:
		tw.tween_property(self, "_shuffle", 0.4, 0.1)
		tw.tween_property(self, "_shuffle", 0.0, 0.3)
