extends Node3D
## The deck battle. Two colonies on low-poly platforms, Pokemon-style.
## The player's Strand is read four genes at a time by the Reader; genes in the
## window are expressed for Charge. Rules: see the run-layer brief / Cards FX schema.

const GeneArt := preload("res://scripts/run/gene_art.gd")
const PixelBar := preload("res://scripts/run/pixel_bar.gd")
const Backdrop := preload("res://scripts/run/region_backdrop.gd")
const StrandView := preload("res://scripts/run/strand_view.gd")
const CardButton := preload("res://scripts/battle/card_button.gd")
const Cluster := preload("res://scripts/battle/colony_cluster.gd")

const P_POS := Vector3(0, 0, 0)
const E_POS := Vector3(7.6, 0.4, -4.2)
const CAM_POS := Vector3(0, 1.15, 3.8)
const CAM_LOOK := Vector3(4.2, -1.2, -6.0)

const ENEMY_BOX := Rect2(4, 4, 176, 40)
const INTENT_BOX := Rect2(4, 46, 176, 14)
const CHORUS_BOX := Rect2(186, 4, 124, 16)
const LEDGER_BOX := Rect2(186, 22, 124, 14)
const PLAYER_BOX := Rect2(206, 86, 176, 48)
const RIBBON_Y := 136
const DESC_BOX := Rect2(2, 144, 380, 24)
const CARD_Y := 170
const CARD_W := 84
const CARD_H := 44

# ------------------------------------------------------------------ fight state
var region := "wound"
var kind := "fight"
var enemy_id := ""
var strand: Array = []        ## fight copy: [{"id": String, "uid": int}]
var reader := 0
var win: Array = []           ## window entries (Dictionary) or null once removed
var used: Array = []          ## bool per window slot
var charge := 0
var charge_next := 0
var free_next := false
var chorus := 0
var trap := 0
var last_fx: Array = []
var pattern: Array = []
var intent_i := 0
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

# ------------------------------------------------------------------ presentation
var _cam: Camera3D
var _t := 0.0
var _hud: Control
var _p_bar: Control
var _e_bar: Control
var _cards: Array = []
var _end_btn: Control
var _mut_btn: Control
var _desc: Label
var _banner: PanelContainer
var _banner_lbl: Label
var _fx_layer: CanvasLayer
var _intent_pop := 0.0

# reward overlay
signal _reward_chosen(index: int)
var _reward_layer: CanvasLayer
var _reward_cards: Array = []
var _reward_sel := 0
var _reward_ids: Array = []
var _reward_desc: Label


func _ready() -> void:
	UI.apply_stage_post()
	if Game.run.is_empty():
		Game.start_run(Game.args_region())
		Game.run["row"] = 0
		Game.run["col"] = 0
		Game.run["battle"] = {"kind": "fight"}
	region = String(Game.run.get("region", "wound"))
	kind = String((Game.run.get("battle", {}) as Dictionary).get("kind", "fight"))
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


func _setup_fight() -> void:
	var re: Dictionary = Cards.REGION_ENEMIES.get(region, Cards.REGION_ENEMIES["wound"])
	match kind:
		"boss":
			enemy_id = re["boss"]
		"elite":
			enemy_id = re["elite"]
		_:
			var normals: Array = re["normal"]
			enemy_id = normals[randi() % normals.size()]
	var ed: Dictionary = Cards.enemy(enemy_id)
	var growth: int = int(Game.run.get("growth", 1))
	var mult := 1.0 + 0.12 * (growth - 1) + 0.06 * Game.stage
	var col := int(round(float(ed["colony"]) * mult))
	if kind == "elite":
		col = int(round(col * 1.4))
	E = _actor("e", String(ed["name"]), col, col)
	if kind == "elite":
		E["grow"] = 1
	var pat = ed["pattern"]
	if pat is String:
		_pattern_kind = pat
		if pat == "mimic_last":
			pattern = Cards.mimic_pattern(Game.last_failed_strand)
		else:
			pattern = Cards.mimic_pattern(Game.run.get("strand", []))
	else:
		pattern = pat
	var pc: int = int(Game.run.get("colony", Game.START_COLONY))
	var pm: int = int(Game.run.get("max_colony", Game.START_COLONY))
	P = _actor("p", "CULTURE", pc, pm)
	strand = []
	for id in Game.run.get("strand", []):
		strand.append(_new_entry(String(id)))
	reader = 0
	bind_on = Game.run.get("is_root", false) and kind == "boss" and Game.graft_ready()


