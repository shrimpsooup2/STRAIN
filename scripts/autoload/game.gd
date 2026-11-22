extends Node
## Persistent meta state (the human, the lab, the clock) + scene flow.
## Everything that survives between runs lives here and is saved as JSON.

const SAVE_PATH := "user://strain_save.json"
const SCENES := {
	"title": "res://scenes/title/title.tscn",
	"lab": "res://scenes/lab/lab.tscn",
	"body_map": "res://scenes/run/body_map.tscn",
	"run_map": "res://scenes/run/run_map.tscn",
	"battle": "res://scenes/battle/battle.tscn",
	"dream": "res://scenes/dream/dream.tscn",
	"ending": "res://scenes/ending/ending.tscn",
	"culture": "res://scenes/culture/culture.tscn",
}

const REGIONS := ["wound", "rivers", "hollow", "archive"]
const REGION_NAMES := {
	"wound": "THE WOUND", "rivers": "THE RIVERS", "hollow": "THE HOLLOW",
	"archive": "THE ARCHIVE", "root": "THE ROOT",
}
## What clearing a region gives back to the human.
const REGION_REWARD_TEXT := {
	"wound": "STEADY HANDS: bench work costs less.",
	"rivers": "The spread slows. Clock pushed back.",
	"hollow": "Breath comes easier. +1 BREATH. First clear: CANTOR strain.",
	"archive": "Something comes back to you.",
	"root": "",
}
## Reagent cost to restore a room's breaker. "generator" must come first.
const ROOM_POWER_COST := {
	"generator": 0, "medbay": 3, "freezer": 3, "cctv": 2, "comms": 3,
	"archive": 4, "incubator": 4, "garden": 6,
}

const STAGE_FALLOW := 6          ## reaching this stage inside the wing = failure ending
const PURGE_LAST_STAGE := 4      ## Purge / Graft impossible past this
const DAY_PROGRESS := 25.0       ## stage progress per day (100 = next stage)
const UPTAKE_PROGRESS := 6.0     ## per Green gene expressed during the run
const TREAT_AMOUNT := 25.0
const RIVERS_AMOUNT := 40.0
const REGROW_EVERY := 3          ## days between region regrowth ticks
const START_COLONY := 30

# ---------------------------------------------------------------- state
var day := 1
var stage := 0
var stage_progress := 0.0
var breath := 4
var reagent := 3
var green_samples := 0
var lore: Dictionary = {}            ## lore id -> day found
var thoughts: Array = []             ## internal lines collected, in order
var powered: Dictionary = {"bench": true}
var regions: Dictionary = {"wound": 1, "rivers": 2, "hollow": 2, "archive": 3}  ## growth 0..3 (0 = cleared)
var cleared_once: Dictionary = {}
var memories := 0                    ## archive clears → dreams 1..4
var pending_dream := 0
var leash_pages: Dictionary = {}     ## "1".."4" -> true
var unlocked: Array = []             ## gene ids in the reward pool
var gene_bank: Array = []            ## gene ids added to every run's starting strand
var bank_slots := 2
var strain := "scrubber"
var strains: Array = ["scrubber"]
var start_order: Array = []          ## player-arranged starting strand (strain genes); empty = default
var last_failed_strand: Array = []
var hollow_bonus := 0
var extra_breath := 0                ## one-off bonus for the next day
var steady_hands := false
var treated_today := false
var supply_taken_day := 0
var ending := ""
var flags: Dictionary = {}
var materials: Dictionary = {"clot": 0, "plasma": 0, "alveoli": 0, "myelin": 0}  ## tissue brought back from runs
## The culture prepared at the bench between runs (see scenes/culture).
##   grown: adaptation ids available to equip (crafted or found as specimens)
##   traits: equipped adaptation ids (≤ trait_slots), active from the start of every run
##   boosters: prepared booster ids (≤ 2), carried into the next run and consumed
##   primer: HELD chain the first gene of each fight opens on (0..3, costs Colony)
var culture: Dictionary = {"grown": [], "traits": [], "trait_slots": 1, "boosters": [], "primer": 0}
var run: Dictionary = {}             ## current run; empty when in the lab

var _scene_busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input()
	call_deferred("_handle_debug_args")


# ------------------------------------------------------------ input map

