extends Node3D
## The Culture bench (design §14): a real bench between runs. A gloved hand
## snaps between stations; each station is a small prop that shows its state.
##   PETRI DISH   the culture itself, with the plasmid ring (arrange / enrich / bank)
##   VIAL RACK    banked tissue, reagent, green samples
##   SEQUENCER    reagent + breath buy new genes for the reward pool
##   INCUBATOR    tissue grows traits (Adapt.CRAFT); equip up to trait_slots
##   SYRINGE TRAY boosters (scripts/culture/boosters.gd), max 2 carried
##   PRIMER       culture.primer: the first gene of each fight opens on a HELD chain
##   STRAIN STOCK switch strain
##   INJECTOR     go in (body map)        DOOR  back to the lab
## Debug: --station=<id> starts the hand on that station.

const Props := preload("res://scripts/culture/culture_props.gd")
const BenchOps := preload("res://scripts/culture/bench_ops.gd")
const Boosters := preload("res://scripts/culture/boosters.gd")
const Tissue := preload("res://scripts/culture/tissue.gd")
const ColonyCluster := preload("res://scripts/battle/colony_cluster.gd")
const GeneArt := preload("res://scripts/run/gene_art.gd")
const LabMenus := preload("res://scripts/lab/lab_menus.gd")

const CAM_DIST := 8.8
const CAM_PITCH := 55.0
const CAM_TARGET := Vector3(0, 0, 0.25)
const DISH_R := 0.72
const RING_R := 1.02
const RING_Y := 0.09

## id -> name, pos (anchor on the bench), hover (hand height), desc (≤ 46 chars).
const STATIONS := {
	"dish": {"name": "PETRI DISH", "pos": Vector3(0, 0, 0.3), "hover": 0.62,
		"desc": "The culture. Arrange and feed its ring."},
	"vials": {"name": "VIAL RACK", "pos": Vector3(-2.4, 0, 0.65), "hover": 0.95,
		"desc": "Tissue carried back from inside."},
	"tray": {"name": "SYRINGE TRAY", "pos": Vector3(2.1, 0, 0.7), "hover": 0.5,
		"desc": "Boosters. Two go in with me."},
	"inject": {"name": "INJECTOR", "pos": Vector3(3.75, 0, 0.55), "hover": 1.75,
		"desc": "Go in."},
	"shelf": {"name": "STRAIN STOCK", "pos": Vector3(-3.2, 0, -1.0), "hover": 1.0,
		"desc": "Cultures kept cold. Pick one."},
	"sequencer": {"name": "SEQUENCER", "pos": Vector3(-1.1, 0, -1.05), "hover": 1.05,
		"desc": "Reagent and breath buy new genes."},
	"incubator": {"name": "INCUBATOR", "pos": Vector3(1.2, 0, -1.0), "hover": 1.3,
		"desc": "Tissue grows traits. Equip what fits."},
	"primer": {"name": "PRIMER", "pos": Vector3(2.95, 0, -1.0), "hover": 1.4,
		"desc": "Start each fight already chained."},
	"door": {"name": "DOOR", "pos": Vector3(4.35, 0, -1.6), "hover": 1.2,
		"desc": "Back to the lab."},
}

const VIAL_KEYS := ["clot", "plasma", "alveoli", "myelin", "reagent", "green"]
const CULTURE_DEFAULTS := {"grown": [], "traits": [], "trait_slots": 1, "boosters": [], "primer": 0}

var _ops: BenchOps
var _menus: LabMenus
var _cam: Camera3D
var _cur := "dish"
var _acting := false
var _leaving := false
var _t := 0.0

var _stations: Dictionary = {}   ## id -> Node3D prop root
var _vials: Dictionary = {}      ## VIAL_KEYS -> Node3D
var _dish_life: Node3D           ## colony + trait features (rebuilt)
var _colony: ColonyCluster
var _ring: Node3D
var _beads: Array = []           ## [gene id, Node3D, banked]
var _inj_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _glow_light: OmniLight3D
var _glow_boost := 0.0
var _hand: Node3D
var _hand_body: Node3D
var _hand_goal := Vector3.ZERO

var _hud_name: Label
var _hud_mats: Dictionary = {}
var _hud_reagent: Label
var _hud_state: Label
var _hud_desc_panel: PanelContainer
var _hud_desc: Label


