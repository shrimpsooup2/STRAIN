extends Node3D
## The path through one region: a branching DAG of node rows, bottom to top, ending at the heart.
## Game.run.nodes = [[{"type","enemy","event","links":[cols in next row]}...]...] (built by Game._make_nodes).
## Game.run.row / col = the node last entered (row -1 = not started); Game.run.path = column per row.
## On load it consumes Game.run.pending_reward (RewardView) and the debug hook Game.run.debug_open.

const GeneArt := preload("res://scripts/run/gene_art.gd")
const PixelBar := preload("res://scripts/run/pixel_bar.gd")
const Backdrop := preload("res://scripts/run/region_backdrop.gd")
const StrandView := preload("res://scripts/run/strand_view.gd")
const RestView := preload("res://scripts/run/rest_view.gd")
const RewardView := preload("res://scripts/run/reward_view.gd")
const ShopView := preload("res://scripts/run/shop_view.gd")
const EventView := preload("res://scripts/run/event_view.gd")
const Boosters := preload("res://scripts/culture/boosters.gd")
const GLOSSARY_PATH := "res://scripts/ui/glossary.gd"
const JUICE_PATH := "res://scripts/fx/juice.gd"

const MAP := Rect2(4, 4, 180, 208)
const HUD := Rect2(188, 4, 192, 88)
const INFO := Rect2(188, 96, 192, 116)
const COL_GAP := 40
const NODE := 16
const ICON_Y := 66

const ICONS := {
	"fight": ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"],
	"elite": [".#####.", "#######", "#.##.##", "#######", ".#####.", ".#.#.#.", "......."],
	"rest": ["..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.."],
	"event": ["..###..", ".#...#.", ".....#.", "...##..", "...#...", ".......", "...#..."],
	"boss": ["#.#.#.#", ".#####.", "##.#.##", ".#####.", "##...##", ".#####.", "#.#.#.#"],
	"lesion": [".#####.", "#.....#", "#.###.#", "#.#.#.#", "#.###.#", "#.....#", ".#####."],
	"cyst": ["..###..", ".#####.", "###.###", "##...##", "###.###", ".#####.", "..###.."],
	"needle": ["......#", ".....#.", "...##..", "..###..", ".###...", ".##....", "#......"],
}
const NAMES := {"fight": "FIGHT", "elite": "ELITE", "rest": "REST", "event": "EVENT", "boss": "HEART",
	"lesion": "LESION", "cyst": "CYST", "needle": "NEEDLE"}
const COLORS := {"fight": Color("d86048"), "elite": Color("e8a040"), "rest": Color("58d0a8"),
	"event": Color("e8c840"), "boss": Color("70d850"), "lesion": Color("c070e0"),
	"cyst": Color("60b0f0"), "needle": Color("d0d8e8")}
const ENTRY_THOUGHT := {
	"wound": "The cut. Where it got in.",
	"rivers": "The blood. It moves fast here.",
	"hollow": "The lungs. It breathes with me.",
	"archive": "Behind the eyes. It reads me.",
	"root": "The centre. No way around it.",
}
const TIPS := ["Paths fork. They never cross back.", "What I don't spend comes home."]
const NEEDLE_COLONY := 12
const NEEDLE_FRAY := 2
const CYST_COST := 8

var region := "wound"
var nodes: Array = []
var path: Array = []
var row := -1
var sel := 0
var _busy := true
var _t := 0.0
var _map: Control
var _hud: Control
var _bar                  ## PixelBar
var _info: Label
var _cam: Camera3D
var _cells: Array = []
var _focus := -1          ## index into _hud_items() while the HUD icon row is selected


func _ready() -> void:
	UI.apply_stage_post()
	if Game.run.is_empty():
		Game.start_run(Game.args_region())
	region = String(Game.run.get("region", "wound"))
	nodes = Game.run.get("nodes", [])
	_normalize_nodes()
	row = int(Game.run.get("row", -1))
	path = Game.run.get("path", [])
	# Debug entry points may set row/col without a path: fill it in.
	while path.size() < row + 1:
		path.append(int(Game.run.get("col", 0)))
	Game.run["path"] = path
	Sfx.drone(region)
	_build_world()
	_build_ui()
	sel = 0
	_refresh()
	_begin()


