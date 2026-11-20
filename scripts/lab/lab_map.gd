extends Node3D
## Station Fallow, west wing. ASCII map -> per-room floor/wall meshes, room
## lights (powered / dark / alarm), props and interactable objects.
##
## Map chars: '#' wall, ' ' void, anything else = floor of the room with that letter.
## World: tile (x, y) is centred at Vector3(x, 0, y). The camera looks north (-Z),
## so walls with floor directly north of them are cut low.

const TALL := 1.6
const LOW := 0.3
const LIGHT_COL := Color(0.82, 0.92, 1.0)
const RED := Color(0.9, 0.12, 0.08)

const MAP := [
	"#########################################",
	"#PPPPP#SSSSS#GGGGGGGGGGGGG#AAAAAAA#KKKKK#",
	"#PPPPP#SSSSS#GGGGGGGGGGGGG#AAAAAAA#KKKKK#",
	"#PPPPP#SSSSS#GGGGGGGGGGGGG#AAAAAAA#KKKKK#",
	"#PPPPP#SSSSS#GGGGGGGGGGGGG#AAAAAAA#KKKKK#",
	"#PPPPP#SSSSS#GGGGGGGGGGGGG#AAAAAAA#KKKKK#",
	"###c#####c#########c##########c######c###",
	"###c#####c#########c##########c######c###",
	"#ccccccccccccccccccccccccccccccccccccccc#",
	"#ccccccccccccccccccccccccccccccccccccccc#",
	"#####c#######c#######c#######c###c####c##",
	"#####c#######c#######c#######c###c####c##",
	"#LLLLLLLLL#MMMMMM#BBBBBBBB#FFFFF#HHH#III#",
	"#LLLLLLLLL#MMMMMM#BBBBBBBB#FFFFF#HHH#III#",
	"#LLLLLLLLL#MMMMMM#BBBBBBBB#FFFFF#HHH#III#",
	"#LLLLLLLLL#MMMMMM#BBBBBBBB#FFFFF#HHH#III#",
	"#LLLLLLLLL#MMMMMM#BBBBBBBB#FFFFF#########",
	"#LLLLLLLLL#MMMMMM#BBBBBBBB#FFFFF#        ",
	"#################################        ",
]

## letter -> id, shown name, power keys (lit if the generator runs and any key is on).
const ROOMS := {
	"L": {"id": "lab", "name": "SPLICE LAB", "power": ["generator"]},
	"c": {"id": "corridor", "name": "CORRIDOR", "power": ["generator"]},
	"M": {"id": "medbay", "name": "MEDBAY", "power": ["medbay"]},
	"B": {"id": "break", "name": "BREAK ROOM", "power": ["generator"]},
	"F": {"id": "freezer", "name": "FREEZER", "power": ["freezer"]},
	"S": {"id": "security", "name": "SECURITY", "power": ["cctv"]},
	"A": {"id": "comms", "name": "COMMS / ARCHIVE", "power": ["comms", "archive"]},
	"G": {"id": "garden", "name": "GARDEN", "power": ["garden"]},
	"P": {"id": "generator", "name": "GENERATOR", "power": ["generator"]},
	"K": {"id": "airlock", "name": "AIRLOCK", "power": ["generator"]},
	"H": {"id": "hatch", "name": "SUPPLY HATCH", "power": ["generator"]},
	"I": {"id": "incubator", "name": "INCUBATOR", "power": ["incubator"]},
}

## Door signs: [text, door x, door y of the corridor-side wall row, top room?]
const SIGNS := [
	["GENERATOR", 3, true], ["SECURITY", 9, true], ["GARDEN", 19, true],
	["COMMS", 30, true], ["AIRLOCK", 37, true],
	["SPLICE LAB", 5, false], ["MEDBAY", 13, false], ["BREAK RM", 21, false],
	["FREEZER", 29, false], ["SUPPLY", 33, false], ["INCUB.", 38, false],
]

static var _tex: Dictionary = {}

var objs: Dictionary = {}       ## Vector2i -> object id (interactable)
var blocked: Dictionary = {}    ## Vector2i -> true (props on floor)
var room_bounds: Dictionary = {}  ## room id -> Rect2i (floor tiles)
var _room_letter: Dictionary = {}  ## room id -> letter
var _white: Dictionary = {}     ## room id -> Array[OmniLight3D]
var _red: Dictionary = {}       ## room id -> OmniLight3D
var _strips: Dictionary = {}    ## room id -> Array[Node3D]
var _glows: Array = []          ## [MeshInstance3D, room id] screens/lamps lit with power
var _badge: Node3D
var _t := 0.0
var _alarm := false


# ------------------------------------------------------------ queries

func ch(t: Vector2i) -> String:
	if t.y < 0 or t.y >= MAP.size() or t.x < 0 or t.x >= (MAP[0] as String).length():
		return " "
	return (MAP[t.y] as String)[t.x]