func _ready() -> void:
	UI.apply_stage_post()
	Sfx.drone("lab")
	if Game.unlocked.is_empty():
		Game.new_game()
	_ensure_state()
	_drone("lab")
	_ops = BenchOps.new()
	add_child(_ops)
	_ops.changed.connect(_on_changed)
	_menus = LabMenus.new()
	add_child(_menus)
	_build_world()
	_build_hud()
	_refresh_all(false)
	var start: String = String(Game._user_args().get("station", "dish"))
	_select(start if STATIONS.has(start) else "dish", true)
	_first_visit()


func _ensure_state() -> void:
	for k in CULTURE_DEFAULTS:
		if not Game.culture.has(k):
			var v = CULTURE_DEFAULTS[k]
			Game.culture[k] = v.duplicate() if v is Array else v
	# Specimens found in the lab grow here too.
	var grown: Array = Game.culture["grown"]
	var sp = Game.flags.get("specimens", [])
	if sp is Array:
		for id in sp:
			if not grown.has(String(id)):
				grown.append(String(id))
	Game.culture["grown"] = grown
	var traits: Array = Game.culture["traits"]
	for id in traits.duplicate():
		if not grown.has(id):
			traits.erase(id)


func _drone(region: String) -> void:
	var s := get_node_or_null("/root/Sfx")
	if s and s.has_method("drone"):
		s.call("drone", region)


func _first_visit() -> void:
	if Game.flags.has("tips_culture") or Game._user_args().has("input"):
		return
	Game.flags["tips_culture"] = true
	Game.save_game()
	_acting = true
	await get_tree().create_timer(0.4).timeout
	await UI.say(["Tissue feeds the dish.", "Grow traits. Equip what fits.",
		"Fill a syringe before injecting."], "think")
	_acting = false


# ------------------------------------------------------------ world