## Saves from before the DAG stored bare type strings; give them full links.
func _normalize_nodes() -> void:
	for r in nodes.size():
		var cur: Array = nodes[r]
		var next_n := 1
		if r + 1 < nodes.size():
			next_n = (nodes[r + 1] as Array).size()
		for c in cur.size():
			if cur[c] is Dictionary:
				continue
			var links: Array = []
			for k in next_n:
				links.append(k)
			cur[c] = {"type": String(cur[c]), "enemy": "", "event": "", "links": links}
	Game.run["nodes"] = nodes


func _begin() -> void:
	await get_tree().create_timer(0.4).timeout
	if Game.run.has("pending_reward"):
		var pending: Dictionary = Game.run["pending_reward"]
		Game.run.erase("pending_reward")
		Game.save_game()
		await RewardView.open(self, pending)
		Game.save_game()
		_refresh()
	if Game.run.has("debug_open"):
		var kind := String(Game.run["debug_open"])
		var ev := String(Game.run.get("debug_event", ""))
		Game.run.erase("debug_open")
		Game.run.erase("debug_event")
		if await _debug_open(kind, ev):
			return
	if row < 0:
		await UI.say([ENTRY_THOUGHT.get(region, "In.")], "think")
	if not Game.flags.has("tips_map"):
		Game.flags["tips_map"] = true
		await UI.say(TIPS, "think")
		Game.save_game()
	_busy = false
	_refresh()


## --setup=shop|event|cyst|needle|rest opens that screen straight away. True if it left the scene.
func _debug_open(kind: String, ev: String) -> bool:
	match kind:
		"shop":
			await ShopView.open(self, "debug")
		"rest":
			await RestView.open(self)
		"cyst":
			await _cyst()
		"needle":
			await _needle()
		"event":
			if ev == "":
				for rr in nodes:
					for n in rr:
						var nd: Dictionary = n
						if String(nd.get("type", "")) == "event" and String(nd.get("event", "")) != "":
							ev = String(nd["event"])
							break
					if ev != "":
						break
			if ev == "":
				var evs = load("res://scripts/run/events.gd")
				ev = String(evs.pick(region, Game.stage, Game.day, []))
			if ev != "" and await EventView.open(self, ev):
				return true
	Game.save_game()
	_refresh()
	return false


# ------------------------------------------------------------------ 3D

func _build_world() -> void:
	var bd := Backdrop.new()
	add_child(bd)
	bd.setup(region, {"center": Vector3(0, 0.5, -3), "extent": Vector3(10, 5, 10), "floor_y": -1.5,
		"fog": 0.045, "motes": 60})
	var pal: Dictionary = Cards.REGION_COLORS.get(region, Cards.REGION_COLORS["wound"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region) + 7
	# Nearby floating cells, each with a nucleus.
	for i in 9:
		var p := Vector3(rng.randf_range(-3.5, 5.0), rng.randf_range(-0.6, 2.6), rng.randf_range(-7.0, -1.5))
		var r := rng.randf_range(0.35, 0.9)
		var cell := Node3D.new()
		cell.position = p
		var shell_col := (pal["floor"] as Color).lerp(pal["accent"], rng.randf_range(0.1, 0.4))
		var shell := Retro.ball(r, shell_col, 8, 5)
		cell.add_child(shell)
		cell.add_child(Retro.ball(r * 0.4, (pal["accent"] as Color).lerp(Color.WHITE, 0.2), 5, 3,
			Vector3(r * 0.3, r * 0.35, r * 0.55)))
		add_child(cell)
		_cells.append([cell, p, rng.randf() * TAU])
	add_child(Retro.omni(pal["accent"], 9.0, 0.9, Vector3(2, 3, -2)))
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.position = Vector3(0.5, 1.2, 3.5)
	add_child(_cam)
	_cam.look_at(Vector3(1.5, 0.8, -4))
	_cam.current = true


func _process(dt: float) -> void:
	_t += dt
	for e in _cells:
		var c: Node3D = e[0]
		var p: Vector3 = e[1]
		var ph: float = e[2]
		c.position = p + Vector3(sin(_t * 0.4 + ph) * 0.2, sin(_t * 0.6 + ph) * 0.25, 0)
		c.rotation.y += dt * 0.2
	if _cam:
		_cam.position = Vector3(0.5 + sin(_t * 0.15) * 0.4, 1.2 + sin(_t * 0.21) * 0.15, 3.5)
		_cam.look_at(Vector3(1.5, 0.8, -4))
	if _map:
		_map.queue_redraw()
	if _hud and _focus >= 0:
		_hud.queue_redraw()


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_map = Control.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_PASS
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	layer.add_child(_map)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_bar = PixelBar.new()
	_bar.position = HUD.position + Vector2(7, 26)
	_bar.size = Vector2(HUD.size.x - 14, 5)
	_hud.add_child(_bar)
	_bar.set_values(int(Game.run.get("colony", 1)), int(Game.run.get("max_colony", 1)), true)
	var ip := UI.panel(INFO, true)
	ip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ip)
	_info = UI.label("", UI.C_THINK_FG)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(INFO.size.x - 14, INFO.size.y - 28)
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ip.add_child(_info)
	for i in 2:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = "STRAND" if i == 0 else "LEAVE"
		b.position = Vector2(INFO.position.x + 6 + i * 92, INFO.end.y - 17)
		b.size = Vector2(86, 13)
		b.add_theme_color_override("font_color", UI.C_THINK_FG)
		b.add_theme_stylebox_override("normal", UI.box_style(Color("1c2a32"), UI.C_ACCENT.darkened(0.4), 1, 2, Vector4(4, 2, 4, 2)))
		b.add_theme_stylebox_override("hover", UI.box_style(UI.C_FOCUS, UI.C_ACCENT, 1, 2, Vector4(4, 2, 4, 2)))
		b.add_theme_stylebox_override("pressed", UI.box_style(UI.C_FOCUS, UI.C_ACCENT, 1, 2, Vector4(4, 2, 4, 2)))
		if i == 0:
			b.pressed.connect(_on_strand_btn)
		else:
			b.pressed.connect(_on_leave_btn)
		layer.add_child(b)