func is_floor(t: Vector2i) -> bool:
	var c := ch(t)
	return c != "#" and c != " "


func is_wall(t: Vector2i) -> bool:
	return ch(t) == "#"


func walkable(t: Vector2i) -> bool:
	return is_floor(t) and not blocked.has(t)


func room_at(t: Vector2i) -> String:
	var c := ch(t)
	if ROOMS.has(c):
		return ROOMS[c]["id"]
	return ""


func room_name(id: String) -> String:
	if _room_letter.has(id):
		return ROOMS[_room_letter[id]]["name"]
	return ""


func room_center(id: String) -> Vector3:
	var r: Rect2i = room_bounds.get(id, Rect2i())
	return Vector3(r.position.x + (r.size.x - 1) / 2.0, 0, r.position.y + (r.size.y - 1) / 2.0)


func room_lit(id: String) -> bool:
	if not Game.is_powered("generator"):
		return false
	var keys: Array = ROOMS[_room_letter[id]]["power"]
	for k in keys:
		if Game.is_powered(k):
			return true
	return false


# ------------------------------------------------------------ textures / materials

static func _t_cache(key: String, make: Callable) -> Texture2D:
	if not _tex.has(key):
		_tex[key] = make.call()
	return _tex[key]


func _floor_mat(room: String) -> ShaderMaterial:
	var tex: Texture2D
	match room:
		"lab":
			tex = _t_cache("f_lab", func(): return Retro.tex_tiles(Color("c8d0d0"), Color("8c989c")))
		"medbay":
			tex = _t_cache("f_med", func(): return Retro.tex_tiles(Color("d0e4e0"), Color("98b4b0")))
		"break":
			tex = _t_cache("f_break", func(): return Retro.tex_tiles(Color("b8a888"), Color("807058")))
		"freezer":
			tex = _t_cache("f_frz", func(): return Retro.tex_tiles(Color("b8c8d8"), Color("8098b0")))
		"garden":
			tex = _t_cache("f_gdn", func(): return Retro.tex_noise(Color("7c7870"), Color("68645c"), 16, 7))
		"comms", "security":
			tex = _t_cache("f_carpet", func(): return Retro.tex_noise(Color("58606c"), Color("4c5460"), 16, 3, 0.5))
		"generator", "hatch", "incubator":
			tex = _t_cache("f_metal", func(): return Retro.tex_tiles(Color("787c80"), Color("4c5054"), 8))
		"airlock":
			tex = _t_cache("f_air", func(): return Retro.tex_tiles(Color("8c9094"), Color("5c6064"), 8))
		_:
			tex = _t_cache("f_cor", func(): return Retro.tex_tiles(Color("a4acb4"), Color("6c747c")))
	return Retro.mat(Color.WHITE, {"tex": tex})


func _wall_mat(room: String) -> ShaderMaterial:
	var tex: Texture2D
	match room:
		"lab", "medbay":
			tex = _t_cache("w_white", func(): return Retro.tex_panel(Color("c4ccd0"), Color("8890a0")))
		"garden":
			tex = _t_cache("w_gdn", func(): return Retro.tex_panel(Color("a0a898"), Color("707868")))
		"break":
			tex = _t_cache("w_break", func(): return Retro.tex_panel(Color("b8b0a0"), Color("888070")))
		_:
			tex = _t_cache("w_grey", func(): return Retro.tex_panel(Color("a8b0b8"), Color("707884")))
	return Retro.mat(Color.WHITE, {"tex": tex})


# ------------------------------------------------------------ build

func build() -> void:
	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			var c := row[x]
			if not ROOMS.has(c):
				continue
			var id: String = ROOMS[c]["id"]
			_room_letter[id] = c
			var t := Vector2i(x, y)
			if room_bounds.has(id):
				var r: Rect2i = room_bounds[id]
				room_bounds[id] = r.expand(t).expand(t + Vector2i.ONE)
			else:
				room_bounds[id] = Rect2i(t, Vector2i.ONE)
	_build_geometry()
	_build_lights()
	_build_props()
	_build_signs()
	apply_power()


## Wall height: low if floor is directly north (it would hide whoever stands
## there); pillars in a low run with no floor south are cut low too.
func _wall_heights() -> Dictionary:
	var low := {}
	var h := {}
	for y in MAP.size():
		for x in (MAP[0] as String).length():
			var t := Vector2i(x, y)
			if is_wall(t) and is_floor(t + Vector2i(0, -1)):
				low[t] = true
	for y in MAP.size():
		for x in (MAP[0] as String).length():
			var t := Vector2i(x, y)
			if not is_wall(t):
				continue
			var lo := low.has(t)
			if not lo and not is_floor(t + Vector2i(0, 1)) and (low.has(t + Vector2i(-1, 0)) or low.has(t + Vector2i(1, 0))):
				lo = true
			h[t] = LOW if lo else TALL
	return h