## Fray ≥ 5: two random non-junk genes overgrow. Returns how many did.
func _apply_fray() -> int:
	if int(Game.run.get("fray", 0)) < 5:
		return 0
	var cand: Array = []
	for i in strand.size():
		if not Cards.is_junk(strand[i]["id"]):
			cand.append(i)
	cand.shuffle()
	var n := mini(2, cand.size())
	for k in n:
		strand[cand[k]] = _new_entry("overgrowth")
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
	add_child(Retro.omni((pal["accent"] as Color).lerp(UI.C_GREEN, 0.5), 5.0, 0.9, E_POS + Vector3(0.5, 2.5, 1.0)))

	var pc := Cluster.new()
	pc.position = P_POS + Vector3(0, 0.06, 0)
	add_child(pc)
	pc.setup(Color("d8f0f4"), _cell_cap(P), 0.19, 0, 11)
	P["cluster"] = pc
	var boss := kind == "boss"
	var ec := Cluster.new()
	ec.position = E_POS + Vector3(0, 0.06, 0)
	add_child(ec)
	var ecol := Color("58b848") if enemy_id != "core" else Color("3c9a34")
	if _pattern_kind != "":
		ecol = Color("88b878")
	ec.setup(ecol, _cell_cap(E), 0.5 if boss else 0.44, 7 if boss else 4, hash(enemy_id),
		Color("2c6a24") if enemy_id != "core" else Color("1c4a18"))
	E["cluster"] = ec
	pc.set_count(0, false)
	ec.set_count(0, false)

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
	_e_bar.position = ENEMY_BOX.position + Vector2(32, 17)
	_e_bar.size = Vector2(76, 6)
	_hud.add_child(_e_bar)
	_p_bar = PixelBar.new()
	_p_bar.position = PLAYER_BOX.position + Vector2(32, 17)
	_p_bar.size = Vector2(76, 6)
	_hud.add_child(_p_bar)
	_e_bar.set_values(E["colony"], E["max"], true)
	_p_bar.set_values(P["colony"], P["max"], true)

	var dp := UI.panel(DESC_BOX, true)
	dp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dp.add_theme_stylebox_override("panel", UI.box_style(UI.C_THINK_BG, UI.C_ACCENT.darkened(0.3), 2, 3, Vector4(6, 3, 6, 2)))
	layer.add_child(dp)
	_desc = UI.label("", UI.C_THINK_FG)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(DESC_BOX.size.x - 12, 18)
	_desc.add_theme_constant_override("line_spacing", 2)
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dp.add_child(_desc)

	for i in 4:
		var cb := CardButton.new()
		cb.position = Vector2(2 + i * (CARD_W + 2), CARD_Y)
		cb.size = Vector2(CARD_W, CARD_H)
		var idx := i
		cb.hovered.connect(func(): _on_hover(idx))
		cb.pressed.connect(func(): _on_click(idx))
		layer.add_child(cb)
		_cards.append(cb)
	_end_btn = CardButton.new()
	_end_btn.caption = "END"
	_end_btn.position = Vector2(348, CARD_Y)
	_end_btn.size = Vector2(34, 21)
	_end_btn.hovered.connect(func(): _on_hover(4))
	_end_btn.pressed.connect(func(): _on_click(4))
	layer.add_child(_end_btn)
	_mut_btn = CardButton.new()
	_mut_btn.caption = "MUT"
	_mut_btn.position = Vector2(348, CARD_Y + 23)
	_mut_btn.size = Vector2(34, 21)
	_mut_btn.pressed.connect(func(): if not busy and not over and not UI.busy: _mutate())
	layer.add_child(_mut_btn)

	_banner = UI.panel(Rect2(0, 0, 0, 0))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_lbl = UI.label("")
	_banner.add_child(_banner_lbl)
	_banner.visible = false
	layer.add_child(_banner)

	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 12
	add_child(_fx_layer)


# ================================================================== flow

func _intro() -> void:
	busy = true
	var fr := _apply_fray()
	await get_tree().create_timer(0.35).timeout
	(P["cluster"] as Node).call("set_count", _cells_for(P))
	(E["cluster"] as Node).call("set_count", _cells_for(E))
	await _wait(0.5)
	var line := "%s BLOCKS THE STRAND." % E["name"]
	if kind == "boss":
		line = "%s. IT FILLS THE REGION." % E["name"]
	elif kind == "elite":
		line = "%s, SWOLLEN. IT HITS HARDER." % E["name"]
	await _announce(line, "e", 1.0)
	if _pattern_kind == "mimic_last":
		_say_log("It moves like your last culture.")
		await _wait(0.9)
	elif _pattern_kind == "mimic_run":
		_say_log("It is reading your Strand back to you.")
		await _wait(0.9)
	if fr > 0:
		UI.toast("FRAY: %d GENES OVERGROW" % fr, UI.C_BAD)
		_refresh()
		await _wait(0.6)
	if Game.stage >= 4 and pattern.size() > 1:
		_say_log("You can feel what it means to do next.")
		await _wait(1.0)
	if bind_on:
		_say_log("BIND: hold the core at 40% or less with Chorus 10 for 3 turns.")
		await _wait(1.4)
	await _player_turn_start()


func _player_turn_start() -> void:
	P["film"] = 0
	await _tick_start(P)
	if _check_end():
		return
	var pc := 0
	var pf := 0
	for e in strand:
		var c: Dictionary = Cards.card(e["id"])
		if c["kind"] == "passive":
			var ps: Dictionary = c.get("passive", {})
			pc += int(ps.get("charge", 0))
			pf += int(ps.get("film", 0))
	charge = 3 + pc + charge_next
	charge_next = 0
	P["film"] = int(P["film"]) + pf
	if pf > 0:
		_float(P, "FILM+%d" % pf, GeneArt.C_FILM)
	free_next = false
	_fill_window()
	_msg = ""
	sel = _next_playable(-1)
	busy = false
	_refresh()


func _fill_window() -> void:
	win = []
	used = []
	var n := strand.size()
	if n == 0:
		return
	reader = posmod(reader, n)
	for i in mini(4, n):
		win.append(strand[(reader + i) % n])
		used.append(false)


func _end_turn() -> void:
	if busy or over:
		return
	busy = true
	_msg = ""
	if bind_on:
		var low := float(E["colony"]) <= float(E["max"]) * 0.4
		if low and chorus >= 10:
			bind += 1
			_refresh()
			await _announce("BIND %d/3. THE CORE GOES STILL." % bind, "p", 0.9)
			if bind >= 3:
				await _win("bind")
				return
		elif bind > 0:
			bind = 0
			_refresh()
			await _announce("THE BIND SLIPS.", "e", 0.7)
	var present := 0
	for e in win:
		if e != null:
			present += 1
	if strand.size() > 0:
		reader = (reader + present) % strand.size()
	win = []
	used = []
	_refresh()
	await _enemy_turn()
	if over:
		return
	if chorus > 0:
		chorus -= 1
	await _player_turn_start()


