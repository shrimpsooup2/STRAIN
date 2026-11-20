extends Node
## Gene (card) and enemy definitions. Pure data + small lookups.
##
## Card fields:
##   name   ≤10 chars, shown on the card
##   cost   Charge to express
##   kind   "gene" | "passive" | "junk"
##   green  true for Green genes (expressing one adds 1 Uptake → speeds the real infection)
##   short  ≤10 chars, the one-line summary on the card face
##   desc   full rules text (description box, ≤ ~90 chars)
##   fx     effect list (see FX below)
##   passive  (passive only) {"charge": n} and/or {"film": n}, applied at the start of each turn while in the Strand
##   pact   (optional) colony lost if this gene is ever removed from the Strand
##
## FX schema — `src` is whoever expresses, `dst` their opponent:
##   {"t":"dmg","n":N,"k":K}       deal N (+src grow) K times (k default 1); Film absorbs first
##   {"t":"film","n":N}            src gains N Film (Film clears at the start of src's turn)
##   {"t":"heal","n":N}            src regains N Colony (up to max)
##   {"t":"chorus","n":±N}         shared Chorus track, clamped 0..10
##   {"t":"if_chorus","min":N,"fx":[..]}  apply nested fx if Chorus ≥ N
##   {"t":"dmg_chorus","mult":M}   deal Chorus × M
##   {"t":"free_next"}             next gene this turn costs 0 (player)
##   {"t":"charge","n":N}          +N Charge now (player)
##   {"t":"charge_next","n":N}     +N Charge next turn (player)
##   {"t":"drifter","burst":N,"latent":M,"turns":T}  Chorus < 5: deal N now. Else plant a Latent on dst that deals M after T turns
##   {"t":"hop","ahead":A}         copy this gene A slots ahead in the fight Strand, overwriting (silencing) what was there
##   {"t":"ledger"}                record the enemy's current intent id for the rest of the run (max 3); recorded intents fizzle
##   {"t":"tripwire"}              arm a trap: the next enemy plant/uproot/drain is cancelled; you lose 3 Colony
##   {"t":"rot","n":N,"turns":T}   dst loses N at the start of each of its turns, T times
##   {"t":"fray","n":±N}           run-level mutation meter
##   {"t":"grow","n":N}            src permanent +N damage this fight
##   {"t":"plant","n":N}           (enemy) insert N OVERGROWTH junk into the player's fight Strand just after the Reader
##   {"t":"uproot"}                (enemy) remove a random non-junk gene from the fight Strand; Pact genes punish their owner
##   {"t":"drain","n":N}           deal N; src heals the amount that got through Film
##   {"t":"echo"}                  repeat the previous expressed gene's fx
##   {"t":"clear"}                 remove this gene from the fight Strand (junk)

