extends Node3D
## Combat v2. The Reader shows a WINDOW of genes: READ zone (left) leaves at END,
## NEXT zone (right) slides in. LINK adjacent slots, CLEAN the read bar, SPLICE,
## MUTATE, inject BOOSTERS, BREAK wind-ups, HOLD a chain over END. See strain_design §1, §9-§12.

const GeneArt := preload("res://scripts/run/gene_art.gd")
const PixelBar := preload("res://scripts/run/pixel_bar.gd")
const Backdrop := preload("res://scripts/run/region_backdrop.gd")
const StrandView := preload("res://scripts/run/strand_view.gd")
const CardButton := preload("res://scripts/battle/card_button.gd")
const Cluster := preload("res://scripts/battle/colony_cluster.gd")
const ReadBar := preload("res://scripts/battle/read_bar.gd")
const MutateReel := preload("res://scripts/battle/mutate_reel.gd")
const Tutorial := preload("res://scripts/battle/tutorial.gd")
const Boosters := preload("res://scripts/culture/boosters.gd")
const BenchOps := preload("res://scripts/culture/bench_ops.gd")
const JUICE_PATH := "res://scripts/fx/juice.gd"
const GLOSSARY_PATH := "res://scripts/ui/glossary.gd"
const CREATURES_PATH := "res://scripts/battle/creatures/creatures.gd"

const P_POS := Vector3(0, 0, 0)
const E_POS := Vector3(7.6, 0.4, -4.2)
const CAM_POS := Vector3(0, 1.15, 3.8)
const CAM_LOOK := Vector3(4.2, -0.5, -6.0)

const ENEMY_BOX := Rect2(4, 4, 176, 40)
const INTENT_BOX := Rect2(4, 46, 168, 26)
const ORDER_BOX := Rect2(200, 4, 182, 28)
const ICON_Y := 34
const PLAYER_BOX := Rect2(206, 94, 176, 26)
const HINT_Y := 122
const DESC_BOX := Rect2(2, 131, 380, 33)
const ZONE_Y := 165
const CARD_Y := 174
const CARD_H := 40
const TILE_AREA := 324.0
const BTN_X := 330
const BTN_W := 52
const HINT := "Z EXPRESS Q SPLICE R MUT E END F SHOT H ?"
const ROT_COL := Color("c8d060")
const C_HI := Color("e8c840")
const C_SEVER := Color("d05050")

## Keys that take LINK/GROWS bonuses and the CLEAN multiplier, per fx type.
const NUM_KEYS := {"dmg": ["n"], "film": ["n"], "heal": ["n"], "drain": ["n"], "stagger_dmg": ["n"],
	"rot": ["n"], "cap": ["per"], "dmg_count": ["per"], "latent": ["n"], "lull": ["n"]}
const DAMAGING := ["dmg", "drain", "stagger_dmg", "dmg_count", "latent", "cap"]

# ------------------------------------------------------------------ fight state
var region := "wound"
var kind := "fight"
var from_event := false
var enemy_id := ""
var trait_id := ""
var trait_name := ""
var strand: Array = []        ## fight copy: [{"id", "uid"}]
var reader := 0               ## draw pointer into strand (wraps)
var win: Array = []           ## window: [{"id","uid","spent","marked","knotted"}]
var charge := 0
var charge_next := 0
var free_next := false
var splices := 0
var chain := 0
var last_slot := -1
var exp_count := 0
var promote_from := -1
var best_chain := 0           ## longest chain reached this turn (BIND)
var carry_uid := -1           ## HOLD: the unspent gene right of the last expressed one at END
var carry_chain := 0          ## HOLD: chain it may continue next turn
var primer := 0               ## PRIMER (bench): fight-start HELD chain, consumed turn 1
var lull := 0
var trap := 0
var last_fx: Array = []
var last_gene := ""
var pattern: Array = []
var windup_every := 0
var windup_intent: Dictionary = {}
var intent_i := 0
var break_need := 0
var break_progress := 0
var staggered := false
var scramble_pending := false
var split_done := false
var shot_used := false
var turn := 0
var bind := 0
var bind_on := false
var over := false
var busy := true
var sel := 0
var P: Dictionary = {}
var E: Dictionary = {}
var _uid := 0
var _msg := ""
var _modal := false
var _pattern_kind := ""
var _grows: Dictionary = {}        ## uid -> times expressed this fight
var _knot_next: Dictionary = {}    ## uid -> true: knotted next turn
var _hook_turn: Dictionary = {}
var _hook_fight: Dictionary = {}
var _hook_depth := 0
var _hook_running: Dictionary = {}
var _tut_order_due := false
var tut  ## Tutorial instance (untyped: dynamic member access)

# ------------------------------------------------------------------ presentation
var _juice: Script
var _cam: Camera3D
var _t := 0.0
var _hud: Control
var _p_bar: Control
var _e_bar: Control
var _tiles: Array = []
var _end_btn: Control
var _mut_btn: Control
var _shot_btn: Control
var _desc: RichTextLabel
var _banner: PanelContainer
var _banner_lbl: Label
var _fx_layer: CanvasLayer
var _intent_pop := 0.0
var _chain_flash := 0.0
var _icon_flash: Dictionary = {}


func _ready() -> void:
	UI.apply_stage_post()
	if Game.run.is_empty():
		Game.start_run(Game.args_region())
		Game.run["row"] = 0
		Game.run["col"] = 0
		Game.run["battle"] = {"kind": "fight"}
	region = String(Game.run.get("region", "wound"))
	if ResourceLoader.exists(JUICE_PATH):
		_juice = load(JUICE_PATH)
	tut = Tutorial.new()
	_setup_fight()
	_build_world()
	_build_ui()
	_refresh()
	_intro()


# ================================================================== setup

func _actor(side: String, nm: String, colony: int, mx: int) -> Dictionary:
	return {"side": side, "name": nm, "colony": colony, "max": mx, "film": 0, "grow": 0,
		"rot": [], "latent": [], "cluster": null}


func _new_entry(id: String) -> Dictionary:
	_uid += 1
	return {"id": id, "uid": _uid}


func _pick_enemy(re: Dictionary) -> String:
	match kind:
		"boss":
			return String(re.get("boss", "creeper"))
		"elite":
			var el = re.get("elite", [])
			if el is Array:
				var arr: Array = el
				return String(arr[randi() % arr.size()]) if not arr.is_empty() else "creeper"
			return String(el)
		_:
			var normals: Array = re.get("normal", ["creeper"])
			return String(normals[randi() % normals.size()])


func _setup_fight() -> void:
	var bt: Dictionary = Game.run.get("battle", {})
	kind = String(bt.get("kind", "fight"))
	from_event = bool(bt.get("event", false))
	var re: Dictionary = Cards.REGION_ENEMIES.get(region, Cards.REGION_ENEMIES["wound"])
	enemy_id = String(bt.get("enemy", ""))
	if enemy_id == "" or not Cards.ENEMIES.has(enemy_id):
		enemy_id = _pick_enemy(re)
	var ed: Dictionary = Cards.enemy(enemy_id)
	var growth: int = int(Game.run.get("growth", 1))
	var mult := 1.0 + 0.12 * (growth - 1) + 0.06 * Game.stage
	var col := int(round(float(ed["colony"]) * mult))
	if kind == "elite":
		col = int(round(col * 1.4))
	E = _actor("e", String(ed["name"]), col, col)
	if kind == "elite":
		E["grow"] = 1
	var tr: Dictionary = ed.get("trait", {})
	trait_id = String(tr.get("id", ""))
	trait_name = String(tr.get("name", ""))
	var pat = ed["pattern"]
	if pat is String:
		_pattern_kind = String(pat)
		if _pattern_kind == "mimic_last":
			pattern = Cards.mimic_pattern(Game.last_failed_strand)
		if pattern.is_empty():
			pattern = Cards.mimic_pattern(Game.run.get("strand", []))
	else:
		pattern = pat
	if pattern.is_empty():
		pattern = [{"id": "x_strike", "name": "STRIKE 5", "fx": [{"t": "dmg", "n": 5}]}]
	windup_every = int(ed.get("windup_every", 0))
	windup_intent = ed.get("windup", {})
	var pc: int = int(Game.run.get("colony", Game.START_COLONY))
	var pm: int = int(Game.run.get("max_colony", Game.START_COLONY))
	P = _actor("p", "CULTURE", pc, pm)
	strand = []
	for id in Game.run.get("strand", []):
		strand.append(_new_entry(String(id)))
	reader = 0
	bind_on = bool(Game.run.get("is_root", false)) and kind == "boss" and Game.graft_ready()


## Fray ≥ 5: two random non-junk genes overgrow. Returns how many did.
func _apply_fray() -> int:
	if int(Game.run.get("fray", 0)) < 5:
		return 0
	var cand: Array = []
	for i in strand.size():
		if not Cards.is_junk(String(strand[i]["id"])):
			cand.append(i)
	cand.shuffle()
	var n := mini(2, cand.size())
	for k in n:
		var idx: int = cand[k]
		strand[idx] = _new_entry("overgrowth")
	return n


func _build_world() -> void:
	var bd := Backdrop.new()
	add_child(bd)
	bd.setup(region, {"center": Vector3(3.8, 0, -2.0), "extent": Vector3(10, 5, 8), "floor_y": -0.9, "fog": 0.025})
	var pal: Dictionary = Cards.REGION_COLORS.get(region, Cards.REGION_COLORS["wound"])
	var floor_c: Color = pal["floor"]
	_platform(P_POS, 1.25, floor_c.lightened(0.25))
	_platform(E_POS, 2.2, floor_c.lightened(0.15))
	add_child(Retro.omni(Color("d0f0f0"), 4.0, 0.8, P_POS + Vector3(-0.8, 2.0, 1.2)))
	add_child(Retro.omni((pal["accent"] as Color).lerp(UI.C_GREEN, 0.5), 6.5, 1.4, E_POS + Vector3(0.5, 2.5, 1.0)))

	var pc := Cluster.new()
	pc.position = P_POS + Vector3(0, 0.06, 0)
	add_child(pc)
	pc.setup(Color("d8f0f4"), _cell_cap(P), 0.19, 0, 11)
	P["cluster"] = pc
	var boss := kind == "boss"
	var ec: Node3D = null
	if ResourceLoader.exists(CREATURES_PATH):
		var cs: Script = load(CREATURES_PATH)
		if cs != null and cs.can_instantiate():
			var made = cs.call("build", enemy_id, region, _cell_cap(E), kind == "elite", boss)
			if made is Node3D:
				ec = made
	if ec == null:
		var cl := Cluster.new()
		cl.position = E_POS + Vector3(0, 0.06, 0)
		var ecol := Color("58b848") if enemy_id != "core" else Color("3c9a34")
		if _pattern_kind != "":
			ecol = Color("88b878")
		add_child(cl)
		cl.setup(ecol, _cell_cap(E), 0.5 if boss else 0.44, 7 if boss else 4, hash(enemy_id),
			Color("2c6a24") if enemy_id != "core" else Color("1c4a18"))
		ec = cl
	else:
		add_child(ec)
	E["cluster"] = ec
	pc.set_count(0, false)
	ec.call("set_count", 0, false)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.position = CAM_POS
	add_child(_cam)
	_cam.look_at(CAM_LOOK)
	_cam.current = true


func _platform(pos: Vector3, r: float, col: Color) -> void:
	add_child(Retro.cyl(r, r * 1.05, 0.14, col, 8, pos))
	add_child(Retro.cyl(r * 0.78, r * 0.78, 0.02, col.darkened(0.25), 8, pos + Vector3(0, 0.075, 0)))
	add_child(Retro.cyl(r * 1.05, r * 0.8, 0.25, col.darkened(0.5), 8, pos + Vector3(0, -0.19, 0)))


func _cell_cap(a: Dictionary) -> int:
	return clampi(int(ceil(float(a["max"]) / 3.0)), 1, 40)