func _enemy_turn() -> void:
	E["film"] = 0
	_refresh()
	await _wait(0.25)
	await _tick_start(E)
	if _check_end():
		return
	if pattern.is_empty():
		return
	var it: Dictionary = pattern[intent_i % pattern.size()]
	_intent_pop = 1.0
	await _announce("%s: %s" % [E["name"], it["name"]], "e", 0.75)
	if (Game.run.get("ledger", []) as Array).has(it["id"]):
		_float(E, "RECORDED", UI.C_DIM)
		_say_log("RECORDED. %s fizzles." % it["name"])
		await _wait(0.6)
	else:
		await _apply(it["fx"], E, P, {})
	intent_i = (intent_i + 1) % pattern.size()
	_refresh()
	_check_end()


## Start of the victim's turn: rot ticks, then latent settles count down and land.
func _tick_start(a: Dictionary) -> void:
	var rots: Array = a["rot"]
	for r in rots.duplicate():
		await _lose(a, int(r["n"]), "ROT")
		r["t"] = int(r["t"]) - 1
		if int(r["t"]) <= 0:
			rots.erase(r)
		if _dead(a):
			return
	var lats: Array = a["latent"]
	for l in lats.duplicate():
		l["t"] = int(l["t"]) - 1
		if int(l["t"]) <= 0:
			lats.erase(l)
			_say_log("A settled drifter wakes.")
			await _lose(a, int(l["n"]), "SETTLE")
			if _dead(a):
				return
	_refresh()


func _check_end() -> bool:
	if over:
		return true
	if int(P["colony"]) <= 0:
		_lose_fight()
		return true
	if int(E["colony"]) <= 0:
		_win("destroy" if Game.run.get("is_root", false) else "")
		return true
	return false


func _dead(a: Dictionary) -> bool:
	return int(a["colony"]) <= 0


func _any_dead() -> bool:
	return _dead(P) or _dead(E)


# ================================================================== player actions

func _playable(i: int) -> bool:
	if i < 0 or i >= win.size() or win[i] == null or used[i]:
		return false
	var c: Dictionary = Cards.card(win[i]["id"])
	if c["kind"] == "passive":
		return false
	return (0 if free_next else int(c["cost"])) <= charge


func _next_playable(from: int) -> int:
	for k in range(1, 5):
		var i := (from + k) % 4 if from >= 0 else k - 1
		if _playable(i):
			return i
	return 4


func _on_hover(i: int) -> void:
	if busy or over or _modal or UI.busy:
		return
	_select(i)


func _on_click(i: int) -> void:
	if busy or over or _modal or UI.busy:
		return
	_select(i)
	_activate(i)


func _select(i: int) -> void:
	sel = clampi(i, 0, 4)
	_msg = ""
	_refresh()


func _activate(i: int) -> void:
	if i == 4:
		_end_turn()
	else:
		_express(i)


func _express(slot: int) -> void:
	if busy or over:
		return
	if slot >= win.size() or win[slot] == null:
		return
	if used[slot]:
		_say_log("Already expressed this turn.")
		return
	var e: Dictionary = win[slot]
	var c: Dictionary = Cards.card(e["id"])
	if c["kind"] == "passive":
		_say_log("PASSIVE. It works from anywhere in the Strand.")
		return
	var cost := 0 if free_next else int(c["cost"])
	if cost > charge:
		_say_log("Not enough Charge.")
		(_cards[slot] as Control).create_tween().tween_property(_cards[slot], "position:x",
			(_cards[slot] as Control).position.x, 0.12).from((_cards[slot] as Control).position.x + 3)
		return
	busy = true
	charge -= cost
	free_next = false
	used[slot] = true
	_msg = ""
	_refresh()
	if Cards.is_green(e["id"]):
		Game.run["uptake"] = int(Game.run.get("uptake", 0)) + 1
		UI.flash(Color(0.44, 0.85, 0.31), 0.25)
		UI.toast("UPTAKE +1", Color("287818"))
	await _announce(String(c["name"]), "p", 0.4)
	var fx: Array = c["fx"]
	await _apply(fx, P, E, {"entry": e})
	var echoes := false
	for f in fx:
		if f["t"] == "echo" or f["t"] == "clear":
			echoes = true
	if not echoes:
		last_fx = fx
	if _check_end():
		return
	sel = _next_playable(slot)
	busy = false
	_refresh()


func _mutate() -> void:
	if busy or over:
		return
	if sel >= win.size() or win[sel] == null or used[sel]:
		_say_log("MUTATE: pick a gene in the Reader first.")
		return
	if charge < 1:
		_say_log("MUTATE needs 1 Charge.")
		return
	var pool: Array = Game.unlocked if not Game.unlocked.is_empty() else Cards.STARTING_POOL
	busy = true
	charge -= 1
	var old: Dictionary = win[sel]
	var ne := _new_entry(String(pool[randi() % pool.size()]))
	var idx := _index_of(old)
	if idx >= 0:
		strand[idx] = ne
	win[sel] = ne
	Game.run["fray"] = int(Game.run.get("fray", 0)) + 1
	_say_log("MUTATED: %s became %s. FRAY +1." % [Cards.card(old["id"])["name"], Cards.card(ne["id"])["name"]])
	UI.flash(Color(0.9, 0.7, 0.3), 0.15)
	_refresh()
	await _wait(0.3)
	busy = false
	_refresh()


# ================================================================== strand ops

func _index_of(e: Dictionary) -> int:
	for i in strand.size():
		if strand[i]["uid"] == e["uid"]:
			return i
	return -1


func _remove_entry(e: Dictionary) -> void:
	var i := _index_of(e)
	if i < 0:
		return
	strand.remove_at(i)
	if i < reader:
		reader -= 1
	reader = posmod(reader, strand.size()) if strand.size() > 0 else 0
	for s in win.size():
		if win[s] != null and win[s]["uid"] == e["uid"]:
			win[s] = null