func _wall_room(t: Vector2i) -> String:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1)]:
		var r := room_at(t + d)
		if r != "":
			return r
	return ""


## Mesh group key: one mesh per room (corridor split in chunks so each mesh
## only touches a few lights).
func _group(room: String, t: Vector2i) -> String:
	if room == "corridor":
		return "corridor|%d" % (t.x / 8)
	return room + "|0"


func _build_geometry() -> void:
	var heights := _wall_heights()
	var floors := {}
	var walls := {}
	var caps := {}
	var w: int = (MAP[0] as String).length()
	for y in MAP.size():
		for x in w:
			var t := Vector2i(x, y)
			if is_floor(t):
				var g := _group(room_at(t), t)
				if not floors.has(g):
					floors[g] = _st()
				_floor_quad(floors[g], t)
			elif is_wall(t):
				var room := _wall_room(t)
				if room == "":
					continue
				var g := _group(room, t)
				if not walls.has(g):
					walls[g] = _st()
					caps[g] = _st()
				_wall_box(walls[g], caps[g], t, heights)
	var cap_mat := Retro.mat(Color("3c4652"))
	for g in floors.keys():
		var room: String = (g as String).split("|")[0]
		_commit(floors[g], _floor_mat(room))
	for g in walls.keys():
		var room: String = (g as String).split("|")[0]
		_commit(walls[g], _wall_mat(room))
		_commit(caps[g], cap_mat)


func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _commit(st: SurfaceTool, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Adds a quad (4 corners in order around it), wound so it faces `n`.
func _quad(st: SurfaceTool, v: Array, n: Vector3, uv: Array) -> void:
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = v[tri[0]]
		var b: Vector3 = v[tri[1]]
		var c: Vector3 = v[tri[2]]
		var order: Array = tri
		if (b - a).cross(c - a).dot(n) > 0.0:
			order = [tri[0], tri[2], tri[1]]
		for i in order:
			st.set_normal(n)
			st.set_uv(uv[i])
			st.add_vertex(v[i])


func _floor_quad(st: SurfaceTool, t: Vector2i) -> void:
	var x0 := t.x - 0.5
	var z0 := t.y - 0.5
	_quad(st, [Vector3(x0, 0, z0), Vector3(x0 + 1, 0, z0), Vector3(x0 + 1, 0, z0 + 1), Vector3(x0, 0, z0 + 1)],
		Vector3.UP, [Vector2(x0, z0), Vector2(x0 + 1, z0), Vector2(x0 + 1, z0 + 1), Vector2(x0, z0 + 1)])


func _wall_box(st: SurfaceTool, cap: SurfaceTool, t: Vector2i, heights: Dictionary) -> void:
	var h: float = heights[t]
	var x0 := t.x - 0.5
	var x1 := t.x + 0.5
	var z0 := t.y - 0.5
	var z1 := t.y + 0.5
	_quad(cap, [Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1)],
		Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var v0 := 2.0 - h
	var v1 := 2.0
	# Faces toward each neighbour that is not an equal-or-taller wall.
	var sides := [
		[Vector2i(0, -1), Vector3(0, 0, -1), [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, h, z0), Vector3(x0, h, z0)], x0],
		[Vector2i(0, 1), Vector3(0, 0, 1), [Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x0, h, z1)], x0],
		[Vector2i(-1, 0), Vector3(-1, 0, 0), [Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(x0, h, z1), Vector3(x0, h, z0)], z0],
		[Vector2i(1, 0), Vector3(1, 0, 0), [Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x1, h, z0)], z0],
	]
	for s in sides:
		var nt: Vector2i = t + (s[0] as Vector2i)
		if is_wall(nt) and float(heights.get(nt, 0.0)) >= h:
			continue
		if not is_wall(nt) and not is_floor(nt) and (s[0] as Vector2i).y != 1:
			continue  # faces into the void, never seen (except south faces)
		var u: float = s[3]
		_quad(st, s[2], s[1], [Vector2(u, v1), Vector2(u + 1, v1), Vector2(u + 1, v0), Vector2(u, v0)])


# ------------------------------------------------------------ lights

func _build_lights() -> void:
	for id in room_bounds.keys():
		var r: Rect2i = room_bounds[id]
		var lights: Array = []
		var n := 1
		if id == "corridor":
			n = 5
		elif r.size.x >= 8:
			n = 2
		for i in n:
			var fx := r.position.x + (r.size.x - 1) * (i + 0.5) / float(n)
			var fz := r.position.y + (r.size.y - 1) / 2.0
			var rng := maxf(r.size.y, float(r.size.x) / n) * 0.8 + 2.5
			var l := Retro.omni(LIGHT_COL, rng, 1.9, Vector3(fx, 2.6, fz))
			add_child(l)
			lights.append(l)
		_white[id] = lights
		# Emergency strip along the back wall + its red glow.
		var strip := Retro.box(Vector3(maxf(1.0, r.size.x - 1.0), 0.06, 0.04), RED, \
			Vector3(r.position.x + (r.size.x - 1) / 2.0, 1.25, r.position.y - 0.48), {"unlit": true})
		add_child(strip)
		_strips[id] = [strip]
		var red := Retro.omni(RED, maxf(r.size.x, r.size.y) * 0.7 + 2.0, 0.8,
			Vector3(r.position.x + (r.size.x - 1) / 2.0, 1.4, r.position.y + 0.4))
		add_child(red)
		_red[id] = red