func _on_strand_btn() -> void:
	if not _busy and not UI.busy:
		_view_strand()


func _on_leave_btn() -> void:
	if not _busy and not UI.busy:
		_withdraw()


# ------------------------------------------------------------------ map geometry

func _node_pos(r: int, c: int) -> Vector2:
	var n := nodes.size()
	var top := MAP.position.y + 12.0
	var bottom := MAP.end.y - 12.0
	var y := bottom - (bottom - top) * float(r) / float(maxi(1, n - 1))
	var k: int = (nodes[r] as Array).size()
	var x := MAP.position.x + MAP.size.x / 2.0 + (float(c) - float(k - 1) / 2.0) * COL_GAP
	return Vector2(roundf(x), roundf(y))


func _node(r: int, c: int) -> Dictionary:
	if r < 0 or r >= nodes.size():
		return {}
	var rr: Array = nodes[r]
	if c < 0 or c >= rr.size():
		return {}
	return rr[c]


func _cur_col() -> int:
	if row < 0 or path.size() <= row:
		return -1
	return int(path[row])


## Columns of row+1 that can be entered now.
func _reachable() -> Array:
	if row + 1 >= nodes.size():
		return []
	if row < 0:
		var out: Array = []
		for c in (nodes[0] as Array).size():
			out.append(c)
		return out
	var here := _node(row, _cur_col())
	var links: Array = here.get("links", [])
	var res: Array = []
	for v in links:
		var c := int(v)
		if c >= 0 and c < (nodes[row + 1] as Array).size() and not res.has(c):
			res.append(c)
	res.sort()
	return res


func _sel_col() -> int:
	var reach := _reachable()
	if reach.is_empty():
		return -1
	return int(reach[clampi(sel, 0, reach.size() - 1)])


func _enemy_name(id: String) -> String:
	if not Cards.ENEMIES.has(id):
		return "SOMETHING"
	return String(Cards.enemy(id).get("name", id.to_upper()))


## 0..1 danger by enemy colony, for the fight icon tint.
func _danger(id: String) -> float:
	if not Cards.ENEMIES.has(id):
		return 0.3
	var col: int = int(Cards.enemy(id).get("colony", 40))
	return clampf((col - 30) / 40.0, 0.0, 1.0)


func _node_color(nd: Dictionary) -> Color:
	var type := String(nd.get("type", "fight"))
	var base: Color = COLORS.get(type, UI.C_DIM)
	if type == "fight":
		base = base.lerp(UI.C_BAD, _danger(String(nd.get("enemy", ""))) * 0.6)
	return base


# ------------------------------------------------------------------ drawing