func _build_world() -> void:
	add_child(Retro.environment(Color("05070a"), Color(0.4, 0.46, 0.58), 0.3, Color("080c10"), 0.02))
	add_child(Retro.sun(Vector3(-65, 25, 0), Color(0.7, 0.78, 0.92), 0.14))
	add_child(Props.bench())
	var lamp := Props.lamp()
	lamp.position = Vector3(0, 2.55, -0.55)
	add_child(lamp)
	var bulb_col := Color("f0e4c8").lerp(UI.C_GREEN, clampf(Game.stage * 0.06, 0.0, 0.3))
	add_child(Retro.omni(bulb_col, 9.0, 1.5, Vector3(0, 2.2, -0.4)))
	add_child(Retro.omni(Color("8098b0"), 6.0, 0.35, Vector3(-3.5, 2.0, 1.5)))

	_cam = Camera3D.new()
	_cam.fov = 35.0
	_cam.near = 0.3
	_cam.far = 60.0
	_cam.rotation_degrees.x = -CAM_PITCH
	_cam.position = CAM_TARGET + Vector3(0, sin(deg_to_rad(CAM_PITCH)), cos(deg_to_rad(CAM_PITCH))) * CAM_DIST
	add_child(_cam)
	_cam.make_current()

	# Petri dish + plasmid ring.
	var dish := _station_root("dish")
	dish.add_child(Props.dish(DISH_R))
	_dish_life = Node3D.new()
	dish.add_child(_dish_life)
	dish.add_child(Props.torus(RING_R - 0.03, RING_R + 0.03, Color("2a3238"), Vector3(0, 0.02, 0)))
	_ring = Node3D.new()
	dish.add_child(_ring)
	var head := Props.read_head(UI.C_ACCENT)
	head.position = Vector3(0, RING_Y + 0.28, -RING_R)
	dish.add_child(head)
	var tw := head.create_tween().set_loops()
	tw.tween_property(head, "position:y", RING_Y + 0.36, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(head, "position:y", RING_Y + 0.28, 0.5).set_trans(Tween.TRANS_SINE)

	# Vial rack: tissue, reagent, green.
	var vr := _station_root("vials")
	var w := VIAL_KEYS.size() * 0.26 + 0.1
	vr.add_child(Props.rack(w))
	for i in VIAL_KEYS.size():
		var k: String = VIAL_KEYS[i]
		var col: Color = Tissue.C_REAGENT if k == "reagent" else (UI.C_GREEN if k == "green" else Tissue.color(k))
		var v := Props.vial(col)
		v.position = Vector3(-w * 0.5 + 0.18 + i * 0.26, 0.06, 0)
		vr.add_child(v)
		_vials[k] = v

	_station_root("sequencer").add_child(Props.sequencer())

	var inc := _station_root("incubator")
	inc.add_child(Props.incubator())
	var glow := inc.get_child(0).get_node("Glow") as MeshInstance3D
	_glow_mat = glow.material_override as ShaderMaterial
	_glow_light = Retro.omni(Color("90f0b0"), 1.8, 0.5, Vector3(0, 0.7, 0.1))
	inc.add_child(_glow_light)

	_station_root("primer").add_child(Props.primer())
	_station_root("shelf").add_child(Props.shelf())
	_station_root("tray").add_child(Props.tray())

	var inj := _station_root("inject")
	inj.add_child(Props.injector(_culture_color()))
	var fl := inj.get_child(0).get_node("Fluid") as MeshInstance3D
	_inj_mat = fl.material_override as ShaderMaterial

	var door := _station_root("door")
	var dp := Props.door()
	dp.position = Vector3(0, 0, -0.22)
	door.add_child(dp)

	_hand = Node3D.new()
	add_child(_hand)
	_hand_body = Props.hand(Game.stage)
	_hand.add_child(_hand_body)


func _station_root(id: String) -> Node3D:
	var n := Node3D.new()
	var st: Dictionary = STATIONS[id]
	n.position = st["pos"]
	add_child(n)
	_stations[id] = n
	return n


func _prop(id: String) -> Node3D:
	var root: Node3D = _stations[id]
	return root.get_child(0) as Node3D


func _culture_color() -> Color:
	var st: Dictionary = Cards.STRAINS.get(Game.strain, {})
	var c: Color = st.get("color", Color("58a8e8"))
	return c.lerp(UI.C_GREEN, clampf(Game.stage * 0.08, 0.0, 0.4))


func _trait_color(id: String) -> Color:
	var h := float(absi(hash(id)) % 1000) / 1000.0
	return Color.from_hsv(h, 0.45, 0.9)


# ------------------------------------------------------------ refresh

func _refresh_all(animate: bool) -> void:
	_refresh_dish()
	_refresh_ring(animate)
	_refresh_vials()
	_refresh_incubator()
	_refresh_tray()
	_refresh_shelf()
	Props.set_pips(_prop("primer"), int(Game.culture.get("primer", 0)), BenchOps.PRIMER_MAX)
	var c := _culture_color()
	_inj_mat.set_shader_parameter("albedo", c)
	_inj_mat.set_shader_parameter("emission", c * 0.4)
	_refresh_hud()


## Colony in the dish: size from what's grown, tendrils/sheen/spots from traits.
func _refresh_dish() -> void:
	Props.clear(_dish_life)
	var grown: Array = Game.culture["grown"]
	var traits: Array = Game.culture["traits"]
	var col := _culture_color()
	var holder := Node3D.new()
	_dish_life.add_child(holder)
	_colony = ColonyCluster.new()
	_colony.position = Vector3(0, 0.06, 0)
	holder.add_child(_colony)
	var count := clampi(10 + grown.size() + traits.size() * 4, 8, 30)
	_colony.setup(col, count, 0.075, mini(traits.size() * 2, 6), 7 + traits.size(), col.darkened(0.45))
	if not traits.is_empty():
		var sheen_col := _trait_color(String(traits[0]))
		var sheen := Retro.ball(0.42, sheen_col, 8, 4, Vector3(0, 0.12, 0), {"alpha": 0.22})
		sheen.scale = Vector3(1, 0.55, 1)
		_dish_life.add_child(sheen)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in grown.size():
		var id := String(grown[i])
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.42, DISH_R - 0.08)
		var spot := Retro.cyl(0.05, 0.05, 0.02, _trait_color(id), 6, Vector3(cos(a) * r, 0.075, sin(a) * r),
			{"emit": _trait_color(id) * (0.5 if traits.has(id) else 0.1)})
		_dish_life.add_child(spot)


func _bead_angle(k: int, n: int) -> float:
	return TAU * float(k) / float(maxi(n, 1))


func _ring_point(a: float) -> Vector3:
	return Vector3(sin(a) * RING_R, RING_Y, -cos(a) * RING_R)