## Lights follow the breakers. Call after any power change.
func apply_power() -> void:
	_alarm = not Game.is_powered("generator")
	for id in _white.keys():
		var lit := room_lit(id)
		for l in _white[id]:
			(l as OmniLight3D).visible = lit
		for s in _strips[id]:
			(s as Node3D).visible = not lit
		var red: OmniLight3D = _red[id]
		red.visible = not lit
		red.light_energy = 0.7
	for g in _glows:
		var mi: MeshInstance3D = g[0]
		var room: String = g[1]
		mi.visible = room == "" or (Game.is_powered("generator") and Game.is_powered(room))


func _process(dt: float) -> void:
	_t += dt
	if _alarm:
		# Lockdown alarm: slow red pulses through the whole wing.
		var k := pow(maxf(0.0, sin(_t * 3.2)), 2.0)
		for id in _red.keys():
			(_red[id] as OmniLight3D).light_energy = 0.25 + 1.4 * k


# ------------------------------------------------------------ props

func _add(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	add_child(n)
	return n


func _b(size: Vector3, color: Color, pos: Vector3, opts: Dictionary = {}) -> MeshInstance3D:
	var m := Retro.box(size, color, pos, opts)
	add_child(m)
	return m


func _reg(id: String, tiles: Array, block := true) -> void:
	for t in tiles:
		objs[t] = id
		if block:
			blocked[t] = true


func _block(tiles: Array) -> void:
	for t in tiles:
		blocked[t] = true


## A screen/lamp that only shows when its room has power ("" = always).
func _glow(m: MeshInstance3D, room: String) -> MeshInstance3D:
	_glows.append([m, room])
	return m


## Something hung on the back wall of tile row `wy` (south face at wy + 0.5).
func _on_wall(size: Vector3, color: Color, x: float, wy: int, y: float, opts: Dictionary = {}) -> MeshInstance3D:
	return _b(size, color, Vector3(x, y, wy + 0.5 + size.z / 2.0), opts)


func _desk(x0: float, x1: float, z: float, color := Color("8c7860"), depth := 0.8) -> void:
	_b(Vector3(x1 - x0 + 0.9, 0.08, depth), color, Vector3((x0 + x1) / 2.0, 0.7, z))
	_b(Vector3(x1 - x0 + 0.8, 0.62, depth - 0.1), color.darkened(0.3), Vector3((x0 + x1) / 2.0, 0.33, z))


func _breaker(room: String, wt: Vector2i) -> void:
	_on_wall(Vector3(0.5, 0.6, 0.08), Color("586068"), wt.x, wt.y, 1.0)
	_on_wall(Vector3(0.38, 0.12, 0.1), Color("e8c840"), wt.x, wt.y, 1.18)
	var lamp := _on_wall(Vector3(0.08, 0.08, 0.12), Color("40ff60"), wt.x + 0.14, wt.y, 0.86, {"unlit": true})
	_glow(lamp, room)
	_reg("breaker:" + room, [wt], false)


func _build_props() -> void:
	_props_lab()
	_props_medbay()
	_props_break()
	_props_freezer()
	_props_hatch()
	_props_incubator()
	_props_generator()
	_props_security()
	_props_garden()
	_props_comms()
	_props_airlock()


func _props_lab() -> void:
	# BENCH: splice bench with hood, rack and a screen that never loses power.
	_desk(2, 3, 12.0, Color("a8b4b8"))
	_b(Vector3(1.7, 0.7, 0.1), Color("90a8b0"), Vector3(2.5, 1.15, 11.62))
	_b(Vector3(1.7, 0.06, 0.6), Color("707c84"), Vector3(2.5, 1.5, 11.9))
	_b(Vector3(0.5, 0.36, 0.08), Color("203028"), Vector3(3.0, 0.98, 12.0))
	_glow(_b(Vector3(0.42, 0.28, 0.02), Color("58d0a8"), Vector3(3.0, 0.98, 12.05), {"unlit": true}), "")
	for i in 5:
		_b(Vector3(0.06, 0.18, 0.06), Color("70d850") if i == 2 else Color("b0c8d0"), Vector3(1.85 + i * 0.12, 0.83, 12.1))
	var lamp := Retro.omni(Color(0.7, 1.0, 0.85), 3.2, 0.9, Vector3(2.5, 1.4, 12.6))
	add_child(lamp)
	_reg("bench", [Vector2i(2, 12), Vector2i(3, 12)])
	# WHITEBOARD on the back wall.
	_on_wall(Vector3(1.8, 0.9, 0.05), Color("f0f0ec"), 7.5, 11, 1.05)
	var scrawl := Retro.tex_from_rows([
		"................",
		".##..#.#..###...",
		"......#.....#.#.",
		".#.##....##.....",
		"....#..#.#..##..",
		".##...##..#.....",
		"................",
		"..####..........",
	], {".": Color("f0f0ec"), "#": Color("405890")})
	_b(Vector3(1.6, 0.7, 0.02), Color.WHITE, Vector3(7.5, 1.05, 11.56), {"tex": scrawl, "unlit": true})
	_reg("whiteboard", [Vector2i(7, 11), Vector2i(8, 11)], false)
	# BINDER desk on the east wall.
	_b(Vector3(0.8, 0.08, 1.8), Color("8c7860"), Vector3(9.0, 0.7, 14.5))
	_b(Vector3(0.7, 0.62, 1.7), Color("62543f"), Vector3(9.0, 0.33, 14.5))
	_b(Vector3(0.3, 0.08, 0.38), Color("c84838"), Vector3(9.0, 0.78, 14.2))
	_b(Vector3(0.2, 0.06, 0.26), Color("e8e4d8"), Vector3(9.0, 0.76, 14.8))
	_reg("binder", [Vector2i(9, 14), Vector2i(9, 15)])
	# Your desk: PHOTO pinned up, DRAWING lying on it.
	_b(Vector3(0.8, 0.08, 1.8), Color("7c6850"), Vector3(1.0, 0.7, 15.5))
	_b(Vector3(0.7, 0.62, 1.7), Color("564834"), Vector3(1.0, 0.33, 15.5))
	_b(Vector3(0.05, 0.6, 1.0), Color("a08060"), Vector3(0.53, 1.15, 15.2))
	_b(Vector3(0.04, 0.26, 0.34), Color("e0d8c0"), Vector3(0.56, 1.2, 15.1))
	_b(Vector3(0.045, 0.1, 0.3), Color("60a048"), Vector3(0.57, 1.12, 15.1))
	_b(Vector3(0.36, 0.02, 0.28), Color("f0ece0"), Vector3(1.0, 0.75, 16.0))
	_b(Vector3(0.12, 0.025, 0.12), Color("78d040"), Vector3(0.95, 0.76, 15.95))
	_b(Vector3(0.3, 0.025, 0.06), Color("8a6838"), Vector3(1.0, 0.76, 16.08))
	_reg("photo", [Vector2i(1, 15)])
	_reg("drawing", [Vector2i(1, 16)])
	# The broken VIAL: glass and a green stain.
	var stain := Retro.tex_noise(Color("4c8838"), Color("2c4c24"), 8, 11, 0.4)
	_b(Vector3(0.7, 0.01, 0.5), Color.WHITE, Vector3(5.0, 0.005, 15.05), {"tex": stain})
	_b(Vector3(0.12, 0.05, 0.08), Color("b8e0e8"), Vector3(4.9, 0.03, 15.0), {"unlit": true})
	_b(Vector3(0.07, 0.04, 0.12), Color("a0d0d8"), Vector3(5.15, 0.03, 15.12), {"unlit": true})
	_b(Vector3(0.05, 0.03, 0.05), Color("d0f0f0"), Vector3(5.0, 0.03, 14.86), {"unlit": true})
	_reg("vial", [Vector2i(5, 15)], false)
	# BADGE on the floor until you pick it up.
	if not Game.lore.has("badge"):
		_badge = Node3D.new()
		_badge.add_child(Retro.box(Vector3(0.18, 0.02, 0.24), Color("f0f0f0")))
		_badge.add_child(Retro.box(Vector3(0.1, 0.025, 0.08), Color("4c8838"), Vector3(0, 0.002, -0.04)))
		_badge.add_child(Retro.box(Vector3(0.04, 0.015, 0.4), Color("b03030"), Vector3(0.1, 0, -0.22)))
		_add(_badge, Vector3(6.1, 0.012, 16.0))
		_reg("badge", [Vector2i(6, 16)], false)
	# Shelving.
	_b(Vector3(1.6, 1.2, 0.4), Color("7c8890"), Vector3(5.5, 0.6, 17.25))
	_block([Vector2i(5, 17), Vector2i(6, 17)])


func remove_badge() -> void:
	if _badge:
		_badge.queue_free()
		_badge = null
	objs.erase(Vector2i(6, 16))


func _props_medbay() -> void:
	# Scanner bed under an arch.
	_b(Vector3(0.8, 0.5, 1.8), Color("c8d4d8"), Vector3(15.0, 0.25, 13.5))
	_b(Vector3(0.7, 0.1, 1.6), Color("e8f0f0"), Vector3(15.0, 0.55, 13.5))
	_b(Vector3(0.1, 1.3, 0.3), Color("8898a0"), Vector3(14.55, 0.65, 13.2))
	_b(Vector3(0.1, 1.3, 0.3), Color("8898a0"), Vector3(15.45, 0.65, 13.2))
	_b(Vector3(1.0, 0.14, 0.3), Color("8898a0"), Vector3(15.0, 1.3, 13.2))
	_glow(_b(Vector3(0.7, 0.04, 0.2), Color("58d0a8"), Vector3(15.0, 1.22, 13.2), {"unlit": true}), "medbay")
	_reg("scanner", [Vector2i(15, 13), Vector2i(15, 14)])
	_b(Vector3(0.8, 1.3, 0.6), Color("d8e0e0"), Vector3(16.0, 0.65, 12.0))
	_b(Vector3(0.06, 0.3, 0.3), Color("c84040"), Vector3(16.0, 1.0, 12.31))
	_block([Vector2i(16, 12)])
	_breaker("medbay", Vector2i(11, 11))


func _props_break() -> void:
	# Counter with seven MUGS.
	_desk(18, 19, 12.0, Color("a09070"))
	for i in 7:
		var c := Color("e0dcd0") if i != 4 else Color("d8c8a0")
		_b(Vector3(0.12, 0.14, 0.12), c, Vector3(17.75 + i * 0.25, 0.81, 12.0 + (0.12 if i % 2 == 0 else -0.08)))
	_reg("mugs", [Vector2i(18, 12), Vector2i(19, 12)])
	# Seven COAT hooks, one coat.
	_on_wall(Vector3(1.8, 0.08, 0.06), Color("605848"), 23.5, 11, 1.35)
	for i in 7:
		_on_wall(Vector3(0.05, 0.1, 0.12), Color("383028"), 22.75 + i * 0.25, 11, 1.28)
	_on_wall(Vector3(0.36, 0.8, 0.12), Color("e8ecec"), 22.75 + 6 * 0.25, 11, 0.9)
	_reg("coats", [Vector2i(23, 11), Vector2i(24, 11)], false)
	# Table and stools.
	_desk(20, 21, 15.0, Color("907c60"))
	_block([Vector2i(20, 15), Vector2i(21, 15)])
	_b(Vector3(0.3, 0.45, 0.3), Color("504840"), Vector3(20.0, 0.22, 16.0))
	_block([Vector2i(20, 16)])
	# COT.
	_b(Vector3(1.8, 0.3, 0.8), Color("70786c"), Vector3(24.5, 0.18, 16.0))
	_b(Vector3(1.2, 0.08, 0.76), Color("586878"), Vector3(24.8, 0.36, 16.0))
	_b(Vector3(0.4, 0.1, 0.6), Color("e0e0d8"), Vector3(23.85, 0.37, 16.0))
	_reg("cot", [Vector2i(24, 16), Vector2i(25, 16)])


func _props_freezer() -> void:
	for x in [27.5]:
		_b(Vector3(1.9, 1.5, 0.8), Color("d8e4ec"), Vector3(x, 0.75, 12.0))
		_b(Vector3(0.05, 1.3, 0.04), Color("8898a8"), Vector3(x, 0.75, 12.42))
		_b(Vector3(0.3, 0.38, 0.02), Color("f8f8f0"), Vector3(x + 0.4, 1.0, 12.42))
	_b(Vector3(0.8, 1.5, 1.9), Color("d8e4ec"), Vector3(31.0, 0.75, 13.5))
	_b(Vector3(0.04, 1.3, 0.05), Color("8898a8"), Vector3(30.58, 0.75, 13.5))
	_glow(_b(Vector3(0.02, 0.1, 0.2), Color("80c0ff"), Vector3(30.58, 1.3, 13.1), {"unlit": true}), "freezer")
	_reg("freezer", [Vector2i(27, 12), Vector2i(28, 12), Vector2i(31, 13), Vector2i(31, 14)])
	_breaker("freezer", Vector2i(31, 11))


func _props_hatch() -> void:
	# Ladder up to the ceiling hatch, crate below.
	for i in 6:
		_on_wall(Vector3(0.5, 0.05, 0.05), Color("a0a8a8"), 35.0, 11, 0.2 + i * 0.25)
	_on_wall(Vector3(0.05, 1.6, 0.06), Color("a0a8a8"), 34.78, 11, 0.8)
	_on_wall(Vector3(0.05, 1.6, 0.06), Color("a0a8a8"), 35.22, 11, 0.8)
	_on_wall(Vector3(0.8, 0.08, 0.6), Color("505860"), 35.0, 11, 1.62)
	var crate := Retro.tex_stripes(Color("a08850"), Color("8c7444"), 8, false)
	_b(Vector3(0.7, 0.55, 0.7), Color.WHITE, Vector3(35.0, 0.28, 13.0), {"tex": crate})
	_reg("hatch", [Vector2i(35, 11), Vector2i(35, 13)])


func _props_incubator() -> void:
	_b(Vector3(0.8, 1.4, 1.8), Color("c0c8c8"), Vector3(39.0, 0.7, 13.5))
	_b(Vector3(0.04, 0.9, 1.4), Color("304048"), Vector3(38.58, 0.85, 13.5))
	for i in 3:
		_glow(_b(Vector3(0.03, 0.12, 0.3), Color("a8f080"), Vector3(38.57, 0.6 + i * 0.3, 13.5), {"unlit": true}), "incubator")
	_reg("incubator", [Vector2i(39, 13), Vector2i(39, 14)])
	_breaker("incubator", Vector2i(37, 11))


func _props_generator() -> void:
	_b(Vector3(2.8, 1.3, 1.8), Color("6c7058"), Vector3(3.0, 0.65, 1.5))
	_b(Vector3(1.0, 0.5, 1.0), Color("585c48"), Vector3(2.4, 1.5, 1.4))
	_b(Vector3(0.3, 0.9, 0.3), Color("484c40"), Vector3(3.9, 1.7, 1.2))
	_b(Vector3(2.9, 0.1, 0.1), Color("e8c840"), Vector3(3.0, 0.1, 2.42))
	_glow(_b(Vector3(0.3, 0.16, 0.02), Color("60ff70"), Vector3(3.6, 1.0, 2.41), {"unlit": true}), "generator")
	_reg("generator", [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)])
	var drum := Retro.cyl(0.28, 0.28, 0.8, Color("8c4030"), 8, Vector3(1.0, 0.4, 5.0))
	add_child(drum)
	add_child(Retro.cyl(0.28, 0.28, 0.8, Color("7c3828"), 8, Vector3(2.0, 0.4, 5.0)))
	_block([Vector2i(1, 5), Vector2i(2, 5)])


