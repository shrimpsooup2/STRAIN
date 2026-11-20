extends Node3D
## Endings. Shown, never explained.
##   purge  - you scan clean and walk out into the grey. The last seed burns behind you.
##   root   - you lie down in the test bed and open the vent. Green spreads. So does the risk.
##   graft  - a leashed seed goes up the vent, you purge, you walk out. It doesn't climb your hand.
##   fallow - nobody leaves. The wing sterilizes itself.

const GROUND_SHADER := preload("res://shaders/ground_spread.gdshader")
const HandView := preload("res://scripts/ui/hand_view.gd")

var _set: Node3D
var _cam: Camera3D
var _env: WorldEnvironment
var _layer: CanvasLayer
var _key := "purge"
var _walkers: Array = []  ## [{fig, speed, t}]
var _motes: Array = []
var _ground_mat: ShaderMaterial
var _skip := false


func _ready() -> void:
	_key = Game.ending if Game.ending != "" else "purge"
	var args := Game._user_args()
	if args.has("ending"):
		_key = args["ending"]
	UI.set_post(0.0, 0.0)
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)
	_cam = Camera3D.new()
	_cam.fov = 40
	add_child(_cam)
	_play()


func _process(dt: float) -> void:
	for w in _walkers:
		if not is_instance_valid(w["fig"]):
			continue
		var fig: Node3D = w["fig"]
		w["t"] += dt
		fig.position += -fig.global_transform.basis.z * w["speed"] * dt
		Figure.walk(fig, w["t"])
	for m in _motes:
		if not is_instance_valid(m["node"]):
			continue
		var mi: Node3D = m["node"]
		mi.position += m["vel"] * dt
		if mi.position.x > 20.0:
			mi.position.x = -20.0


func _play() -> void:
	match _key:
		"purge":
			await _shot_airlock()
			await _shot_surface_walk(false)
			await _shot_hand(true, false)
			await _card("I", "PURGE")
		"root":
			await _shot_garden_lie_down()
			await _shot_aerial_spread()
			await _shot_stranger()
			await _shot_hand(false, false, 1)
			await _card("II", "ROOT")
		"graft":
			await _shot_capsule()
			await _shot_airlock()
			await _shot_surface_walk(true)
			await _shot_hand(true, true)
			await _card("III", "GRAFT")
		_:
			await _shot_fallow()
			await _card("0", "FALLOW")
	Game.record_ending(_key)
	Game.ending = ""
	Game.goto("title")


# ------------------------------------------------------------------ utilities

func _new_set(bg: Color, ambient: Color, ambient_energy := 1.0, fog := Color.BLACK, fog_density := 0.0) -> void:
	if _set:
		_set.queue_free()
	_walkers.clear()
	_motes.clear()
	_set = Node3D.new()
	add_child(_set)
	_env = Retro.environment(bg, ambient, ambient_energy, fog, fog_density)
	_set.add_child(_env)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _cut() -> void:
	await UI.fade_out(0.6)


func _reveal() -> void:
	await UI.fade_in(0.6)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at)


func _cam_move(to: Vector3, at: Vector3, t: float) -> void:
	var tw := create_tween()
	tw.tween_method(_cam_step.bind(_cam.position, to, at), 0.0, 1.0, t).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _cam_step(k: float, from: Vector3, to: Vector3, at: Vector3) -> void:
	_cam.position = from.lerp(to, k)
	_cam.look_at(at)


func _ground(size: float, center: Vector3, radius: float) -> MeshInstance3D:
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	p.subdivide_width = 16
	p.subdivide_depth = 16
	var mi := MeshInstance3D.new()
	mi.mesh = p
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GROUND_SHADER
	_ground_mat.set_shader_parameter("center", center)
	_ground_mat.set_shader_parameter("radius", radius)
	mi.material_override = _ground_mat
	_set.add_child(mi)
	return mi