## Beads keep their identity: reordered genes slide round the ring.
func _refresh_ring(animate: bool) -> void:
	var strand := Game.starting_strand()
	var base_n := strand.size() - Game.gene_bank.size()
	var old: Array = _beads.duplicate()
	_beads = []
	for k in strand.size():
		var id: String = strand[k]
		var banked := k >= base_n
		var a1 := _bead_angle(k, strand.size())
		var node: Node3D = null
		for j in old.size():
			var e: Array = old[j]
			if String(e[0]) == id and bool(e[2]) == banked:
				node = e[1]
				old.remove_at(j)
				break
		if node == null:
			node = Props.bead(id, GeneArt.gene_color(id), banked)
			_ring.add_child(node)
			node.position = _ring_point(a1)
			if animate:
				node.scale = Vector3.ONE * 0.05
				node.create_tween().tween_property(node, "scale", Vector3.ONE, 0.3) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif animate:
			var a0 := atan2(node.position.x, -node.position.z)
			var moving := node
			var tw := node.create_tween()
			var slide := func(t: float) -> void:
				moving.position = _ring_point(lerp_angle(a0, a1, t)) + Vector3(0, sin(t * PI) * 0.3, 0)
			tw.tween_method(slide, 0.0, 1.0, 0.4).set_trans(Tween.TRANS_SINE)
		else:
			node.position = _ring_point(a1)
		_beads.append([id, node, banked])
	for e in old:
		var gone: Node3D = e[1]
		if animate:
			var tw := gone.create_tween()
			tw.tween_property(gone, "scale", Vector3.ONE * 0.05, 0.2)
			tw.tween_callback(gone.queue_free)
		else:
			gone.queue_free()


func _refresh_vials() -> void:
	for k in VIAL_KEYS:
		var v: Node3D = _vials[k]
		var f := 0.0
		match String(k):
			"reagent":
				f = Game.reagent / 20.0
			"green":
				f = Game.green_samples / 5.0
			_:
				f = Tissue.have(String(k)) / 8.0
		Props.set_fill(v, f)


func _refresh_incubator() -> void:
	var jars := _prop("incubator").get_node("Jars") as Node3D
	Props.clear(jars)
	var grown: Array = Game.culture["grown"]
	var traits: Array = Game.culture["traits"]
	for i in mini(grown.size(), 10):
		var id := String(grown[i])
		var j := Props.trait_jar(_trait_color(id), traits.has(id))
		var row := int(i / 5.0)
		j.position = Vector3(-0.48 + (i % 5) * 0.24, 0.08 if row == 0 else 0.5, 0.05)
		jars.add_child(j)


func _refresh_tray() -> void:
	var held_root := _prop("tray").get_node("Held") as Node3D
	Props.clear(held_root)
	var held: Array = Game.culture["boosters"]
	for i in Boosters.MAX_CARRIED:
		var s: Node3D
		if i < held.size():
			var d := Boosters.info(String(held[i]))
			s = Props.syringe(d["color"], true)
		else:
			s = Props.syringe(Props.C_GLASS, false)
		s.position = Vector3(-0.05, 0.12, -0.15 + i * 0.3)
		held_root.add_child(s)


func _refresh_shelf() -> void:
	var jars := _prop("shelf").get_node("Jars") as Node3D
	Props.clear(jars)
	var n := Game.strains.size()
	for i in n:
		var sid := String(Game.strains[i])
		var st: Dictionary = Cards.STRAINS.get(sid, {})
		var c: Color = st.get("color", Color("b0b8c8"))
		var j := Props.stock_jar(c, sid == Game.strain)
		j.position = Vector3((i - (n - 1) * 0.5) * 0.34, 0.45, 0)
		jars.add_child(j)


# ------------------------------------------------------------ feedback

func _on_changed(kind: String, arg: String, to: String) -> void:
	match kind:
		"pour":
			_pour_fx(arg, to)
		"grow":
			_glow_boost = 1.0
			_refresh_incubator()
			_refresh_dish()
			_colony.flash(_trait_color(arg))
		"equip", "unequip":
			_refresh_incubator()
			_refresh_dish()
			_colony.flash(_trait_color(arg) if kind == "equip" else Color("404850"))
		"booster", "empty":
			_refresh_tray()
		"primer":
			Props.set_pips(_prop("primer"), int(arg), BenchOps.PRIMER_MAX)
			_twitch_primer(int(arg))
		"strain":
			_refresh_all(true)
			_colony.flash(Color.WHITE)
		"ring":
			_refresh_ring(true)
		"enrich":
			_refresh_ring(true)
			_colony.flash(GeneArt.gene_color(arg))
			for e in _beads:
				if String(e[0]) == arg:
					var b: Node3D = e[1]
					b.scale = Vector3.ONE * 1.8
					b.create_tween().tween_property(b, "scale", Vector3.ONE, 0.35)
		"sequence":
			_flicker_screen()
	_refresh_vials()
	_refresh_hud()