func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _register_input() -> void:
	_add_keys("move_up", [KEY_UP, KEY_W])
	_add_keys("move_down", [KEY_DOWN, KEY_S])
	_add_keys("move_left", [KEY_LEFT, KEY_A])
	_add_keys("move_right", [KEY_RIGHT, KEY_D])
	_add_keys("interact", [KEY_Z, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER])
	_add_keys("back", [KEY_X, KEY_ESCAPE, KEY_BACKSPACE])
	_add_keys("menu", [KEY_TAB, KEY_C])
	_add_keys("end_turn", [KEY_E])
	_add_keys("mutate", [KEY_R])
	_add_keys("splice", [KEY_Q])
	_add_keys("help", [KEY_H, KEY_F1])
	_add_keys("inject", [KEY_F])
	# Buttons respond to ui_accept/ui_cancel: let Z / X drive them too.
	_add_keys("ui_accept", [KEY_Z])
	_add_keys("ui_cancel", [KEY_X])
	_add_keys("ui_up", [KEY_W])
	_add_keys("ui_down", [KEY_S])
	_add_keys("ui_left", [KEY_A])
	_add_keys("ui_right", [KEY_D])


# ------------------------------------------------------------ scene flow

func goto(key: String) -> void:
	if _scene_busy:
		return
	_scene_busy = true
	print("SCENE -> ", key)
	await UI.fade_out()
	get_tree().change_scene_to_file(SCENES[key])
	await get_tree().process_frame
	await get_tree().process_frame
	_scene_busy = false
	await UI.fade_in()


# ------------------------------------------------------------ new / save

func new_game() -> void:
	day = 1
	stage = 0
	stage_progress = 0.0
	reagent = 3
	green_samples = 0
	lore = {}
	thoughts = []
	powered = {"bench": true}
	regions = {"wound": 1, "rivers": 2, "hollow": 2, "archive": 3}
	cleared_once = {}
	memories = 0
	pending_dream = 0
	leash_pages = {}
	unlocked = Cards.STARTING_POOL.duplicate()
	gene_bank = []
	bank_slots = 2
	strain = "scrubber"
	strains = ["scrubber"]
	start_order = []
	last_failed_strand = []
	hollow_bonus = 0
	extra_breath = 0
	steady_hands = false
	treated_today = false
	supply_taken_day = 0
	ending = ""
	materials = {"clot": 0, "plasma": 0, "alveoli": 0, "myelin": 0}
	culture = {"grown": [], "traits": [], "trait_slots": 1, "boosters": [], "primer": 0}
	flags = {}
	run = {}
	breath = breath_max()
	save_game()


func _state_keys() -> Array:
	return ["day", "stage", "stage_progress", "breath", "reagent", "green_samples", "lore",
		"thoughts", "powered", "regions", "cleared_once", "memories", "pending_dream",
		"leash_pages", "unlocked", "gene_bank", "bank_slots", "strain", "strains", "start_order",
		"last_failed_strand", "hollow_bonus", "extra_breath", "steady_hands", "treated_today",
		"supply_taken_day", "ending", "flags", "materials", "culture"]


func save_game() -> void:
	var d := {}
	for k in _state_keys():
		d[k] = get(k)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "\t"))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	if not has_save():
		return false
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	for k in _state_keys():
		if d.has(k):
			var v = d[k]
			# JSON numbers come back as float; restore ints.
			if typeof(get(k)) == TYPE_INT and typeof(v) == TYPE_FLOAT:
				v = int(v)
			set(k, v)
	for r in regions.keys():
		regions[r] = int(regions[r])
	_migrate()
	return true


