extends Node
## Hub menus: the splice BENCH, the pause menu (notebook / hand / strand),
## and the medbay scan panel. All awaitable; built on UI.choose / UI.say.

const HandView := preload("res://scripts/ui/hand_view.gd")

var _layer: CanvasLayer


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)


func _gene_name(id: String) -> String:
	return Cards.card(id).get("name", id.to_upper())


func _strain_name(id: String) -> String:
	return Cards.STRAINS[id]["name"]


## The arranged strain genes, without the gene-bank extras.
func _base_strand() -> Array:
	var s := Game.starting_strand()
	return s.slice(0, s.size() - Game.gene_bank.size())


# ------------------------------------------------------------ bench

## Returns true if the player chose to INJECT (scene change started).
func bench() -> bool:
	while true:
		var opts: Array = ["INJECT", "ARRANGE STRAND", "SEQUENCE GENE", "STRAIN",
			{"text": "GENE BANK", "disabled": not Game.is_powered("freezer")}, "LEAVE"]
		var i := await UI.choose(opts, "SPLICE BENCH. STRAIN: %s." % _strain_name(Game.strain))
		match i:
			0:
				Game.goto("body_map")
				return true
			1:
				await _arrange()
			2:
				await _sequence()
			3:
				await _pick_strain()
			4:
				await _gene_bank()
			_:
				return false
	return false


func _arrange() -> void:
	while true:
		var strand := _base_strand()
		var opts: Array = []
		for k in strand.size():
			opts.append("%d %s" % [k + 1, _gene_name(strand[k])])
		var i := await UI.choose(opts, "ARRANGE. PICK A GENE TO MOVE.")
		if i < 0:
			return
		var slots: Array = []
		for k in strand.size():
			slots.append("SLOT %d%s" % [k + 1, "  <" if k == i else ""])
		var j := await UI.choose(slots, "%s. MOVE TO WHICH SLOT?" % _gene_name(strand[i]))
		if j < 0 or j == i:
			continue
		var g: String = strand[i]
		strand.remove_at(i)
		strand.insert(j, g)
		Game.start_order = strand
		Game.flags["order_strain"] = Game.strain


func _sequence() -> void:
	while true:
		var ids: Array = []
		var opts: Array = []
		for id in Cards.SEQUENCEABLE.keys():
			if Game.unlocked.has(id):
				continue
			ids.append(id)
			opts.append("%s  %dR" % [_gene_name(id), _seq_cost(id)])
		if ids.is_empty():
			await UI.say(["Every sequence in the library is already on file."])
			return
		var i := await UI.choose(opts, "SEQUENCER. REAGENT: %d. BREATH: %d." % [Game.reagent, Game.breath])
		if i < 0:
			return
		var id: String = ids[i]
		var c := _seq_cost(id)
		var prompt := "%s: %s\nSEQUENCE? %d REAGENT, 1 BREATH." % [_gene_name(id), Cards.card(id).get("desc", ""), c]
		if not await UI.confirm(prompt):
			continue
		if Game.breath <= 0:
			await UI.say(["Too tired. Rest or inject."], "think")
			return
		if not Game.spend_reagent(c):
			await UI.say(["NOT ENOUGH REAGENT."])
			continue
		Game.spend_breath(1)
		Game.unlocked.append(id)
		Game.save_game()
		await UI.say(["SEQUENCE COMPLETE: %s. Added to the library." % _gene_name(id)])


func _seq_cost(id: String) -> int:
	var c: int = Cards.SEQUENCEABLE[id]
	if Game.steady_hands:
		c -= 1
	return maxi(1, c)


func _pick_strain() -> void:
	var opts: Array = []
	for s in Game.strains:
		opts.append(_strain_name(s) + ("  *" if s == Game.strain else ""))
	var i := await UI.choose(opts, "CULTURE STOCK. ACTIVE: %s." % _strain_name(Game.strain))
	if i < 0:
		return
	var s: String = Game.strains[i]
	var st: Dictionary = Cards.STRAINS[s]
	if s == Game.strain:
		await UI.say(["%s. %s" % [st["name"], st["desc"]]])
		return
	if await UI.confirm("%s. %s\nSWITCH STRAIN?" % [st["name"], st["desc"]]):
		Game.strain = s
		Game.start_order = []
		Game.flags.erase("order_strain")
		Game.save_game()