func _props_security() -> void:
	_desk(8, 10, 1.0, Color("505860"))
	for i in 3:
		_b(Vector3(0.6, 0.45, 0.35), Color("303438"), Vector3(8.0 + i, 1.0, 0.85))
		_glow(_b(Vector3(0.5, 0.35, 0.02), Color("7090a0"), Vector3(8.0 + i, 1.0, 1.04), {"unlit": true}), "cctv")
	_reg("cctv", [Vector2i(8, 1), Vector2i(9, 1), Vector2i(10, 1)])
	_breaker("cctv", Vector2i(11, 0))


var _palm_print: MeshInstance3D


func _props_garden() -> void:
	var soil := Color("5c5650")
	# Pot tables: three runs of grey pots (the rest of the forty-one implied).
	for run in [[14, 2], [21, 2], [14, 4]]:
		var x0: int = run[0]
		var z: int = run[1]
		_b(Vector3(3.9, 0.08, 0.7), Color("707468"), Vector3(x0 + 1.5, 0.55, z))
		_b(Vector3(3.8, 0.5, 0.6), Color("50544c"), Vector3(x0 + 1.5, 0.27, z))
		var tiles: Array = []
		for i in 4:
			var p := Retro.cyl(0.17, 0.13, 0.26, Color("8c8880"), 6, Vector3(x0 + i, 0.72, z))
			add_child(p)
			_b(Vector3(0.26, 0.02, 0.26), soil, Vector3(x0 + i, 0.85, z))
			tiles.append(Vector2i(x0 + i, z))
		_reg("pots", tiles)
	# TEST BED: a raised bed of dark soil, long enough to lie in.
	_b(Vector3(2.8, 0.4, 0.9), Color("605848"), Vector3(22.5, 0.2, 4.0))
	var bed := Retro.tex_noise(Color("3c3428"), Color("2c2820"), 16, 5)
	_b(Vector3(2.6, 0.02, 0.76), Color.WHITE, Vector3(22.5, 0.41, 4.0), {"tex": bed})
	_reg("testbed", [Vector2i(21, 4), Vector2i(22, 4), Vector2i(23, 4)])
	# PALM POT on its own stand by the wall.
	_b(Vector3(0.6, 0.5, 0.6), Color("707468"), Vector3(25.0, 0.25, 5.0))
	add_child(Retro.cyl(0.24, 0.18, 0.34, Color("8c8880"), 8, Vector3(25.0, 0.67, 5.0)))
	var early := Game.day < 4
	var rows := [
		"........",
		".#.#.#..",
		".#.#.#.#",
		".#####.#",
		".######.",
		"..#####.",
		"..####..",
		"........",
	]
	var pal := {".": Color("4c4842"), "#": Color("383430")} if early else {".": Color("4c4842"), "#": Color("58e040")}
	var print_tex := Retro.tex_from_rows(rows, pal)
	var opts := {"tex": print_tex}
	if not early:
		opts["emit"] = Color(0.1, 0.25, 0.05)
	_palm_print = _b(Vector3(0.4, 0.02, 0.4), Color.WHITE, Vector3(25.0, 0.85, 5.0), opts)
	_reg("palm_pot", [Vector2i(25, 5)])
	# VENT shaft: a faint cold light falling from the ceiling grille.
	var beam := Retro.box(Vector3(0.9, 3.0, 0.9), Color(0.75, 0.85, 0.9), Vector3(19.0, 1.5, 2.5), {"alpha": 0.12})
	add_child(beam)
	var grate := Retro.tex_stripes(Color("98a0a0"), Color("383c40"), 8, false)
	_b(Vector3(0.9, 0.01, 0.9), Color.WHITE, Vector3(19.0, 0.006, 2.5), {"tex": grate, "unlit": true})
	add_child(Retro.omni(Color(0.7, 0.8, 0.85), 2.6, 0.7, Vector3(19.0, 2.2, 2.5)))
	_breaker("garden", Vector2i(13, 0))