## Lift the vial, tip it, and drip into the target station.
func _pour_fx(mat: String, to: String) -> void:
	if not _vials.has(mat):
		return
	var v: Node3D = _vials[mat]
	var p0 := v.position
	var tw := v.create_tween()
	tw.tween_property(v, "position:y", p0.y + 0.35, 0.12)
	tw.parallel().tween_property(v, "rotation:z", -0.7, 0.12)
	tw.tween_interval(0.35)
	tw.tween_property(v, "rotation:z", 0.0, 0.12)
	tw.parallel().tween_property(v, "position:y", p0.y, 0.12)
	var from := v.global_position + Vector3(0.1, 0.95, 0)
	var dest := _drip_target(to)
	var col := Tissue.color(mat)
	for i in 6:
		var d := Retro.ball(0.035, col, 4, 3, from, {"unlit": true})
		add_child(d)
		var dtw := d.create_tween()
		dtw.tween_interval(0.12 + i * 0.05)
		var arc := func(t: float) -> void:
			d.position = from.lerp(dest, t) + Vector3(0, sin(t * PI) * 0.8, 0)
		dtw.tween_method(arc, 0.0, 1.0, 0.3)
		dtw.tween_callback(d.queue_free)
	get_tree().create_timer(0.5).timeout.connect(_pour_done.bind(to, col))


func _pour_done(to: String, col: Color) -> void:
	if to == "dish" and is_instance_valid(_colony):
		_colony.flash(col)
	elif to == "incubator":
		_glow_boost = 1.0


func _drip_target(to: String) -> Vector3:
	var root: Node3D = _stations.get(to, _stations["dish"])
	match to:
		"incubator":
			return root.position + Vector3(0, 0.6, 0.2)
		"tray":
			return root.position + Vector3(0, 0.15, 0)
	return root.position + Vector3(0, 0.25, 0)


func _twitch_primer(p: int) -> void:
	var strand := _prop("primer").get_node("Strand") as Node3D
	var tw := strand.create_tween()
	var amp := 0.04 + p * 0.03
	for i in 6:
		tw.tween_property(strand, "position:y", 0.12 + amp * (1.0 if i % 2 == 0 else -0.5), 0.05)
		amp *= 0.7
	tw.tween_property(strand, "position:y", 0.12, 0.05)


func _flicker_screen() -> void:
	var scr := _prop("sequencer").get_node("Screen") as MeshInstance3D
	var m := scr.material_override as ShaderMaterial
	var tw := scr.create_tween()
	for i in 4:
		tw.tween_callback(m.set_shader_parameter.bind("emission", Color("70f0a8")))
		tw.tween_interval(0.06)
		tw.tween_callback(m.set_shader_parameter.bind("emission", Color("1a5a38")))
		tw.tween_interval(0.06)


func _punch(id: String) -> void:
	var n: Node3D = _stations[id]
	n.scale = Vector3(1.06, 0.94, 1.06)
	n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func _process(dt: float) -> void:
	_t += dt
	if _hand:
		_hand.position = _hand.position.lerp(_hand_goal, 1.0 - exp(-dt * 14.0))
		_hand_body.position.y = sin(_t * 3.0) * 0.04
	if _glow_mat:
		_glow_boost = maxf(0.0, _glow_boost - dt * 0.8)
		var g := 0.75 + sin(_t * 1.7) * 0.1 + _glow_boost * 0.6
		_glow_mat.set_shader_parameter("albedo", Color("90f0b0") * g)
		_glow_light.light_energy = 0.4 + _glow_boost * 1.2
	if _hud_desc_panel:
		_hud_desc_panel.visible = not UI.busy and not _acting