func _cells_for(a: Dictionary) -> int:
	var c: int = a["colony"]
	if c <= 0:
		return 0
	return clampi(int(ceil(float(c) * _cell_cap(a) / float(a["max"]))), 1, _cell_cap(a))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_e_bar = PixelBar.new()
	_e_bar.position = ENEMY_BOX.position + Vector2(28, 16)
	_e_bar.size = Vector2(80, 6)
	_hud.add_child(_e_bar)
	_p_bar = PixelBar.new()
	_p_bar.position = PLAYER_BOX.position + Vector2(28, 4)
	_p_bar.size = Vector2(80, 6)
	_hud.add_child(_p_bar)
	_e_bar.call("set_values", E["colony"], E["max"], true)
	_p_bar.call("set_values", P["colony"], P["max"], true)

	var dp := UI.panel(DESC_BOX, true)
	dp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dp.add_theme_stylebox_override("panel", UI.box_style(UI.C_THINK_BG, UI.C_ACCENT.darkened(0.3), 2, 3, Vector4(6, 2, 6, 1)))
	layer.add_child(dp)
	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.scroll_active = false
	_desc.fit_content = false
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc.custom_minimum_size = Vector2(DESC_BOX.size.x - 12, 29)
	_desc.add_theme_font_override("normal_font", UI.font)
	_desc.add_theme_font_size_override("normal_font_size", 8)
	_desc.add_theme_constant_override("line_separation", 2)
	_desc.add_theme_color_override("default_color", UI.C_THINK_FG)
	dp.add_child(_desc)

	_end_btn = _make_button("END", 0, _on_end_pressed)
	_mut_btn = _make_button("MUT", 1, _on_mut_pressed)
	_shot_btn = _make_button("SHOT", 2, _on_shot_pressed)
	for b in [_end_btn, _mut_btn, _shot_btn]:
		layer.add_child(b)

	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 12
	add_child(_fx_layer)
	var bl := CanvasLayer.new()
	bl.layer = 20
	add_child(bl)
	_banner = PanelContainer.new()
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.add_child(_banner)
	_banner_lbl = UI.label("", UI.C_INK)
	_banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_lbl)
	_hud.set_meta("layer", layer)


func _make_button(cap: String, row: int, cb: Callable) -> Control:
	var b := CardButton.new()
	b.caption = cap
	b.position = Vector2(BTN_X, CARD_Y + row * 14)
	b.size = Vector2(BTN_W, 12)
	b.pressed.connect(cb)
	return b


func _on_end_pressed() -> void:
	if _can_act():
		_end_turn()


func _on_mut_pressed() -> void:
	if _can_act():
		_mutate(sel)


func _on_shot_pressed() -> void:
	if _can_act():
		_inject()


## Tiles are rebuilt whenever the window size changes.
func _sync_tiles() -> void:
	var layer: CanvasLayer = _hud.get_meta("layer")
	while _tiles.size() > win.size():
		var t: Control = _tiles.pop_back()
		t.queue_free()
	while _tiles.size() < win.size():
		var cb := CardButton.new()
		var idx := _tiles.size()
		cb.pressed.connect(_on_tile_pressed.bind(idx))
		cb.hovered.connect(_on_tile_hovered.bind(idx))
		layer.add_child(cb)
		_tiles.append(cb)
	for i in _tiles.size():
		var r := _tile_rect(i)
		var t: Control = _tiles[i]
		t.position = r.position
		t.size = r.size


func _shown_read() -> int:
	if _sweep_now():
		return win.size()
	return mini(_read_n(), win.size())


func _tile_rect(i: int) -> Rect2:
	var n := maxi(1, win.size())
	var rn := _shown_read()
	var zg := 4 if rn < n else 0
	var w := mini(62, int(floor((TILE_AREA - 2.0 * (n - 1) - zg) / n)))
	var x := 2 + i * (w + 2) + (zg if i >= rn else 0)
	return Rect2(x, CARD_Y, w, CARD_H)


func _on_tile_pressed(i: int) -> void:
	if not _can_act():
		return
	if i >= win.size():
		return
	sel = i
	_express(i)


func _on_tile_hovered(i: int) -> void:
	if not _can_act() or i >= win.size() or sel == i:
		return
	sel = i
	_sfx("blip", 1.2)
	_refresh()


func _can_act() -> bool:
	return not busy and not over and not _modal and not UI.busy


# ================================================================== flow

func _intro() -> void:
	busy = true
	_sfx_call("drone", [region])
	var fr := _apply_fray()
	await _wait(0.3)
	(P["cluster"] as Node).call("set_count", _cells_for(P), true)
	(E["cluster"] as Node).call("set_count", _cells_for(E), true)
	await _wait(0.7)
	var med: Dictionary = Cards.REGION_MEDIUM.get(region, {})
	if not med.is_empty():
		_sfx("shift")
		_say_log("%s: %s" % [String(med.get("name", "")), String(med.get("desc", ""))])
		await _announce("MEDIUM: %s" % String(med.get("name", "")), "p", 0.9)
	var line := "%s BLOCKS THE STRAND." % E["name"]
	if kind == "boss":
		line = "%s. IT FILLS THE REGION." % E["name"]
	elif kind == "elite":
		line = "%s, SWOLLEN. IT HITS HARDER." % E["name"]
	await _announce(line, "e", 1.0)
	if trait_name != "":
		_say_log("%s: %s" % [trait_name, _trait_desc()])
		await _wait(0.6)
	if _pattern_kind == "mimic_last":
		_say_log("It moves like your last culture.")
		await _wait(0.9)
	elif _pattern_kind == "mimic_run":
		_say_log("It is reading your Strand back to you.")
		await _wait(0.9)
	if fr > 0:
		UI.toast("FRAY: %d GENES OVERGROW" % fr, UI.C_WARN)
		await _wait(0.6)
	if Game.stage >= 4:
		_say_log("You can feel what it means to do next.")
		await _wait(0.8)
	if bind_on:
		await UI.say(["BIND: hold the core at 40% or less and reach CHAIN x4, three turns running."], "see")
	primer = clampi(int(Game.run.get("primer", 0)), 0, 5)
	if primer > 0:
		var pc := primer * BenchOps.PRIMER_COST
		P["colony"] = maxi(1, int(P["colony"]) - pc)
		_sync(P)
		_float(P, "PRIMER -%d" % pc, UI.C_BAD)
		_say_log("PRIMER: my first gene opens at CHAIN x%d." % primer)
	await _run_hooks("fight_start")
	if await _check_end():
		return
	await _player_turn_start()


func _trait_desc() -> String:
	var ed: Dictionary = Cards.enemy(enemy_id)
	var tr: Dictionary = ed.get("trait", {})
	return String(tr.get("desc", ""))


func _player_turn_start() -> void:
	if over:
		return
	busy = true
	turn += 1
	_hook_turn = {}
	lull = 0
	best_chain = 0
	# Film clears (CLOTTING: half).
	var pf: int = P["film"]
	P["film"] = pf / 2 if region == "wound" else 0
	await _tick_status(P, E)
	if await _check_end():
		return
	if region == "rivers" and _surge():
		_float(P, "SURGE: +1 READ", GeneArt.C_FILM)
	elif region == "hollow":
		_float(P, "INHALE" if _inhale() else "EXHALE", UI.C_THINK_FG)
	# Charge and passives.
	var pas_charge := 0
	var pas_film := 0
	for se in strand:
		var c: Dictionary = Cards.card(String(se["id"]))
		var pd: Dictionary = c.get("passive", {})
		pas_charge += int(pd.get("charge", 0))
		pas_film += int(pd.get("film", 0))
	charge = maxi(0, 3 + pas_charge + charge_next + Adapt.mod("charge"))
	charge_next = 0
	if pas_film > 0:
		_gain_film(P, _film_val(P, pas_film))
	splices = maxi(0, 1 + Adapt.mod("splice"))
	chain = 0
	last_slot = -1
	exp_count = 0
	promote_from = -1
	free_next = false
	shot_used = false
	# Knots from last enemy turn.
	for e in win:
		(e as Dictionary)["knotted"] = false
		(e as Dictionary)["marked"] = ""
	if scramble_pending:
		scramble_pending = false
		_shuffle_unspent()
		_float(P, "SCRAMBLED", UI.C_WARN)
	_fill_window()
	for e in win:
		var ed: Dictionary = e
		if _knot_next.has(int(ed["uid"])):
			ed["knotted"] = true
	_knot_next = {}
	if primer > 0:
		_prime(primer)
		primer = 0
	_apply_hold()
	sel = clampi(sel, 0, maxi(0, win.size() - 1))
	_reveal_intent()
	_refresh()
	await _run_hooks("turn_start")
	if await _check_end():
		return
	await _tutorial_turn()
	busy = false
	_refresh()


func _surge() -> bool:
	return region == "rivers" and turn % 2 == 0


func _inhale() -> bool:
	return region == "hollow" and turn % 2 == 1


func _exhale() -> bool:
	return region == "hollow" and turn % 2 == 0


func _tutorial_turn() -> void:
	if not tut.active:
		return
	if turn == 1:
		await tut.show_step("window")
		await tut.show_step("read")
		await tut.show_step("link")
	elif turn == 2:
		await tut.show_step("splice")
	if _has_marks():
		await tut.show_step("marked")
	if break_need > 0:
		await tut.show_step("break")
	if (Game.run.get("boosters", []) as Array).size() > 0:
		await tut.show_step("boost")
	var mode_live := false
	for e in win:
		var c: Dictionary = Cards.card(String((e as Dictionary)["id"]))
		if c.has("deep") or c.has("lone"):
			mode_live = true
	if mode_live or _tut_order_due:
		_tut_order_due = false
		await tut.show_step("order")


func _has_marks() -> bool:
	for e in win:
		if String((e as Dictionary)["marked"]) != "":
			return true
	return false


# ------------------------------------------------------------------ window

func _win_size() -> int:
	return maxi(1, 5 + Adapt.mod("window"))


func _read_n() -> int:
	var n := 3 + Adapt.mod("read")
	if _surge():
		n += 1
	return maxi(1, n)


func _in_window(uid: int) -> bool:
	for e in win:
		if int((e as Dictionary)["uid"]) == uid:
			return true
	return false


## Draws up to `count` genes from the strand at the pointer (never a uid already shown).
func _draw(count: int) -> int:
	var got := 0
	var tries := strand.size()
	while got < count and tries > 0 and not strand.is_empty():
		tries -= 1
		reader = reader % strand.size()
		var se: Dictionary = strand[reader]
		reader = (reader + 1) % strand.size()
		var uid: int = se["uid"]
		if _in_window(uid):
			continue
		win.append({"id": String(se["id"]), "uid": uid, "spent": false, "marked": "", "knotted": false})
		got += 1
	return got


func _fill_window() -> void:
	_draw(_win_size() - win.size())
	_sync_tiles()


func _shuffle_unspent() -> void:
	var idx: Array = []
	var vals: Array = []
	for i in win.size():
		if not bool(win[i]["spent"]):
			idx.append(i)
			vals.append(win[i])
	vals.shuffle()
	for k in idx.size():
		var i: int = idx[k]
		win[i] = vals[k]


func _invert() -> void:
	var idx: Array = []
	var vals: Array = []
	for i in win.size():
		if not bool(win[i]["spent"]):
			idx.append(i)
			vals.append(win[i])
	vals.reverse()
	for k in idx.size():
		var i: int = idx[k]
		win[i] = vals[k]
	_float(P, "INVERTED", UI.C_ACCENT)
	_refresh()


func _strand_index(uid: int) -> int:
	for i in strand.size():
		if int(strand[i]["uid"]) == uid:
			return i
	return -1


## Removes a gene from the fight strand (and the window). Returns its id or "".
func _strand_remove(uid: int) -> String:
	var i := _strand_index(uid)
	var id := ""
	if i >= 0:
		id = String(strand[i]["id"])
		strand.remove_at(i)
		if i < reader:
			reader -= 1
		reader = 0 if strand.is_empty() else posmod(reader, strand.size())
	for s in range(win.size() - 1, -1, -1):
		if int(win[s]["uid"]) == uid and not bool(win[s]["spent"]):
			if id == "":
				id = String(win[s]["id"])
			win.remove_at(s)
			if last_slot >= s:
				last_slot -= 1
	_sync_tiles()
	return id