## Plant: N overgrowth right after the current Reader window.
func _plant(n: int) -> void:
	var size := strand.size()
	if size == 0:
		for k in n:
			strand.append(_new_entry("overgrowth"))
		return
	var p := reader + mini(4, size)
	if p > size:
		p -= size
	for k in n:
		strand.insert(p + k, _new_entry("overgrowth"))
	if p <= reader:
		reader += n


# ================================================================== FX interpreter

func _stage_bonus(src: Dictionary) -> int:
	return Game.stage / 2 if src["side"] == "e" else 0


func _apply(fx: Array, src: Dictionary, dst: Dictionary, ctx: Dictionary) -> void:
	for f in fx:
		if over or _any_dead():
			return
		var t: String = f["t"]
		match t:
			"dmg":
				var n: int = int(f["n"]) + int(src["grow"]) + _stage_bonus(src)
				for k in int(f.get("k", 1)):
					await _hit(src, dst, n)
					if _dead(dst):
						return
			"film":
				src["film"] = int(src["film"]) + int(f["n"])
				_float(src, "FILM+%d" % int(f["n"]), GeneArt.C_FILM)
				_refresh()
				await _wait(0.25)
			"heal":
				await _heal(src, int(f["n"]))
			"chorus":
				await _add_chorus(int(f["n"]))
			"if_chorus":
				if chorus >= int(f["min"]):
					_say_log("CHORUS %d: it resonates." % chorus)
					await _apply(f["fx"], src, dst, ctx)
			"dmg_chorus":
				await _hit(src, dst, chorus * int(f["mult"]) + _stage_bonus(src))
			"free_next":
				if src["side"] == "p":
					free_next = true
					_say_log("The next gene costs 0.")
			"charge":
				if src["side"] == "p":
					charge += int(f["n"])
					_float(src, "CHARGE+%d" % int(f["n"]), UI.C_WARN)
			"charge_next":
				if src["side"] == "p":
					charge_next += int(f["n"])
					_say_log("+%d Charge next turn." % int(f["n"]))
			"drifter":
				if chorus < 5:
					await _hit(src, dst, int(f["burst"]) + _stage_bonus(src))
				else:
					(dst["latent"] as Array).append({"n": int(f["latent"]) + _stage_bonus(src), "t": int(f["turns"])})
					_float(dst, "SETTLED", UI.C_WARN)
					_say_log("It settles in. %d damage in %d turns." % [int(f["latent"]), int(f["turns"])])
					await _wait(0.35)
			"hop":
				if ctx.has("entry"):
					_hop(ctx["entry"], int(f["ahead"]))
			"ledger":
				_ledger()
			"tripwire":
				if src["side"] == "p":
					trap += 1
					_float(src, "TRAP SET", UI.C_WARN)
			"rot":
				(dst["rot"] as Array).append({"n": int(f["n"]), "t": int(f["turns"])})
				_float(dst, "ROT", Color("a0b040"))
				await _wait(0.25)
			"fray":
				Game.run["fray"] = maxi(0, int(Game.run.get("fray", 0)) + int(f["n"]))
				_float(P, "FRAY%+d" % int(f["n"]), UI.C_WARN)
			"grow":
				src["grow"] = int(src["grow"]) + int(f["n"])
				_float(src, "GROW+%d" % int(f["n"]), UI.C_BAD if src["side"] == "e" else UI.C_ACCENT)
				await _wait(0.3)
			"plant":
				if dst["side"] == "p":
					if await _tripped("SEED"):
						continue
					_plant(int(f["n"]))
					_say_log("OVERGROWTH x%d planted in your Strand." % int(f["n"]))
					UI.flash(Color(0.3, 0.6, 0.2), 0.2)
					_refresh()
					await _wait(0.5)
			"uproot":
				if dst["side"] == "p":
					if await _tripped("UPROOT"):
						continue
					await _uproot()
			"drain":
				if dst["side"] == "p" and src["side"] == "e" and await _tripped("DRAIN"):
					continue
				var through := await _hit(src, dst, int(f["n"]) + _stage_bonus(src))
				if through > 0 and not _dead(dst):
					await _heal(src, through)
			"echo":
				if src["side"] == "p" and not last_fx.is_empty():
					_say_log("ECHO repeats the last gene.")
					await _apply(last_fx, src, dst, {})
				else:
					_say_log("Nothing to echo.")
			"clear":
				if ctx.has("entry"):
					_remove_entry(ctx["entry"])
					_float(src, "CLEARED", UI.C_DIM)
					_refresh()
					await _wait(0.25)
	_refresh()


## Enemy plant/uproot/drain against an armed tripwire: cancelled, you lose 3.
func _tripped(what: String) -> bool:
	if trap <= 0:
		return false
	trap -= 1
	_say_log("TRIPWIRE snaps. %s cancelled." % what)
	await _announce("TRIPWIRE! %s CANCELLED" % what, "p", 0.6)
	await _lose(P, 3, "TRAP")
	return true


func _uproot() -> void:
	var cand: Array = []
	for e in strand:
		if not Cards.is_junk(e["id"]):
			cand.append(e)
	if cand.is_empty():
		_say_log("Nothing left to uproot.")
		return
	var e: Dictionary = cand[randi() % cand.size()]
	var c: Dictionary = Cards.card(e["id"])
	_remove_entry(e)
	_say_log("%s torn out of your Strand." % c["name"])
	UI.flash(Color(0.6, 0.2, 0.2), 0.2)
	_refresh()
	await _wait(0.5)
	if c.has("pact"):
		_say_log("PACT broken: lose %d." % int(c["pact"]))
		await _lose(P, int(c["pact"]), "PACT")