## Drop ids from retired content (the old Chorus genes/adaptations) and rename CANTOR.
func _migrate() -> void:
	for arr in [unlocked, gene_bank, start_order, last_failed_strand]:
		var a: Array = arr
		for i in range(a.size() - 1, -1, -1):
			if not Cards.CARDS.has(Cards.base_id(String(a[i]))):
				a.remove_at(i)
	for k in ["grown", "traits"]:
		var a: Array = culture.get(k, [])
		for i in range(a.size() - 1, -1, -1):
			if not Adapt.DATA.has(String(a[i])):
				a.remove_at(i)
	culture.erase("pitch")
	if not culture.has("primer"):
		culture["primer"] = 0
	var known_b: Dictionary = preload("res://scripts/culture/boosters.gd").BOOSTERS
	for holder in [culture, run]:
		var bs: Array = (holder as Dictionary).get("boosters", [])
		for i in range(bs.size() - 1, -1, -1):
			if not known_b.has(String(bs[i])):
				bs.remove_at(i)
	if not run.is_empty():
		run.erase("pitch")
		var rs: Array = run.get("strand", [])
		for i in range(rs.size() - 1, -1, -1):
			if not Cards.CARDS.has(Cards.base_id(String(rs[i]))):
				rs.remove_at(i)
		var ra: Array = run.get("adapt", [])
		for i in range(ra.size() - 1, -1, -1):
			if not Adapt.DATA.has(String(ra[i])):
				ra.remove_at(i)
	var sp: Array = flags.get("specimens", [])
	for i in range(sp.size() - 1, -1, -1):
		if not Adapt.DATA.has(String(sp[i])):
			sp.remove_at(i)
	var si := strains.find("cantor")
	if si >= 0:
		strains[si] = "weaver"
	if strain == "cantor":
		strain = "weaver"


func wipe_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ------------------------------------------------------------ the human

func breath_max() -> int:
	var b := 4 + hollow_bonus
	if stage >= 3:
		b -= 1
	if stage >= 5:
		b -= 1
	return maxi(1, b)


func spend_breath(n := 1) -> bool:
	if breath < n:
		return false
	breath -= n
	return true


func spend_reagent(n: int) -> bool:
	if reagent < n:
		return false
	reagent -= n
	return true


func days_to_next_stage() -> int:
	return int(ceil((100.0 - stage_progress) / DAY_PROGRESS))


func purge_available() -> bool:
	return stage <= PURGE_LAST_STAGE


func root_unlocked() -> bool:
	for r in REGIONS:
		if not cleared_once.has(r):
			return false
	return purge_available()


func graft_ready() -> bool:
	return leash_pages.size() >= 4 and green_samples >= 3 and powered.has("garden") and purge_available()


## Pushes the clock back inside the current stage. Stages themselves never reverse.
func push_back(amount: float) -> void:
	stage_progress = maxf(0.0, stage_progress - amount)


func is_powered(room: String) -> bool:
	return powered.has(room)


func power_room(room: String) -> bool:
	if room != "generator" and not powered.has("generator"):
		return false
	if not spend_reagent(ROOM_POWER_COST.get(room, 3)):
		return false
	powered[room] = true
	if room == "incubator" and not strains.has("courier"):
		strains.append("courier")
	if room == "freezer":
		bank_slots = maxi(bank_slots, 2)
	return true


func treat() -> bool:
	if treated_today or not powered.has("medbay"):
		return false
	if not spend_reagent(3):
		return false
	if not spend_breath(1):
		reagent += 3
		return false
	treated_today = true
	push_back(TREAT_AMOUNT)
	return true


## Reagent the supply hatch yields today. The world outside is failing: it shrinks.
func supply_today() -> int:
	return maxi(0, 4 - (day - 1) / 4)


func take_supply() -> int:
	if supply_taken_day == day:
		return -1
	supply_taken_day = day
	var n := supply_today()
	reagent += n
	return n


func add_thought(line: String) -> void:
	if line != "" and not thoughts.has(line):
		thoughts.append(line)


## Ends the day: the clock advances, regions regrow, a new day starts.
func end_day(uptake := 0) -> void:
	day += 1
	stage_progress += DAY_PROGRESS + uptake * UPTAKE_PROGRESS
	while stage_progress >= 100.0 and stage < STAGE_FALLOW:
		stage += 1
		stage_progress -= 100.0
	if stage >= STAGE_FALLOW:
		stage_progress = 0.0
	if (day - 1) % REGROW_EVERY == 0:
		for r in REGIONS:
			regions[r] = mini(3, int(regions[r]) + 1)
	treated_today = false
	breath = breath_max() + extra_breath
	extra_breath = 0
	if stage >= STAGE_FALLOW and ending == "":
		ending = "fallow"
	save_game()


# ------------------------------------------------------------ runs

func starting_strand() -> Array:
	var base: Array = start_order if start_order.size() > 0 and flags.get("order_strain", "") == strain \
		else Cards.STRAINS[strain]["strand"]
	return base.duplicate() + gene_bank.duplicate()