## Junk planted at the draw pointer: it shows up at the next fill.
func _plant(n: int, id: String) -> void:
	for k in n:
		var e := _new_entry(id)
		if strand.is_empty():
			strand.append(e)
			reader = 0
		else:
			strand.insert(reader % strand.size(), e)
	_float(P, "+%d %s" % [n, Cards.card(id)["name"]], GeneArt.C_JUNK)
	_say_log("%s plants %d %s in your Strand." % [E["name"], n, Cards.card(id)["name"]])
	if E["cluster"] != null and (E["cluster"] as Node).has_method("attack_anim"):
		(E["cluster"] as Node).call("attack_anim", "plant")
	_refresh()
	await _wait(0.4)


func _uproot() -> void:
	var cand: Array = []
	for e in strand:
		if not Cards.is_junk(String(e["id"])):
			cand.append(e)
	if cand.is_empty():
		_say_log("Nothing left to uproot.")
		return
	var e: Dictionary = cand[randi() % cand.size()]
	var c: Dictionary = Cards.card(String(e["id"]))
	_strand_remove(int(e["uid"]))
	_say_log("%s torn out of your Strand." % c["name"])
	UI.flash(Color(0.6, 0.2, 0.2), 0.2)
	_refresh()
	await _wait(0.5)
	await _pact(c)


func _pact(c: Dictionary) -> void:
	if c.has("pact"):
		_say_log("PACT broken: lose %d." % int(c["pact"]))
		await _lose(P, int(c["pact"]), "PACT")


func _hop(ctx: Dictionary, ahead: int) -> void:
	var uid: int = int(ctx.get("uid", -1))
	var n := strand.size()
	var i := _strand_index(uid)
	if i < 0 or n < 2:
		return
	var t := (i + ahead) % n
	if t == i:
		return
	var old: Dictionary = strand[t]
	var ne := _new_entry(String(ctx.get("id", "")))
	strand[t] = ne
	for s in win.size():
		if int(win[s]["uid"]) == int(old["uid"]):
			win[s] = {"id": String(ne["id"]), "uid": int(ne["uid"]), "spent": false, "marked": "", "knotted": false}
	_say_log("HOP: lands on %s %d slots ahead." % [Cards.card(String(old["id"]))["name"], ahead])
	_refresh()


func _ledger() -> void:
	var it := _cur_intent()
	if it.is_empty():
		return
	var ld: Array = Game.run.get("ledger", [])
	Game.run["ledger"] = ld
	if ld.has(it["id"]):
		_say_log("%s is already recorded." % it["name"])
	elif ld.size() >= 3:
		_say_log("LEDGER full.")
	else:
		ld.append(it["id"])
		_float(E, "RECORDED", UI.C_ACCENT)
		_say_log("%s recorded. It will fizzle all run." % it["name"])
		for e in win:
			(e as Dictionary)["marked"] = ""
		if break_need > 0:
			break_need = 0
			_creature("windup", [false])
	_refresh()


# ------------------------------------------------------------------ intent

func _cur_intent() -> Dictionary:
	if pattern.is_empty():
		return {}
	if windup_every > 0 and not windup_intent.is_empty() and (intent_i + 1) % windup_every == 0:
		return windup_intent
	var it: Dictionary = pattern[intent_i % pattern.size()]
	return it


func _recorded(it: Dictionary) -> bool:
	return (Game.run.get("ledger", []) as Array).has(it.get("id", ""))


func _fx_has(fx: Array, t: String) -> bool:
	for f in fx:
		var d: Dictionary = f
		if String(d.get("t", "")) == t:
			return true
		if d.has("fx") and _fx_has(d["fx"], t):
			return true
	return false


func _sweep_now() -> bool:
	var it := _cur_intent()
	return not it.is_empty() and not _recorded(it) and _fx_has(it.get("fx", []), "sweep")


func _intent_is_windup() -> bool:
	return break_need > 0 and not staggered


func _reveal_intent() -> void:
	var it := _cur_intent()
	break_progress = 0
	staggered = false
	break_need = 0
	_intent_pop = 1.0
	if it.is_empty() or _recorded(it):
		return
	break_need = int(it.get("break", 0))
	if break_need > 0:
		_sfx("windup")
		_creature("windup", [true])
	for f in it.get("fx", []):
		var d: Dictionary = f
		match String(d.get("t", "")):
			"gnaw":
				_mark("gnaw", int(d.get("n", 1)))
			"knot":
				_mark("knot", int(d.get("n", 1)))
			"sever":
				_mark("sever", int(d.get("n", 1)))


func _mark(what: String, n: int) -> void:
	var good: Array = []
	var junk: Array = []
	var rn := mini(_read_n(), win.size())
	for i in win.size():
		var e: Dictionary = win[i]
		if bool(e["spent"]) or String(e["marked"]) != "":
			continue
		if what == "knot" and i < rn:
			continue
		if what == "sever" and i >= rn:
			continue
		if what == "sever" and Cards.is_junk(String(e["id"])):
			continue
		if Cards.is_junk(String(e["id"])):
			junk.append(i)
		else:
			good.append(i)
	if what == "knot" and good.is_empty() and junk.is_empty():
		for i in win.size():
			if not bool(win[i]["spent"]) and String(win[i]["marked"]) == "":
				good.append(i)
	good.shuffle()
	junk.shuffle()
	var cand: Array = good + junk
	for k in mini(n, cand.size()):
		var i: int = cand[k]
		win[i]["marked"] = what
	if not cand.is_empty():
		_sfx("mark")


## Rough damage of the current intent (for MIRROR and the intent box).
func _intent_damage() -> int:
	var it := _cur_intent()
	if it.is_empty() or _recorded(it) or staggered:
		return 0
	return _fx_damage(it.get("fx", []), E)


func _fx_damage(fx: Array, src: Dictionary) -> int:
	var tot := 0
	for f in fx:
		var d: Dictionary = f
		match String(d.get("t", "")):
			"dmg":
				tot += _dmg_val(src, int(d.get("n", 0))) * maxi(1, int(d.get("k", 1)))
			"drain", "stagger_dmg":
				tot += _dmg_val(src, int(d.get("n", 0)))
			"dmg_count":
				tot += _dmg_val(src, int(d.get("per", 0)) * exp_count)
	return tot


# ================================================================== express

func _cost_of(slot: int) -> int:
	if slot < 0 or slot >= win.size():
		return 0
	var e: Dictionary = win[slot]
	var c: Dictionary = Cards.card(String(e["id"]))
	var cost: int = int(c.get("cost", 1))
	if bool(e["knotted"]):
		cost += 1
	if free_next:
		cost = 0
	return maxi(0, cost)


func _cant_express(slot: int) -> String:
	if slot < 0 or slot >= win.size():
		return "Nothing there."
	var e: Dictionary = win[slot]
	var c: Dictionary = Cards.card(String(e["id"]))
	if bool(e["spent"]):
		return "Already expressed."
	if String(c.get("kind", "gene")) == "passive":
		return "Passive. It works from the Strand."
	if bool(c.get("unplayable", false)) or String(c.get("kind", "")) == "junk" and (c.get("fx", []) as Array).is_empty():
		return "Junk. It does nothing. Mutate it."
	if _cost_of(slot) > charge:
		return "Not enough Charge."
	return ""


## LINKED: right after the last expressed gene (BRIDGE also across one gap), or the HELD gene
## when nothing has been expressed yet this turn. A SEVERED gene is never linked into.
func _linked(slot: int) -> bool:
	if chain <= 0 or slot < 0 or slot >= win.size():
		return false
	var e: Dictionary = win[slot]
	if String(e["marked"]) == "sever":
		return false
	if last_slot < 0:
		return int(e["uid"]) == carry_uid
	if slot == last_slot + 1:
		return true
	return slot == last_slot + 2 and int(Cards.card(String(e["id"])).get("reach", 1)) + Adapt.mod("reach") >= 2


## Chain length at which DEEP takes over (HIVE MIND lowers it to x2).
func _deep_at() -> int:
	return maxi(2, 3 - Adapt.mod("deep_early"))


## "deep"/"lone" when that mode replaces the card's fx for this expression.
func _mode_for(c: Dictionary, linked: bool, next_chain: int) -> String:
	if linked and next_chain >= _deep_at() and c.has("deep"):
		return "deep"
	if not linked and c.has("lone"):
		return "lone"
	return ""


func _gene_fx(id: String, linked: bool, first: bool, next_chain: int) -> Array:
	var c: Dictionary = Cards.card(id)
	var m := _mode_for(c, linked, next_chain)
	var out: Array = []
	var base: Array = c.get(m, []) if m != "" else c.get("fx", [])
	out.append_array(base)
	if first:
		out.append_array(c.get("first", []))
	if linked:
		out.append_array(c.get("link", []))
	return out.duplicate(true)


## A slot's fx right now. TRACE resolves to the base fx of the gene on its left (spent or not).
func _slot_fx(slot: int, linked: bool, first: bool, next_chain: int) -> Array:
	var out := _gene_fx(String(win[slot]["id"]), linked, first, next_chain)
	if not _fx_has(out, "trace"):
		return out
	var res: Array = []
	for f in out:
		if String((f as Dictionary).get("t", "")) != "trace":
			res.append(f)
		elif slot > 0:
			var lid := String(win[slot - 1]["id"])
			var lfx: Array = Cards.card(lid).get("fx", [])
			if not Cards.is_junk(lid) and not _fx_has(lfx, "trace"):
				res.append_array(lfx.duplicate(true))
	return res


func _bonus_for(slot: int, linked: bool, next_chain: int) -> int:
	var e: Dictionary = win[slot]
	var c: Dictionary = Cards.card(String(e["id"]))
	var b := 0
	if linked:
		b += (next_chain - 1) * (1 + Adapt.mod("link_bonus") + (1 if region == "root" else 0))
	var g: int = int(c.get("grows", 0))
	if g > 0:
		b += g * int(_grows.get(int(e["uid"]), 0))
	return maxi(0, b)

## Adds `add` and multiplies by `mult` (ceil) on the numeric keys of each fx.
func _scaled(fx: Array, add: int, mult: float) -> Array:
	var out: Array = []
	for f in fx:
		var d: Dictionary = (f as Dictionary).duplicate(true)
		var t: String = String(d.get("t", ""))
		if NUM_KEYS.has(t):
			for k in NUM_KEYS[t]:
				var key: String = k
				if d.has(key):
					var v: int = int(d[key])
					if v > 0:
						d[key] = int(ceil((v + add) * mult))
		if d.has("fx") and d["fx"] is Array:
			d["fx"] = _scaled(d["fx"], add, mult)
		out.append(d)
	return out


func _band_frac() -> float:
	var fray: int = int(Game.run.get("fray", 0))
	var pct := maxf(10.0, 30.0 - 4.0 * fray) + float(Adapt.mod("band"))
	return clampf(pct / 100.0, 0.05, 0.9)