func _hop(entry: Dictionary, ahead: int) -> void:
	var n := strand.size()
	var i := _index_of(entry)
	if i < 0 or n < 2:
		return
	var t := (i + ahead) % n
	if t == i:
		return
	var old: Dictionary = strand[t]
	var ne := _new_entry(entry["id"])
	strand[t] = ne
	for s in win.size():
		if win[s] != null and win[s]["uid"] == old["uid"]:
			win[s] = ne
			used[s] = false
	_say_log("HOP: lands on %s %d slots ahead." % [Cards.card(old["id"])["name"], ahead])
	_refresh()


func _ledger() -> void:
	if pattern.is_empty():
		return
	var it: Dictionary = pattern[intent_i % pattern.size()]
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
	_refresh()


func _add_chorus(n: int) -> void:
	var was := chorus
	chorus = clampi(chorus + n, 0, 10)
	if chorus != was:
		_float(P if n > 0 else E, "CHORUS%+d" % (chorus - was), GeneArt.C_CHORUS)
	_refresh()
	await _wait(0.25)


## Attack hit: Film absorbs first. Returns what got through.
func _hit(src: Dictionary, dst: Dictionary, n: int) -> int:
	n = maxi(0, n)
	var sc: Node3D = src["cluster"]
	var dc: Node3D = dst["cluster"]
	sc.call("lunge", dc.global_position)
	await _wait(0.1)
	var absorbed := mini(int(dst["film"]), n)
	dst["film"] = int(dst["film"]) - absorbed
	var through := n - absorbed
	dst["colony"] = maxi(0, int(dst["colony"]) - through)
	if absorbed > 0:
		_float(dst, "-%d FILM" % absorbed, GeneArt.C_FILM, Vector2(0, -10))
	if through > 0 or absorbed == 0:
		_float(dst, str(through), UI.C_PAPER if dst["side"] == "e" else UI.C_BAD)
	if through > 0:
		dc.call("flash")
		dc.call("recoil", sc.global_position)
		if dst["side"] == "p" and through >= 6:
			UI.flash(Color(0.85, 0.2, 0.2), 0.18)
	_sync(dst)
	await _wait(0.32)
	return through


## Direct loss (rot, settle, pact, trap): ignores Film.
func _lose(a: Dictionary, n: int, why: String) -> void:
	a["colony"] = maxi(0, int(a["colony"]) - n)
	_float(a, "%s -%d" % [why, n], Color("c8d060") if why == "ROT" else UI.C_BAD)
	(a["cluster"] as Node).call("flash", Color("e0e070") if why == "ROT" else Color.WHITE)
	_sync(a)
	await _wait(0.4)


func _heal(a: Dictionary, n: int) -> void:
	var was: int = a["colony"]
	a["colony"] = mini(int(a["max"]), was + n)
	var got := int(a["colony"]) - was
	_float(a, "+%d" % got, UI.C_GREEN)
	(a["cluster"] as Node).call("flash", Color("b0ffb0"))
	_sync(a)
	await _wait(0.3)


func _sync(a: Dictionary) -> void:
	if a["side"] == "p":
		Game.run["colony"] = int(a["colony"])
		_p_bar.set_values(a["colony"], a["max"])
	else:
		_e_bar.set_values(a["colony"], a["max"])
	(a["cluster"] as Node).call("set_count", _cells_for(a))
	_refresh()


# ================================================================== outcomes

func _win(result: String) -> void:
	if over:
		return
	over = true
	print("BATTLE -> win %s %s" % [enemy_id, result])
	busy = true
	_refresh()
	if result == "bind":
		await _announce("THE CORE IS BOUND.", "p", 1.4)
	else:
		(E["cluster"] as Node).call("set_count", 0)
		await _announce("%s BREAKS APART." % E["name"], "p", 1.1)
	Game.run["colony"] = int(P["colony"])
	Game.run["battle"] = {}
	if kind == "boss":
		var title := "%s CLEARED" % Game.REGION_NAMES.get(region, region.to_upper())
		if Game.run.get("is_root", false):
			title = "THE ROOT IS BOUND" if result == "bind" else "THE ROOT IS DESTROYED"
		await _big_banner(title)
		var rt := Game.region_reward_text(region)
		if rt != "":
			await UI.say([rt], "see")
		Game.finish_run(true, result)
		return
	var gain := 5 if kind == "elite" else randi_range(2, 3)
	Game.run["reagent"] = int(Game.run.get("reagent", 0)) + gain
	await _announce("+%d REAGENT" % gain, "p", 0.9)
	var picks := 2 if kind == "elite" else 1
	for p in picks:
		await _reward_round(p, picks)
	Game.goto("run_map")


func _lose_fight() -> void:
	if over:
		return
	over = true
	print("BATTLE -> loss %s" % enemy_id)
	busy = true
	Game.run["colony"] = 0
	(P["cluster"] as Node).call("set_count", 0)
	await _wait(0.8)
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


# ------------------------------------------------------------------ rewards

