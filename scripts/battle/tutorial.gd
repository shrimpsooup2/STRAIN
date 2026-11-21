extends RefCounted
## First-fight briefing. Each step shows once, as "think" lines (≤ 8 words).
## Active only while Game.flags["tutorial_done"] is false. The first step
## offers to skip the whole briefing. Call finish() at the end of the fight.

const STEPS := {
	"window": [
		"The Reader shows five genes.",
		"Left three are READ. They leave at END.",
		"Unexpressed genes that leave are SKIPPED.",
		"Expressing costs CHARGE. Three per turn.",
	],
	"read": [
		"A bar sweeps when a gene expresses.",
		"Press Z inside the green. CLEAN.",
		"CLEAN reads hit half again harder.",
	],
	"link": [
		"Express the gene right of your last.",
		"That is a LINK. Chains grow stronger.",
	],
	"marked": [
		"It marked genes in my window.",
		"Express marked genes, or lose them.",
	],
	"break": [
		"It is winding up something big.",
		"Deal damage this turn to fill BREAK.",
		"Fill it and the strike is cancelled.",
	],
	"splice": [
		"Q SPLICE swaps a gene rightward.",
		"Build links the strand will not give.",
		"R MUTATE rerolls a gene. Costs Fray.",
	],
	"chorus": [
		"The Chorus moved. QUIET, HUM, LOUD.",
		"Some genes change in a band.",
		"At ten it RESONATES. Doubles a gene.",
	],
	"boost": [
		"F injects a carried booster. Free.",
	],
}

var active := false
var _asked := false
var _seen := {}


func _init() -> void:
	active = not bool(Game.flags.get("tutorial_done", false))


func pending(key: String) -> bool:
	return active and not _seen.has(key)


## Shows one step (awaitable). Returns immediately if already seen / inactive.
func show_step(key: String) -> void:
	if not pending(key) or not STEPS.has(key):
		return
	_seen[key] = true
	if not _asked:
		_asked = true
		var pick: int = await UI.choose(["BRIEF ME", "SKIP"], "Skip the briefing?", true, 1)
		if pick != 0:
			active = false
			return
	var lines: Array = STEPS[key]
	await UI.say(lines, "think")


func finish() -> void:
	Game.flags["tutorial_done"] = true