## opts (Injection screen, §13): max_colony, colony, fray, uptake, start_row, primer,
## boosters[], adapt[], adapt_rare (int), genes[], unfade (bool), site (String).
## Culture traits/boosters/primer are folded in here; prepared boosters are consumed.
func start_run(region: String, opts: Dictionary = {}) -> void:
	var is_root := region == "root"
	var mx: int = maxi(1, int(opts.get("max_colony", START_COLONY)))
	var col: int = clampi(int(opts.get("colony", mx)), 1, mx)
	var strand: Array = starting_strand()
	var genes: Array = opts.get("genes", [])
	for g in genes:
		strand.append(String(g))
	var boosters: Array = []
	var prepared: Array = culture.get("boosters", [])
	for b in prepared:
		boosters.append(String(b))
	var extra_b: Array = opts.get("boosters", [])
	for b in extra_b:
		boosters.append(String(b))
	culture["boosters"] = []
	run = {
		"region": region,
		"is_root": is_root,
		"growth": 3 if is_root else int(regions.get(region, 1)),
		"strand": strand,
		"colony": col,
		"max_colony": mx,
		"fray": maxi(0, int(opts.get("fray", 0))),
		"ledger": [],
		"uptake": maxi(0, int(opts.get("uptake", 0))),
		"reagent": 0,
		"row": -1,
		"col": -1,
		"path": [],
		"nodes": _make_nodes(region),
		"battle": {},
		"result": "",
		"adapt": [],
		"boosters": boosters,
		"primer": int(culture.get("primer", 0)) + int(opts.get("primer", 0)),
		"tissue": {},
		"unfade": bool(opts.get("unfade", false)),
		"site": String(opts.get("site", "")),
		"shop": {},
	}
	# Adaptations: equipped culture traits, then site extras, then random rares.
	var want: Array = []
	var traits: Array = culture.get("traits", [])
	for id in traits:
		if not want.has(String(id)):
			want.append(String(id))
	var extra_a: Array = opts.get("adapt", [])
	for id in extra_a:
		if not want.has(String(id)):
			want.append(String(id))
	for id in want:
		Adapt.gain(id)
	var rares: int = int(opts.get("adapt_rare", 0))
	if rares > 0:
		var picks: Array = Adapt.offers(rares, "rare", Adapt.owned())
		for id in picks:
			Adapt.gain(String(id))
	# Start further up the map: earlier rows count as already walked.
	var start_row: int = int(opts.get("start_row", 0))
	if start_row > 0:
		_prefill_path(start_row)
	flags["in_run"] = true
	save_game()


## Walks a random linked path through rows 0..start_row-1 and marks them passed.
func _prefill_path(start_row: int) -> void:
	var nodes: Array = run["nodes"]
	var last := mini(start_row, nodes.size() - 1) - 1
	if last < 0:
		return
	var path: Array = []
	var first_row: Array = nodes[0]
	var c := randi() % first_row.size()
	path.append(c)
	for r in range(1, last + 1):
		var prev_row: Array = nodes[r - 1]
		var prev: Dictionary = prev_row[c]
		var links: Array = prev.get("links", [0])
		c = int(links[randi() % links.size()])
		path.append(c)
	run["path"] = path
	run["row"] = last
	run["col"] = c


## A run that was quit mid-way (closed the game) counts as a failed culture.
func resolve_abandoned_run() -> void:
	if not flags.has("in_run"):
		return
	flags.erase("in_run")
	end_day(0)