const CARDS := {
	# --- starters / common
	"lyse": {"name": "LYSE", "cost": 1, "kind": "gene", "short": "DMG 6",
		"desc": "Deal 6.", "fx": [{"t": "dmg", "n": 6}]},
	"film": {"name": "FILM", "cost": 1, "kind": "gene", "short": "FILM 5",
		"desc": "Gain 5 Film.", "fx": [{"t": "film", "n": 5}]},
	"signal": {"name": "SIGNAL", "cost": 0, "kind": "gene", "short": "CHORUS+2",
		"desc": "Chorus +2.", "fx": [{"t": "chorus", "n": 2}]},
	"promoter": {"name": "PROMOTER", "cost": 0, "kind": "gene", "short": "NEXT FREE",
		"desc": "The next gene you express this turn costs 0.", "fx": [{"t": "free_next"}]},
	"spike": {"name": "SPIKE", "cost": 2, "kind": "gene", "short": "DMG 10",
		"desc": "Deal 10. Chorus 6: deal 4 more.",
		"fx": [{"t": "dmg", "n": 10}, {"t": "if_chorus", "min": 6, "fx": [{"t": "dmg", "n": 4}]}]},
	"membrane": {"name": "MEMBRANE", "cost": 1, "kind": "gene", "short": "FILM 4+",
		"desc": "Gain 4 Film. Chorus 4: gain 4 more.",
		"fx": [{"t": "film", "n": 4}, {"t": "if_chorus", "min": 4, "fx": [{"t": "film", "n": 4}]}]},
	"swarm": {"name": "SWARM", "cost": 1, "kind": "gene", "short": "DMG 3x2",
		"desc": "Deal 3 twice.", "fx": [{"t": "dmg", "n": 3, "k": 2}]},
	"divide": {"name": "DIVIDE", "cost": 1, "kind": "gene", "short": "HEAL 5",
		"desc": "Regain 5 Colony.", "fx": [{"t": "heal", "n": 5}]},
	"quorum": {"name": "QUORUM", "cost": 1, "kind": "gene", "short": "DMG=CHOR",
		"desc": "Deal damage equal to the Chorus.", "fx": [{"t": "dmg_chorus", "mult": 1}]},
	"hush": {"name": "HUSH", "cost": 1, "kind": "gene", "short": "CHORUS-3",
		"desc": "Chorus -3. Gain 3 Film.", "fx": [{"t": "chorus", "n": -3}, {"t": "film", "n": 3}]},
	"drifter": {"name": "DRIFTER", "cost": 1, "kind": "gene", "short": "BURST/SET",
		"desc": "Chorus under 5: deal 9 now. Otherwise SETTLE: 15 damage in 2 turns.",
		"fx": [{"t": "drifter", "burst": 9, "latent": 15, "turns": 2}]},
	"hopper": {"name": "HOPPER", "cost": 1, "kind": "gene", "short": "DMG 4 HOP",
		"desc": "Deal 4. HOP: copies itself 5 slots ahead, silencing what it lands on.",
		"fx": [{"t": "dmg", "n": 4}, {"t": "hop", "ahead": 5}]},
	"siphon": {"name": "SIPHON", "cost": 1, "kind": "gene", "short": "DRAIN 5",
		"desc": "Deal 5. Regain what gets through.", "fx": [{"t": "drain", "n": 5}]},
	"proofread": {"name": "PROOFREAD", "cost": 1, "kind": "gene", "short": "FRAY-2",
		"desc": "Fray -2. Gain 3 Film.", "fx": [{"t": "fray", "n": -2}, {"t": "film", "n": 3}]},
	"catalyst": {"name": "CATALYST", "cost": 1, "kind": "gene", "short": "+2 CHG NXT",
		"desc": "+2 Charge next turn.", "fx": [{"t": "charge_next", "n": 2}]},
	"rot": {"name": "ROT", "cost": 1, "kind": "gene", "short": "ROT 3x3",
		"desc": "Enemy loses 3 at the start of its next 3 turns.", "fx": [{"t": "rot", "n": 3, "turns": 3}]},
	# --- sequenced at the bench (meta unlocks)
	"ledger": {"name": "LEDGER", "cost": 1, "kind": "gene", "short": "RECORD",
		"desc": "Record the enemy's intent. It fizzles for the rest of this run. (Max 3.)",
		"fx": [{"t": "ledger"}]},
	"tripwire": {"name": "TRIPWIRE", "cost": 0, "kind": "gene", "short": "TRAP",
		"desc": "Arm a trap: cancel the next enemy plant, uproot or drain. You lose 3 Colony.",
		"fx": [{"t": "tripwire"}]},
	"pact_coil": {"name": "PACT COIL", "cost": 0, "kind": "passive", "short": "+1 CHARGE",
		"desc": "PASSIVE: +1 Charge each turn. PACT: if removed from the Strand, lose 8 Colony.",
		"fx": [], "passive": {"charge": 1}, "pact": 8},
	"thick_wall": {"name": "THICK WALL", "cost": 0, "kind": "passive", "short": "+3 FILM/T",
		"desc": "PASSIVE: gain 3 Film at the start of each turn.", "fx": [], "passive": {"film": 3}},
	"sporewall": {"name": "SPOREWALL", "cost": 2, "kind": "gene", "short": "FILM 12",
		"desc": "Gain 12 Film.", "fx": [{"t": "film", "n": 12}]},
	"echo": {"name": "ECHO", "cost": 1, "kind": "gene", "short": "REPEAT",
		"desc": "Repeat the last gene you expressed.", "fx": [{"t": "echo"}]},
	"crescendo": {"name": "CRESCENDO", "cost": 2, "kind": "gene", "short": "CHOR8:22",
		"desc": "Chorus +2. Chorus 8: deal 22.",
		"fx": [{"t": "chorus", "n": 2}, {"t": "if_chorus", "min": 8, "fx": [{"t": "dmg", "n": 22}]}]},
	# --- Green genes (taken from the thing inside you)
	"g_lash": {"name": "G.LASH", "cost": 0, "kind": "gene", "green": true, "short": "DMG 9",
		"desc": "GREEN. Deal 9. (+1 Uptake: the real infection speeds up.)", "fx": [{"t": "dmg", "n": 9}]},
	"g_root": {"name": "G.ROOT", "cost": 1, "kind": "gene", "green": true, "short": "FILM10 +4",
		"desc": "GREEN. Gain 10 Film, regain 4 Colony. (+1 Uptake.)",
		"fx": [{"t": "film", "n": 10}, {"t": "heal", "n": 4}]},
	"g_chorus": {"name": "G.CHORUS", "cost": 0, "kind": "gene", "green": true, "short": "CHOR+4 +1C",
		"desc": "GREEN. Chorus +4. +1 Charge now. (+1 Uptake.)",
		"fx": [{"t": "chorus", "n": 4}, {"t": "charge", "n": 1}]},
	"g_bloom": {"name": "G.BLOOM", "cost": 1, "kind": "gene", "green": true, "short": "DMG 5x3",
		"desc": "GREEN. Deal 5 three times. (+1 Uptake.)", "fx": [{"t": "dmg", "n": 5, "k": 3}]},
	# --- junk
	"overgrowth": {"name": "OVERGROWTH", "cost": 1, "kind": "junk", "short": "CLEAR",
		"desc": "Junk planted by the Green. Express to clear it from the Strand.",
		"fx": [{"t": "clear"}]},
}