func _props_comms() -> void:
	_desk(27, 28, 1.0, Color("505860"))
	_b(Vector3(1.2, 0.6, 0.3), Color("2c3034"), Vector3(27.5, 1.08, 0.8))
	_glow(_b(Vector3(1.0, 0.48, 0.02), Color("304860"), Vector3(27.5, 1.08, 0.96), {"unlit": true}), "comms")
	_glow(_b(Vector3(0.5, 0.3, 0.025), Color("8c8c84"), Vector3(27.3, 1.08, 0.97), {"unlit": true}), "comms")
	_reg("comms", [Vector2i(27, 1), Vector2i(28, 1)])
	# Archive drawers.
	_b(Vector3(1.8, 1.2, 0.8), Color("7c8478"), Vector3(32.5, 0.6, 1.0))
	for i in 3:
		_b(Vector3(1.7, 0.02, 0.02), Color("4c544c"), Vector3(32.5, 0.3 + i * 0.35, 1.41))
		_b(Vector3(0.2, 0.06, 0.04), Color("c8c8b8"), Vector3(32.5, 0.42 + i * 0.35, 1.42))
	_reg("tillwell", [Vector2i(32, 1), Vector2i(33, 1)])
	_breaker("comms", Vector2i(29, 0))
	_breaker("archive", Vector2i(31, 0))