func _express(slot: int) -> void:
	var why := _cant_express(slot)
	if why != "":
		_sfx("error")
		_say_log(why)
		if slot >= 0 and slot < _tiles.size():
			_juice_call("shake", [_tiles[slot], 2.0, 0.15])
		return
	busy = true
	var e: Dictionary = win[slot]
	var id: String = e["id"]
	var uid: int = e["uid"]
	var c: Dictionary = Cards.card(id)
	var cost := _cost_of(slot)
	charge -= cost
	free_next = false
	var linked := _linked(slot)
	var next_chain := chain + 1 if linked else 1
	var snap := 0 if linked or chain < 2 else chain
	var first := exp_count == 0
	var bonus := _bonus_for(slot, linked, next_chain)
	var times := 1
	if promote_from >= 0 and slot == promote_from + 1:
		times += 1
		_float(P, "PROMOTED", UI.C_ACCENT, Vector2(0, -10))
	if exp_count == 2 and Adapt.mod("third") > 0:
		times += 1
		_float(P, "3RD: TWICE", UI.C_ACCENT, Vector2(0, -20))
	promote_from = -1
	chain = next_chain
	best_chain = maxi(best_chain, chain)
	carry_uid = -1
	e["spent"] = true
	e["marked"] = ""
	last_slot = slot
	exp_count += 1
	last_gene = id
	_sfx("express")
	_refresh()
	# The read bar: press in the band for CLEAN.
	var clean := Cards.is_green(id)
	if not clean:
		var at := Vector2(-1, -1)
		if slot < _tiles.size():
			at = (_tiles[slot] as Control).position + Vector2(0, -26)
		clean = await ReadBar.new().run(self, _band_frac(), "READ", at)
	var mult := 1.5 if clean else 1.0
	if clean:
		_sfx("clean")
		_pop_ui(_tile_center(slot) + Vector2(0, -14), "CLEAN!", UI.C_GREEN, 1)
	if linked and chain >= 2:
		_sfx("link", 1.0 + 0.12 * chain)
		_pop_ui(_tile_center(slot) + Vector2(0, -24), "LINK x%d!" % chain, UI.C_ACCENT, 2 if chain >= 3 else 1)
	var fx := _scaled(_slot_fx(slot, linked, first, next_chain), bonus, mult)
	var tgt := _fx_target_is_enemy(fx)
	await _fly_card(slot, E if tgt else P)
	var title := String(c["name"])
	if times > 1:
		title += " x%d" % times
	await _announce(title, "p", 0.35)
	var ctx := {"slot": slot, "uid": uid, "id": id, "breaker": bool(c.get("breaker", false))}
	for k in times:
		if _dead():
			break
		await _apply(fx, P, E, ctx)
	_grows[uid] = int(_grows.get(uid, 0)) + 1
	last_fx = fx
	if trait_id == "spines" and not _dead() and _damages(fx):
		await _lose(P, 1, "SPINES")
	if snap > 0 and not _dead():
		await _snap(snap)
	if bool(c.get("burn", false)):
		_strand_remove_burn(uid)
	if Cards.is_green(id):
		Game.run["uptake"] = int(Game.run.get("uptake", 0)) + 1
		UI.flash(Color(0.44, 0.85, 0.31), 0.25)
		UI.toast("UPTAKE +1", Color("287818"))
	await _run_hooks("express")
	if linked and chain >= 2:
		await _run_hooks("link")
	if linked and chain >= _deep_at():
		await _run_hooks("deep")
	elif not linked:
		await _run_hooks("lone")
	if clean:
		await _run_hooks("clean")
	if await _check_end():
		return
	_auto_select()
	busy = false
	_refresh()


## BURN: gone from the fight strand; the spent tile keeps its slot until READ.
func _strand_remove_burn(uid: int) -> void:
	var i := _strand_index(uid)
	if i < 0:
		return
	strand.remove_at(i)
	if i < reader:
		reader -= 1
	reader = 0 if strand.is_empty() else posmod(reader, strand.size())
	_float(P, "BURNED", UI.C_WARN, Vector2(0, -20))


func _auto_select() -> void:
	if sel < win.size() and not bool(win[sel]["spent"]):
		return
	for i in range(sel, win.size()):
		if not bool(win[i]["spent"]):
			sel = i
			return
	for i in win.size():
		if not bool(win[i]["spent"]):
			sel = i
			return


func _damages(fx: Array) -> bool:
	for f in fx:
		var d: Dictionary = f
		if DAMAGING.has(String(d.get("t", ""))):
			return true
		if d.has("fx") and d["fx"] is Array and _damages(d["fx"]):
			return true
	return false


func _fx_target_is_enemy(fx: Array) -> bool:
	return _damages(fx) or _fx_has(fx, "rot") or _fx_has(fx, "lull")


func _dead() -> bool:
	return over or int(E["colony"]) <= 0 or int(P["colony"]) <= 0


# ------------------------------------------------------------------ fx

func _dmg_val(src: Dictionary, n: int) -> int:
	if n <= 0:
		return 0
	var v := n + int(src["grow"])
	if String(src["side"]) == "p":
		v += Adapt.mod("dmg")
	else:
		v -= lull
	if _exhale():
		v = int(ceil(v * 1.5))
	return maxi(0, v)


func _film_val(src: Dictionary, n: int) -> int:
	var v := n
	if String(src["side"]) == "p":
		v += Adapt.mod("film")
	if _inhale():
		v = int(ceil(v * 1.5))
	return maxi(0, v)


## Expressing out of order while CHAIN is x2+ SNAPS it. Some enemies answer that.
func _snap(n: int) -> void:
	_float(P, "SNAP x%d" % n, UI.C_WARN, Vector2(0, -16))
	_sfx("mark")
	match trait_id:
		"riposte":
			await _lose(P, 3, "RIPOSTE")
		"discord":
			_heal(E, 5)
			_float(E, "DISCORD", C_SEVER, Vector2(0, -12))
	await _run_hooks("snap")


func _apply(fx: Array, src: Dictionary, dst: Dictionary, ctx: Dictionary) -> void:
	var mine := String(src["side"]) == "p"
	var side := String(src["side"])
	for f0 in fx:
		if _dead():
			return
		var f: Dictionary = f0
		var t: String = String(f.get("t", ""))
		var n: int = int(f.get("n", 0))
		match t:
			"dmg":
				var k: int = maxi(1, int(f.get("k", 1)))
				for i in k:
					if _dead():
						break
					await _hit(src, dst, _dmg_val(src, n), ctx)
			"stagger_dmg":
				var v := n
				if mine and _intent_is_windup():
					v *= 2
					_float(dst, "STAGGER x2", UI.C_WARN, Vector2(0, -12))
				await _hit(src, dst, _dmg_val(src, v), ctx)
			"drain":
				if not mine and await _tripped("DRAIN"):
					continue
				var thr := await _hit(src, dst, _dmg_val(src, n), ctx)
				if thr > 0:
					_heal(src, thr)
			"film":
				_gain_film(src, _film_val(src, n))
			"heal":
				_heal(src, n)
			"self":
				await _lose(src, n, "SELF")
			"grow":
				src["grow"] = int(src["grow"]) + n
				_float(src, "GROW +%d" % n, UI.C_WARN)
				_sfx("tick")
			"rot":
				(dst["rot"] as Array).append({"n": n, "t": int(f.get("turns", 3))})
				_float(dst, "ROT %d" % n, ROT_COL)
				_sfx("rot")
			"lull":
				if mine:
					lull += n
					_float(dst, "LULLED -%d" % n, UI.C_ACCENT)
			"chain":
				if mine:
					chain += n
					best_chain = maxi(best_chain, chain)
					_float(P, "CHAIN x%d" % chain, C_HI)
					_chain_flash = 1.0
			"prime":
				if mine:
					if last_slot < 0 and (carry_uid < 0 or chain <= 0):
						_prime(n)
						_apply_hold()
					else:
						chain += n
						_float(P, "CHAIN x%d" % chain, C_HI)
					best_chain = maxi(best_chain, chain)
					_chain_flash = 1.0
			"unmark":
				if mine:
					var cleared := 0
					for e in win:
						if String((e as Dictionary)["marked"]) != "":
							(e as Dictionary)["marked"] = ""
							cleared += 1
					_float(P, "MARKS CLEARED %d" % cleared, UI.C_ACCENT)
			"dmg_count":
				var cnt := maxi(0, exp_count - 1) if mine else 0
				_float(src, "COUNT %d" % cnt, C_HI, Vector2(0, -12))
				if cnt > 0:
					await _hit(src, dst, _dmg_val(src, int(f.get("per", 0)) * cnt), ctx)
			"latent":
				(dst["latent"] as Array).append({"n": n, "t": int(f.get("turns", 2))})
				_float(dst, "LATENT %d" % n, GeneArt.C_DMG)
			"charge":
				if mine:
					charge += n
					_float(P, "CHARGE +%d" % n, UI.C_WARN)
			"charge_next":
				if mine:
					charge_next += n
					_float(P, "NEXT TURN +%d" % n, UI.C_WARN)
			"free_next":
				if mine:
					free_next = true
					_float(P, "NEXT FREE", UI.C_ACCENT)
			"promote":
				if mine:
					promote_from = int(ctx.get("slot", -1))
			"cap":
				if mine:
					var per: int = int(f.get("per", 1))
					var amt := per * maxi(1, chain)
					var what: String = String(f.get("what", "dmg"))
					_pop_ui(_tile_center(int(ctx.get("slot", 0))) + Vector2(0, -24), "CAP x%d" % maxi(1, chain), UI.C_ACCENT, 1)
					if what == "film":
						_gain_film(P, _film_val(P, amt))
					elif what == "heal":
						_heal(P, amt)
					else:
						await _hit(src, dst, _dmg_val(src, amt), ctx)
					chain = 0
					carry_uid = -1
			"splice":
				if mine:
					splices += n
					_float(P, "SPLICE +%d" % n, UI.C_ACCENT)
			"invert":
				if mine:
					_invert()
			"pull":
				if mine:
					var got := _draw(n)
					_sync_tiles()
					_float(P, "PULL %d" % got, UI.C_ACCENT)
					_refresh()
			"mirror":
				var mv := _intent_damage()
				_gain_film(src, _film_val(src, mv))
			"fray":
				if mine:
					Game.run["fray"] = maxi(0, int(Game.run.get("fray", 0)) + n)
					_float(P, "FRAY %+d" % n, UI.C_WARN)
			"clear":
				if mine and ctx.has("uid"):
					_strand_remove_burn(int(ctx["uid"]))
					_float(P, "CLEARED", UI.C_ACCENT)
			"hop":
				if mine:
					_hop(ctx, int(f.get("ahead", 1)))
			"ledger":
				if mine:
					_ledger()
			"tripwire":
				if mine:
					trap += 1
					_float(src, "TRAP SET", UI.C_WARN)
			"echo":
				if not bool(ctx.get("echo", false)) and not last_fx.is_empty():
					var c2 := ctx.duplicate()
					c2["echo"] = true
					_float(src, "ECHO", UI.C_ACCENT)
					await _apply(last_fx, src, dst, c2)
			"plant":
				if not mine:
					if await _tripped("PLANT"):
						continue
					await _plant(maxi(1, n), String(f.get("id", "overgrowth")))
			"uproot":
				if not mine:
					if await _tripped("UPROOT"):
						continue
					await _uproot()
			"scramble":
				if not mine:
					scramble_pending = true
					_float(P, "SCRAMBLE NEXT", UI.C_WARN)
			"mimic_last":
				if not mine and last_gene != "" and not bool(ctx.get("mimic", false)):
					var pat: Array = Cards.mimic_pattern([last_gene])
					if not pat.is_empty():
						var it: Dictionary = pat[0]
						_say_log("It copies %s." % Cards.card(last_gene)["name"])
						await _announce("COPIES %s" % Cards.card(last_gene)["name"], "e", 0.5)
						var c3 := ctx.duplicate()
						c3["mimic"] = true
						await _apply(it.get("fx", []), src, dst, c3)
			"gnaw", "knot", "sweep":
				pass
		_refresh()


func _tripped(what: String) -> bool:
	if trap <= 0:
		return false
	trap -= 1
	_say_log("TRIPWIRE snaps. %s cancelled." % what)
	await _announce("TRIPWIRE! %s CANCELLED" % what, "p", 0.6)
	await _lose(P, 3, "TRAP")
	return true


# ------------------------------------------------------------------ damage

## Attack hit: BREAK counts raw damage; Film absorbs first. Returns what got through.
func _hit(src: Dictionary, dst: Dictionary, n: int, ctx: Dictionary) -> int:
	if _dead():
		return 0
	var sc: Node3D = src["cluster"]
	var dc: Node3D = dst["cluster"]
	if n <= 0:
		_float(dst, "0", UI.C_DIM)
		return 0
	if not bool(ctx.get("nolunge", false)) and sc != null and dc != null:
		sc.call("lunge", dc.position, 0.8)
		if String(src["side"]) == "e" and sc.has_method("attack_anim"):
			sc.call("attack_anim", "drain" if bool(ctx.get("drain", false)) else "dmg")
	await _wait(0.1)
	if String(src["side"]) == "p" and break_need > 0 and not staggered:
		break_progress += n * (2 if bool(ctx.get("breaker", false)) else 1)
		_refresh()
		if break_progress >= break_need:
			await _do_break()
	var absorbed := mini(int(dst["film"]), n)
	dst["film"] = int(dst["film"]) - absorbed
	var through := n - absorbed
	if absorbed > 0:
		_float(dst, "-%d FILM" % absorbed, GeneArt.C_FILM, Vector2(0, -12))
		_sfx("film", 0.8)
	if through > 0:
		dst["colony"] = maxi(0, int(dst["colony"]) - through)
		_float(dst, "-%d" % through, UI.C_BAD if String(dst["side"]) == "p" else Color.WHITE)
		_sfx("hit_s" if through < 5 else ("hit_m" if through < 12 else "hit_l"), randf_range(0.92, 1.08))
		_juice_call("hitstop", [self, clampf(0.02 + through * 0.005, 0.02, 0.12)])
		_juice_call("shake", [_cam, clampf(0.04 + through * 0.012, 0.04, 0.3), 0.25])
		if dc != null:
			dc.call("flash", Color(1, 0.4, 0.4) if String(dst["side"]) == "p" else Color.WHITE)
			if sc != null:
				dc.call("recoil", sc.position)
			if _juice != null:
				_juice_call("burst", [self, dc.position + Vector3(0, 0.8, 0), GeneArt.C_DMG, mini(6 + through, 24), 2.5])
		if String(dst["side"]) == "p":
			_sfx("hurt")
			if through >= 6:
				UI.flash(Color(0.85, 0.2, 0.2), 0.18)
			if UI.has_method("pulse"):
				UI.pulse(UI.C_BAD, clampf(through / 12.0, 0.2, 0.8))
	_sync(dst)
	if through > 0:
		await _after_hurt(dst)
	await _wait(0.22)
	return through