const STRAINS := {
	"scrubber": {"name": "SCRUBBER", "desc": "Attrition. Film and steady damage.",
		"strand": ["promoter", "spike", "lyse", "film", "signal", "membrane", "lyse", "film"]},
	"courier": {"name": "COURIER", "desc": "Signals, drifters and theft.",
		"strand": ["signal", "drifter", "lyse", "film", "signal", "hopper", "ledger", "film"]},
}

## Reward pool available from day 1.
const STARTING_POOL := ["swarm", "divide", "quorum", "hush", "drifter", "hopper", "siphon",
	"proofread", "catalyst", "rot", "lyse", "film", "membrane", "spike"]
## Genes the bench can sequence into the pool (cost in reagent).
const SEQUENCEABLE := {"ledger": 3, "tripwire": 3, "pact_coil": 5, "thick_wall": 5,
	"sporewall": 4, "echo": 4, "crescendo": 5}
const GREEN_POOL := ["g_lash", "g_root", "g_chorus", "g_bloom"]

# ------------------------------------------------------------------ enemies
## Intent: {"id": unique-for-Ledger, "name": shown text, "fx": [...]}. Patterns cycle.
## Shared region intents use the same id so a Ledger entry keeps paying off.
const ENEMIES := {
	# THE WOUND
	"creeper": {"name": "CREEPER", "colony": 18, "pattern": [
		{"id": "w_lash", "name": "LASH 5", "fx": [{"t": "dmg", "n": 5}]},
		{"id": "w_lash", "name": "LASH 5", "fx": [{"t": "dmg", "n": 5}]},
		{"id": "w_crust", "name": "CRUST 4", "fx": [{"t": "film", "n": 4}]}]},
	"knot": {"name": "TENDRIL KNOT", "colony": 24, "pattern": [
		{"id": "w_thicken", "name": "THICKEN", "fx": [{"t": "grow", "n": 2}]},
		{"id": "w_lash", "name": "LASH 4", "fx": [{"t": "dmg", "n": 4}]},
		{"id": "w_seed", "name": "SEED 1", "fx": [{"t": "plant", "n": 1}]}]},
	"scab": {"name": "THE SCAB", "colony": 52, "boss": true, "pattern": [
		{"id": "w_crust", "name": "CRUST 10", "fx": [{"t": "film", "n": 10}]},
		{"id": "w_lash", "name": "LASH 8", "fx": [{"t": "dmg", "n": 8}]},
		{"id": "w_seed", "name": "SEED 2", "fx": [{"t": "plant", "n": 2}]},
		{"id": "w_rake", "name": "RAKE 4x3", "fx": [{"t": "dmg", "n": 4, "k": 3}]}]},
	# THE RIVERS
	"pod": {"name": "DRIFT POD", "colony": 20, "pattern": [
		{"id": "r_call", "name": "CALL +2", "fx": [{"t": "chorus", "n": 2}]},
		{"id": "r_burst", "name": "BURST 7", "fx": [{"t": "dmg", "n": 7}]}]},
	"current": {"name": "CURRENT", "colony": 26, "pattern": [
		{"id": "r_tide", "name": "TIDE 3x2", "fx": [{"t": "dmg", "n": 3, "k": 2}]},
		{"id": "r_eddy", "name": "EDDY 5", "fx": [{"t": "film", "n": 5}]},
		{"id": "r_pull", "name": "PULL 4", "fx": [{"t": "drain", "n": 4}]}]},
	"undertow": {"name": "UNDERTOW", "colony": 58, "boss": true, "pattern": [
		{"id": "r_uproot", "name": "UPROOT", "fx": [{"t": "uproot"}]},
		{"id": "r_burst", "name": "BURST 10", "fx": [{"t": "dmg", "n": 10}]},
		{"id": "r_pull", "name": "PULL 6", "fx": [{"t": "drain", "n": 6}]},
		{"id": "r_tide", "name": "TIDE 4x3", "fx": [{"t": "dmg", "n": 4, "k": 3}]}]},
	# THE HOLLOW
	"choir_cell": {"name": "CHOIR CELL", "colony": 22, "pattern": [
		{"id": "h_hum", "name": "HUM +3", "fx": [{"t": "chorus", "n": 3}]},
		{"id": "h_peal", "name": "PEAL 4/14", "fx": [{"t": "dmg", "n": 4},
			{"t": "if_chorus", "min": 7, "fx": [{"t": "dmg", "n": 10}]}]}]},
	"bellows": {"name": "BELLOWS", "colony": 28, "pattern": [
		{"id": "h_inhale", "name": "INHALE 8", "fx": [{"t": "film", "n": 8}]},
		{"id": "h_exhale", "name": "EXHALE 9", "fx": [{"t": "dmg", "n": 9}]}]},
	"choir": {"name": "THE CHOIR", "colony": 62, "boss": true, "pattern": [
		{"id": "h_hum", "name": "HUM +4", "fx": [{"t": "chorus", "n": 4}]},
		{"id": "h_swell", "name": "SWELL", "fx": [{"t": "dmg_chorus", "mult": 2}]},
		{"id": "h_tune", "name": "TUNE +2", "fx": [{"t": "grow", "n": 2}, {"t": "chorus", "n": 1}]},
		{"id": "h_exhale", "name": "EXHALE 11", "fx": [{"t": "dmg", "n": 11}]}]},
	# THE ARCHIVE
	"mimic": {"name": "MIMIC", "colony": 26, "pattern": "mimic_last"},
	"eraser": {"name": "ERASER", "colony": 24, "pattern": [
		{"id": "a_blot", "name": "BLOT 2", "fx": [{"t": "plant", "n": 2}]},
		{"id": "a_uproot", "name": "UNWRITE", "fx": [{"t": "uproot"}]},
		{"id": "a_strike", "name": "STRIKE 6", "fx": [{"t": "dmg", "n": 6}]}]},
	"archivist": {"name": "ARCHIVIST", "colony": 48, "boss": true, "pattern": "mimic_run"},
	# THE ROOT
	"core": {"name": "THE CORE", "colony": 100, "boss": true, "pattern": [
		{"id": "x_grow", "name": "SPREAD", "fx": [{"t": "grow", "n": 2}, {"t": "chorus", "n": 2}]},
		{"id": "x_lash", "name": "LASH 12", "fx": [{"t": "dmg", "n": 12}]},
		{"id": "x_seed", "name": "SEED 2", "fx": [{"t": "plant", "n": 2}]},
		{"id": "x_drink", "name": "DRINK 8", "fx": [{"t": "drain", "n": 8}]},
		{"id": "x_bark", "name": "BARK 15", "fx": [{"t": "film", "n": 15}]},
		{"id": "x_lash", "name": "LASH 12", "fx": [{"t": "dmg", "n": 12}]}]},
	"tendril": {"name": "ROOT TENDRIL", "colony": 34, "pattern": [
		{"id": "x_lash", "name": "LASH 7", "fx": [{"t": "dmg", "n": 7}]},
		{"id": "x_seed", "name": "SEED 1", "fx": [{"t": "plant", "n": 1}]},
		{"id": "x_drink", "name": "DRINK 5", "fx": [{"t": "drain", "n": 5}]}]},
}