# ------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if _acting or _leaving or UI.busy:
		return
	var d := Vector2.ZERO
	if e.is_action_pressed("move_left"):
		d = Vector2(-1, 0)
	elif e.is_action_pressed("move_right"):
		d = Vector2(1, 0)
	elif e.is_action_pressed("move_up"):
		d = Vector2(0, -1)
	elif e.is_action_pressed("move_down"):
		d = Vector2(0, 1)
	if d != Vector2.ZERO:
		get_viewport().set_input_as_handled()
		_move_cursor(d)
	elif e.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_use(_cur)
	elif e.is_action_pressed("inject"):
		get_viewport().set_input_as_handled()
		_select("inject")
		_use("inject")
	elif e.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		_select("door")
		_use("door")
	elif e.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_pause()
	elif e.is_action_pressed("help"):
		get_viewport().set_input_as_handled()
		_acting = true
		await preload("res://scripts/ui/glossary.gd").new().run(self)
		_acting = false


## Snap to the nearest station roughly in direction `d` (screen: up = -z).
func _move_cursor(d: Vector2) -> void:
	var st: Dictionary = STATIONS[_cur]
	var cur: Vector3 = st["pos"]
	var best := ""
	var best_s := INF
	for id in STATIONS:
		if id == _cur:
			continue
		var o: Dictionary = STATIONS[id]
		var p: Vector3 = o["pos"]
		var delta := Vector2(p.x - cur.x, p.z - cur.z)
		var along := delta.dot(d)
		var perp := absf(delta.cross(d))
		if along < 0.25 or along < perp * 0.5:
			continue
		var s := along + perp * 2.0
		if s < best_s:
			best_s = s
			best = id
	if best != "":
		_select(best)
		_ops.sfx("select", 1.2)


func _select(id: String, snap := false) -> void:
	_cur = id
	var st: Dictionary = STATIONS[id]
	var p: Vector3 = st["pos"]
	var hover: float = st["hover"]
	_hand_goal = p + Vector3(0, hover, 0)
	if snap:
		_hand.position = _hand_goal
	_refresh_hud()


func _use(id: String) -> void:
	_acting = true
	_punch(id)
	_ops.sfx("confirm" if id == "inject" else "select")
	match id:
		"dish":
			await _ops.ring()
		"vials":
			await _ops.vials()
		"sequencer":
			await _ops.sequence()
		"incubator":
			await _ops.incubator()
		"tray":
			await _ops.tray()
		"primer":
			await _ops.prime()
		"shelf":
			await _ops.pick_strain()
		"inject":
			if await _ops.inject():
				_leaving = true
		"door":
			await _leave()
	_acting = false
	_refresh_hud()


func _leave() -> void:
	if not await UI.confirm("BACK TO THE LAB?"):
		return
	Game.flags["from_culture"] = true
	Game.save_game()
	_leaving = true
	Game.goto("lab")


func _pause() -> void:
	_acting = true
	var r: String = await _menus.pause()
	if r == "title":
		_leaving = true
	_acting = false
	_refresh_all(false)


# ------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var p := UI.panel(Rect2(4, 4, 0, 0), true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	p.add_child(vb)
	_hud_name = UI.label("", UI.C_ACCENT)
	vb.add_child(_hud_name)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	for m in Tissue.MATS:
		var l := UI.label("", Tissue.color(m))
		hb.add_child(l)
		_hud_mats[m] = l
	_hud_reagent = UI.label("", Tissue.C_REAGENT)
	hb.add_child(_hud_reagent)
	_hud_state = UI.label("", UI.C_DIM)
	vb.add_child(_hud_state)
	_hud_desc_panel = UI.panel(Rect2(4, UI.H - 22, UI.W - 8, 18), true)
	_hud_desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud_desc_panel)
	_hud_desc = UI.label("", UI.C_THINK_FG)
	_hud_desc_panel.add_child(_hud_desc)


func _refresh_hud() -> void:
	if _hud_name == null:
		return
	var st: Dictionary = STATIONS[_cur]
	_hud_name.text = String(st["name"])
	_hud_desc.text = String(st["desc"])
	for m in Tissue.MATS:
		var l: Label = _hud_mats[m]
		l.text = "%s%d" % [String(m).left(1).to_upper(), Tissue.have(m)]
	_hud_reagent.text = "R%d" % Game.reagent
	var traits: Array = Game.culture["traits"]
	var held: Array = Game.culture["boosters"]
	_hud_state.text = "%s  T%d/%d  S%d/%d" % [_ops.strain_name(Game.strain), traits.size(),
		int(Game.culture.get("trait_slots", 1)), held.size(), Boosters.MAX_CARRIED]