func _draw_map() -> void:
	var ci := _map
	ci.draw_rect(Rect2(MAP.position, MAP.size), Color(0.02, 0.03, 0.04, 0.45))
	var reach := _reachable()
	var target := _sel_col()
	var cur := _cur_col()
	var blink := fmod(_t, 0.8) < 0.5
	# Links.
	for r in nodes.size() - 1:
		var cur_row: Array = nodes[r]
		for c in cur_row.size():
			var nd: Dictionary = cur_row[c]
			var a := _node_pos(r, c)
			for v in nd.get("links", []):
				var c2 := int(v)
				if c2 >= (nodes[r + 1] as Array).size():
					continue
				var b := _node_pos(r + 1, c2)
				var taken := path.size() > r + 1 and int(path[r]) == c and int(path[r + 1]) == c2
				var avail := r == row and c == cur and reach.has(c2)
				var next := avail and c2 == target and not _busy and _focus < 0
				_link(ci, a, b, taken, avail, next)
	# Nodes.
	for r in nodes.size():
		var cur_row: Array = nodes[r]
		for c in cur_row.size():
			var nd: Dictionary = cur_row[c]
			var type := String(nd.get("type", "fight"))
			var p := _node_pos(r, c)
			var sz := NODE + 6 if type == "boss" else NODE
			var rect := Rect2(p - Vector2(sz, sz) / 2.0, Vector2(sz, sz))
			var col := _node_color(nd)
			var taken := r <= row and path.size() > r and int(path[r]) == c
			var skipped := r <= row and not taken
			var is_reach := r == row + 1 and reach.has(c)
			var is_sel := is_reach and c == target and not _busy and _focus < 0
			var bg := Color("141c24")
			var bd := col.darkened(0.3)
			var ic := col
			if skipped:
				bd = Color("303840")
				ic = Color("404850")
				bg = Color("0c1014")
			elif taken:
				bg = col.darkened(0.6)
				bd = col.darkened(0.2)
				ic = col.darkened(0.15)
			elif is_reach:
				bd = col if not blink or is_sel else col.darkened(0.2)
			elif r > row + 1:
				ic = col.darkened(0.35)
				bd = col.darkened(0.55)
			if is_sel:
				ci.draw_rect(rect.grow(3), UI.C_PAPER)
				ci.draw_rect(rect.grow(2), UI.C_INK)
			ci.draw_rect(rect, bd)
			ci.draw_rect(rect.grow(-1), bg)
			var px := 2
			var icon: Array = ICONS.get(type, ICONS["fight"])
			GeneArt.bitmap(ci, rect.position + (rect.size - Vector2(7 * px, 7 * px)) / 2.0, icon, ic, px)
			# You-are-here marker.
			if r == row and taken:
				var my := rect.position.y - 6 + (1 if blink else 0)
				ci.draw_rect(Rect2(p.x - 2, my, 5, 2), UI.C_PAPER)
				ci.draw_rect(Rect2(p.x - 1, my + 2, 3, 1), UI.C_PAPER)
	# Selected node name beside it.
	if target >= 0 and not _busy and _focus < 0:
		var nd := _node(row + 1, target)
		var nm := String(NAMES.get(String(nd.get("type", "")), ""))
		var p := _node_pos(row + 1, target)
		var w := GeneArt.text_w(nm)
		var lx := p.x + NODE / 2.0 + 4
		if lx + w > MAP.end.x - 2:
			lx = p.x - NODE / 2.0 - 4 - w
		ci.draw_rect(Rect2(lx - 2, p.y - 6, w + 4, 11), Color(0, 0, 0, 0.75))
		GeneArt.text(ci, Vector2(lx, p.y - 4), nm, UI.C_PAPER)


func _link(ci: Control, a: Vector2, b: Vector2, taken: bool, avail: bool, next: bool) -> void:
	var col := Color(0.8, 0.84, 0.88, 0.6)
	var w := 1.0
	if taken:
		col = UI.C_ACCENT
		w = 2.0
	elif next:
		col = UI.C_PAPER
		w = 2.0
	elif avail:
		col = UI.C_THINK_FG
	# Pixel-stepped line: small squares along it; faint links are dotted.
	var d := b - a
	var steps := int(maxf(absf(d.x), absf(d.y)) / 3.0)
	for i in steps + 1:
		if not taken and not next and not avail and i % 2 == 1:
			continue
		var p := a + d * (float(i) / float(maxi(1, steps)))
		ci.draw_rect(Rect2(roundf(p.x), roundf(p.y), w, w), col)


## Icons in the HUD row: carried boosters first, then adaptations. [{kind, id}]
func _hud_items() -> Array:
	var out: Array = []
	for v in Game.run.get("boosters", []):
		out.append({"kind": "booster", "id": String(v)})
	for v in Adapt.owned():
		out.append({"kind": "adapt", "id": String(v)})
	return out


