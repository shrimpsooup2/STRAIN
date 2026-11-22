extends Node
## The Culture bench's station menus (moved from lab_menus' old BENCH and
## grown from it). All awaitable; built on UI.choose / UI.say. Every change
## is saved at once and reported through `changed` so the scene can animate.
##
## changed(kind, arg, to):
##   "pour"     arg = material spent, to = station it pours into
##   "grow"     arg = adaptation id          "equip" / "unequip"  arg = id
##   "booster"  arg = booster id drawn up    "empty"  arg = booster id
##   "primer"   arg = new primer             "strain" arg = strain id
##   "ring"     strand reordered / banked    "enrich" arg = new gene id
##   "sequence" arg = gene id

const Boosters := preload("res://scripts/culture/boosters.gd")
const Tissue := preload("res://scripts/culture/tissue.gd")

const PRIMER_MAX := 3
const PRIMER_COST := 3     ## Colony per primer step, paid at each fight start
const ENRICH_COST := 2

signal changed(kind: String, arg: String, to: String)


# ------------------------------------------------------------ helpers

func sfx(n: String, pitch := 1.0) -> void:
	var s := get_node_or_null("/root/Sfx")
	if s and s.has_method("play"):
		s.call("play", n, pitch)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _gene_name(id: String) -> String:
	return String(Cards.card(id).get("name", id.to_upper()))


func strain_name(id: String) -> String:
	var st: Dictionary = Cards.STRAINS.get(id, {})
	return String(st.get("name", id.to_upper()))


func _trait_name(id: String) -> String:
	var d: Dictionary = Adapt.info(id)
	return String(d.get("name", id.to_upper()))


func _trait_desc(id: String) -> String:
	var d: Dictionary = Adapt.info(id)
	return String(d.get("desc", ""))


## The arranged strain genes, without the gene-bank extras.
func base_strand() -> Array:
	var s := Game.starting_strand()
	return s.slice(0, s.size() - Game.gene_bank.size())


func mats_line() -> String:
	var parts: Array = []
	for m in Tissue.MATS:
		parts.append("%s %d" % [Tissue.SHORT[m], Tissue.have(m)])
	return " ".join(PackedStringArray(parts))


func _save(kind: String, arg := "", to := "") -> void:
	Game.save_game()
	changed.emit(kind, arg, to)


func _pour(cost: Dictionary, to: String) -> void:
	for m in cost:
		changed.emit("pour", String(m), to)


func primer_text(p: int) -> String:
	if p == 0:
		return "PRIMER 0. Fights start cold: no chain."
	return "PRIMER %d. My first gene opens at CHAIN x%d, never ALONE. -%d Colony each fight." % [p, p, p * PRIMER_COST]


# ------------------------------------------------------------ vial rack

func vials() -> void:
	sfx("vial")
	var lines: Array = ["CLOT %d. PLASMA %d. ALVEOLI %d. MYELIN %d." % [Tissue.have("clot"),
		Tissue.have("plasma"), Tissue.have("alveoli"), Tissue.have("myelin")],
		"REAGENT %d. GREEN SAMPLES %d." % [Game.reagent, Game.green_samples]]
	await UI.say(lines)
	var total := 0
	for m in Tissue.MATS:
		total += Tissue.have(m)
	if total == 0:
		await UI.say(["Empty. Tissue comes back from inside."], "think")


# ------------------------------------------------------------ sequencer

func sequence() -> void:
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
			sfx("error")
			await UI.say(["Too tired. Rest or inject."], "think")
			return
		if not Game.spend_reagent(c):
			sfx("error")
			await UI.say(["NOT ENOUGH REAGENT."])
			continue
		Game.spend_breath(1)
		Game.unlocked.append(id)
		_save("sequence", id)
		sfx("confirm")
		await _wait(0.5)
		await UI.say(["SEQUENCE COMPLETE: %s. Added to the library." % _gene_name(id)])


func _seq_cost(id: String) -> int:
	var c: int = Cards.SEQUENCEABLE[id]
	if Game.steady_hands:
		c -= 1
	return maxi(1, c)


# ------------------------------------------------------------ ring (plasmid)

func ring() -> void:
	while true:
		var opts: Array = ["ARRANGE", "ENRICH",
			{"text": "GENE BANK", "disabled": not Game.is_powered("freezer")}]
		var i := await UI.choose(opts, "PLASMID. %d GENES. READ FROM THE MARK." % Game.starting_strand().size())
		match i:
			0:
				await arrange()
			1:
				await enrich()
			2:
				await gene_bank()
			_:
				return


func arrange() -> void:
	while true:
		var strand := base_strand()
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
		sfx("select")
		_save("ring")