## Direct loss (rot, self, pact, trap, spines): ignores Film.
func _lose(a: Dictionary, n: int, why: String) -> void:
	if n <= 0 or over:
		return
	a["colony"] = maxi(0, int(a["colony"]) - n)
	_float(a, "%s -%d" % [why, n], ROT_COL if why == "ROT" else UI.C_BAD)
	_sfx("rot" if why == "ROT" else "hurt", 0.9)
	var cl: Node3D = a["cluster"]
	if cl != null:
		cl.call("flash", ROT_COL if why == "ROT" else UI.C_BAD)
	_sync(a)
	await _after_hurt(a)
	await _wait(0.3)


func _after_hurt(a: Dictionary) -> void:
	if String(a["side"]) == "e":
		if trait_id == "split" and not split_done and int(E["colony"]) > 0 and int(E["colony"]) * 2 < int(E["max"]):
			split_done = true
			E["film"] = int(E["film"]) + 12
			_float(E, "SPLITS +12 FILM", GeneArt.C_FILM, Vector2(0, -20))
			_say_log("It splits. The halves harden.")
	elif int(P["colony"]) > 0:
		await _run_hooks("hurt")


func _heal(a: Dictionary, n: int) -> void:
	if n <= 0:
		return
	var before: int = a["colony"]
	a["colony"] = mini(int(a["max"]), before + n)
	var got: int = int(a["colony"]) - before
	if got > 0:
		_float(a, "+%d" % got, UI.C_GREEN)
		_sfx("heal")
		var cl: Node3D = a["cluster"]
		if cl != null:
			cl.call("flash", UI.C_GREEN)
	_sync(a)


func _gain_film(a: Dictionary, n: int) -> void:
	if n <= 0:
		return
	a["film"] = int(a["film"]) + n
	_float(a, "+%d FILM" % n, GeneArt.C_FILM, Vector2(0, -12))
	_sfx("film")
	var cl: Node3D = a["cluster"]
	if cl != null:
		cl.call("flash", GeneArt.C_FILM)
	_refresh()


func _sync(a: Dictionary) -> void:
	if String(a["side"]) == "p":
		Game.run["colony"] = int(a["colony"])
		_p_bar.call("set_values", a["colony"], a["max"])
		var frac := float(a["colony"]) / maxf(1.0, float(a["max"]))
		_sfx_call("heartbeat", [1.0 + (0.3 - frac) * 3.0 if frac < 0.3 and frac > 0.0 else 0.0])
	else:
		_e_bar.call("set_values", a["colony"], a["max"])
	var cl: Node = a["cluster"]
	if cl != null:
		cl.call("set_count", _cells_for(a))
	_refresh()


func _do_break() -> void:
	staggered = true
	_sfx("break")
	_sfx("stagger", 0.9)
	var ec: Node3D = E["cluster"]
	_juice_call("shake", [_cam, 0.35, 0.4])
	_juice_call("hitstop", [self, 0.12])
	if ec != null:
		_juice_call("burst", [self, ec.position + Vector3(0, 1.0, 0), UI.C_WARN, 24, 3.5])
		if ec.has_method("stagger"):
			ec.call("stagger")
		elif ec.has_method("windup"):
			ec.call("windup", false)
	UI.flash(Color(1.0, 0.85, 0.4), 0.2)
	_pop_ui(Vector2(INTENT_BOX.position.x + 60, INTENT_BOX.position.y + 4), "BREAK!", UI.C_WARN, 2)
	_say_log("BROKEN. It staggers and loses its turn.")
	_refresh()
	await _run_hooks("break")


## Start-of-turn ticks for `a`: rot (ignores Film) then latent sets (hit through Film).
func _tick_status(a: Dictionary, other: Dictionary) -> void:
	var keep: Array = []
	for r in a["rot"]:
		var rd: Dictionary = r
		if _dead():
			return
		await _lose(a, int(rd["n"]), "ROT")
		rd["t"] = int(rd["t"]) - 1
		if int(rd["t"]) > 0:
			keep.append(rd)
	a["rot"] = keep
	var keep2: Array = []
	for l in a["latent"]:
		var ld: Dictionary = l
		ld["t"] = int(ld["t"]) - 1
		if int(ld["t"]) <= 0:
			if _dead():
				return
			_float(a, "LATENT", GeneArt.C_DMG, Vector2(0, -12))
			await _hit(other, a, int(ld["n"]), {"nolunge": true})
		else:
			keep2.append(ld)
	a["latent"] = keep2


# ------------------------------------------------------------------ hooks

func _run_hooks(hname: String) -> void:
	if over or _hook_depth > 0 and _hook_running.has(hname):
		return
	var hs: Array = Adapt.hook(hname)
	if hs.is_empty():
		return
	_hook_depth += 1
	_hook_running[hname] = true
	for h0 in hs:
		if _dead():
			break
		var h: Dictionary = h0
		var aid: String = String(h.get("id", ""))
		var key := "%s:%s" % [aid, hname]
		var lim: String = String(h.get("limit", ""))
		if lim == "turn" and _hook_turn.has(key):
			continue
		if lim == "fight" and _hook_fight.has(key):
			continue
		_hook_turn[key] = true
		_hook_fight[key] = true
		_icon_flash[aid] = 1.0
		_sfx("adapt", 1.3)
		var fx: Array = h.get("fx", [])
		await _apply(fx, P, E, {"hook": hname})
	_hook_running.erase(hname)
	_hook_depth -= 1
	_refresh()


func _check_end() -> bool:
	if over:
		return true
	if int(E["colony"]) <= 0:
		var res := ""
		if bool(Game.run.get("is_root", false)) and kind == "boss":
			res = "destroy"
		await _win(res)
		return true
	if int(P["colony"]) <= 0:
		await _lose_fight()
		return true
	return false


# ================================================================== end / READ

func _end_turn() -> void:
	busy = true
	_sfx("confirm")
	await _run_hooks("turn_end")
	if await _check_end():
		return
	if bind_on:
		if float(E["colony"]) <= float(E["max"]) * 0.4 and best_chain >= 4:
			bind += 1
			_say_log("BIND %d/3. THE CORE GOES STILL." % bind)
			await _announce("BIND %d/3" % bind, "p", 0.8)
			if bind >= 3:
				await _win("bind")
				return
		elif bind > 0:
			bind = 0
			_say_log("THE BIND SLIPS.")
			await _announce("THE BIND SLIPS.", "e", 0.7)
	var marks: Array = []
	for e in win:
		var ed: Dictionary = e
		if not bool(ed["spent"]) and String(ed["marked"]) != "":
			marks.append({"uid": int(ed["uid"]), "id": String(ed["id"]), "kind": String(ed["marked"])})
	var sweep := _sweep_now()
	var rn := win.size() if sweep else mini(_read_n(), win.size())
	await _set_hold(rn)
	if sweep:
		_sfx("skip", 0.7)
		await _announce("SWEEP: THE WINDOW IS READ", "e", 0.7)
	await _read_out(rn)
	if await _check_end():
		return
	await _enemy_turn(marks)


## HOLD: if the gene right of your last expression sits in NEXT (it survives the READ),
## the chain waits for it. Expressing it first next turn keeps the chain going.
func _set_hold(rn: int) -> void:
	if exp_count == 0 and carry_uid >= 0:
		return
	carry_uid = -1
	carry_chain = 0
	var s := last_slot + 1
	if chain <= 0 or last_slot < 0 or s < rn or s >= win.size():
		return
	var e: Dictionary = win[s]
	var c: Dictionary = Cards.card(String(e["id"]))
	if bool(e["spent"]) or Cards.is_junk(String(e["id"])) or String(c.get("kind", "gene")) == "passive":
		return
	if trait_id == "blank":
		_float(P, "BLANK: NO HOLD", C_SEVER, Vector2(0, -12))
		return
	carry_uid = int(e["uid"])
	carry_chain = chain
	_pop_ui(_tile_center(s) + Vector2(0, -14), "HOLD x%d" % chain, C_HI, 1)
	await _run_hooks("hold")


## Turn start: a HELD chain resumes while its gene is still in the window.
func _apply_hold() -> void:
	if carry_uid < 0:
		return
	for e in win:
		var ed: Dictionary = e
		if int(ed["uid"]) == carry_uid and not bool(ed["spent"]):
			chain = carry_chain + Adapt.mod("hold_bonus")
			_float(P, "HELD x%d" % chain, C_HI, Vector2(0, -12))
			_tut_order_due = true
			return
	carry_uid = -1


## PRIMER: the fight's first real gene starts HELD at chain xN (it can't go ALONE).
func _prime(n: int) -> void:
	for e in win:
		var ed: Dictionary = e
		var id := String(ed["id"])
		if bool(ed["spent"]) or Cards.is_junk(id) or String(Cards.card(id).get("kind", "gene")) == "passive":
			continue
		carry_uid = int(ed["uid"])
		carry_chain = n
		return