func _hud_icon_rect(i: int) -> Rect2:
	return Rect2(HUD.position.x + 7 + i * 10, HUD.position.y + ICON_Y, 8, 8)


func _draw_hud() -> void:
	var ci := _hud
	GeneArt.box(ci, HUD, true)
	var x := HUD.position.x + 7
	var rx := HUD.end.x - 7
	var y := HUD.position.y + 5
	var pal: Dictionary = Cards.REGION_COLORS.get(region, Cards.REGION_COLORS["wound"])
	GeneArt.text(ci, Vector2(x, y), String(Game.REGION_NAMES.get(region, region)), (pal["accent"] as Color).lightened(0.2))
	var depth := "%d/%d" % [maxi(0, row + 1), nodes.size()]
	GeneArt.text(ci, Vector2(rx - GeneArt.text_w(depth), y), depth, UI.C_DIM)
	var col: int = int(Game.run.get("colony", 0))
	var mx: int = int(Game.run.get("max_colony", 1))
	GeneArt.text(ci, Vector2(x, y + 11), "COLONY", UI.C_WARN)
	var num := "%d/%d" % [col, mx]
	GeneArt.text(ci, Vector2(rx - GeneArt.text_w(num), y + 11), num, UI.C_PAPER)
	var fray: int = int(Game.run.get("fray", 0))
	var uptake: int = int(Game.run.get("uptake", 0))
	var mat := RestView.region_mat()
	var tis := "-" if mat == "" else "%s %d" % [mat.to_upper(), RestView.tissue(mat)]
	var lines := [
		["FRAY %d" % fray, "CLEAN %d%%" % RestView.band_pct(fray), UI.C_BAD if fray >= 5 else UI.C_THINK_FG],
		["STRAND %d" % (Game.run.get("strand", []) as Array).size(), "REAGENT %d" % int(Game.run.get("reagent", 0)), UI.C_THINK_FG],
		["UPTAKE %d" % uptake, tis, UI.C_GREEN if uptake > 0 else UI.C_THINK_FG],
	]
	for i in lines.size():
		var ly := y + 31 + i * 10
		var l: Array = lines[i]
		GeneArt.text(ci, Vector2(x, ly), String(l[0]), l[2])
		GeneArt.text(ci, Vector2(rx - GeneArt.text_w(String(l[1])), ly), String(l[1]), UI.C_THINK_FG)
	var items := _hud_items()
	if items.is_empty():
		GeneArt.text(ci, Vector2(x, HUD.position.y + ICON_Y), "NO ADAPTATIONS", UI.C_DIM)
	for i in items.size():
		var r := _hud_icon_rect(i)
		if r.end.x > HUD.end.x - 4:
			break
		var it: Dictionary = items[i]
		var id := String(it["id"])
		var icol := UI.C_ACCENT
		var bmp: Array = ICONS["needle"]
		if String(it["kind"]) == "booster":
			var binfo: Dictionary = Boosters.info(id)
			icol = binfo.get("color", UI.C_WARN)
		else:
			bmp = Adapt.icon(id)
			var rar := String(Adapt.info(id).get("rarity", "common"))
			icol = UI.C_WARN if rar == "rare" else (UI.C_BAD if rar == "cursed" else UI.C_ACCENT)
		if i == _focus:
			ci.draw_rect(r.grow(1), UI.C_PAPER)
			ci.draw_rect(r, UI.C_INK)
		GeneArt.bitmap(ci, r.position + Vector2(0.5, 0.5), bmp, icol, 1)
	var hint := "W LOOK  A/D  S BACK" if _focus >= 0 else "Z GO  C STRAND  H ?"
	GeneArt.text(ci, Vector2(x, HUD.end.y - 12), hint, UI.C_DIM)


func _refresh() -> void:
	var reach := _reachable()
	if not reach.is_empty():
		sel = clampi(sel, 0, reach.size() - 1)
	_bar.set_values(int(Game.run.get("colony", 1)), int(Game.run.get("max_colony", 1)))
	_hud.queue_redraw()
	_map.queue_redraw()
	if _focus >= 0:
		_info.text = _item_text(_focus)
		return
	if reach.is_empty():
		_info.text = ""
		return
	_info.text = _node_text(_node(row + 1, _sel_col()))


