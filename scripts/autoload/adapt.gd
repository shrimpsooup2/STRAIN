extends Node
## ADAPTATIONS (run relics). Autoload `Adapt`.
##
## Entry schema:
##   id: {"name" (<= 14 chars), "rarity": "common"|"rare"|"cursed", "desc",
##        "hooks": {hook_name: {"fx": [player fx], "limit": "turn"|"fight"|""}},  optional
##        "mods": {mod_key: int},                                                   optional
##        "gain": {"max_colony","colony","fray","uptake": int},  applied once on pickup
##        "icon": 7 strings of 7 chars ('#' lit, '.' empty) for GeneArt.bitmap}
##
## Hooks fired by the battle (CombatEngine), see Adapt.hook():
##   fight_start, turn_start, turn_end, express, link, clean, skip, splice, mutate,
##   break, hurt, kill, inject,
##   deep (expressed LINKED at chain >= DEEP), lone (expressed unlinked: ALONE),
##   hold (a chain HOLDS over END), snap (a chain of 2+ SNAPS)
##
## Mod keys summed by Adapt.mod():
##   Battle (doc §1): charge, window, read, splice, band, link_bonus, dmg, film,
##                    mut_cost, mut_fray
##   Order:
##     deep_early  DEEP starts this many steps earlier (min x2)
##     reach       every gene LINKs across this many extra slots (like BRIDGE)
##     hold_bonus  a HELD chain resumes this many steps longer
##     third       1 = the 3rd gene expressed each turn fires twice
##   Run layer: reward_choices (extra reward picks), rest_heal (%), shop_discount
##
## Every function is safe in the lab (Game.run empty): it returns empty / zero.

