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
	"hollow": "Breath comes easier. +1 BREATH.",
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
	flags = {}
	run = {}
	breath = breath_max()
	save_game()


func _state_keys() -> Array:
	return ["day", "stage", "stage_progress", "breath", "reagent", "green_samples", "lore",
		"thoughts", "powered", "regions", "cleared_once", "memories", "pending_dream",
		"leash_pages", "unlocked", "gene_bank", "bank_slots", "strain", "strains", "start_order",
		"last_failed_strand", "hollow_bonus", "extra_breath", "steady_hands", "treated_today",
		"supply_taken_day", "ending", "flags"]


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
	return true


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


func start_run(region: String) -> void:
	var is_root := region == "root"
	run = {
		"region": region,
		"is_root": is_root,
		"growth": 3 if is_root else int(regions.get(region, 1)),
		"strand": starting_strand(),
		"colony": START_COLONY,
		"max_colony": START_COLONY,
		"fray": 0,
		"ledger": [],
		"uptake": 0,
		"reagent": 0,
		"row": -1,
		"col": -1,
		"nodes": _make_nodes(is_root),
		"battle": {},
		"result": "",
	}
	flags["in_run"] = true
	save_game()


## A run that was quit mid-way (closed the game) counts as a failed culture.
func resolve_abandoned_run() -> void:
	if not flags.has("in_run"):
		return
	flags.erase("in_run")
	end_day(0)


## Rows of node types. Each row: 1–2 options. Last row is the boss.
func _make_nodes(is_root: bool) -> Array:
	if is_root:
		return [["fight"], ["rest"], ["elite", "fight"], ["rest"], ["boss"]]
	var rows: Array = [["fight"]]
	var pool := ["fight", "rest", "event"]
	for i in 3:
		var a: String = pool[randi() % pool.size()]
		var b: String = pool[randi() % pool.size()]
		if a == b:
			b = "fight" if a != "fight" else "event"
		rows.append([a, b] if i != 1 else [a, b, "elite"])
	rows.append(["boss"])
	return rows


## Called by the run layer when the run is over. won=true means the region boss fell.
## For the Root, `root_result` is "destroy" (→ purge) or "bind" (→ graft).
func finish_run(won: bool, root_result := "") -> void:
	var region: String = run.get("region", "")
	var uptake: int = run.get("uptake", 0)
	if won:
		reagent += int(run.get("reagent", 0))
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
		reagent += int(run.get("reagent", 0)) / 2
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


func debug_setup(kind: String) -> void:
	new_game()
	match kind:
		"run":
			start_run("wound")
		"battle":
			start_run(args_region())
			run["row"] = 0
			run["col"] = 0
			run["battle"] = {"kind": "fight"}
		"boss":
			start_run(args_region())
			run["battle"] = {"kind": "boss"}
		"root":
			for r in REGIONS:
				cleared_once[r] = true
			leash_pages = {"1": true, "2": true, "3": true, "4": true}
			green_samples = 3
			powered = {"bench": true, "generator": true, "garden": true}
			start_run("root")
			run["battle"] = {"kind": "boss"}
		"midgame":
			day = 9
			stage = 2
			stage_progress = 40.0
			reagent = 12
			powered = {"bench": true, "generator": true, "medbay": true, "cctv": true}
			cleared_once = {"wound": true}
			regions["wound"] = 0
			lore = {"vial": 1, "whiteboard": 1, "badge": 1, "binder": 3}
		"late":
			day = 18
			stage = 4
			stage_progress = 50.0
			reagent = 20
			powered = {"bench": true, "generator": true, "medbay": true, "cctv": true, "comms": true, "garden": true}
	breath = breath_max()


func args_region() -> String:
	return _user_args().get("region", "wound")