func _item_text(i: int) -> String:
	var items := _hud_items()
	if i < 0 or i >= items.size():
		return ""
	var it: Dictionary = items[i]
	var id := String(it["id"])
	if String(it["kind"]) == "booster":
		var b: Dictionary = Boosters.info(id)
		return "BOOSTER: %s\n%s\nINJECT IT MID-FIGHT. ONE USE." % [String(b.get("name", id.to_upper())), String(b.get("desc", ""))]
	var a: Dictionary = Adapt.info(id)
	return "%s  %s\n%s" % [String(a.get("name", id.to_upper())), String(a.get("rarity", "")).to_upper(), String(a.get("desc", ""))]


func _tissue_drop(n: int) -> String:
	var mat := RestView.region_mat()
	if mat == "":
		return ""
	return ", +%d %s" % [n, mat.to_upper()]


func _node_text(nd: Dictionary) -> String:
	var type := String(nd.get("type", ""))
	var enemy := String(nd.get("enemy", ""))
	match type:
		"fight":
			var blurb := ""
			if Cards.ENEMIES.has(enemy):
				blurb = String(Cards.enemy(enemy).get("blurb", ""))
			return "FIGHT: %s\n%s\nWIN: 1 OF %d GENES, +2-3 REAGENT%s." % [_enemy_name(enemy), blurb,
				3 + Adapt.mod("reward_choices"), _tissue_drop(1)]
		"elite":
			var trait_txt := ""
			if Cards.ENEMIES.has(enemy):
				var t: Dictionary = Cards.enemy(enemy).get("trait", {})
				if not t.is_empty():
					trait_txt = "%s: %s" % [String(t.get("name", "")), String(t.get("desc", ""))]
			return "ELITE: %s\n%s\nWIN: 1 OF 3 ADAPTATIONS, A GENE, +5 REAGENT%s." % [_enemy_name(enemy), trait_txt, _tissue_drop(2)]
		"boss":
			var txt := "HEART: %s" % _enemy_name(enemy)
			if Cards.ENEMIES.has(enemy):
				var e: Dictionary = Cards.enemy(enemy)
				txt += "\n" + String(e.get("blurb", ""))
				var t: Dictionary = e.get("trait", {})
				if not t.is_empty():
					txt += "\n%s: %s" % [String(t.get("name", "")), String(t.get("desc", ""))]
			if region == "root":
				return txt + "\nEND IT HERE."
			return txt + "\nWIN: REGION CLEARED%s. ALL REAGENT BANKED." % _tissue_drop(3)
		"rest":
			var mend := RestView.mend_amount()
			return "REST\nPick one: MEND +%d, ENRICH 1 GENE, EXCISE 1, ARRANGE %d, PROOFREAD FRAY -%d." % [
				mend, RestView.ARRANGE_MOVES, RestView.PROOFREAD_N]
		"event":
			var eid := String(nd.get("event", ""))
			var ev: Dictionary = {}
			if eid != "":
				var evs = load("res://scripts/run/events.gd")
				ev = evs.get_event(eid)
			if ev.is_empty():
				return "EVENT\nSomething drifts in the current."
			return "EVENT: %s\n%s" % [String(ev.get("title", "")), String(ev.get("teaser", ""))]
		"lesion":
			return "LESION\nA shop. Spend run reagent (%d) on genes, adaptations, cuts. Spent reagent is not banked." % int(Game.run.get("reagent", 0))
		"cyst":
			return "CYST\nA sealed pocket. Take 1 of 2 adaptations, or crack it: 2 picks, -%d COLONY." % CYST_COST
		"needle":
			return "NEEDLE\nA needle from outside. LIBRARY gene, or +%d COLONY +1 UPTAKE, or FRAY -%d%s." % [
				NEEDLE_COLONY, NEEDLE_FRAY, (" -1 " + RestView.region_mat().to_upper()) if RestView.region_mat() != "" else ""]
	return ""


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if _busy or UI.busy:
		return
	var reach := _reachable()
	if _focus >= 0:
		var items := _hud_items()
		if e.is_action_pressed("move_left"):
			_focus = posmod(_focus - 1, maxi(1, items.size()))
			Sfx.play("blip")
		elif e.is_action_pressed("move_right"):
			_focus = posmod(_focus + 1, maxi(1, items.size()))
			Sfx.play("blip")
		elif e.is_action_pressed("move_down") or e.is_action_pressed("back") or e.is_action_pressed("interact"):
			_focus = -1
			Sfx.play("cancel")
		elif e.is_action_pressed("menu"):
			_focus = -1
			_view_strand()
		else:
			return
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("move_left"):
		if not reach.is_empty():
			sel = posmod(sel - 1, reach.size())
			Sfx.play("blip")
			_refresh()
	elif e.is_action_pressed("move_right"):
		if not reach.is_empty():
			sel = posmod(sel + 1, reach.size())
			Sfx.play("blip")
			_refresh()
	elif e.is_action_pressed("move_up") or e.is_action_pressed("move_down"):
		if not _hud_items().is_empty():
			_focus = 0
			Sfx.play("blip")
			_refresh()
	elif e.is_action_pressed("interact"):
		if not reach.is_empty():
			_enter(_sel_col())
	elif e.is_action_pressed("menu"):
		_view_strand()
	elif e.is_action_pressed("back"):
		_withdraw()
	elif e.is_action_pressed("help"):
		_help()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_map_input(e: InputEvent) -> void:
	if _busy or UI.busy:
		return
	var click := false
	var mpos := Vector2.ZERO
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		click = true
		mpos = mb.position
	elif e is InputEventMouseMotion:
		mpos = (e as InputEventMouseMotion).position
	else:
		return
	# HUD icon row.
	var items := _hud_items()
	for i in items.size():
		if _hud_icon_rect(i).grow(1).has_point(mpos):
			if _focus != i:
				_focus = i
				_refresh()
			return
	if _focus >= 0 and HUD.has_point(mpos):
		return
	if _focus >= 0:
		_focus = -1
		_refresh()
	var reach := _reachable()
	for k in reach.size():
		var c := int(reach[k])
		var p := _node_pos(row + 1, c)
		if Rect2(p - Vector2(12, 12), Vector2(24, 24)).has_point(mpos):
			if k != sel:
				sel = k
				_refresh()
			if click:
				_enter(c)
			return