const DATA := {
	# ------------------------------------------------------------ specimens
	"pellicle": {"name": "PELLICLE", "rarity": "common",
		"desc": "Start each fight with 6 Film.",
		"hooks": {"fight_start": {"fx": [{"t": "film", "n": 6}], "limit": ""}},
		"icon": [".......", ".#####.", "#.....#", "#.###.#", "#.....#", ".#####.", "......."]},
	"quorum_sense": {"name": "QUORUM SENSE", "rarity": "common",
		"desc": "First DEEP gene each turn: +1 Charge.",
		"hooks": {"deep": {"fx": [{"t": "charge", "n": 1}], "limit": "turn"}},
		"icon": [".#...#.", "#.#.#.#", ".#...#.", "...#...", "..#.#..", "...#...", "......."]},
	"steady_hand": {"name": "STEADY HAND", "rarity": "common",
		"desc": "CLEAN band +12% wider. Each CLEAN read: +2 Film.",
		"mods": {"band": 12},
		"hooks": {"clean": {"fx": [{"t": "film", "n": 2}], "limit": ""}},
		"icon": [".#.#.#.", ".#.#.#.", ".#####.", "######.", ".#####.", "..###..", "..###.."]},
	"loose_splice": {"name": "LOOSE SPLICE", "rarity": "common",
		"desc": "+1 free SPLICE per turn. Each SPLICE deals 2.",
		"mods": {"splice": 1},
		"hooks": {"splice": {"fx": [{"t": "dmg", "n": 2}], "limit": ""}},
		"icon": ["##...##", ".##.##.", "..###..", "...#...", "..###..", ".##.##.", "##...##"]},
	"long_read": {"name": "LONG READ", "rarity": "common",
		"desc": "Window +1 slot: you see 3 genes in NEXT.",
		"mods": {"window": 1},
		"icon": [".......", ".......", "#######", "#.#.#.#", "#######", ".......", "......."]},
	"chain_enzyme": {"name": "CHAIN ENZYME", "rarity": "rare",
		"desc": "LINK gives +1 more to every number per chain step.",
		"mods": {"link_bonus": 1},
		"icon": [".......", "##.....", "#.##...", ".##.##.", "...##.#", ".....##", "......."]},
	# ------------------------------------------------------------ craftable
	"scar_tissue": {"name": "SCAR TISSUE", "rarity": "common",
		"desc": "Whenever you lose Colony, gain 2 Film.",
		"hooks": {"hurt": {"fx": [{"t": "film", "n": 2}], "limit": ""}},
		"icon": [".......", "#......", ".#.#.#.", "#######", ".#.#.#.", "......#", "......."]},
	"clotting_factor": {"name": "CLOT FACTOR", "rarity": "common",
		"desc": "Every Film you gain is +2 bigger.",
		"mods": {"film": 2},
		"icon": ["..###..", ".#####.", "###.###", "##...##", "###.###", ".#####.", "..###.."]},
	"glutton": {"name": "GLUTTON", "rarity": "common",
		"desc": "When an enemy dies, regain 6 Colony.",
		"hooks": {"kill": {"fx": [{"t": "heal", "n": 6}], "limit": ""}},
		"icon": [".#####.", "#.....#", "#.#.#.#", "#.....#", "#.#.#.#", "#.....#", ".#####."]},
	"plasma_reserve": {"name": "PLASMA RESERVE", "rarity": "common",
		"desc": "+8 max Colony. First hit each fight: regain 4.",
		"gain": {"max_colony": 8, "colony": 8},
		"hooks": {"hurt": {"fx": [{"t": "heal", "n": 4}], "limit": "fight"}},
		"icon": ["...#...", "..###..", "..###..", ".#####.", ".##.##.", ".#####.", "..###.."]},
	"dormant_pocket": {"name": "DORMANT POCKET", "rarity": "common",
		"desc": "Each SKIPPED gene gives 2 Film.",
		"hooks": {"skip": {"fx": [{"t": "film", "n": 2}], "limit": ""}},
		"icon": [".......", "#.....#", "#.....#", "#..#..#", "#.....#", ".#####.", "......."]},
	"echo_chamber": {"name": "ECHO CHAMBER", "rarity": "common",
		"desc": "Each time a chain HOLDS over END: +5 Film.",
		"hooks": {"hold": {"fx": [{"t": "film", "n": 5}], "limit": ""}},
		"icon": ["#######", "#.....#", "#.###.#", "#.#.#.#", "#.###.#", "#.....#", "#######"]},
	"whiplash": {"name": "WHIPLASH", "rarity": "common",
		"desc": "When your chain SNAPS, deal 6.",
		"hooks": {"snap": {"fx": [{"t": "dmg", "n": 6}], "limit": ""}},
		"icon": ["#......", ".#.....", "..#....", "...#...", "...#.#.", "....#.#", "......#"]},
	"tendon": {"name": "TENDON", "rarity": "rare",
		"desc": "A HELD chain resumes 2 steps longer.",
		"mods": {"hold_bonus": 2},
		"icon": ["..###..", ".#...#.", ".#...#.", "..#.#..", ".#...#.", ".#...#.", "..###.."]},
	"rot_sac": {"name": "ROT SAC", "rarity": "common",
		"desc": "Fights start with ROT 2 on the enemy for 4 turns.",
		"hooks": {"fight_start": {"fx": [{"t": "rot", "n": 2, "turns": 4}], "limit": ""}},
		"icon": ["..#.#..", ".#####.", "##.#.##", "#######", "##.#.##", ".#####.", "..#.#.."]},
	"triple_helix": {"name": "TRIPLE HELIX", "rarity": "rare",
		"desc": "The 3rd gene you express each turn fires twice.",
		"mods": {"third": 1},
		"icon": ["#.#.#.#", ".#.#.#.", "#.#.#.#", ".......", "#.#.#.#", ".#.#.#.", "#.#.#.#"]},
	# ------------------------------------------------------------ common
	"burr": {"name": "BURR", "rarity": "common",
		"desc": "Each LINK also deals 2.",
		"hooks": {"link": {"fx": [{"t": "dmg", "n": 2}], "limit": ""}},
		"icon": ["#..#..#", ".#####.", ".##.##.", "###.###", ".##.##.", ".#####.", "#..#..#"]},
	"killer_instinct": {"name": "KILL INSTINCT", "rarity": "common",
		"desc": "When you BREAK a wind-up, deal 10.",
		"hooks": {"break": {"fx": [{"t": "dmg", "n": 10}], "limit": ""}},
		"icon": ["#.....#", ".#...#.", "..#.#..", ".......", "..#.#..", ".#...#.", "#.....#"]},
	"proofreader": {"name": "PROOFREADER", "rarity": "common",
		"desc": "MUTATE adds no Fray. Each MUTATE: +3 Film.",
		"mods": {"mut_fray": -1},
		"hooks": {"mutate": {"fx": [{"t": "film", "n": 3}], "limit": ""}},
		"icon": [".......", "......#", ".....#.", "#...#..", ".#.#...", "..#....", "......."]},
	"spare_ribosome": {"name": "SPARE RIBOSOME", "rarity": "common",
		"desc": "First MUTATE each turn refunds 1 Charge.",
		"hooks": {"mutate": {"fx": [{"t": "charge", "n": 1}], "limit": "turn"}},
		"icon": ["..###..", ".#####.", ".#####.", ".......", "#######", "#######", ".#####."]},
	"cyst_wall": {"name": "CYST WALL", "rarity": "common",
		"desc": "Each gene expressed ALONE (unlinked) gives 3 Film.",
		"hooks": {"lone": {"fx": [{"t": "film", "n": 3}], "limit": ""}},
		"icon": ["..###..", ".#...#.", "#.....#", "#..#..#", "#.....#", ".#...#.", "..###.."]},
	"adrenal_node": {"name": "ADRENAL NODE", "rarity": "common",
		"desc": "First time you lose Colony each turn: +1 Charge next turn.",
		"hooks": {"hurt": {"fx": [{"t": "charge_next", "n": 1}], "limit": "turn"}},
		"icon": ["...##..", "..##...", ".##....", "#######", "....##.", "...##..", "..##..."]},
	"vein_map": {"name": "VEIN MAP", "rarity": "common",
		"desc": "Each booster you inject also gives 1 Charge and 4 Film.",
		"hooks": {"inject": {"fx": [{"t": "charge", "n": 1}, {"t": "film", "n": 4}], "limit": ""}},
		"icon": [".....##", "....###", "...###.", "..###..", ".###...", ".#.....", "#......"]},
	# ------------------------------------------------------------ rare
	"hive_mind": {"name": "HIVE MIND", "rarity": "rare",
		"desc": "DEEP starts at chain x2 instead of x3.",
		"mods": {"deep_early": 1},
		"icon": [".##.##.", "#..#..#", ".##.##.", "#..#..#", ".##.##.", "#..#..#", ".##.##."]},
	"phage_memory": {"name": "PHAGE MEMORY", "rarity": "rare",
		"desc": "Every reward offers 1 more choice.",
		"mods": {"reward_choices": 1},
		"icon": ["..###..", ".#...#.", "..###..", "...#...", "...#...", ".#.#.#.", "#..#..#"]},
	"twin_nucleus": {"name": "TWIN NUCLEUS", "rarity": "rare",
		"desc": "READ zone is 1 slot smaller: fewer genes get read past.",
		"mods": {"read": -1},
		"icon": [".......", ".##.##.", "#..#..#", "#..#..#", "#..#..#", ".##.##.", "......."]},
	"perfect_copy": {"name": "PERFECT COPY", "rarity": "rare",
		"desc": "First CLEAN read each turn: +1 Charge.",
		"hooks": {"clean": {"fx": [{"t": "charge", "n": 1}], "limit": "turn"}},
		"icon": ["###....", "#.#....", "###....", ".......", "....###", "....#.#", "....###"]},
	"saltatory": {"name": "SALTATORY", "rarity": "rare",
		"desc": "Any gene can LINK across a 1-slot gap.",
		"mods": {"reach": 1},
		"icon": ["#......", "##.....", ".#.#...", "..###..", "...#.#.", ".....##", "......#"]},
	# ------------------------------------------------------------ cursed
	"blind_spot": {"name": "BLIND SPOT", "rarity": "cursed",
		"desc": "+1 Charge every turn. Window is 1 slot smaller.",
		"mods": {"charge": 1, "window": -1},
		"icon": ["#......", ".#####.", "#.#..##", "#..#..#", "##..#.#", ".#####.", "......#"]},
	"fevered": {"name": "FEVERED", "rarity": "cursed",
		"desc": "Every damage you deal is +2. CLEAN band is 10% narrower.",
		"mods": {"dmg": 2, "band": -10},
		"icon": ["...#...", "..##...", "..###..", ".#####.", ".##.##.", ".#...#.", "..###.."]},
	"green_thread": {"name": "GREEN THREAD", "rarity": "cursed",
		"desc": "+1 UPTAKE on pickup. When your chain SNAPS, lose 2 Colony.",
		"gain": {"uptake": 1},
		"hooks": {"snap": {"fx": [{"t": "self", "n": 2}], "limit": ""}},
		"icon": ["#......", ".#.....", "..#...#", "...#.#.", "....#..", "...#...", "..#...."]},
	"metabolic_surge": {"name": "SURGE GLAND", "rarity": "cursed",
		"desc": "+1 Charge every turn. +2 FRAY on pickup.",
		"mods": {"charge": 1},
		"gain": {"fray": 2},
		"icon": ["...#...", "..###..", ".#.#.#.", "...#...", "..###..", ".#.#.#.", "...#..."]},
	"second_mouth": {"name": "SECOND MOUTH", "rarity": "cursed",
		"desc": "Each LINK also deals 3, and you lose 1 Colony.",
		"hooks": {"link": {"fx": [{"t": "dmg", "n": 3}, {"t": "self", "n": 1}], "limit": ""}},
		"icon": [".#####.", "#.#.#.#", ".#####.", ".......", ".#####.", "#.#.#.#", ".#####."]},
}