const REGION_ENEMIES := {
	"wound": {"normal": ["creeper", "knot"], "elite": "knot", "boss": "scab"},
	"rivers": {"normal": ["pod", "current"], "elite": "current", "boss": "undertow"},
	"hollow": {"normal": ["choir_cell", "bellows"], "elite": "bellows", "boss": "choir"},
	"archive": {"normal": ["mimic", "eraser"], "elite": "mimic", "boss": "archivist"},
	"root": {"normal": ["tendril"], "elite": "tendril", "boss": "core"},
}

## Visual palette per region (battle backdrop, body map tint).
const REGION_COLORS := {
	"wound": {"bg": Color("2a0c10"), "fog": Color("4a1418"), "floor": Color("6a2028"), "accent": Color("e06060")},
	"rivers": {"bg": Color("200810"), "fog": Color("501020"), "floor": Color("802030"), "accent": Color("ff7070")},
	"hollow": {"bg": Color("182028"), "fog": Color("3a4858"), "floor": Color("c09aa8"), "accent": Color("a8d0f0")},
	"archive": {"bg": Color("100c20"), "fog": Color("281c48"), "floor": Color("483870"), "accent": Color("b098f0")},
	"root": {"bg": Color("061008"), "fog": Color("0c2810"), "floor": Color("1c3a18"), "accent": Color("70d850")},
}