func _props_airlock() -> void:
	# The sealed door, red light, scan panel and plaque.
	var haz := Retro.tex_stripes(Color("e8c840"), Color("282828"), 16, true)
	_on_wall(Vector3(2.6, 1.55, 0.12), Color("687078"), 37.0, 0, 0.78)
	_on_wall(Vector3(0.06, 1.4, 0.14), Color("383c40"), 37.0, 0, 0.7)
	_on_wall(Vector3(2.4, 0.16, 0.14), Color.WHITE, 37.0, 0, 1.42, {"tex": haz})
	_b(Vector3(2.8, 0.01, 0.4), Color.WHITE, Vector3(37.0, 0.006, 1.0), {"tex": haz})
	_on_wall(Vector3(0.18, 0.18, 0.16), RED, 37.0, 0, 1.58, {"unlit": true})
	add_child(Retro.omni(RED, 3.5, 1.2, Vector3(37.0, 1.4, 1.2)))
	_reg("airlock", [Vector2i(36, 0), Vector2i(37, 0), Vector2i(38, 0)], false)
	_on_wall(Vector3(0.36, 0.5, 0.08), Color("404850"), 35.0, 0, 1.0)
	_on_wall(Vector3(0.24, 0.16, 0.1), Color("d84848"), 35.0, 0, 1.1, {"unlit": true})
	_reg("doorlog", [Vector2i(35, 0)], false)
	_on_wall(Vector3(0.6, 0.4, 0.05), Color("a08848"), 39.0, 0, 1.1)
	_on_wall(Vector3(0.16, 0.16, 0.07), Color("e8d890"), 39.0, 0, 1.12)
	_reg("plaque", [Vector2i(39, 0)], false)


# ------------------------------------------------------------ signs

func _label(text: String, color: Color, px := 0.026) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font
	l.font_size = 8
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	return l


func _build_signs() -> void:
	for s in SIGNS:
		var text: String = s[0]
		var x: int = s[1]
		var top: bool = s[2]
		if top:
			# Plate on the corridor's back wall, beside the door.
			var w := text.length() * 8 * 0.026 + 0.16
			var cx := x + 0.5 + w / 2.0 + 0.04
			_b(Vector3(w, 0.32, 0.04), Color("283038"), Vector3(cx, 1.15, 7.52))
			var l := _label(text, Color("d0f0e0"))
			l.position = Vector3(cx, 1.15, 7.56)
			add_child(l)
		else:
			# Stencilled on the corridor floor in front of the door.
			var l := _label(text, Color(0.95, 0.85, 0.3, 0.85), 0.03)
			l.rotation_degrees.x = -90
			l.position = Vector3(x, 0.01, 9.25)
			add_child(l)