func _reward_round(p: int, picks: int) -> void:
	_reward_ids = Cards.reward_offers(Game.unlocked, Game.stage)
	_reward_layer = CanvasLayer.new()
	_reward_layer.layer = 40
	add_child(_reward_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reward_layer.add_child(dim)
	var pnl := UI.panel(Rect2(18, 36, 348, 112))
	_reward_layer.add_child(pnl)
	var title := "TAKE A GENE" + ("  (%d/%d)" % [p + 1, picks] if picks > 1 else "")
	var tl := UI.label(title)
	tl.position = Vector2(28, 44)
	_reward_layer.add_child(tl)
	var hint := UI.label("<> CHOOSE  Z TAKE", UI.C_BORDER)
	hint.position = Vector2(UI.W - 28 - 18 * 8, 44)
	_reward_layer.add_child(hint)
	_reward_cards = []
	var n := _reward_ids.size() + 1
	var cw := 84
	var skip_w := 48
	var gap := 4
	var x0 := (UI.W - ((n - 1) * cw + skip_w + (n - 1) * gap)) / 2
	for i in n:
		var cb := CardButton.new()
		if i < _reward_ids.size():
			cb.set_card(_reward_ids[i])
		else:
			cb.caption = "SKIP"
		cb.position = Vector2(x0 + i * (cw + gap), 64)
		cb.size = Vector2(cw if i < _reward_ids.size() else skip_w, CARD_H)
		var idx := i
		cb.hovered.connect(func(): _reward_select(idx))
		cb.pressed.connect(func(): _reward_chosen.emit(idx))
		_reward_layer.add_child(cb)
		_reward_cards.append(cb)
	_reward_desc = UI.label("", UI.C_INK)
	_reward_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_desc.position = Vector2(28, 116)
	_reward_desc.size = Vector2(328, 26)
	_reward_layer.add_child(_reward_desc)
	_reward_select(0)
	var chosen: int = await _reward_chosen
	_reward_layer.queue_free()
	_reward_layer = null
	_reward_cards = []
	if chosen < 0 or chosen >= _reward_ids.size():
		return
	var id: String = _reward_ids[chosen]
	_modal = true
	var strand_now: Array = Game.run.get("strand", [])
	var at: int = await StrandView.new().run(self, strand_now, "place",
		{"moving": id, "title": "INSERT %s WHERE?" % Cards.card(id)["name"], "cancel": false})
	_modal = false
	strand_now.insert(clampi(at, 0, strand_now.size()), id)
	Game.run["strand"] = strand_now


func _reward_select(i: int) -> void:
	_reward_sel = clampi(i, 0, _reward_cards.size() - 1)
	for k in _reward_cards.size():
		(_reward_cards[k] as Control).call("set_selected", k == _reward_sel)
	if _reward_sel < _reward_ids.size():
		var c: Dictionary = Cards.card(_reward_ids[_reward_sel])
		var cost := "PASSIVE. " if c["kind"] == "passive" else "COST %d. " % int(c["cost"])
		_reward_desc.text = cost + String(c["desc"])
		_reward_desc.add_theme_color_override("font_color", Color("287818") if Cards.is_green(_reward_ids[_reward_sel]) else UI.C_INK)
	else:
		_reward_desc.text = "Leave the Strand as it is."
		_reward_desc.add_theme_color_override("font_color", UI.C_INK)


# ================================================================== input

func _unhandled_input(e: InputEvent) -> void:
	if UI.busy or _modal:
		return
	if _reward_layer != null:
		if e.is_action_pressed("move_left"):
			_reward_select(_reward_sel - 1)
		elif e.is_action_pressed("move_right"):
			_reward_select(_reward_sel + 1)
		elif e.is_action_pressed("interact"):
			_reward_chosen.emit(_reward_sel)
		elif e.is_action_pressed("back"):
			_reward_chosen.emit(_reward_ids.size())
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if busy or over:
		return
	if e.is_action_pressed("move_left"):
		_select(posmod(sel - 1, 5))
	elif e.is_action_pressed("move_right"):
		_select(posmod(sel + 1, 5))
	elif e.is_action_pressed("interact"):
		_activate(sel)
	elif e.is_action_pressed("end_turn"):
		_end_turn()
	elif e.is_action_pressed("mutate"):
		_mutate()
	elif e.is_action_pressed("menu"):
		_view_strand()
	else:
		return
	get_viewport().set_input_as_handled()


func _view_strand() -> void:
	_modal = true
	var ids: Array = []
	for en in strand:
		ids.append(en["id"])
	await StrandView.new().run(self, ids, "view", {"title": "FIGHT STRAND (READER AT %d)" % (reader + 1),
		"cursor": reader})
	_modal = false


# ================================================================== presentation

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _say_log(text: String) -> void:
	_msg = text
	_refresh()


## Pokemon move-announcement banner. side "p" = paper box, "e" = dark box.
func _announce(text: String, side: String, t := 0.6) -> void:
	_banner_lbl.text = text
	if side == "e":
		_banner.add_theme_stylebox_override("panel", UI.box_style(UI.C_THINK_BG, UI.C_BAD.darkened(0.2)))
		_banner_lbl.add_theme_color_override("font_color", UI.C_PAPER)
	else:
		_banner.add_theme_stylebox_override("panel", UI.box_style(UI.C_PAPER, UI.C_BORDER))
		_banner_lbl.add_theme_color_override("font_color", UI.C_INK)
	var w := text.length() * 8 + 16
	_banner.size = Vector2(w, 16)
	_banner.position = Vector2(roundf((UI.W - w) / 2.0), 64)
	_banner.pivot_offset = Vector2(w / 2.0, 8)
	_banner.scale = Vector2(0.4, 0.4)
	_banner.visible = true
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.08)
	await _wait(t)
	_banner.visible = false


func _float(a: Dictionary, text: String, color: Color, off := Vector2.ZERO) -> void:
	var cl: Node3D = a["cluster"]
	if cl == null or _cam == null:
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


func _process(dt: float) -> void:
	_t += dt
	if _cam:
		_cam.position = CAM_POS + Vector3(sin(_t * 0.31) * 0.12, sin(_t * 0.23) * 0.06, cos(_t * 0.27) * 0.08)
		_cam.look_at(CAM_LOOK + Vector3(sin(_t * 0.19) * 0.08, 0, 0))
	if _intent_pop > 0.0:
		_intent_pop = maxf(0.0, _intent_pop - dt * 2.0)
		_hud.queue_redraw()