func _view_strand() -> void:
	_busy = true
	await StrandView.new().run(self, Game.run.get("strand", []), "view", {"title": "STRAND  (READ TOP DOWN)"})
	_busy = false
	_refresh()


func _help() -> void:
	if not ResourceLoader.exists(GLOSSARY_PATH):
		return
	_busy = true
	var g = load(GLOSSARY_PATH).new()
	await g.run(self)
	_busy = false


func _withdraw() -> void:
	_busy = true
	var rg: int = int(Game.run.get("reagent", 0)) / 2
	var parts := PackedStringArray()
	var tissue: Dictionary = Game.run.get("tissue", {})
	for mat in tissue:
		var n: int = int(tissue[mat]) / 2
		if n > 0:
			parts.append("%d %s" % [n, String(mat).to_upper()])
	var bank := "%d REAGENT" % rg
	if not parts.is_empty():
		bank += ", " + ", ".join(parts)
	if await UI.confirm("Withdraw? Banks half: %s." % bank):
		Game.finish_run(false)
		return
	_busy = false


# ------------------------------------------------------------------ nodes

func _enter(c: int) -> void:
	if _busy or c < 0:
		return
	_busy = true
	_focus = -1
	row += 1
	path.append(c)
	Game.run["row"] = row
	Game.run["col"] = c
	Game.run["path"] = path
	var nd := _node(row, c)
	var type := String(nd.get("type", "fight"))
	Sfx.play("map_step")
	_map.queue_redraw()
	Game.save_game()
	await get_tree().create_timer(0.3).timeout
	match type:
		"fight", "elite", "boss":
			Game.run["battle"] = {"kind": type, "enemy": String(nd.get("enemy", ""))}
			Game.save_game()
			Game.goto("battle")
			return
		"rest":
			await RestView.open(self)
		"lesion":
			await ShopView.open(self, "%d_%d" % [row, c])
		"event":
			var eid := String(nd.get("event", ""))
			if eid != "" and await EventView.open(self, eid):
				return
		"cyst":
			await _cyst()
		"needle":
			await _needle()
	Game.save_game()
	sel = 0
	_busy = false
	_refresh()


## Adaptation offers; one slot may roll rare.
func _adapt_offers(n: int) -> Array:
	var ids: Array = Adapt.offers(n, "common", Adapt.owned())
	if randf() < 0.25 and not ids.is_empty():
		var rare: Array = Adapt.offers(1, "rare", Adapt.owned())
		if not rare.is_empty() and not ids.has(rare[0]):
			ids[ids.size() - 1] = rare[0]
	return ids