## READ: slots [0, rn) and every spent gene leave. Unexpressed leavers are SKIPPED.
func _read_out(rn: int) -> void:
	var leaving: Array = []
	var skipped: Array = []
	for i in win.size():
		var e: Dictionary = win[i]
		if i < rn or bool(e["spent"]):
			leaving.append(i)
			var c: Dictionary = Cards.card(String(e["id"]))
			if not bool(e["spent"]) and String(c.get("kind", "gene")) != "passive":
				skipped.append(i)
	for i in leaving:
		var t: Control = _tiles[i]
		if skipped.has(i):
			t.set("ghost", "SKIP")
			t.queue_redraw()
		var tw := t.create_tween()
		tw.tween_property(t, "modulate:a", 0.15, 0.3)
	if not skipped.is_empty():
		_sfx("skip")
	await _wait(0.4)
	for i in skipped:
		if _dead():
			return
		var e: Dictionary = win[i]
		var c: Dictionary = Cards.card(String(e["id"]))
		var dor: Array = c.get("dormant", [])
		if not dor.is_empty():
			var en := bool(c.get("dormant_enemy", false))
			_pop_ui(_tile_center(i) + Vector2(0, -12), "DORMANT", UI.C_THINK_FG, 1)
			await _apply(dor, E if en else P, P if en else E, {"uid": int(e["uid"]), "id": String(e["id"]), "dormant": true})
		if trait_id == "hoarder":
			E["grow"] = int(E["grow"]) + 1
			_float(E, "HOARDS +1", UI.C_WARN)
		await _run_hooks("skip")
	# Remaining genes slide left.
	var old_x: Array = []
	var keep: Array = []
	for i in win.size():
		if not leaving.has(i):
			keep.append(win[i])
			old_x.append((_tiles[i] as Control).position.x)
	win = keep
	_sync_tiles()
	for i in _tiles.size():
		var t: Control = _tiles[i]
		t.modulate.a = 1.0
		var nx := t.position.x
		t.position.x = float(old_x[i])
		var tw := t.create_tween()
		tw.tween_property(t, "position:x", nx, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	last_slot = -1
	_refresh()
	await _wait(0.25)


func _enemy_turn(marks: Array) -> void:
	if over:
		return
	var ef: int = E["film"]
	E["film"] = ef / 2 if region == "wound" else 0
	if trait_id == "regrow" and int(E["colony"]) < int(E["max"]):
		_float(E, "REGROWS", UI.C_GREEN, Vector2(0, -12))
		_heal(E, 3)
	await _tick_status(E, P)
	if await _check_end():
		return
	var it := _cur_intent()
	var acted := false
	if staggered:
		_sfx("stagger")
		_creature("stagger", [])
		await _announce("%s STAGGERS" % E["name"], "p", 0.8)
	elif it.is_empty():
		pass
	elif _recorded(it):
		_float(E, "RECORDED", UI.C_ACCENT)
		await _announce("%s: RECORDED. IT FIZZLES." % it["name"], "p", 0.7)
	else:
		acted = true
		await _announce("%s: %s" % [E["name"], it["name"]], "e", 0.6)
		await _apply(it.get("fx", []), E, P, {"intent": true})
	if await _check_end():
		return
	if acted:
		for m in marks:
			var md: Dictionary = m
			var uid: int = md["uid"]
			if String(md["kind"]) == "gnaw":
				var gid := _strand_remove(uid)
				if gid != "":
					_sfx("gnaw")
					_float(P, "GNAWED %s" % Cards.card(gid)["name"], UI.C_BAD, Vector2(0, -20))
					_say_log("%s is chewed out of the fight." % Cards.card(gid)["name"])
					await _wait(0.35)
					await _pact(Cards.card(gid))
					if await _check_end():
						return
			elif String(md["kind"]) == "knot":
				_knot_next[uid] = true
				_sfx("knot")
				_float(P, "KNOTTED", UI.C_WARN, Vector2(0, -20))
	if break_need > 0:
		_creature("windup", [false])
	if trait_id == "hardened" and int(E["colony"]) > 0:
		_gain_film(E, 3)
	intent_i += 1
	break_need = 0
	break_progress = 0
	_refresh()
	await _wait(0.2)
	await _player_turn_start()


# ================================================================== outcomes

func _win(result: String) -> void:
	if over:
		return
	over = true
	busy = true
	print("BATTLE -> win %s %s" % [enemy_id, result])
	_sfx_call("heartbeat", [0.0])
	_refresh()
	var ec: Node3D = E["cluster"]
	if result == "bind":
		await _announce("THE CORE IS BOUND.", "p", 1.4)
	else:
		_sfx("enemy_die")
		_juice_call("shake", [_cam, 0.3, 0.5])
		if ec != null:
			_juice_call("burst", [self, ec.position + Vector3(0, 1.0, 0), GeneArt.C_DMG, 30, 3.5])
			if ec.has_method("die"):
				ec.call("die")
				await _wait(1.1)
			else:
				ec.call("set_count", 0)
		await _announce("%s BREAKS APART." % E["name"], "p", 1.0)
	_sfx("win")
	Game.run["colony"] = int(P["colony"])
	if kind != "boss":
		var gain := 5 if kind == "elite" else randi_range(2, 3)
		Game.run["reagent"] = int(Game.run.get("reagent", 0)) + gain
		_sfx("reward")
		await _announce("+%d REAGENT" % gain, "p", 0.9)
	await _give_tissue()
	await _run_hooks_after_win("kill")
	Game.run["colony"] = int(P["colony"])
	Game.run["battle"] = {}
	_sfx_call("drone", [""])
	if kind == "boss":
		var title := "%s CLEARED" % Game.REGION_NAMES.get(region, region.to_upper())
		if bool(Game.run.get("is_root", false)):
			title = "THE ROOT IS BOUND" if result == "bind" else "THE ROOT IS DESTROYED"
		await _big_banner(title)
		var rt: String = Game.region_reward_text(region)
		if rt != "":
			await UI.say([rt], "see")
		Game.finish_run(true, result)
		return
	Game.run["pending_reward"] = {"kind": "event" if from_event else kind, "enemy": enemy_id}
	Game.goto("run_map")


func _give_tissue() -> void:
	var mat: String = String(Cards.REGION_TISSUE.get(region, ""))
	if mat == "":
		return
	var n := 1
	if kind == "elite":
		n = 2
	elif kind == "boss":
		n = 3
	if not Game.run.has("tissue") or not (Game.run["tissue"] is Dictionary):
		Game.run["tissue"] = {}
	var ti: Dictionary = Game.run["tissue"]
	ti[mat] = int(ti.get(mat, 0)) + n
	_sfx("vial")
	_pop_ui(Vector2(UI.W / 2.0, 100), "+%d %s" % [n, mat.to_upper()], UI.C_ACCENT, 2)
	await _wait(0.7)


## Kill hooks fire after `over` is set: run them without the usual death guard.
func _run_hooks_after_win(hname: String) -> void:
	var hs: Array = Adapt.hook(hname)
	for h0 in hs:
		var h: Dictionary = h0
		var aid: String = String(h.get("id", ""))
		_icon_flash[aid] = 1.0
		for f0 in h.get("fx", []):
			var f: Dictionary = f0
			var n: int = int(f.get("n", 0))
			match String(f.get("t", "")):
				"heal":
					P["colony"] = mini(int(P["max"]), int(P["colony"]) + n)
					_float(P, "+%d" % n, UI.C_GREEN)
				"film", "charge", "charge_next":
					pass
		_refresh()
		await _wait(0.3)


func _lose_fight() -> void:
	if over:
		return
	over = true
	busy = true
	print("BATTLE -> loss %s" % enemy_id)
	_sfx_call("heartbeat", [0.0])
	_sfx("lose")
	Game.run["colony"] = 0
	Game.last_failed_strand = (Game.run.get("strand", []) as Array).duplicate()
	(P["cluster"] as Node).call("set_count", 0)
	await _wait(0.8)
	_sfx_call("drone", [""])
	await UI.say(["THE CULTURE DIES."], "see")
	Game.finish_run(false)


func _big_banner(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var band := ColorRect.new()
	band.color = Color(0.03, 0.05, 0.06, 0.9)
	band.position = Vector2(0, 84)
	band.size = Vector2(UI.W, 40)
	layer.add_child(band)
	var line := ColorRect.new()
	line.color = UI.C_ACCENT
	line.position = Vector2(0, 86)
	line.size = Vector2(UI.W, 2)
	layer.add_child(line)
	var line2 := line.duplicate() as ColorRect
	line2.position = Vector2(0, 120)
	layer.add_child(line2)
	var l := UI.label(text, UI.C_PAPER, 16)
	l.position = Vector2((UI.W - text.length() * 16) / 2.0, 96)
	layer.add_child(l)
	band.scale = Vector2(1, 0)
	band.pivot_offset = Vector2(0, 20)
	var tw := create_tween()
	tw.tween_property(band, "scale:y", 1.0, 0.25)
	UI.flash(Color(0.9, 1.0, 0.95), 0.4)
	await _wait(2.0)


# ================================================================== splice / mutate / shot

func _splice(slot: int) -> void:
	if slot < 0 or slot + 1 >= win.size():
		_deny("No right neighbour to splice.")
		return
	if splices <= 0:
		_deny("No splices left this turn.")
		return
	if bool(win[slot]["spent"]) or bool(win[slot + 1]["spent"]):
		_deny("Spent genes hold their slot.")
		return
	splices -= 1
	var a: Dictionary = win[slot]
	win[slot] = win[slot + 1]
	win[slot + 1] = a
	_sfx("splice")
	var ta: Control = _tiles[slot]
	var tb: Control = _tiles[slot + 1]
	var xa := ta.position.x
	var xb := tb.position.x
	ta.position.x = xb
	tb.position.x = xa
	ta.create_tween().tween_property(ta, "position:x", xa, 0.12)
	tb.create_tween().tween_property(tb, "position:x", xb, 0.12)
	sel = slot + 1
	_refresh()
	busy = true
	await _run_hooks("splice")
	if tut.active:
		await tut.show_step("splice")
	if await _check_end():
		return
	busy = false
	_refresh()


func _mut_cost() -> int:
	return maxi(0, 1 + Adapt.mod("mut_cost"))


func _mutate(slot: int) -> void:
	if slot < 0 or slot >= win.size() or bool(win[slot]["spent"]):
		_deny("Pick an unspent gene to mutate.")
		return
	var cost := _mut_cost()
	if charge < cost:
		_deny("Mutation needs %d Charge." % cost)
		return
	busy = true
	charge -= cost
	var fr := maxi(0, 1 + Adapt.mod("mut_fray"))
	Game.run["fray"] = int(Game.run.get("fray", 0)) + fr
	var e: Dictionary = win[slot]
	var pool: Array = Game.unlocked if not Game.unlocked.is_empty() else Cards.STARTING_POOL
	_sfx("mutate")
	var nid: String = await MutateReel.new().run(self, pool, String(e["id"]))
	if nid == "":
		nid = String(e["id"])
	var uid: int = e["uid"]
	var i := _strand_index(uid)
	if i >= 0:
		strand[i]["id"] = nid
	e["id"] = nid
	e["knotted"] = false
	_grows.erase(uid)
	_float(P, "%s  FRAY +%d" % [Cards.card(nid)["name"], fr], UI.C_WARN)
	_say_log("It rewrites into %s." % Cards.card(nid)["name"])
	_refresh()
	await _run_hooks("mutate")
	if await _check_end():
		return
	busy = false
	_refresh()


func _inject() -> void:
	var bs: Array = Game.run.get("boosters", [])
	if bs.is_empty():
		_deny("No boosters carried.")
		return
	if shot_used:
		_deny("One shot per turn.")
		return
	busy = true
	var pick := 0
	if bs.size() > 1:
		var opts: Array = []
		for b in bs:
			var inf: Dictionary = Boosters.info(String(b))
			opts.append("%s: %s" % [String(inf.get("name", b)), String(inf.get("desc", ""))])
		_modal = true
		pick = await UI.choose(opts, "INJECT WHICH?")
		_modal = false
		if pick < 0:
			busy = false
			_refresh()
			return
	var bid: String = String(bs[pick])
	var info: Dictionary = Boosters.info(bid)
	shot_used = true
	_sfx("needle")
	var syr := _syringe(String(info.get("name", bid)), info.get("color", UI.C_ACCENT))
	await _wait(0.3)
	var clean: bool = await ReadBar.new().run(self, _band_frac(), "PLUNGE", Vector2(130, 92))
	_sfx("plunger")
	_sfx("inject", 1.15 if clean else 1.0)
	var fx: Array = info.get("fx", [])
	if clean:
		fx = _scaled(fx, 0, 1.5)
		_pop_ui(Vector2(UI.W / 2.0, 92), "CLEAN!", UI.C_GREEN, 1)
	var tw := syr.create_tween()
	tw.tween_property(syr, "modulate:a", 0.0, 0.3)
	tw.tween_callback(syr.queue_free)
	bs.remove_at(pick)
	Game.run["boosters"] = bs
	await _announce(String(info.get("name", bid)).to_upper(), "p", 0.4)
	await _apply(fx, P, E, {"booster": bid})
	await _run_hooks("inject")
	if await _check_end():
		return
	busy = false
	_refresh()


## A syringe that slides in from the left, plunger drawn back.
func _syringe(label: String, col: Color) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2(-120, 104)
	_fx_layer.add_child(root)
	var barrel := ColorRect.new()
	barrel.color = Color(0.85, 0.92, 0.95, 0.9)
	barrel.position = Vector2(20, 0)
	barrel.size = Vector2(70, 12)
	root.add_child(barrel)
	var liquid := ColorRect.new()
	liquid.color = col
	liquid.position = Vector2(24, 3)
	liquid.size = Vector2(56, 6)
	root.add_child(liquid)
	var needle := ColorRect.new()
	needle.color = Color(0.8, 0.8, 0.85)
	needle.position = Vector2(90, 5)
	needle.size = Vector2(26, 2)
	root.add_child(needle)
	var plunger := ColorRect.new()
	plunger.color = UI.C_BORDER
	plunger.position = Vector2(0, 2)
	plunger.size = Vector2(22, 8)
	root.add_child(plunger)
	var l := UI.label(label, UI.C_PAPER)
	l.position = Vector2(20, -11)
	root.add_child(l)
	root.create_tween().tween_property(root, "position:x", 120.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


func _deny(why: String) -> void:
	_sfx("error")
	_say_log(why)


# ================================================================== presentation

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _say_log(text: String) -> void:
	_msg = text
	_refresh()


func _sfx(n: String, pitch := 1.0, vol := 0.0) -> void:
	_sfx_call("play", [n, pitch, vol])


func _sfx_call(method: String, args: Array) -> void:
	var s := get_node_or_null("/root/Sfx")
	if s != null and s.has_method(method):
		s.callv(method, args)


func _juice_call(method: String, args: Array) -> void:
	if _juice == null:
		return
	if method == "burst" or method == "shake":
		if args.is_empty() or args[0] == null:
			return
	_juice.callv(method, args)


func _creature(method: String, args: Array) -> void:
	var ec: Node = E.get("cluster")
	if ec != null and ec.has_method(method):
		ec.callv(method, args)


func _tile_center(i: int) -> Vector2:
	var r := _tile_rect(clampi(i, 0, maxi(0, win.size() - 1)))
	return r.position + Vector2(r.size.x / 2.0, 0)


## Floating pop in UI space (Juice.pop if available, else our own label).
func _pop_ui(pos: Vector2, text: String, color: Color, sz := 1) -> void:
	if _juice != null:
		_juice.callv("pop", [_hud, pos, text, color, sz])
		return
	var l := UI.label(text, color, 8 * sz)
	l.add_theme_color_override("font_outline_color", UI.C_INK)
	l.add_theme_constant_override("outline_size", 4)
	l.position = Vector2(roundf(pos.x - text.length() * 4 * sz), roundf(pos.y - 4 * sz))
	_fx_layer.add_child(l)
	l.pivot_offset = Vector2(text.length() * 4 * sz, 4 * sz)
	l.scale = Vector2(1.6, 1.6)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.12)
	tw.tween_property(l, "position:y", l.position.y - 10, 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func _float(a: Dictionary, text: String, color: Color, off := Vector2.ZERO) -> void:
	var cl: Node3D = a.get("cluster")
	if cl == null or _cam == null or _fx_layer == null:
		return
	var top: Vector3 = cl.call("top")
	var p := _cam.unproject_position(top) + off
	var l := UI.label(text, color)
	l.add_theme_color_override("font_outline_color", UI.C_INK)
	l.add_theme_constant_override("outline_size", 4)
	l.position = Vector2(roundf(p.x - text.length() * 4), roundf(p.y - 8))
	_fx_layer.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 14, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.5)
	tw.tween_callback(l.queue_free)


## Pokemon move-announcement banner. side "p" = paper box, "e" = dark box.
func _announce(text: String, side: String, t := 0.6) -> void:
	_banner_lbl.text = text
	if side == "e":
		_banner.add_theme_stylebox_override("panel", UI.box_style(UI.C_THINK_BG, UI.C_BAD.darkened(0.2)))
		_banner_lbl.add_theme_color_override("font_color", UI.C_PAPER)
	else:
		_banner.add_theme_stylebox_override("panel", UI.box_style(UI.C_PAPER, UI.C_BORDER))
		_banner_lbl.add_theme_color_override("font_color", UI.C_INK)
	var w := mini(text.length() * 8 + 16, UI.W - 8)
	_banner.size = Vector2(w, 16)
	_banner.position = Vector2(roundf((UI.W - w) / 2.0), 64)
	_banner.pivot_offset = Vector2(w / 2.0, 8)
	_banner.scale = Vector2(0.4, 0.4)
	_banner.visible = true
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.08)
	await _wait(t)
	_banner.visible = false


## A ghost copy of the tile flies toward its target before the fx land.
func _fly_card(slot: int, target: Dictionary) -> void:
	if slot < 0 or slot >= _tiles.size() or _cam == null:
		return
	var src: Control = _tiles[slot]
	var ghost := ColorRect.new()
	ghost.color = GeneArt.gene_color(String(win[slot]["id"]))
	ghost.size = src.size * 0.6
	ghost.position = src.position + src.size * 0.2
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(ghost)
	var cl: Node3D = target.get("cluster")
	var dest := Vector2(UI.W / 2.0, 60)
	if cl != null:
		dest = _cam.unproject_position(cl.call("top")) - ghost.size / 2.0
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "position", dest, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ghost, "scale", Vector2(0.3, 0.3), 0.18)
	tw.tween_callback(ghost.queue_free)
	await _wait(0.18)