## Feed tissue to one gene: it becomes its "+" form in the arranged strand.
func enrich() -> void:
	while true:
		var strand := base_strand()
		var opts: Array = []
		for k in strand.size():
			var id: String = strand[k]
			var up := Cards.can_upgrade(id)
			opts.append({"text": "%d %s" % [k + 1, _gene_name(id)], "disabled": not up})
		var i := await UI.choose(opts, "ENRICH. %d TISSUE MAKES A GENE STRONGER." % ENRICH_COST)
		if i < 0:
			return
		var gid: String = strand[i]
		var mats: Array = []
		var mopts: Array = []
		for m in Tissue.MATS:
			mats.append(m)
			mopts.append({"text": "%s  %d" % [Tissue.mat_name(m), Tissue.have(m)],
				"disabled": Tissue.have(m) < ENRICH_COST})
		var j := await UI.choose(mopts, "%s. FEED IT %d OF WHAT?" % [_gene_name(gid), ENRICH_COST])
		if j < 0:
			continue
		var m: String = mats[j]
		var cost := {m: ENRICH_COST}
		if not Tissue.pay(cost):
			sfx("error")
			await UI.say([Tissue.lack_text(cost) + "."])
			continue
		var nid: String = Cards.upgraded(gid)
		strand[i] = nid
		Game.start_order = strand
		Game.flags["order_strain"] = Game.strain
		_pour(cost, "dish")
		sfx("bubble")
		await _wait(0.55)
		_save("enrich", nid)
		sfx("confirm")
		await UI.say(["%s ENRICHED. %s" % [_gene_name(nid), String(Cards.card(nid).get("desc", ""))]])


func gene_bank() -> void:
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
			_save("ring")
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
			sfx("select")
			_save("ring")


# ------------------------------------------------------------ strain shelf

func pick_strain() -> void:
	var opts: Array = []
	for s in Game.strains:
		opts.append(strain_name(s) + ("  *" if s == Game.strain else ""))
	var i := await UI.choose(opts, "CULTURE STOCK. ACTIVE: %s." % strain_name(Game.strain))
	if i < 0:
		return
	var s: String = Game.strains[i]
	var st: Dictionary = Cards.STRAINS.get(s, {})
	var line := "%s. %s" % [strain_name(s), String(st.get("desc", ""))]
	if s == Game.strain:
		await UI.say([line])
		return
	if await UI.confirm(line + "\nSWITCH STRAIN?"):
		Game.strain = s
		Game.start_order = []
		Game.flags.erase("order_strain")
		sfx("pour")
		_save("strain", s)


# ------------------------------------------------------------ incubator

func incubator() -> void:
	while true:
		var grown: Array = Game.culture["grown"]
		var traits: Array = Game.culture["traits"]
		var slots: int = int(Game.culture.get("trait_slots", 1))
		var opts: Array = ["GROW", {"text": "EQUIP  %d/%d" % [traits.size(), slots], "disabled": grown.is_empty()}]
		var i := await UI.choose(opts, "INCUBATOR. %d GROWN. %s" % [grown.size(), mats_line()])
		match i:
			0:
				await grow()
			1:
				await equip()
			_:
				return


func grow() -> void:
	while true:
		var grown: Array = Game.culture["grown"]
		var ids: Array = []
		var opts: Array = []
		for id in Adapt.CRAFT:
			if grown.has(id):
				continue
			var cost: Dictionary = Adapt.CRAFT[id]
			ids.append(String(id))
			opts.append({"text": "%s  %s" % [_trait_name(id), Tissue.cost_short(cost)],
				"disabled": not Tissue.can_pay(cost)})
		if ids.is_empty():
			await UI.say(["Every culture I know is growing."], "think")
			return
		var i := await UI.choose(opts, "GROW. %s" % mats_line())
		if i < 0:
			return
		var id: String = ids[i]
		var cost: Dictionary = Adapt.CRAFT[id]
		var prompt := "%s: %s\nGROW? %s." % [_trait_name(id), _trait_desc(id), Tissue.cost_text(cost)]
		if not Tissue.can_pay(cost):
			sfx("error")
			await UI.say(["%s: %s" % [_trait_name(id), _trait_desc(id)], Tissue.lack_text(cost) + "."])
			continue
		if not await UI.confirm(prompt):
			continue
		if not Tissue.pay(cost):
			continue
		grown.append(id)
		Game.culture["grown"] = grown
		_pour(cost, "incubator")
		sfx("bubble")
		await _wait(0.7)
		_save("grow", id)
		sfx("confirm")
		await UI.say(["GROWN: %s. Ready to equip." % _trait_name(id)])