func _gene_bank() -> void:
	while true:
		var opts: Array = []
		for id in Game.gene_bank:
			opts.append("- " + _gene_name(id))
		var can_add := Game.gene_bank.size() < Game.bank_slots
		opts.append({"text": "ADD GENE", "disabled": not can_add})
		opts.append("DONE")
		var i := await UI.choose(opts, "GENE BANK. %d/%d SLOTS. BANKED GENES JOIN EVERY STRAND." % [Game.gene_bank.size(), Game.bank_slots])
		if i < 0 or i == opts.size() - 1:
			Game.save_game()
			return
		if i < Game.gene_bank.size():
			Game.gene_bank.remove_at(i)
			continue
		var ids: Array = []
		var names: Array = []
		for id in Game.unlocked:
			if not Game.gene_bank.has(id) and not Cards.is_junk(id):
				ids.append(id)
				names.append(_gene_name(id))
		if ids.is_empty():
			continue
		var j := await UI.choose(names, "BANK WHICH GENE?")
		if j >= 0:
			Game.gene_bank.append(ids[j])


# ------------------------------------------------------------ hand / scan panels

## Hand panel. With `scan`, adds the projection and purge warning. Closes with the textbox.
func hand_panel(scan: bool) -> void:
	var p := UI.panel(Rect2(104, 8, 240, 152), true)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	p.add_child(hb)
	var hv: Control = HandView.new()
	hv.set("stage", Game.stage)
	hv.set("progress", Game.stage_progress)
	hb.add_child(hv)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	hb.add_child(vb)
	vb.add_child(UI.label("BIOSCAN" if scan else "LEFT HAND", UI.C_ACCENT))
	vb.add_child(UI.label("STAGE %d" % Game.stage, UI.C_PAPER))
	vb.add_child(UI.label("DAY %d" % Game.day, UI.C_DIM))
	if scan:
		var days := Game.days_to_next_stage()
		vb.add_child(UI.label("NEXT CHANGE:", UI.C_PAPER))
		vb.add_child(UI.label("~%d DAY%s" % [days, "" if days == 1 else "S"], UI.C_WARN))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(110, 8)
		bar.max_value = 100.0
		bar.value = Game.stage_progress
		vb.add_child(bar)
		if Game.stage >= 4:
			var closed := Game.stage > Game.PURGE_LAST_STAGE
			var w := UI.label("PURGE WINDOW:\n%s" % ("CLOSED" if closed else "CLOSING"), UI.C_BAD)
			vb.add_child(w)
			var tw := w.create_tween().set_loops()
			tw.tween_property(w, "modulate:a", 0.35, 0.4)
			tw.tween_property(w, "modulate:a", 1.0, 0.4)
	_layer.add_child(p)
	var lines: Array = []
	if scan:
		lines.append("SCAN COMPLETE. SPREAD: STAGE %d, %d%%." % [Game.stage, int(Game.stage_progress)])
	else:
		lines.append(["The cut, and the lines around it.", "The lines reach my wrist.",
			"It won't stop shaking.", "It's past my elbow.", "I can't see the grey in it any more.",
			"It isn't only my hand."][clampi(Game.stage, 0, 5)])
	await UI.say(lines, "see" if scan else "think")
	p.queue_free()


# ------------------------------------------------------------ pause menu

## Returns "title" if the player left for the title screen.
func pause() -> String:
	while true:
		var i := await UI.choose(["NOTEBOOK", "HAND", "STRAND", "SAVE", "TITLE", "CLOSE"])
		match i:
			0:
				await _notebook()
			1:
				await hand_panel(false)
			2:
				await _strand_panel()
			3:
				Game.save_game()
				UI.toast("SAVED")
			4:
				Game.save_game()
				Game.goto("title")
				return "title"
			_:
				return ""
	return ""


func _notebook() -> void:
	while true:
		var ids := Lore.found()
		var opts: Array = []
		for id in ids:
			opts.append(Lore.entry(id).get("title", id.to_upper()))
		opts.append({"text": "THOUGHTS", "disabled": Game.thoughts.is_empty()})
		var i := await UI.choose(opts, "NOTEBOOK. %d ENTRIES." % ids.size())
		if i < 0:
			return
		if i == ids.size():
			await UI.say(Game.thoughts.duplicate(), "think")
		else:
			await UI.say(Lore.lines(ids[i]))


func _strand_panel() -> void:
	var strand := Game.starting_strand()
	var p := UI.panel(Rect2(104, 8, 240, 152), true)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	vb.add_child(UI.label("STRAND - %s" % _strain_name(Game.strain), UI.C_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	vb.add_child(grid)
	var base_n := strand.size() - Game.gene_bank.size()
	for k in strand.size():
		var id: String = strand[k]
		var col := UI.C_PAPER
		if k >= base_n:
			col = UI.C_WARN
		elif Cards.is_green(id):
			col = UI.C_GREEN
		grid.add_child(UI.label("%2d %s" % [k + 1, _gene_name(id)], col))
	_layer.add_child(p)
	var line := "%d GENES. BANKED GENES IN ORANGE." % strand.size() if Game.gene_bank.size() > 0 \
		else "%d GENES." % strand.size()
	await UI.say([line])
	p.queue_free()