func _process(dt: float) -> void:
	_t += dt
	if _cam:
		_cam.position = CAM_POS + Vector3(sin(_t * 0.31) * 0.12, sin(_t * 0.23) * 0.06, cos(_t * 0.27) * 0.08)
		_cam.look_at(CAM_LOOK + Vector3(sin(_t * 0.19) * 0.08, 0, 0))
	_intent_pop = maxf(0.0, _intent_pop - dt * 2.0)
	_chain_flash = maxf(0.0, _chain_flash - dt * 1.5)
	if _msg_t > 0.0:
		_msg_t = maxf(0.0, _msg_t - dt)
	for k in _icon_flash.keys():
		_icon_flash[k] = maxf(0.0, float(_icon_flash[k]) - dt * 1.5)
	var pl := 0.5 + 0.5 * sin(_t * 6.0)
	for i in _tiles.size():
		var t: Control = _tiles[i]
		var p := 0.0
		if not busy and i < win.size() and _linked(i) and not bool(win[i]["spent"]):
			p = pl
		t.set("pulse", p)
		if p > 0.0:
			t.queue_redraw()
	if _hud:
		_hud.queue_redraw()


# ------------------------------------------------------------------ refresh / desc

var _msg_shown := ""
var _msg_t := 0.0


func _faded(i: int) -> bool:
	return region == "archive" and not bool(Game.run.get("unfade", false)) and i >= _shown_read()


func _refresh() -> void:
	if _hud == null:
		return
	if _msg != _msg_shown:
		_msg_shown = _msg
		_msg_t = 4.0
	if _tiles.size() != win.size():
		_sync_tiles()
	var rn := _shown_read()
	for i in _tiles.size():
		var t: Control = _tiles[i]
		var e: Dictionary = win[i]
		var id: String = e["id"]
		var c: Dictionary = Cards.card(id)
		var spent: bool = e["spent"]
		var cost := _cost_of(i)
		t.call("set_card", id, spent, spent or cost <= charge, cost)
		var lk := not spent and _linked(i)
		t.call("set_state", {"marked": String(e["marked"]), "knotted": bool(e["knotted"]), "faded": _faded(i),
			"mode": "" if spent else _mode_for(c, lk, chain + 1 if lk else 1), "link": lk, "next": i >= rn,
			"held": lk and last_slot < 0, "ghost": ""})
		t.call("set_selected", i == sel and not over)
	var can := not busy and not over
	_end_btn.call("set_selected", false)
	_mut_btn.set("affordable", can and charge >= _mut_cost())
	_mut_btn.set("caption", "MUT %d" % _mut_cost())
	_mut_btn.queue_redraw()
	var bs: Array = Game.run.get("boosters", [])
	_shot_btn.set("affordable", can and not bs.is_empty() and not shot_used)
	_shot_btn.set("caption", "SHOT %d" % bs.size())
	_shot_btn.queue_redraw()
	_end_btn.set("affordable", can)
	_end_btn.queue_redraw()
	_desc.text = _desc_text()
	_hud.queue_redraw()


func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


func _desc_text() -> String:
	if win.is_empty() or sel < 0 or sel >= win.size():
		return "[color=%s]The window is empty.[/color]" % _hex(UI.C_DIM)
	var e: Dictionary = win[sel]
	var id: String = e["id"]
	if _faded(sel):
		return "[color=%s]??? FADED[/color]\nThe Archive hides it until it is READ.\nExpress it blind, or splice it closer." % _hex(UI.C_DIM)
	var c: Dictionary = Cards.card(id)
	var linked := _linked(sel)
	var first := exp_count == 0
	var mode := _mode_for(c, linked, chain + 1 if linked else 1)
	var head := "[color=%s]%s[/color]  %dC" % [_hex(GeneArt.gene_color(id)), String(c["name"]), _cost_of(sel)]
	var tags: Array = []
	if bool(e["knotted"]):
		tags.append("KNOTTED +1")
	if String(e["marked"]) == "gnaw":
		tags.append("MARKED: GNAW")
	elif String(e["marked"]) == "knot":
		tags.append("MARKED: KNOT")
	elif String(e["marked"]) == "sever":
		tags.append("SEVERED")
	if linked and last_slot < 0:
		tags.append("HELD x%d" % chain)
	if bool(c.get("burn", false)):
		tags.append("BURN")
	if bool(c.get("breaker", false)):
		tags.append("BREAKER")
	if int(c.get("grows", 0)) > 0:
		tags.append("GROWS %d" % int(c["grows"]))
	if Cards.is_green(id):
		tags.append("GREEN")
	if not tags.is_empty():
		head += "  [color=%s]%s[/color]" % [_hex(UI.C_WARN), " ".join(tags)]
	var body := String(c.get("desc", ""))
	body = _hl(body, "LINK:", linked)
	body = _hl(body, "FIRST:", first)
	body = _hl(body, "DORMANT:", false)
	body = _hl(body, "DEEP:", mode == "deep")
	body = _hl(body, "ALONE:", mode == "lone")
	var now := _preview(sel)
	if now != "":
		head += "  [color=%s]%s[/color]" % [_hex(UI.C_ACCENT), now]
	return head + "\n" + body


func _hl(s: String, key: String, on: bool) -> String:
	if s.find(key) < 0:
		return s
	var col := C_HI if on else UI.C_DIM
	return s.replace(key, "[color=%s]%s[/color]" % [_hex(col), key])


## Computed numbers if expressed now (no CLEAN).
func _preview(slot: int) -> String:
	var e: Dictionary = win[slot]
	if bool(e["spent"]):
		return ""
	var c: Dictionary = Cards.card(String(e["id"]))
	if String(c.get("kind", "gene")) == "passive":
		return ""
	var linked := _linked(slot)
	var nc := chain + 1 if linked else 1
	var fx := _scaled(_slot_fx(slot, linked, exp_count == 0, nc), _bonus_for(slot, linked, nc), 1.0)
	var parts: Array = []
	var d := _fx_damage(fx, P)
	if d > 0:
		parts.append("DMG %d" % d)
	var fl := 0
	var hl := 0
	for f in fx:
		var fd: Dictionary = f
		match String(fd.get("t", "")):
			"film":
				fl += _film_val(P, int(fd.get("n", 0)))
			"heal":
				hl += int(fd.get("n", 0))
			"latent":
				parts.append("LATENT %d" % int(fd.get("n", 0)))
	if fl > 0:
		parts.append("FILM %d" % fl)
	if hl > 0:
		parts.append("HEAL %d" % hl)
	if linked:
		parts.insert(0, "LINK x%d" % nc)
	return "= " + " ".join(parts) if not parts.is_empty() else ""


# ------------------------------------------------------------------ HUD

func _box(r: Rect2, dark: bool, border := Color(0, 0, 0, 0)) -> void:
	var bg := UI.C_THINK_BG if dark else UI.C_PAPER
	var bd := border if border.a > 0.0 else (UI.C_ACCENT.darkened(0.3) if dark else UI.C_BORDER)
	_hud.draw_style_box(UI.box_style(bg, bd, 1, 2, Vector4.ZERO), r)


func _txt(pos: Vector2, s: String, col: Color, max_w := -1) -> void:
	GeneArt.text(_hud, pos, s, col, max_w)


func _txt_r(right_x: float, y: float, s: String, col: Color) -> void:
	GeneArt.text(_hud, Vector2(right_x - GeneArt.text_w(s), y), s, col)


func _status_text(a: Dictionary) -> String:
	var parts: Array = []
	if int(a["film"]) > 0:
		parts.append("FILM %d" % int(a["film"]))
	if int(a["grow"]) > 0:
		parts.append("GROW+%d" % int(a["grow"]))
	for r in a["rot"]:
		var rd: Dictionary = r
		parts.append("ROT%d/%d" % [int(rd["n"]), int(rd["t"])])
	for l in a["latent"]:
		var ld: Dictionary = l
		parts.append("SET%d/%d" % [int(ld["n"]), int(ld["t"])])
	if String(a["side"]) == "p" and trap > 0:
		parts.append("TRAP%d" % trap if trap > 1 else "TRAP")
	return " ".join(parts)