## Map rows, bottom to top. Each node: {"type", "enemy", "event", "links": [cols in next row]}.
## Types: fight, elite, rest, event, lesion (shop), cyst (treasure), needle, boss.
## Normal regions: 7 rows of 2-4 nodes, then the heart. Links never cross.
func _make_nodes(region: String) -> Array:
	if region == "root":
		var rr: Array = [
			[_node("fight", region, [0])],
			[_node("rest", region, [0, 1])],
			[_node("elite", region, [0]), _node("fight", region, [0])],
			[_node("rest", region, [0])],
			[_node("boss", region, [])],
		]
		return rr
	var sizes: Array = [randi_range(2, 3)]
	for i in 5:
		sizes.append(randi_range(2, 4))
	sizes.append(randi_range(2, 3))
	sizes.append(1)
	# Types.
	var types: Array = []
	for r in sizes.size():
		var row_t: Array = []
		var n: int = sizes[r]
		for c in n:
			var t := "fight"
			if r == sizes.size() - 1:
				t = "boss"
			elif r == sizes.size() - 2:
				t = "rest"
			elif r >= 1:
				t = _roll_type(r, row_t)
			row_t.append(t)
		types.append(row_t)
	# Guarantees: one elite, one lesion, one needle in the middle rows.
	_force_type(types, "elite", 2, 5)
	_force_type(types, "lesion", 2, 4)
	_force_type(types, "needle", 2, 5)
	_cap_type(types, "needle", 1)
	_cap_type(types, "lesion", 2)
	# Links.
	var links: Array = []
	for r in sizes.size() - 1:
		links.append(_row_links(int(sizes[r]), int(sizes[r + 1])))
	links.append([[]])
	# Build.
	var used_events: Array = []
	var rows: Array = []
	for r in sizes.size():
		var row_n: Array = []
		var row_t: Array = types[r]
		var row_l: Array = links[r]
		for c in row_t.size():
			var t: String = row_t[c]
			var nd := _node(t, region, row_l[c])
			if t == "event":
				var eid := _pick_event(region, used_events)
				if eid == "":
					nd = _node("fight", region, row_l[c])
				else:
					nd["event"] = eid
					used_events.append(eid)
			row_n.append(nd)
		rows.append(row_n)
	return rows


func _node(type: String, region: String, links: Array) -> Dictionary:
	var re: Dictionary = Cards.REGION_ENEMIES.get(region, Cards.REGION_ENEMIES["wound"])
	var enemy := ""
	match type:
		"fight":
			var normal = re.get("normal", [])
			if normal is Array and not (normal as Array).is_empty():
				enemy = String((normal as Array)[randi() % (normal as Array).size()])
			else:
				enemy = String(normal)
		"elite":
			var elite = re.get("elite", "")
			if elite is Array and not (elite as Array).is_empty():
				enemy = String((elite as Array)[randi() % (elite as Array).size()])
			else:
				enemy = String(elite)
		"boss":
			enemy = String(re.get("boss", ""))
	return {"type": type, "enemy": enemy, "event": "", "links": links.duplicate()}


## Weighted pick for a middle row. Keeps events and cysts spread (max 1 each per row).
func _roll_type(r: int, row_t: Array) -> String:
	var bag: Array = ["fight", "fight", "fight", "fight", "fight", "event", "event"]
	if r >= 2:
		bag.append("elite")
	if r >= 2 and r <= 4:
		bag.append("rest")
	if r >= 2:
		bag.append("cyst")
	for t in ["event", "cyst", "elite", "rest"]:
		if row_t.has(t):
			while bag.has(t):
				bag.erase(t)
	return String(bag[randi() % bag.size()])


## Make sure at least one node of `type` exists in rows lo..hi (turns a fight into it).
func _force_type(types: Array, type: String, lo: int, hi: int) -> void:
	var spots: Array = []
	for r in range(lo, mini(hi, types.size() - 3) + 1):
		var row_t: Array = types[r]
		if row_t.has(type):
			return
		for c in row_t.size():
			if row_t[c] == "fight":
				spots.append(Vector2i(r, c))
	if spots.is_empty():
		return
	var s: Vector2i = spots[randi() % spots.size()]
	var row_s: Array = types[s.x]
	row_s[s.y] = type


## At most `cap` nodes of `type` in the whole map; extras become fights.
func _cap_type(types: Array, type: String, cap: int) -> void:
	var seen := 0
	for row_t in types:
		var rt: Array = row_t
		for c in rt.size():
			if rt[c] == type:
				seen += 1
				if seen > cap:
					rt[c] = "fight"


## Non-crossing links between a row of n nodes and a row of m: a monotone staircase.
## Every node gets an edge in and out; each node links to 1-2 nodes ahead.
func _row_links(n: int, m: int) -> Array:
	var out: Array = []
	for i in n:
		out.append([])
	var i := 0
	var j := 0
	(out[0] as Array).append(0)
	while i < n - 1 or j < m - 1:
		var cand: Array = []
		var li: Array = out[i]
		# advance j: node i takes a second link.
		if j < m - 1 and li.size() < 2 and (m - 2 - j) <= 2 * (n - 1 - i):
			cand.append("j")
		# advance both.
		if i < n - 1 and j < m - 1 and (m - 2 - j) <= 1 + 2 * (n - 2 - i):
			cand.append("b")
			cand.append("b")
		# advance i: next node shares node j.
		if i < n - 1 and (m - 1 - j) <= 1 + 2 * (n - 2 - i):
			cand.append("i")
		if cand.is_empty():
			break
		var step: String = cand[randi() % cand.size()]
		if step != "i":
			j += 1
		if step != "j":
			i += 1
		(out[i] as Array).append(j)
	return out