func _cyst() -> void:
	Sfx.play("event")
	await UI.say(["A sealed pocket, taut and pale.", "Something grew in here, apart from the rest."], "see")
	var col: int = int(Game.run.get("colony", 0))
	var after := maxi(1, col - CYST_COST)
	var rows: Array = [
		{"label": "TAKE ONE", "right": "1 OF 2",
			"desc": "Choose 1 of 2 adaptations. No cost."},
		{"label": "CRACK IT", "right": "-%d COLONY" % CYST_COST,
			"desc": "Choose 2 of 3 adaptations. Colony %d > %d." % [col, after]},
	]
	var i: int = await RestView.new().choose(self, rows, {"title": "CYST", "cancel": false})
	if i == 1:
		RestView.hurt(CYST_COST)
		Sfx.play("hurt")
		UI.flash(Color(0.8, 0.2, 0.2), 0.2)
		_refresh()
		var ids := _adapt_offers(3)
		for k in 2:
			if ids.is_empty():
				break
			var got: String = await RewardView.pick_adapt(self, ids, "CRACKED. TAKE %s." % ("ONE" if k == 0 else "ANOTHER"), false)
			if got == "":
				break
			RewardView.gain_adapt(got)
			ids.erase(got)
	else:
		var ids := _adapt_offers(2)
		var got: String = await RewardView.pick_adapt(self, ids, "TAKE ONE.", true)
		if got != "":
			RewardView.gain_adapt(got)
	_refresh()


## LIBRARY pool: unlocked genes that came from the bench (sequenced or found).
func _library_offers() -> Array:
	var pool: Array = []
	for v in Game.unlocked:
		var id := Cards.base_id(String(v))
		if (Cards.SEQUENCEABLE.has(id) or Cards.LAB_FIND.has(id)) and not pool.has(id):
			pool.append(id)
	pool.shuffle()
	var out: Array = pool.slice(0, 3)
	if out.size() < 3:
		for id in RewardView.gene_offers(6):
			if out.size() >= 3:
				break
			if not out.has(id):
				out.append(id)
	return out


func _needle() -> void:
	Sfx.play("needle")
	await UI.say(["A needle comes in from outside.", "The plunger waits on something."], "see")
	await UI.say(["My hand. Through the skin."], "think")
	var col: int = int(Game.run.get("colony", 0))
	var mx: int = int(Game.run.get("max_colony", 1))
	var up: int = int(Game.run.get("uptake", 0))
	var fray: int = int(Game.run.get("fray", 0))
	var mat := RestView.region_mat()
	var have := RestView.tissue(mat) if mat != "" else 0
	var flush_cost := (", -1 " + mat.to_upper()) if mat != "" else ""
	var rows: Array = [
		{"label": "LIBRARY", "right": "1 OF 3 GENES",
			"desc": "A gene from the bench: sequenced or found. Place it where you choose."},
		{"label": "REFILL", "right": "+%d COLONY" % NEEDLE_COLONY,
			"desc": "Colony %d > %d. Uptake %d > %d. Uptake speeds the real infection." % [
				col, mini(mx, col + NEEDLE_COLONY), up, up + 1]},
		{"label": "FLUSH", "right": "FRAY -%d" % NEEDLE_FRAY,
			"desc": "Fray %d > %d. CLEAN band %d%% > %d%%%s." % [fray, maxi(0, fray - NEEDLE_FRAY),
				RestView.band_pct(fray), RestView.band_pct(maxi(0, fray - NEEDLE_FRAY)), flush_cost]},
	]
	if mat != "" and have < 1:
		rows[2]["disabled"] = true
		rows[2]["desc"] = String(rows[2]["desc"]) + "\nNEEDS 1 %s (HAVE 0)." % mat.to_upper()
	elif fray == 0:
		rows[2]["disabled"] = true
		rows[2]["desc"] = "Fray is 0. Nothing to flush."
	var i: int = await RestView.new().choose(self, rows, {"title": "NEEDLE. ONE DOSE.", "cancel": false})
	match i:
		0:
			var id: String = await RewardView.pick_gene(self, _library_offers(), "LIBRARY. TAKE ONE GENE.", 0)
			if id != "":
				await RestView.place_gene(self, id)
		1:
			var got := RestView.heal(NEEDLE_COLONY)
			Game.run["uptake"] = up + 1
			UI.toast("COLONY +%d. UPTAKE +1" % got, UI.C_GREEN)
		2:
			RestView.add_fray(-NEEDLE_FRAY)
			if mat != "":
				RestView.add_tissue(mat, -1)
			Sfx.play("clean")
			UI.toast("FRAY -%d" % NEEDLE_FRAY, UI.C_GREEN)
	_refresh()