func card(id: String) -> Dictionary:
	return CARDS.get(id, CARDS["overgrowth"])


func is_green(id: String) -> bool:
	return CARDS.get(id, {}).get("green", false)


func is_passive(id: String) -> bool:
	return CARDS.get(id, {}).get("kind", "") == "passive"


func is_junk(id: String) -> bool:
	return CARDS.get(id, {}).get("kind", "") == "junk"


## Three reward offers. From stage 1 on, one slot is a Green gene.
func reward_offers(unlocked: Array, stage: int) -> Array:
	var pool := unlocked.duplicate()
	pool.shuffle()
	var out: Array = []
	for id in pool:
		if not out.has(id):
			out.append(id)
		if out.size() == 3:
			break
	if stage >= 1 and out.size() > 0:
		out[out.size() - 1] = GREEN_POOL[randi() % GREEN_POOL.size()]
	return out


func enemy(id: String) -> Dictionary:
	return ENEMIES[id]


## Converts a card list into an intent pattern (MIMIC / ARCHIVIST play your genes back at you).
func mimic_pattern(strand: Array) -> Array:
	var out: Array = []
	for id in strand:
		var c := card(id)
		if c["kind"] != "gene" or (c["fx"] as Array).is_empty():
			continue
		var fx: Array = []
		for e in c["fx"]:
			# Player-only effects make no sense for an enemy: swap for something equivalent.
			match e["t"]:
				"free_next", "charge", "charge_next", "ledger", "tripwire", "fray", "hop", "echo":
					fx.append({"t": "film", "n": 3})
				_:
					fx.append(e)
		out.append({"id": "m_" + id, "name": c["name"], "fx": fx})
	if out.is_empty():
		out = [{"id": "m_blank", "name": "SCRAWL 6", "fx": [{"t": "dmg", "n": 6}]}]
	return out