func _dust(count: int, color: Color, area: float, height: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in count:
		var b := Retro.box(Vector3(0.05, 0.05, 0.05), color,
			Vector3(rng.randf_range(-area, area), rng.randf_range(0.2, height), rng.randf_range(-area, area)), {"unlit": true})
		_set.add_child(b)
		_motes.append({"node": b, "vel": Vector3(rng.randf_range(0.6, 1.4), rng.randf_range(-0.05, 0.05), 0)})


func _bunker(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var concrete := Retro.tex_noise(Color("7c7e7c"), Color("6c6e6c"), 16, 9, 0.4)
	n.add_child(Retro.box(Vector3(4, 1.6, 3), Color.WHITE, Vector3(0, 0.8, 0), {"tex": concrete}))
	# Door faces -Z (the way out); the vent sits on the roof behind it.
	n.add_child(Retro.box(Vector3(1.4, 1.3, 0.1), Color("3a3e42"), Vector3(0, 0.65, -1.52)))
	n.add_child(Retro.box(Vector3(0.6, 0.6, 0.6), Color("5a5e60"), Vector3(1.2, 1.9, 0.6)))
	_set.add_child(n)
	return n


## A tall stack of dark boxes rising from the vent: the wing burning behind you.
func _smoke(pos: Vector3) -> void:
	var glow := Retro.omni(Color("ff8030"), 6.0, 2.0, pos + Vector3(0, 0.5, 0))
	_set.add_child(glow)
	for i in 10:
		var s := 0.5 + i * 0.18
		var b := Retro.box(Vector3(s, s, s), Color("2a2a2c").lerp(Color("6a6a6a"), i / 10.0),
			pos + Vector3(sin(i * 1.7) * 0.3 + i * 0.3, 0.6 + i * 0.7, cos(i * 1.3) * 0.2 + i * 0.25), {"unlit": true})
		b.rotation_degrees = Vector3(i * 17, i * 31, 0)
		_set.add_child(b)
	var tw := glow.create_tween().set_loops()
	tw.tween_property(glow, "light_energy", 3.0, 0.2)
	tw.tween_property(glow, "light_energy", 1.6, 0.3)


# ------------------------------------------------------------------ shots

## Airlock: scan, CLEAN, the red light turns green, the door lifts into white.
func _shot_airlock() -> void:
	_new_set(Color("05070a"), Color("202830"), 0.5)
	var wall := Retro.tex_panel(Color("5a6670"), Color("3a444c"))
	_set.add_child(Retro.box(Vector3(6, 0.1, 8), Color("2a3036"), Vector3(0, -0.05, 0)))
	_set.add_child(Retro.box(Vector3(0.2, 3, 8), Color.WHITE, Vector3(-1.6, 1.5, 0), {"tex": wall, "uv": 3.0}))
	_set.add_child(Retro.box(Vector3(0.2, 3, 8), Color.WHITE, Vector3(1.6, 1.5, 0), {"tex": wall, "uv": 3.0}))
	_set.add_child(Retro.box(Vector3(3.4, 0.6, 0.3), Color("3a444c"), Vector3(0, 2.7, -3)))
	var door := Retro.box(Vector3(3.0, 2.4, 0.2), Color.WHITE, Vector3(0, 1.2, -3),
		{"tex": Retro.tex_stripes(Color("c8a030"), Color("2a2a2a")), "uv": 3.0})
	_set.add_child(door)
	var lamp_mat := Retro.mat_unique(Color("e04040"), {"unlit": true})
	var lamp := Retro.box(Vector3(0.4, 0.15, 0.1), Color.WHITE, Vector3(0, 2.6, -2.8))
	lamp.material_override = lamp_mat
	_set.add_child(lamp)
	var light := Retro.omni(Color("e04040"), 6.0, 1.8, Vector3(0, 2.2, -2.2))
	_set.add_child(light)
	var fig := Figure.build()
	fig.position = Vector3(0, 0, 0.6)
	fig.rotation_degrees.y = 0
	_set.add_child(fig)
	_look(Vector3(0.8, 2.5, 4.6), Vector3(0, 0.9, -2))
	await _reveal()
	await _wait(0.8)
	await UI.say(Lore.FLAVOR["airlock_clean"], "see")
	lamp_mat.set_shader_parameter("albedo", Color("70d850"))
	light.light_color = Color("70d850")
	await _wait(1.2)
	var white := Retro.omni(Color("ffffff"), 10.0, 0.0, Vector3(0, 1.5, -4))
	_set.add_child(white)
	var tw := create_tween().set_parallel()
	tw.tween_property(door, "position:y", 3.8, 2.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(white, "light_energy", 6.0, 2.5)
	tw.tween_property(_env.environment, "background_color", Color("e8ecec"), 2.5)
	await tw.finished
	_walkers.append({"fig": fig, "speed": 1.0, "t": 0.0})
	await _wait(1.5)
	await _cut()


## Surface: grey to the horizon. graft=true: a green patch far off, the figure kneels at its edge.
func _shot_surface_walk(graft: bool) -> void:
	_new_set(Color("8a8c8c"), Color("b0b2b0"), 0.8, Color("8a8c8c"), 0.03)
	_set.add_child(Retro.sun(Vector3(-40, -30, 0), Color("d0d0c8"), 0.7))
	var green_center := Vector3(0, 0, -26)
	_ground(120.0, green_center, 0.0)
	_bunker(Vector3(0, 0, 4))
	if not graft:
		_smoke(Vector3(1.2, 2.2, 4.6))
	_dust(60, Color("b8b8b0"), 18.0, 3.0)
	var fig := Figure.build()
	fig.position = Vector3(0, 0, 2.2)
	fig.rotation_degrees.y = 0
	_set.add_child(fig)
	_look(Vector3(-3.0, 4.6, 11.0), Vector3(0.5, 0.6, -4))
	_walkers.append({"fig": fig, "speed": 1.1, "t": 0.0})
	await _reveal()
	if not graft:
		await _cam_move(Vector3(-3.6, 6.0, 13.5), Vector3(0.5, 0.5, -8), 7.0)
		await _cut()
		return
	# Graft: the seed has already taken somewhere ahead. It spreads; you reach the edge.
	var tw := create_tween()
	tw.tween_method(func(r: float): _ground_mat.set_shader_parameter("radius", r), 0.0, 16.0, 9.0)
	await _cam_move(Vector3(2.5, 3.2, -1.0), Vector3(0, 0.6, -12), 6.0)
	await _wait(2.5)
	_walkers.clear()
	Figure.idle(fig)
	var kneel := create_tween()
	kneel.tween_property(fig, "position:y", -0.35, 0.8)
	kneel.parallel().tween_property(fig.get_node("ArmL"), "rotation:x", -1.2, 0.8)
	await _cam_move(fig.position + Vector3(1.6, 1.0, 1.6), fig.position + Vector3(0, 0.3, -1.2), 2.5)
	await _wait(1.0)
	await _cut()


## A last look at your hand.
func _shot_hand(clean: bool, moss_edge: bool, stage := 0) -> void:
	if _set:
		_set.queue_free()
		_set = null
	var bg := ColorRect.new()
	bg.color = Color("06090c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)
	var hv: Control = HandView.new()
	hv.stage = stage
	hv.progress = 0.0
	hv.clean = clean
	hv.position = Vector2((UI.W - 96) / 2.0, 40)
	_layer.add_child(hv)
	var moss: ColorRect = null
	if moss_edge:
		moss = ColorRect.new()
		moss.color = Color("4a9a3c")
		moss.position = Vector2((UI.W - 120) / 2.0, 152)
		moss.size = Vector2(120, 6)
		_layer.add_child(moss)
	await _reveal()
	if moss:
		# It reaches for the fingers, and stops.
		var tw := create_tween().set_loops(3)
		tw.tween_property(moss, "size:y", 9.0, 0.6)
		tw.tween_property(moss, "size:y", 6.0, 0.6)
	await _wait(4.0)
	await _cut()
	bg.queue_free()
	hv.queue_free()
	if moss:
		moss.queue_free()


## Root: you lie down in the test bed. The camera rises up the vent shaft into light.
func _shot_garden_lie_down() -> void:
	_new_set(Color("040806"), Color("1a2a1c"), 0.6, Color("040806"), 0.06)
	_set.add_child(Retro.box(Vector3(10, 0.1, 10), Color("2a302a"), Vector3(0, -0.05, 0)))
	for x in 5:
		for z in 3:
			_set.add_child(Retro.cyl(0.22, 0.17, 0.35, Color("6a6c6a"), 6, Vector3(-2.5 + x * 0.9, 0.18, -2.4 + z * 0.8)))
			_set.add_child(Retro.cyl(0.2, 0.2, 0.02, Color("8a8a84"), 6, Vector3(-2.5 + x * 0.9, 0.36, -2.4 + z * 0.8)))
	_set.add_child(Retro.box(Vector3(1.2, 0.4, 2.4), Color("4a3a2c"), Vector3(0, 0.2, 1.0)))
	_set.add_child(Retro.box(Vector3(1.0, 0.06, 2.2), Color("8a8a84"), Vector3(0, 0.42, 1.0)))
	var shaft := Retro.cyl(0.7, 0.7, 12.0, Color("d8f0c8"), 8, Vector3(0, 6.5, 1.0), {"alpha": 0.12})
	_set.add_child(shaft)
	_set.add_child(Retro.omni(Color("c8f0b0"), 5.0, 1.4, Vector3(0, 3.0, 1.0)))
	var fig := Figure.build(Figure.COAT, Color("70d850"))
	fig.position = Vector3(0, 0.5, 1.9)
	fig.rotation_degrees = Vector3(-90, 0, 0)
	_set.add_child(fig)
	_look(Vector3(0, 4.0, 1.01), Vector3(0, 0.5, 1.0))
	await _reveal()
	await _wait(2.0)
	await _cam_move(Vector3(0, 11.0, 1.02), Vector3(0, 0.5, 1.0), 5.0)
	await UI.fade_out(1.2)


## Root: from above, green spreads out of the station across the grey; seasons turn.
func _shot_aerial_spread() -> void:
	_new_set(Color("8a8c8c"), Color("b0b2b0"), 0.9, Color("8a8c8c"), 0.012)
	_set.add_child(Retro.sun(Vector3(-55, -20, 0), Color("e0e0d8"), 0.7))
	_ground(240.0, Vector3.ZERO, 0.0)
	_bunker(Vector3.ZERO)
	_env.environment.fog_density = 0.004
	_env.environment.ambient_light_energy = 0.7
	_look(Vector3(0, 26, 26), Vector3(0, 0, -6))
	await _reveal()
	# Trees pop where the green has reached.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var trees: Array = []
	for i in 70:
		var a := rng.randf() * TAU
		var d := rng.randf_range(4.0, 70.0)
		trees.append({"pos": Vector3(cos(a) * d, 0, sin(a) * d), "d": d, "done": false})
	var seasons := [Color("8a8c8c"), Color("a8c8d8"), Color("c8d8e8"), Color("d8c8a8"), Color("a8b8c8")]
	var dur := 11.0
	var t := 0.0
	while t < dur:
		var k := t / dur
		var r := k * 78.0
		_ground_mat.set_shader_parameter("radius", r)
		var si := mini(int(k * (seasons.size() - 1)), seasons.size() - 2)
		var sf := k * (seasons.size() - 1) - si
		_env.environment.background_color = (seasons[si] as Color).lerp(seasons[si + 1], sf)
		_env.environment.fog_light_color = _env.environment.background_color
		for tr in trees:
			if not tr["done"] and tr["d"] < r - 2.0:
				tr["done"] = true
				var tree := Node3D.new()
				tree.position = tr["pos"]
				tree.add_child(Retro.cyl(0.0, 0.9, 2.0, Color("2c6a28"), 6, Vector3(0, 1.4, 0)))
				tree.add_child(Retro.box(Vector3(0.25, 0.5, 0.25), Color("5a3a28"), Vector3(0, 0.25, 0)))
				tree.scale = Vector3(0.01, 0.01, 0.01)
				_set.add_child(tree)
				create_tween().tween_property(tree, "scale", Vector3.ONE, 0.6)
		_cam.position = Vector3(0, 26 + k * 18.0, 26 + k * 14.0)
		_cam.look_at(Vector3(0, 0, -6))
		await get_tree().process_frame
		t += get_process_delta_time()
	await _cut()


## Root: years later, someone standing in a green field. They look at their hand.
func _shot_stranger() -> void:
	_new_set(Color("a8c8d8"), Color("d0e0d0"), 0.9, Color("a8c8d8"), 0.02)
	_set.add_child(Retro.sun(Vector3(-40, -40, 0), Color("fff0d0"), 0.9))
	_ground(120.0, Vector3.ZERO, 500.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 120:
		var p := Vector3(rng.randf_range(-20, 20), 0.15, rng.randf_range(-24, 4))
		_set.add_child(Retro.box(Vector3(0.06, 0.3, 0.06), Color("5ab048"), p))
	var fig := Figure.build(Color("8a6a48"), Color("d8a888"), Color("c8a868"), Color("3a4a5a"))
	fig.position = Vector3(0, 0, -2)
	fig.rotation_degrees.y = 200
	_set.add_child(fig)
	_look(Vector3(2.5, 1.6, 2.5), Vector3(0, 1.0, -2))
	await _reveal()
	await _wait(1.5)
	var tw := create_tween()
	tw.tween_property(fig.get_node("ArmL"), "rotation:x", -1.4, 1.2)
	await _cam_move(Vector3(0.9, 1.4, -0.6), fig.position + Vector3(-0.3, 1.0, 0), 3.0)
	await _wait(1.0)
	await _cut()


## Graft: a sealed capsule from the palm-print pot rises up the vent into daylight.
func _shot_capsule() -> void:
	_new_set(Color("040806"), Color("1a2a1c"), 0.6, Color("040806"), 0.06)
	_set.add_child(Retro.box(Vector3(10, 0.1, 10), Color("2a302a"), Vector3(0, -0.05, 0)))
	_set.add_child(Retro.box(Vector3(2.0, 0.9, 1.0), Color("586068"), Vector3(0, 0.45, 0)))
	_set.add_child(Retro.cyl(0.3, 0.24, 0.45, Color("6a6c6a"), 6, Vector3(0, 1.12, 0)))
	_set.add_child(Retro.cyl(0.28, 0.28, 0.02, Color("4a9a3c"), 6, Vector3(0, 1.35, 0), {"unlit": true}))
	var shaft := Retro.cyl(0.6, 0.6, 14.0, Color("d8f0c8"), 8, Vector3(0, 8.0, 0), {"alpha": 0.12})
	_set.add_child(shaft)
	_set.add_child(Retro.omni(Color("70d850"), 4.0, 1.6, Vector3(0, 1.8, 0.5)))
	var capsule := Node3D.new()
	capsule.position = Vector3(0, 1.4, 0)
	capsule.add_child(Retro.cyl(0.16, 0.16, 0.4, Color("d0e8e0"), 8, Vector3(0, 0.2, 0), {"alpha": 0.5}))
	capsule.add_child(Retro.cyl(0.11, 0.11, 0.28, Color("70d850"), 6, Vector3(0, 0.2, 0), {"unlit": true}))
	capsule.add_child(Retro.cyl(0.17, 0.17, 0.06, Color("405060"), 8, Vector3(0, 0.43, 0)))
	capsule.scale = Vector3(0.01, 0.01, 0.01)
	_set.add_child(capsule)
	_look(Vector3(1.8, 2.2, 2.4), Vector3(0, 1.3, 0))
	await _reveal()
	await _wait(0.8)
	var grow := create_tween()
	grow.tween_property(capsule, "scale", Vector3.ONE, 1.0)
	await grow.finished
	await _wait(0.6)
	var up := create_tween().set_parallel()
	up.tween_property(capsule, "position:y", 14.0, 5.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _cam_move(Vector3(1.2, 6.0, 1.6), Vector3(0, 12.0, 0), 4.5)
	await _cut()


## Fallow: a security camera's view. No one gets up.
func _shot_fallow() -> void:
	_new_set(Color("05070a"), Color("304030"), 0.7)
	UI.set_post(0.7, 0.2)
	var tile := Retro.tex_tiles(Color("3a4044"), Color("2a3034"))
	_set.add_child(Retro.box(Vector3(8, 0.1, 6), Color.WHITE, Vector3(0, -0.05, 0), {"tex": tile, "uv": 8.0}))
	_set.add_child(Retro.box(Vector3(8, 3, 0.2), Color("4a5458"), Vector3(0, 1.5, -3)))
	_set.add_child(Retro.box(Vector3(3, 0.12, 1.2), Color("b8bcb8"), Vector3(-1, 1.0, -2)))
	_set.add_child(Retro.box(Vector3(2.0, 0.4, 0.9), Color("4a5a4a"), Vector3(2.0, 0.2, -1.6)))
	var fig := Figure.build(Figure.COAT, Color("70d850"))
	fig.position = Vector3(1.6, 0.42, -1.6)
	fig.rotation_degrees = Vector3(-90, 90, 0)
	_set.add_child(fig)
	var moss := Retro.cyl(1.2, 1.2, 0.02, Color("3c8a30"), 7, Vector3(1.8, 0.02, -1.2), {"unlit": true})
	_set.add_child(moss)
	var fire := Retro.omni(Color("ff7020"), 12.0, 0.0, Vector3(0, 2.5, 0))
	_set.add_child(fire)
	_look(Vector3(-3.2, 3.2, 2.6), Vector3(0.6, 0.4, -1.6))
	var stamp := UI.label("CAM 02   DAY %02d   03:12" % Game.day, Color("a8c8a0"))
	stamp.position = Vector2(8, 8)
	_layer.add_child(stamp)
	await _reveal()
	await _wait(1.5)
	await UI.say(["OCCUPANT VITALS: NONE.", "WING B: STERILIZATION CYCLE ENGAGED."], "see")
	var tw := create_tween().set_parallel()
	tw.tween_property(fire, "light_energy", 8.0, 4.0)
	tw.tween_property(_env.environment, "background_color", Color("ff9040"), 4.0)
	await tw.finished
	UI.flash(Color.WHITE, 1.0)
	await _wait(0.5)
	stamp.queue_free()
	UI.set_post(0.0, 0.0)
	await _cut()


# ------------------------------------------------------------------ card

func _card(num: String, word: String) -> void:
	if _set:
		_set.queue_free()
		_set = null
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)
	var a := UI.label("ENDING " + num, UI.C_DIM)
	var b := UI.label(word, UI.C_PAPER, 16)
	var c := UI.label("STRAIN", UI.C_THINK_FG)
	a.position = Vector2((UI.W - a.text.length() * 8) / 2.0, 80)
	b.position = Vector2((UI.W - word.length() * 16) / 2.0, 96)
	c.position = Vector2((UI.W - 48) / 2.0, 150)
	_layer.add_child(a)
	_layer.add_child(b)
	_layer.add_child(c)
	var seen := Game.endings_seen()
	if not seen.has(_key):
		seen.append(_key)
	var d := UI.label("ENDINGS SEEN: %d / 4" % seen.size(), UI.C_DIM)
	d.position = Vector2((UI.W - d.text.length() * 8) / 2.0, 186)
	_layer.add_child(d)
	await _reveal()
	var t := 0.0
	while t < 7.0 and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 1.5 and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("back")):
			break
	await _cut()