func _refresh() -> void:
	if _hud == null:
		return
	_hud.queue_redraw()
	for i in 4:
		var cb: Control = _cards[i]
		if i < win.size() and win[i] != null:
			var id: String = win[i]["id"]
			var c: Dictionary = Cards.card(id)
			var cost := 0 if free_next else int(c["cost"])
			var aff: bool = c["kind"] != "passive" and cost <= charge
			cb.call("set_card", id, used[i], aff, 0 if free_next else -1)
		else:
			cb.call("set_card", "")
		cb.call("set_selected", i == sel and not busy and not over)
	_end_btn.call("set_selected", sel == 4 and not busy and not over)
	_mut_btn.set("affordable", charge >= 1 and not busy)
	_mut_btn.queue_redraw()
	if _msg != "":
		_desc.text = _msg
		_desc.add_theme_color_override("font_color", UI.C_WARN.lightened(0.3))
	elif busy or over:
		_desc.text = ""
	elif sel == 4:
		_desc.text = "END: the Reader moves on 4 genes. %s acts." % E["name"]
		_desc.add_theme_color_override("font_color", UI.C_THINK_FG)
	elif sel < win.size() and win[sel] != null:
		var c: Dictionary = Cards.card(win[sel]["id"])
		_desc.text = String(c["desc"])
		_desc.add_theme_color_override("font_color", UI.C_GREEN if Cards.is_green(win[sel]["id"]) else UI.C_THINK_FG)
	else:
		_desc.text = "Z EXPRESS  E END  R MUTATE  TAB STRAND"
		_desc.add_theme_color_override("font_color", UI.C_DIM)


func _status_text(a: Dictionary) -> String:
	var parts: Array = []
	var rot := 0
	for r in a["rot"]:
		rot += int(r["n"])
	if rot > 0:
		parts.append("ROT%d" % rot)
	for l in a["latent"]:
		parts.append("SET%d/%d" % [int(l["n"]), int(l["t"])])
	if a["side"] == "p" and trap > 0:
		parts.append("TRAP%d" % trap if trap > 1 else "TRAP")
	return " ".join(parts)


func _draw_hud() -> void:
	var ci := _hud
	# ---- enemy box
	GeneArt.box(ci, ENEMY_BOX, false)
	var ex := ENEMY_BOX.position.x
	var ey := ENEMY_BOX.position.y
	var ename: String = E["name"]
	if kind == "elite":
		ename += " +"
	GeneArt.text(ci, Vector2(ex + 7, ey + 5), ename, UI.C_INK)
	if int(E["grow"]) > 0:
		var g := "+%d" % int(E["grow"])
		GeneArt.text(ci, Vector2(ENEMY_BOX.end.x - 7 - GeneArt.text_w(g), ey + 5), g, UI.C_BAD)
	GeneArt.text(ci, Vector2(ex + 7, ey + 16), "CO", UI.C_WARN.darkened(0.3))
	GeneArt.text(ci, Vector2(ex + 112, ey + 16), "%d/%d" % [int(E["colony"]), int(E["max"])], UI.C_INK)
	GeneArt.text(ci, Vector2(ex + 7, ey + 27), "FILM %d" % int(E["film"]), GeneArt.C_FILM.darkened(0.3) if int(E["film"]) > 0 else UI.C_DIM)
	var est := _status_text(E)
	if est != "":
		GeneArt.text(ci, Vector2(ex + 72, ey + 27), est, Color("788020"), int(ENEMY_BOX.size.x - 78))
	# ---- intent tag (Pokemon move label)
	if not pattern.is_empty() and not over:
		var it: Dictionary = pattern[intent_i % pattern.size()]
		var recorded := (Game.run.get("ledger", []) as Array).has(it["id"])
		var r := INTENT_BOX
		if _intent_pop > 0.0:
			r = r.grow(roundf(_intent_pop * 2.0))
		GeneArt.box(ci, r, true, UI.C_BAD.darkened(0.2) if not recorded else UI.C_DIM)
		GeneArt.text(ci, Vector2(r.position.x + 6, r.position.y + 3), ">", UI.C_BAD)
		GeneArt.text(ci, Vector2(r.position.x + 16, r.position.y + 3), String(it["name"]), UI.C_DIM if recorded else UI.C_PAPER)
		if recorded:
			GeneArt.text(ci, Vector2(r.end.x - 6 - 64, r.position.y + 3), "RECORDED", UI.C_ACCENT)
		var y := INTENT_BOX.end.y + 2
		if Game.stage >= 4 and pattern.size() > 1:
			var r2 := Rect2(INTENT_BOX.position.x, y, INTENT_BOX.size.x, 14)
			GeneArt.box(ci, r2, true, Color("305030"))
			var nx: Array = []
			for k in range(1, 3):
				nx.append(String(pattern[(intent_i + k) % pattern.size()]["name"]))
			GeneArt.text(ci, r2.position + Vector2(6, 3), "~ " + " > ".join(nx), UI.C_GREEN, int(r2.size.x - 10))
			y += 16
		if bind_on:
			_draw_bind(ci, Rect2(INTENT_BOX.position.x, y, INTENT_BOX.size.x, 25))
	# ---- chorus track
	GeneArt.box(ci, CHORUS_BOX, true, GeneArt.C_CHORUS.darkened(0.4))
	GeneArt.text(ci, CHORUS_BOX.position + Vector2(6, 4), "CHR", GeneArt.C_CHORUS)
	for i in 10:
		var px := CHORUS_BOX.position.x + 34 + i * 8
		var on := i < chorus
		var pc := GeneArt.C_CHORUS if on else Color("303828")
		if on and i >= 7:
			pc = Color("fff0a0")
		ci.draw_rect(Rect2(px, CHORUS_BOX.position.y + 5, 6, 6), pc)
	GeneArt.text(ci, Vector2(CHORUS_BOX.end.x - 6 - GeneArt.text_w(str(chorus)), CHORUS_BOX.position.y + 4), str(chorus), GeneArt.C_CHORUS)
	# ---- ledger
	var ld: Array = Game.run.get("ledger", [])
	if not ld.is_empty() or _strand_has("ledger"):
		GeneArt.box(ci, LEDGER_BOX, true)
		GeneArt.text(ci, LEDGER_BOX.position + Vector2(6, 3), "LEDGER %d/3" % ld.size(), UI.C_ACCENT if ld.size() > 0 else UI.C_DIM)
	# ---- player box
	GeneArt.box(ci, PLAYER_BOX, false)
	var px0 := PLAYER_BOX.position.x
	var py0 := PLAYER_BOX.position.y
	GeneArt.text(ci, Vector2(px0 + 7, py0 + 5), "CULTURE", UI.C_INK)
	var pst := _status_text(P)
	if pst != "":
		GeneArt.text(ci, Vector2(PLAYER_BOX.end.x - 7 - GeneArt.text_w(pst), py0 + 5), pst, UI.C_WARN.darkened(0.35))
	GeneArt.text(ci, Vector2(px0 + 7, py0 + 16), "CO", UI.C_WARN.darkened(0.3))
	GeneArt.text(ci, Vector2(px0 + 112, py0 + 16), "%d/%d" % [int(P["colony"]), int(P["max"])], UI.C_INK)
	GeneArt.text(ci, Vector2(px0 + 7, py0 + 27), "FILM %d" % int(P["film"]), GeneArt.C_FILM.darkened(0.3) if int(P["film"]) > 0 else UI.C_DIM)
	var fray: int = int(Game.run.get("fray", 0))
	GeneArt.text(ci, Vector2(px0 + 96, py0 + 27), "FRAY %d" % fray, UI.C_BAD if fray >= 5 else (UI.C_WARN.darkened(0.3) if fray > 0 else UI.C_DIM))
	GeneArt.text(ci, Vector2(px0 + 7, py0 + 37), "CHG", UI.C_WARN.darkened(0.3))
	var shown := maxi(charge, 3)
	for i in mini(shown, 12):
		var cx := px0 + 34 + i * 8
		ci.draw_rect(Rect2(cx, py0 + 38, 6, 6), UI.C_INK)
		ci.draw_rect(Rect2(cx + 1, py0 + 39, 4, 4), UI.C_WARN if i < charge else Color("c0c4c8"))
	if free_next:
		GeneArt.text(ci, Vector2(PLAYER_BOX.end.x - 7 - 32, py0 + 37), "FREE", Color("306848"))
	elif charge_next > 0:
		var cn := "+%d" % charge_next
		GeneArt.text(ci, Vector2(PLAYER_BOX.end.x - 7 - GeneArt.text_w(cn), py0 + 37), cn, UI.C_WARN.darkened(0.3))
	_draw_ribbon(ci)