## Lab specimens (the Lab agent hides one jar per id).
const SPECIMENS := ["pellicle", "quorum_sense", "steady_hand", "loose_splice", "long_read",
	"chain_enzyme"]

## Culture incubator recipes: id -> {material: n}. Materials: clot, plasma, alveoli, myelin.
const CRAFT := {
	"scar_tissue": {"clot": 2},
	"clotting_factor": {"clot": 3},
	"glutton": {"clot": 2, "plasma": 1},
	"plasma_reserve": {"plasma": 2},
	"dormant_pocket": {"plasma": 2, "myelin": 1},
	"echo_chamber": {"alveoli": 2},
	"whiplash": {"alveoli": 2, "myelin": 1},
	"tendon": {"alveoli": 3},
	"rot_sac": {"myelin": 2},
	"triple_helix": {"myelin": 3},
}

const _BLANK_ICON := ["#######", "#.....#", "#.###.#", "#...#.#", "#..#..#", "#.....#", "###.###"]


## Adaptations owned this run (empty in the lab).
func owned() -> Array:
	if Game.run.is_empty():
		return []
	var list: Array = Game.run.get("adapt", [])
	return list


func has(id: String) -> bool:
	return owned().has(id)


## Sum of a mod key over every owned adaptation.
func mod(key: String) -> int:
	var total := 0
	for id in owned():
		var d: Dictionary = DATA.get(id, {})
		var mods: Dictionary = d.get("mods", {})
		total += int(mods.get(key, 0))
	return total