func equip() -> void:
	while true:
		var grown: Array = Game.culture["grown"]
		var traits: Array = Game.culture["traits"]
		var slots: int = int(Game.culture.get("trait_slots", 1))
		if grown.is_empty():
			await UI.say(["Nothing grown yet."], "think")
			return
		var opts: Array = []
		for id in grown:
			opts.append("%s %s" % ["*" if traits.has(id) else " ", _trait_name(String(id))])
		var i := await UI.choose(opts, "TRAITS %d/%d. EQUIPPED ONES GO IN WITH ME." % [traits.size(), slots])
		if i < 0:
			return
		var id: String = grown[i]
		var head := "%s: %s" % [_trait_name(id), _trait_desc(id)]
		if traits.has(id):
			if await UI.confirm(head + "\nTAKE IT OUT?"):
				traits.erase(id)
				Game.culture["traits"] = traits
				sfx("select")
				_save("unequip", id)
			continue
		if not await UI.confirm(head + "\nEQUIP?"):
			continue
		if traits.size() >= slots and slots > 0:
			var out_i := 0
			if traits.size() > 1:
				var names: Array = []
				for t in traits:
					names.append(_trait_name(String(t)))
				out_i = await UI.choose(names, "SLOTS FULL. TAKE WHICH OUT?")
				if out_i < 0:
					continue
			var gone: String = traits[out_i]
			traits.remove_at(out_i)
			changed.emit("unequip", gone, "")
		if slots <= 0:
			continue
		traits.append(id)
		Game.culture["traits"] = traits
		sfx("confirm")
		_save("equip", id)


# ------------------------------------------------------------ syringe tray

func tray() -> void:
	while true:
		var held: Array = Game.culture["boosters"]
		var keys: Array = Boosters.BOOSTERS.keys()
		var full := held.size() >= Boosters.MAX_CARRIED
		var opts: Array = []
		for b in held:
			opts.append("- " + String(Boosters.info(String(b))["name"]))
		for id in keys:
			var d: Dictionary = Boosters.BOOSTERS[id]
			var cost: Dictionary = d["cost"]
			opts.append({"text": "%s  %s" % [String(d["name"]), Tissue.cost_short(cost)],
				"disabled": full or not Tissue.can_pay(cost)})
		var prompt := "SYRINGES %d/%d. %s" % [held.size(), Boosters.MAX_CARRIED,
			"FULL. EMPTY ONE FIRST." if full else "DRAW ONE UP."]
		var i := await UI.choose(opts, prompt)
		if i < 0:
			return
		if i < held.size():
			var hid: String = held[i]
			var hd := Boosters.info(hid)
			if await UI.confirm("%s: %s\nEMPTY IT? THE TISSUE IS LOST." % [String(hd["name"]), String(hd["desc"])]):
				held.remove_at(i)
				Game.culture["boosters"] = held
				sfx("pour", 0.8)
				_save("empty", hid)
			continue
		var id: String = keys[i - held.size()]
		var d := Boosters.info(id)
		var cost: Dictionary = d["cost"]
		if not await UI.confirm("%s: %s\nDRAW UP? %s." % [String(d["name"]), String(d["desc"]), Tissue.cost_text(cost)]):
			continue
		if not Tissue.pay(cost):
			sfx("error")
			await UI.say([Tissue.lack_text(cost) + "."])
			continue
		held.append(id)
		Game.culture["boosters"] = held
		_pour(cost, "tray")
		sfx("plunger")
		await _wait(0.55)
		_save("booster", id)
		await UI.say(["%s DRAWN UP. It goes in with me." % String(d["name"])])


# ------------------------------------------------------------ primer

## A primer is where a strand starts copying: each step means the fight's
## first gene resumes a HELD chain one longer. Paid in Colony every fight.
func prime() -> void:
	while true:
		var p: int = int(Game.culture.get("primer", 0))
		var opts: Array = [{"text": "LENGTHEN", "disabled": p >= PRIMER_MAX},
			{"text": "SHORTEN", "disabled": p <= 0}, "DONE"]
		var i := await UI.choose(opts, primer_text(p))
		match i:
			0:
				p += 1
			1:
				p -= 1
			_:
				return
		Game.culture["primer"] = clampi(p, 0, PRIMER_MAX)
		sfx("select", 0.8 + p * 0.1)
		_save("primer", str(p))


# ------------------------------------------------------------ inject

## Returns true if the scene change to the body map started.
func inject() -> bool:
	var traits: Array = Game.culture["traits"]
	var held: Array = Game.culture["boosters"]
	var prompt := "INJECT %s? %d TRAIT%s. %d SYRINGE%s." % [strain_name(Game.strain),
		traits.size(), "" if traits.size() == 1 else "S", held.size(), "" if held.size() == 1 else "S"]
	if not await UI.confirm(prompt):
		return false
	sfx("inject")
	Game.save_game()
	Game.goto("body_map")
	return true