func _strand_has(id: String) -> bool:
	for e in strand:
		if e["id"] == id:
			return true
	return false


func _draw_bind(ci: Control, r: Rect2) -> void:
	var low := float(E["colony"]) <= float(E["max"]) * 0.4
	var full := chorus >= 10
	GeneArt.box(ci, r, true, UI.C_GREEN.darkened(0.3))
	GeneArt.text(ci, r.position + Vector2(6, 3), "BIND", UI.C_GREEN)
	for i in 3:
		var bx := r.position.x + 44 + i * 10
		ci.draw_rect(Rect2(bx, r.position.y + 4, 8, 6), UI.C_INK)
		ci.draw_rect(Rect2(bx + 1, r.position.y + 5, 6, 4), UI.C_GREEN if i < bind else Color("283028"))
	GeneArt.text(ci, r.position + Vector2(80, 3), "%d/3" % bind, UI.C_GREEN)
	GeneArt.text(ci, r.position + Vector2(6, 13), "CORE<=40%", UI.C_GREEN if low else UI.C_DIM)
	GeneArt.text(ci, r.position + Vector2(92, 13), "CHR=10", UI.C_GREEN if full else UI.C_DIM)


func _draw_ribbon(ci: Control) -> void:
	var n := strand.size()
	if n == 0:
		return
	var step := 7 if n * 7 <= 196 else maxi(2, int(196.0 / n))
	var sq := step - 1
	var x0 := 6.0
	var y := float(RIBBON_Y)
	var in_win := {}
	var sel_uid := -1
	if win.is_empty():
		for i in mini(4, n):
			in_win[strand[(reader + i) % n]["uid"]] = false
	else:
		for s in win.size():
			if win[s] != null:
				in_win[win[s]["uid"]] = used[s]
		if sel < win.size() and win[sel] != null:
			sel_uid = win[sel]["uid"]
	ci.draw_rect(Rect2(x0 - 2, y - 2, n * step + 3, sq + 4), Color(0.03, 0.05, 0.06, 0.75))
	for i in n:
		var e: Dictionary = strand[i]
		var x := x0 + i * step
		var col := GeneArt.gene_color(e["id"])
		var uid: int = e["uid"]
		if in_win.has(uid):
			if in_win[uid]:
				col = col.darkened(0.6)
			var oc := UI.C_PAPER if not win.is_empty() else UI.C_DIM
			if uid == sel_uid:
				oc = UI.C_WARN
			ci.draw_rect(Rect2(x - 1, y - 1, sq + 2, sq + 2), oc)
		else:
			col = col.darkened(0.25)
		ci.draw_rect(Rect2(x, y, sq, sq), col)
	# Reader mark.
	var rx := x0 + posmod(reader, n) * step
	ci.draw_rect(Rect2(rx, y - 4, sq, 2), UI.C_PAPER)