## Every owned hook of this name: [{"id", "fx", "limit"}].
func hook(hook_name: String) -> Array:
	var out: Array = []
	for id in owned():
		var d: Dictionary = DATA.get(id, {})
		var hooks: Dictionary = d.get("hooks", {})
		if not hooks.has(hook_name):
			continue
		var h: Dictionary = hooks[hook_name]
		var fx: Array = h.get("fx", [])
		var limit: String = h.get("limit", "")
		out.append({"id": id, "fx": fx.duplicate(true), "limit": limit})
	return out


## All ids of a rarity ("" = every non-cursed id).
func ids(rarity := "") -> Array:
	var out: Array = []
	for id in DATA:
		var d: Dictionary = DATA[id]
		var r: String = d.get("rarity", "common")
		if (rarity == "" and r != "cursed") or r == rarity:
			out.append(id)
	return out


## Up to n random unowned ids of a rarity. Common and rare pools top each other
## up when they run dry; cursed never mixes in unless asked for.
func offers(n: int, rarity := "common", exclude := []) -> Array:
	var have := owned()
	var pool: Array = []
	for id in ids(rarity):
		if not have.has(id) and not exclude.has(id):
			pool.append(id)
	pool.shuffle()
	if pool.size() < n and rarity != "cursed":
		var extra: Array = []
		for id in ids(""):
			if not have.has(id) and not exclude.has(id) and not pool.has(id):
				extra.append(id)
		extra.shuffle()
		pool.append_array(extra)
	return pool.slice(0, maxi(0, n))


## Adds the adaptation to the run and applies its `gain` once per run.
## Safe to call for ids already in run.adapt (start_run may pre-fill the list).
func gain(id: String) -> void:
	if Game.run.is_empty() or not DATA.has(id):
		return
	var list: Array = Game.run.get("adapt", [])
	if not list.has(id):
		list.append(id)
	Game.run["adapt"] = list
	var done: Array = Game.run.get("adapt_gained", [])
	if done.has(id):
		return
	done.append(id)
	Game.run["adapt_gained"] = done
	var d: Dictionary = DATA[id]
	var g: Dictionary = d.get("gain", {})
	if g.is_empty():
		return
	var max_c: int = int(Game.run.get("max_colony", 0)) + int(g.get("max_colony", 0))
	max_c = maxi(1, max_c)
	Game.run["max_colony"] = max_c
	var col: int = int(Game.run.get("colony", 0)) + int(g.get("colony", 0))
	Game.run["colony"] = clampi(col, 1, max_c)
	var fray: int = int(Game.run.get("fray", 0)) + int(g.get("fray", 0))
	Game.run["fray"] = maxi(0, fray)
	var up: int = int(Game.run.get("uptake", 0)) + int(g.get("uptake", 0))
	Game.run["uptake"] = maxi(0, up)


## 7 strings of 7 chars for GeneArt.bitmap.
func icon(id: String) -> Array:
	var d: Dictionary = DATA.get(id, {})
	var rows: Array = d.get("icon", _BLANK_ICON)
	return rows.duplicate()


## {name, desc, rarity} for the description box.
func info(id: String) -> Dictionary:
	if not DATA.has(id):
		return {"name": id.to_upper(), "desc": "", "rarity": ""}
	var d: Dictionary = DATA[id]
	var nm: String = d.get("name", id.to_upper())
	var desc: String = d.get("desc", "")
	var rarity: String = d.get("rarity", "common")
	return {"name": nm, "desc": desc, "rarity": rarity}


## Recipe as plain words, e.g. "2 CLOT + 1 PLASMA" ("" if not craftable).
func cost_text(id: String) -> String:
	var recipe: Dictionary = CRAFT.get(id, {})
	var parts: Array = []
	for mat in recipe:
		parts.append("%d %s" % [int(recipe[mat]), str(mat).to_upper()])
	return " + ".join(PackedStringArray(parts))