func _draw_hud() -> void:
	if E.is_empty() or P.is_empty():
		return
	# --- enemy
	_box(ENEMY_BOX, false)
	var ex := ENEMY_BOX.position.x + 4
	var ey := ENEMY_BOX.position.y
	var nm := String(E["name"])
	if kind == "elite":
		nm += " *"
	_txt(Vector2(ex, ey + 3), nm, UI.C_INK, int(ENEMY_BOX.size.x) - 8)
	_txt(Vector2(ex, ey + 15), "HP", UI.C_INK)
	_txt(Vector2(ex + 110, ey + 15), "%d/%d" % [int(E["colony"]), int(E["max"])], UI.C_INK)
	var est := _status_text(E)
	if trait_name != "":
		est = trait_name.to_upper() + ("  " + est if est != "" else "")
	_txt(Vector2(ex, ey + 27), est, Color("406050"), int(ENEMY_BOX.size.x) - 8)
	# --- intent
	var pop := _intent_pop
	var ir := INTENT_BOX.grow(roundf(pop * 2.0))
	var wind := _intent_is_windup()
	var ib := UI.C_WARN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 8.0)) if wind else Color(0, 0, 0, 0)
	_box(ir, true, ib)
	var it := _cur_intent()
	var ix := INTENT_BOX.position.x + 4
	var iy := INTENT_BOX.position.y
	if not it.is_empty():
		var line := "> " + String(it["name"])
		var dm := _intent_damage()
		if _recorded(it):
			line += "  RECORDED"
		elif staggered:
			line += "  STAGGERED"
		elif dm > 0:
			line += "  %d" % dm
		var lc := UI.C_DIM if _recorded(it) or staggered else UI.C_THINK_FG
		_txt(Vector2(ix, iy + 3), line, lc, int(INTENT_BOX.size.x) - 8)
		if wind:
			_txt(Vector2(ix, iy + 14), "BREAK", UI.C_WARN)
			var bw := 100.0
			var br := Rect2(ix + 44, iy + 15, bw, 6)
			_hud.draw_rect(br, Color(0.1, 0.1, 0.1))
			var fr := clampf(float(break_progress) / float(maxi(1, break_need)), 0.0, 1.0)
			_hud.draw_rect(Rect2(br.position, Vector2(bw * fr, 6)), UI.C_WARN)
			_hud.draw_rect(br, UI.C_WARN.darkened(0.3), false, 1.0)
			_txt_r(INTENT_BOX.end.x - 4, iy + 14, "%d" % maxi(0, break_need - break_progress), UI.C_WARN)
		elif not _recorded(it) and not staggered:
			_txt(Vector2(ix, iy + 14), _intent_extra(it), UI.C_DIM, int(INTENT_BOX.size.x) - 8)
	# --- order: chain pips (DEEP from _deep_at), HELD, region rule
	var held := chain > 0 and last_slot < 0
	var oc := C_HI if held or chain >= _deep_at() else UI.C_ACCENT
	_box(ORDER_BOX, true, oc.lerp(Color.WHITE, _chain_flash * 0.6))
	var cx := ORDER_BOX.position.x + 4
	var cy := ORDER_BOX.position.y
	var head := "CHAIN -" if chain <= 0 else ("HELD x%d" if held else "CHAIN x%d") % chain
	_txt(Vector2(cx, cy + 2), head, oc.lerp(Color.WHITE, 0.3))
	_txt_r(ORDER_BOX.end.x - 4, cy + 2, "DEEP x%d" % _deep_at(), C_HI.darkened(0.35))
	for s in 10:
		var sr := Rect2(cx + s * 17, cy + 13, 15, 4)
		var deep := s + 1 >= _deep_at()
		if s < chain:
			_hud.draw_rect(sr, C_HI if deep else UI.C_ACCENT)
		else:
			_hud.draw_rect(sr, Color(0.12, 0.14, 0.16))
			if deep:
				_hud.draw_rect(sr, C_HI.darkened(0.6), false, 1.0)
	_txt(Vector2(cx, cy + 19), _medium_line(), UI.C_DIM, int(ORDER_BOX.size.x) - 8)
	# --- adaptations + syringes
	var ax := ORDER_BOX.position.x
	for aid0 in Adapt.owned():
		var aid: String = String(aid0)
		var fl: float = float(_icon_flash.get(aid, 0.0))
		var col := UI.C_ACCENT.lerp(Color.WHITE, fl)
		GeneArt.bitmap(_hud, Vector2(ax, ICON_Y + (0 if fl <= 0.0 else -1)), Adapt.icon(aid), col, 1)
		ax += 9
		if ax > ORDER_BOX.end.x - 40:
			break
	var bs: Array = Game.run.get("boosters", [])
	var sx := ORDER_BOX.end.x - 4
	for b in bs:
		var inf: Dictionary = Boosters.info(String(b))
		var bc: Color = inf.get("color", UI.C_ACCENT)
		sx -= 14
		_hud.draw_rect(Rect2(sx, ICON_Y + 2, 10, 4), Color(0.85, 0.92, 0.95))
		_hud.draw_rect(Rect2(sx + 1, ICON_Y + 3, 8, 2), bc)
		_hud.draw_rect(Rect2(sx + 10, ICON_Y + 3, 3, 1), Color(0.8, 0.8, 0.85))
	# status lines live in the empty strip under the intent box, clear of the enemy
	var ld: Array = Game.run.get("ledger", [])
	var sline := ""
	if not ld.is_empty():
		sline = "LEDGER %d/3" % ld.size()
	if bind_on:
		sline += ("  " if sline != "" else "") + "BIND %d/3" % bind
	if sline != "":
		_txt(Vector2(4, 86), sline, C_HI if bind_on else UI.C_ACCENT)
	# --- player
	_box(PLAYER_BOX, false)
	var px := PLAYER_BOX.position.x + 4
	var py := PLAYER_BOX.position.y
	_txt(Vector2(px, py + 3), "HP", UI.C_INK)
	_txt(Vector2(px + 110, py + 3), "%d/%d" % [int(P["colony"]), int(P["max"])], UI.C_INK)
	var fray_s := "FRAY %d" % int(Game.run.get("fray", 0))
	_txt_r(PLAYER_BOX.end.x - 4, py + 15, fray_s, UI.C_WARN.darkened(0.3))
	var pline := "C%d S%d" % [charge, splices]
	if free_next:
		pline += " FREE"
	var pst := _status_text(P)
	if pst != "":
		pline += " " + pst
	_txt(Vector2(px, py + 15), pline, Color("305040"), int(PLAYER_BOX.size.x - 16 - GeneArt.text_w(fray_s)))
	for k in charge:
		if k >= 8:
			break
		_hud.draw_rect(Rect2(PLAYER_BOX.position.x - 6, py + 20 - k * 5, 4, 4), UI.C_WARN)
	# --- message / hint
	if _msg_t > 0.0 and _msg != "":
		_txt(Vector2(4, HINT_Y), _msg, UI.C_THINK_FG.lerp(Color.WHITE, 0.2), int(UI.W) - 8)
	else:
		_txt(Vector2(4, HINT_Y), HINT, UI.C_DIM.darkened(0.2), int(UI.W) - 8)
	# --- zones
	if not win.is_empty():
		var rn := _shown_read()
		var r0 := _tile_rect(0)
		var rl := _tile_rect(maxi(0, rn - 1))
		_hud.draw_rect(Rect2(r0.position.x, ZONE_Y + 6, rl.end.x - r0.position.x, 1), UI.C_ACCENT.darkened(0.2))
		_txt(Vector2(r0.position.x, ZONE_Y - 2), "READ %d" % rn, UI.C_ACCENT)
		if rn < win.size():
			var n0 := _tile_rect(rn)
			var nl := _tile_rect(win.size() - 1)
			_hud.draw_rect(Rect2(n0.position.x, ZONE_Y + 6, nl.end.x - n0.position.x, 1), UI.C_DIM.darkened(0.3))
			_txt(Vector2(n0.position.x, ZONE_Y - 2), "NEXT", UI.C_DIM)
		elif _sweep_now() and _read_n() < win.size():
			var s0 := _tile_rect(mini(_read_n(), win.size() - 1))
			var wave := "~SWEEP~"
			var wy := ZONE_Y - 2 + roundf(sin(_t * 6.0))
			_txt(Vector2(s0.position.x, wy), wave, UI.C_BAD)
		if splices > 0 and sel + 1 < win.size() and not busy:
			var a := _tile_rect(sel)
			_txt(Vector2(a.end.x - 6, ZONE_Y - 2), "<>", UI.C_DIM.darkened(0.1))


func _intent_extra(it: Dictionary) -> String:
	var parts: Array = []
	for f in it.get("fx", []):
		var d: Dictionary = f
		var n: int = int(d.get("n", 0))
		match String(d.get("t", "")):
			"gnaw":
				parts.append("GNAWS %d" % n)
			"knot":
				parts.append("KNOTS %d" % n)
			"sweep":
				parts.append("SWEEPS ALL")
			"plant":
				parts.append("PLANTS %d" % maxi(1, n))
			"uproot":
				parts.append("UPROOTS")
			"drain":
				parts.append("DRAINS")
			"film":
				parts.append("FILM %d" % n)
			"sever":
				parts.append("SEVERS %d" % n)
			"scramble":
				parts.append("SCRAMBLES")
			"mimic_last":
				parts.append("COPIES YOU")
			"rot":
				parts.append("ROT %d" % n)
			"grow":
				parts.append("GROWS")
	return " ".join(parts)


func _medium_line() -> String:
	var med: Dictionary = Cards.REGION_MEDIUM.get(region, {})
	var s := String(med.get("name", ""))
	match region:
		"rivers":
			s = "SURGE: +1 READ" if _surge() else "CURRENT: SURGE NEXT"
		"hollow":
			s = "INHALE: FILM x1.5" if _inhale() else "EXHALE: DMG x1.5"
		"wound":
			s += ": FILM 1/2"
		"archive":
			s += ": NEXT HIDDEN"
		"root":
			s += ": LINK +2"
	return s


# ================================================================== input

func _unhandled_input(ev: InputEvent) -> void:
	if _modal or over or UI.busy:
		return
	if ev.is_action_pressed("help"):
		get_viewport().set_input_as_handled()
		_help()
		return
	if busy:
		return
	if ev.is_action_pressed("move_left"):
		_move_sel(-1)
	elif ev.is_action_pressed("move_right"):
		_move_sel(1)
	elif ev.is_action_pressed("interact") or ev.is_action_pressed("ui_accept"):
		_express(sel)
	elif ev.is_action_pressed("splice"):
		_splice(sel)
	elif ev.is_action_pressed("mutate"):
		_mutate(sel)
	elif ev.is_action_pressed("end_turn"):
		_end_turn()
	elif ev.is_action_pressed("inject"):
		_inject()
	elif ev.is_action_pressed("menu"):
		_view_strand()
	else:
		return
	get_viewport().set_input_as_handled()


func _move_sel(d: int) -> void:
	if win.is_empty():
		return
	sel = posmod(sel + d, win.size())
	_sfx("blip")
	_refresh()


func _view_strand() -> void:
	_modal = true
	var ids: Array = []
	for en in strand:
		ids.append(String(en["id"]))
	_sfx("select")
	await StrandView.new().run(self, ids, "view", {"title": "FIGHT STRAND (READER AT %d)" % (reader + 1), "cursor": reader})
	_modal = false
	_refresh()


func _help() -> void:
	_modal = true
	if ResourceLoader.exists(GLOSSARY_PATH):
		var gs: Script = load(GLOSSARY_PATH)
		if gs != null and gs.can_instantiate():
			var g = gs.new()
			if g != null and g.has_method("run"):
				await g.run(self)
				_modal = false
				return
	await UI.say([
		"Genes in READ leave at END. Unused ones are SKIPPED.",
		"Express a gene right of the last: LINK. Chains grow.",
		"Press in the band: CLEAN, x1.5. Q splices, R mutates.",
		"Fill the BREAK bar to stagger a wind-up. F injects.",
		"Chain into NEXT before END: it HOLDS to next turn."], "see")
	_modal = false