func _pick_event(region: String, exclude: Array) -> String:
	var path := "res://scripts/run/events.gd"
	if not ResourceLoader.exists(path):
		return ""
	var ev: Script = load(path)
	return String(ev.pick(region, stage, day, exclude))


## Called by the run layer when the run is over. won=true means the region boss fell.
## For the Root, `root_result` is "destroy" (→ purge) or "bind" (→ graft).
## Tissue: a won run banks all of `run.tissue`, a lost run half (floor). Shown as a toast
## and kept in flags["last_bank"].
func finish_run(won: bool, root_result := "") -> void:
	var region: String = run.get("region", "")
	var uptake: int = run.get("uptake", 0)
	var parts := PackedStringArray()
	var tissue: Dictionary = run.get("tissue", {})
	for mat in tissue.keys():
		var n: int = int(tissue[mat])
		if not won:
			n = n / 2
		if n > 0:
			materials[mat] = int(materials.get(mat, 0)) + n
			parts.append("%d %s" % [n, String(mat).to_upper()])
	var run_reagent: int = int(run.get("reagent", 0))
	if won:
		reagent += run_reagent
		for id in run.get("strand", []):
			if Cards.is_green(id):
				green_samples += 1
		if region == "root":
			ending = "graft" if root_result == "bind" else "purge"
		else:
			regions[region] = 0
			var first := not cleared_once.has(region)
			cleared_once[region] = true
			_region_reward(region, first)
	else:
		last_failed_strand = (run.get("strand", []) as Array).duplicate()
		run_reagent = run_reagent / 2
		reagent += run_reagent
	if run_reagent > 0:
		parts.append("%d REAGENT" % run_reagent)
	var bank_text := "BANKED: " + (", ".join(parts) if parts.size() > 0 else "NOTHING")
	flags["last_bank"] = bank_text
	UI.toast(bank_text, UI.C_INK)
	run = {}
	flags.erase("in_run")
	end_day(uptake)
	if ending != "":
		goto("ending")
	elif pending_dream > 0:
		goto("dream")
	else:
		goto("lab")


const ENDINGS_PATH := "user://strain_endings.json"


## Endings seen across all saves. Finishing a save erases it (the story is over).
func record_ending(key: String) -> void:
	var seen := endings_seen()
	if not seen.has(key):
		seen.append(key)
	var f := FileAccess.open(ENDINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(seen))
	wipe_save()


func endings_seen() -> Array:
	if not FileAccess.file_exists(ENDINGS_PATH):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(ENDINGS_PATH))
	return d if d is Array else []


func _region_reward(region: String, first: bool) -> void:
	match region:
		"wound":
			if first:
				steady_hands = true
			else:
				reagent += 3
		"rivers":
			push_back(RIVERS_AMOUNT)
		"hollow":
			if first:
				hollow_bonus = 1
				if not strains.has("weaver"):
					strains.append("weaver")
			extra_breath += 1
		"archive":
			if memories < 4:
				memories += 1
				pending_dream = memories
				if memories <= 3:
					leash_pages[str(memories)] = true


func region_reward_text(region: String) -> String:
	return REGION_REWARD_TEXT.get(region, "")


# ------------------------------------------------------------ debug

## Command-line: godot --path . -- --scene=battle --setup=midgame --shot=out.png --frames=30
func _handle_debug_args() -> void:
	var args := _user_args()
	if args.has("setup"):
		debug_setup(args["setup"])
	if args.has("scene"):
		get_tree().change_scene_to_file(SCENES[args["scene"]])


func _user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


## Kinds: run, battle, boss, root, midgame, late, rich, and the run_map screens
## shop / event / reward / cyst / needle / rest (use with --scene=run_map;
## --event=<id> forces a specific event).
func debug_setup(kind: String) -> void:
	new_game()
	match kind:
		"run":
			culture["traits"] = ["pellicle", "scar_tissue"]
			culture["trait_slots"] = 2
			culture["boosters"] = ["clotter"]
			start_run("wound")
		"battle":
			start_run(args_region())
			_debug_walk(0)
			run["battle"] = {"kind": "fight", "enemy": _debug_node()["enemy"]}
		"boss":
			start_run(args_region())
			var nodes: Array = run["nodes"]
			_debug_walk(nodes.size() - 1)
			run["battle"] = {"kind": "boss", "enemy": _debug_node()["enemy"]}
		"root":
			for r in REGIONS:
				cleared_once[r] = true
			leash_pages = {"1": true, "2": true, "3": true, "4": true}
			green_samples = 3
			powered = {"bench": true, "generator": true, "garden": true}
			start_run("root")
			var rnodes: Array = run["nodes"]
			_debug_walk(rnodes.size() - 1)
			run["battle"] = {"kind": "boss", "enemy": _debug_node()["enemy"]}
		"midgame":
			_debug_midgame()
		"rich":
			_debug_midgame()
			reagent = 20
			materials = {"clot": 5, "plasma": 5, "alveoli": 5, "myelin": 5}
			strains = ["scrubber", "courier", "lytic", "weaver"]
			culture["grown"] = ["pellicle", "quorum_sense", "scar_tissue", "whiplash"]
			culture["traits"] = ["pellicle"]
			culture["boosters"] = ["saline", "clotter"]
			flags["specimens"] = ["pellicle", "quorum_sense"]
			flags["found"] = {"pellicle": true, "quorum_sense": true, "drawer": true, "cabinet": true, "key": true}
		"shop", "event", "reward", "cyst", "needle", "rest":
			culture["traits"] = ["pellicle"]
			culture["boosters"] = ["clotter"]
			start_run(args_region())
			run["reagent"] = 14
			run["tissue"] = {Cards.REGION_TISSUE.get(args_region(), "clot"): 3}
			_debug_walk(1)
			if kind == "reward":
				var re: Dictionary = Cards.REGION_ENEMIES.get(args_region(), Cards.REGION_ENEMIES["wound"])
				var el = re.get("elite", "")
				var eid: String = String((el as Array)[0]) if el is Array else String(el)
				run["pending_reward"] = {"kind": "elite", "enemy": eid}
			else:
				run["debug_open"] = kind
				run["debug_event"] = String(_user_args().get("event", ""))
		"late":
			day = 18
			stage = 4
			stage_progress = 50.0
			reagent = 20
			powered = {"bench": true, "generator": true, "medbay": true, "cctv": true, "comms": true, "garden": true}
	if kind in ["battle", "boss", "root"]:
		var ua := _user_args()
		flags["tutorial_done"] = not ua.has("tut")
		if ua.has("enemy") and Cards.ENEMIES.has(String(ua["enemy"])):
			run["battle"]["enemy"] = String(ua["enemy"])
	breath = breath_max()


func _debug_midgame() -> void:
	day = 9
	stage = 2
	stage_progress = 40.0
	reagent = 12
	powered = {"bench": true, "generator": true, "medbay": true, "cctv": true}
	cleared_once = {"wound": true}
	regions["wound"] = 0
	lore = {"vial": 1, "whiteboard": 1, "badge": 1, "binder": 3}


## Debug: mark rows 0..to_row as walked along links, ending on that row.
func _debug_walk(to_row: int) -> void:
	var nodes: Array = run["nodes"]
	var path: Array = []
	var c := 0
	for r in range(0, mini(to_row, nodes.size() - 1) + 1):
		if r > 0:
			var prev_row: Array = nodes[r - 1]
			var prev: Dictionary = prev_row[c]
			var links: Array = prev.get("links", [0])
			c = int(links[0]) if links.size() > 0 else 0
		path.append(c)
	run["path"] = path
	run["row"] = path.size() - 1
	run["col"] = c


func _debug_node() -> Dictionary:
	var nodes: Array = run["nodes"]
	var r: int = clampi(int(run.get("row", 0)), 0, nodes.size() - 1)
	var row_n: Array = nodes[r]
	var c: int = clampi(int(run.get("col", 0)), 0, row_n.size() - 1)
	return row_n[c]


func args_region() -> String:
	return _user_args().get("region", "wound")
