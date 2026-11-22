extends Node
## Gene (card) and enemy definitions. Pure data + small lookups.
##
## Card fields:
##   name     ≤8 chars, shown on the card ("+" is appended for upgraded ids)
##   cost     Charge to express
##   kind     "gene" | "passive" | "junk"
##   rarity   "common" | "uncommon" | "rare" (reward weighting)
##   green    true for Green genes (always CLEAN; expressing one adds 1 Uptake → speeds the real infection)
##   short    ≤10 chars, the one-line summary on the card face
##   desc     full rules text (≤ 2 lines × 46 chars). Mode text is always written as trailing
##            " DEEP: ..." / " ALONE: ..." segments so the UI can split and brighten the active one.
##   fx       effect list (see FX below)
##   link     [fx] extra when LINKED (expressed in the slot directly right of the last expressed gene)
##   reach    2: also LINKS across a one-slot gap (BRIDGE)
##   first    [fx] extra when it is the first gene expressed this turn
##   dormant  [fx] runs when the gene is SKIPPED (read without being expressed)
##   deep     [fx] REPLACES fx when expressed LINKED at CHAIN x3 or more
##   lone     [fx] REPLACES fx when expressed unlinked (ALONE: it starts a new chain)
##   burn     true: removed from the fight Strand after it is expressed (one-shot)
##   grows    N: +N to the gene's numbers each time it is expressed this fight
##   breaker  true: its damage counts double toward BREAK
##   up       {overrides} merged over the base for the upgraded id (base + "+")
##   passive  (passive only) {"charge": n} and/or {"film": n}, applied at the start of each turn while in the Strand
##   pact     (optional) colony lost if this gene is ever removed from the Strand
##   unplayable  (junk) true: cannot be expressed
##   dormant_enemy  true: the dormant fx run with the ENEMY as src (scab_plate)
##
## FX schema — `src` is whoever expresses, `dst` their opponent:
##   {"t":"dmg","n":N,"k":K}       deal N (+src grow) K times (k default 1); Film absorbs first
##   {"t":"film","n":N}            src gains N Film (Film clears at the start of src's turn)
##   {"t":"heal","n":N}            src regains N Colony (up to max)
##   {"t":"chain","n":N}           CHAIN +N (player; capped like any chain)
##   {"t":"dmg_count","per":N}     deal N × genes already expressed this turn
##   {"t":"latent","n":N,"turns":T}  plant a Latent on dst that deals N after T of its turns
##   {"t":"trace"}                 resolved on express: the base fx of the gene on its left (spent or not)
##   {"t":"lull","n":N}            enemy's current intent deals N less per hit (min 0)
##   {"t":"free_next"}             next gene this turn costs 0 (player)
##   {"t":"promote"}               if the NEXT gene you express this turn is in the slot directly right, it fires twice
##   {"t":"cap","per":N,"what":"dmg"|"film"}  deal / gain N × current CHAIN, then CHAIN = 0 (terminator)
##   {"t":"splice","n":N}          +N splices this turn
##   {"t":"invert"}                reverse the order of the unspent genes in the window
##   {"t":"pull","n":N}            draw N extra genes into the window this turn (appended at the end)
##   {"t":"mirror"}                gain Film equal to the damage of the enemy's current intent
##   {"t":"self","n":N}            lose N Colony (ignores Film)
##   {"t":"stagger_dmg","n":N}     deal N, doubled if the enemy is winding up (intent has `break`)
##   {"t":"charge","n":N}          +N Charge now (player)
##   {"t":"charge_next","n":N}     +N Charge next turn (player)
##   {"t":"hop","ahead":A}         copy this gene A slots ahead in the fight Strand, overwriting (silencing) what was there
##   {"t":"ledger"}                record the enemy's current intent id for the rest of the run (max 3); recorded intents fizzle
##   {"t":"tripwire"}              arm a trap: the next enemy plant/uproot/drain is cancelled; you lose 3 Colony
##   {"t":"rot","n":N,"turns":T}   dst loses N at the start of each of its turns, T times
##   {"t":"fray","n":±N}           run-level mutation meter
##   {"t":"drain","n":N}           deal N; src heals the amount that got through Film
##   {"t":"echo"}                  repeat the previous expressed gene's fx
##   {"t":"clear"}                 remove this gene from the fight Strand (junk)
## Enemy-only FX:
##   {"t":"grow","n":N}            src permanent +N damage this fight
##   {"t":"plant","n":N,"id":X}    insert N junk (id X, default "overgrowth") into the fight Strand at the draw pointer
##   {"t":"uproot"}                remove a random non-junk gene from the fight Strand; Pact genes punish their owner
##   {"t":"gnaw","n":N}            mark N unspent window genes; unexpressed marked genes are removed for this fight
##   {"t":"knot","n":N}            mark N NEXT genes; unexpressed marked genes are KNOTTED (+1 cost) next turn
##   {"t":"sweep"}                 at this END the whole window is read (NEXT counts as skipped)
##   {"t":"scramble"}              shuffle the unspent window at the start of the next player turn
##   {"t":"mimic_last"}            express a copy of the last gene the player expressed (via mimic_pattern)
##   {"t":"sever","n":N}           on reveal, mark N READ genes: a SEVERED gene can never be LINKED into
## Intent: {"id": unique-for-Ledger, "name": ≤12 chars, "fx": [...], "break": N (optional wind-up)}

const CARDS := {
	# ================================================================ ATTACK
	"lyse": {"name": "LYSE", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "DMG 6", "desc": "Deal 6. LINK: deal 3 more.",
		"fx": [{"t": "dmg", "n": 6}], "link": [{"t": "dmg", "n": 3}],
		"up": {"short": "DMG 9", "desc": "Deal 9. LINK: deal 4 more.",
			"fx": [{"t": "dmg", "n": 9}], "link": [{"t": "dmg", "n": 4}]}},
	"swarm": {"name": "SWARM", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "DMG 3x2", "desc": "Deal 3 twice. LINK: hit once more. DEEP: deal 3 three times.",
		"fx": [{"t": "dmg", "n": 3, "k": 2}], "link": [{"t": "dmg", "n": 3}],
		"deep": [{"t": "dmg", "n": 3, "k": 3}],
		"up": {"short": "DMG 4x2", "desc": "Deal 4 twice. LINK: hit once more. DEEP: deal 4 three times.",
			"fx": [{"t": "dmg", "n": 4, "k": 2}], "link": [{"t": "dmg", "n": 4}],
			"deep": [{"t": "dmg", "n": 4, "k": 3}]}},
	"spike": {"name": "SPIKE", "cost": 2, "kind": "gene", "rarity": "common", "green": false,
		"short": "DMG 11", "desc": "Deal 11. ALONE: deal 16.",
		"fx": [{"t": "dmg", "n": 11}], "lone": [{"t": "dmg", "n": 16}],
		"up": {"short": "DMG 14", "desc": "Deal 14. ALONE: deal 20.",
			"fx": [{"t": "dmg", "n": 14}], "lone": [{"t": "dmg", "n": 20}]}},
	"siphon": {"name": "SIPHON", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "DRAIN 5", "desc": "Deal 5. Regain what gets through. DEEP: drain 8.",
		"fx": [{"t": "drain", "n": 5}], "deep": [{"t": "drain", "n": 8}],
		"up": {"short": "DRAIN 7", "desc": "Deal 7. Regain what gets through. DEEP: drain 11.",
			"fx": [{"t": "drain", "n": 7}], "deep": [{"t": "drain", "n": 11}]}},
	"rot": {"name": "ROT", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "ROT 3x3", "desc": "Enemy loses 3 at the start of its next 3 turns. DEEP: 4 per turn.",
		"fx": [{"t": "rot", "n": 3, "turns": 3}], "deep": [{"t": "rot", "n": 4, "turns": 3}],
		"up": {"short": "ROT 4x3", "desc": "Enemy loses 4 at the start of its next 3 turns. DEEP: 6 per turn.",
			"fx": [{"t": "rot", "n": 4, "turns": 3}], "deep": [{"t": "rot", "n": 6, "turns": 3}]}},
	"needle": {"name": "NEEDLE", "cost": 0, "kind": "gene", "rarity": "common", "green": false,
		"short": "DMG 3", "desc": "Deal 3. LINK: +1 Charge. ALONE: deal 6.",
		"fx": [{"t": "dmg", "n": 3}], "link": [{"t": "charge", "n": 1}],
		"lone": [{"t": "dmg", "n": 6}],
		"up": {"short": "DMG 5", "desc": "Deal 5. LINK: +1 Charge. ALONE: deal 8.",
			"fx": [{"t": "dmg", "n": 5}], "lone": [{"t": "dmg", "n": 8}]}},
	"lance": {"name": "LANCE", "cost": 2, "kind": "gene", "rarity": "rare", "green": false,
		"short": "BREAK 8", "desc": "Deal 8, doubled vs a wind-up. Counts double toward BREAK.",
		"fx": [{"t": "stagger_dmg", "n": 8}], "breaker": true,
		"up": {"short": "BREAK 11", "desc": "Deal 11, doubled vs a wind-up. Counts double toward BREAK.",
			"fx": [{"t": "stagger_dmg", "n": 11}]}},
	"cascade": {"name": "CASCADE", "cost": 2, "kind": "gene", "rarity": "rare", "green": false,
		"short": "4 x CHAIN", "desc": "Deal 4 per CHAIN step, then the chain ends. DEEP: 6 per step.",
		"fx": [{"t": "cap", "per": 4, "what": "dmg"}], "deep": [{"t": "cap", "per": 6, "what": "dmg"}],
		"up": {"short": "5 x CHAIN", "desc": "Deal 5 per CHAIN step, then the chain ends. DEEP: 8 per step.",
			"fx": [{"t": "cap", "per": 5, "what": "dmg"}], "deep": [{"t": "cap", "per": 8, "what": "dmg"}]}},
	"fever": {"name": "FEVER", "cost": 1, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "DMG14 -4C", "desc": "Deal 14. Lose 4 Colony. DEEP: deal 20, lose 4.",
		"fx": [{"t": "dmg", "n": 14}, {"t": "self", "n": 4}],
		"deep": [{"t": "dmg", "n": 20}, {"t": "self", "n": 4}],
		"up": {"short": "DMG18 -3C", "desc": "Deal 18. Lose 3 Colony. DEEP: deal 24, lose 3.",
			"fx": [{"t": "dmg", "n": 18}, {"t": "self", "n": 3}],
			"deep": [{"t": "dmg", "n": 24}, {"t": "self", "n": 3}]}},
	"bloom": {"name": "BLOOM", "cost": 1, "kind": "gene", "rarity": "rare", "green": false,
		"short": "DMG 4 GRW", "desc": "Deal 4. GROWS: +3 each time it is expressed. DEEP: deal 8.",
		"fx": [{"t": "dmg", "n": 4}], "grows": 3, "deep": [{"t": "dmg", "n": 8}],
		"up": {"short": "DMG 5 GRW", "desc": "Deal 5. GROWS: +4 each time it is expressed. DEEP: deal 10.",
			"fx": [{"t": "dmg", "n": 5}], "grows": 4, "deep": [{"t": "dmg", "n": 10}]}},
	"quorum": {"name": "QUORUM", "cost": 1, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "4 x COUNT", "desc": "Deal 4 per gene you already expressed this turn.",
		"fx": [{"t": "dmg_count", "per": 4}],
		"up": {"short": "6 x COUNT", "desc": "Deal 6 per gene you already expressed this turn.",
			"fx": [{"t": "dmg_count", "per": 6}]}},
	"crescendo": {"name": "TORRENT", "cost": 2, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "DMG 6/22", "desc": "Deal 6. DEEP: deal 22.",
		"fx": [{"t": "dmg", "n": 6}], "deep": [{"t": "dmg", "n": 22}],
		"up": {"short": "DMG 8/26", "desc": "Deal 8. DEEP: deal 26.",
			"fx": [{"t": "dmg", "n": 8}], "deep": [{"t": "dmg", "n": 26}]}},
	"drifter": {"name": "DRIFTER", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "SETTLE 15", "desc": "Plant a Latent: 15 damage in 2 turns. ALONE: deal 9 now instead.",
		"fx": [{"t": "latent", "n": 15, "turns": 2}], "lone": [{"t": "dmg", "n": 9}],
		"up": {"short": "SETTLE 20", "desc": "Plant a Latent: 20 damage in 2 turns. ALONE: deal 12 now instead.",
			"fx": [{"t": "latent", "n": 20, "turns": 2}], "lone": [{"t": "dmg", "n": 12}]}},
	"hopper": {"name": "HOPPER", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "DMG 4 HOP", "desc": "Deal 4. HOP: copies itself 5 slots ahead, over what is there.",
		"fx": [{"t": "dmg", "n": 4}, {"t": "hop", "ahead": 5}],
		"up": {"short": "DMG 6 HOP", "desc": "Deal 6. HOP: copies itself 5 slots ahead, over what is there.",
			"fx": [{"t": "dmg", "n": 6}, {"t": "hop", "ahead": 5}]}},

	# ================================================================ DEFENCE
	"film": {"name": "FILM", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "FILM 5", "desc": "Gain 5 Film. LINK: gain 3 more. ALONE: gain 8.",
		"fx": [{"t": "film", "n": 5}], "link": [{"t": "film", "n": 3}],
		"lone": [{"t": "film", "n": 8}],
		"up": {"short": "FILM 7", "desc": "Gain 7 Film. LINK: gain 4 more. ALONE: gain 11.",
			"fx": [{"t": "film", "n": 7}], "link": [{"t": "film", "n": 4}],
			"lone": [{"t": "film", "n": 11}]}},
	"membrane": {"name": "MEMBRANE", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "FILM 5", "desc": "Gain 5 Film. DEEP: gain 10.",
		"fx": [{"t": "film", "n": 5}], "deep": [{"t": "film", "n": 10}],
		"up": {"short": "FILM 7", "desc": "Gain 7 Film. DEEP: gain 13.",
			"fx": [{"t": "film", "n": 7}], "deep": [{"t": "film", "n": 13}]}},
	"sporewall": {"name": "BULWARK", "cost": 2, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "FILM 12", "desc": "Gain 12 Film.",
		"fx": [{"t": "film", "n": 12}],
		"up": {"short": "FILM 16", "desc": "Gain 16 Film.", "fx": [{"t": "film", "n": 16}]}},
	"clot": {"name": "CLOT", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "FILM 6", "desc": "Gain 6 Film. DORMANT: gain 4 Film. ALONE: gain 9.",
		"fx": [{"t": "film", "n": 6}], "dormant": [{"t": "film", "n": 4}],
		"lone": [{"t": "film", "n": 9}],
		"up": {"short": "FILM 8", "desc": "Gain 8 Film. DORMANT: gain 6 Film. ALONE: gain 12.",
			"fx": [{"t": "film", "n": 8}], "dormant": [{"t": "film", "n": 6}],
			"lone": [{"t": "film", "n": 12}]}},
	"cyst": {"name": "CYST", "cost": 0, "kind": "gene", "rarity": "rare", "green": false,
		"short": "SKIP:FILM7", "desc": "Gain 2 Film. DORMANT: gain 7 Film.",
		"fx": [{"t": "film", "n": 2}], "dormant": [{"t": "film", "n": 7}],
		"up": {"short": "SKIP:FLM10", "desc": "Gain 3 Film. DORMANT: gain 10 Film.",
			"fx": [{"t": "film", "n": 3}], "dormant": [{"t": "film", "n": 10}]}},
	"hush": {"name": "SHELL", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "FILM 4", "desc": "Gain 4 Film. ALONE: gain 10.",
		"fx": [{"t": "film", "n": 4}], "lone": [{"t": "film", "n": 10}],
		"up": {"short": "FILM 6", "desc": "Gain 6 Film. ALONE: gain 13.",
			"fx": [{"t": "film", "n": 6}], "lone": [{"t": "film", "n": 13}]}},
	"mirror": {"name": "MIRROR", "cost": 1, "kind": "gene", "rarity": "rare", "green": false,
		"short": "FILM=HIT", "desc": "Gain Film equal to the enemy's intent damage. LINK: +3 Film.",
		"fx": [{"t": "mirror"}], "link": [{"t": "film", "n": 3}],
		"up": {"short": "FILM=HIT+3", "desc": "Gain Film equal to the intent damage, +3. LINK: +3 Film.",
			"fx": [{"t": "mirror"}, {"t": "film", "n": 3}]}},
	"terminator": {"name": "TERMINUS", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "3 x CHAIN", "desc": "Gain 3 Film per CHAIN step, then the chain ends. DEEP: 5 per step.",
		"fx": [{"t": "cap", "per": 3, "what": "film"}], "deep": [{"t": "cap", "per": 5, "what": "film"}],
		"up": {"short": "4 x CHAIN", "desc": "Gain 4 Film per CHAIN step, then the chain ends. DEEP: 6 per step.",
			"fx": [{"t": "cap", "per": 4, "what": "film"}], "deep": [{"t": "cap", "per": 6, "what": "film"}]}},

	# ================================================================ HEAL
	"divide": {"name": "DIVIDE", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "HEAL 5", "desc": "Regain 5 Colony. LINK: regain 3 more. DEEP: regain 9.",
		"fx": [{"t": "heal", "n": 5}], "link": [{"t": "heal", "n": 3}],
		"deep": [{"t": "heal", "n": 9}],
		"up": {"short": "HEAL 7", "desc": "Regain 7 Colony. LINK: regain 4 more. DEEP: regain 12.",
			"fx": [{"t": "heal", "n": 7}], "link": [{"t": "heal", "n": 4}],
			"deep": [{"t": "heal", "n": 12}]}},

	# ================================================================ ORDER (chain openers, bridges, copies)
	"signal": {"name": "SIGNAL", "cost": 0, "kind": "gene", "rarity": "common", "green": false,
		"short": "FILM 2", "desc": "Gain 2 Film. ALONE: the chain starts at x2.",
		"fx": [{"t": "film", "n": 2}], "lone": [{"t": "film", "n": 2}, {"t": "chain", "n": 1}],
		"up": {"short": "FILM 4", "desc": "Gain 4 Film. ALONE: the chain starts at x2.",
			"fx": [{"t": "film", "n": 4}], "lone": [{"t": "film", "n": 4}, {"t": "chain", "n": 1}]}},
	"hymn": {"name": "SPOOL", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "FILM 3", "desc": "Gain 3 Film. DEEP: deal 9 instead.",
		"fx": [{"t": "film", "n": 3}], "deep": [{"t": "dmg", "n": 9}],
		"up": {"short": "FILM 5", "desc": "Gain 5 Film. DEEP: deal 12 instead.",
			"fx": [{"t": "film", "n": 5}], "deep": [{"t": "dmg", "n": 12}]}},
	"drone": {"name": "BRIDGE", "cost": 1, "kind": "gene", "rarity": "common", "green": false, "reach": 2,
		"short": "DMG 5", "desc": "Deal 5. REACH: links across a one-slot gap.",
		"fx": [{"t": "dmg", "n": 5}],
		"up": {"short": "DMG 7", "desc": "Deal 7. REACH: links across a one-slot gap.",
			"fx": [{"t": "dmg", "n": 7}]}},
	"chant": {"name": "STITCH", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "DMG 4", "desc": "Deal 4. LINK: +1 splice this turn.",
		"fx": [{"t": "dmg", "n": 4}], "link": [{"t": "splice", "n": 1}],
		"up": {"short": "DMG 6", "desc": "Deal 6. LINK: +1 splice this turn.",
			"fx": [{"t": "dmg", "n": 6}]}},
	"trace": {"name": "TRACE", "cost": 1, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "COPY LEFT", "desc": "Copy the base effect of the gene on its left, spent or not.",
		"fx": [{"t": "trace"}],
		"up": {"cost": 0}},
	"whisper": {"name": "STRAY", "cost": 0, "kind": "gene", "rarity": "common", "green": false,
		"short": "DMG 2", "desc": "Deal 2. ALONE: deal 5, +1 splice.",
		"fx": [{"t": "dmg", "n": 2}], "lone": [{"t": "dmg", "n": 5}, {"t": "splice", "n": 1}],
		"up": {"short": "DMG 4", "desc": "Deal 4. ALONE: deal 8, +1 splice.",
			"fx": [{"t": "dmg", "n": 4}], "lone": [{"t": "dmg", "n": 8}, {"t": "splice", "n": 1}]}},
	"lullaby": {"name": "SEDATE", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "LULL 4", "desc": "Enemy intent deals 4 less per hit. ALONE: 8 less.",
		"fx": [{"t": "lull", "n": 4}], "lone": [{"t": "lull", "n": 8}],
		"up": {"short": "LULL 6", "desc": "Enemy intent deals 6 less per hit. ALONE: 10 less.",
			"fx": [{"t": "lull", "n": 6}], "lone": [{"t": "lull", "n": 10}]}},

	# ================================================================ ENGINE / UTILITY
	"promoter": {"name": "PROMOTER", "cost": 0, "kind": "gene", "rarity": "common", "green": false,
		"short": "NEXT x2", "desc": "Express the gene right of this next and it fires twice.",
		"fx": [{"t": "promote"}],
		"up": {"short": "NEXT x2 +F", "desc": "Gain 3 Film. Express the gene right of this next: it fires twice.",
			"fx": [{"t": "film", "n": 3}, {"t": "promote"}]}},
	"catalyst": {"name": "CATALYST", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "+2 CHG NXT", "desc": "+2 Charge next turn. ALONE: +3 Charge next turn.",
		"fx": [{"t": "charge_next", "n": 2}], "lone": [{"t": "charge_next", "n": 3}],
		"up": {"cost": 0}},
	"splicer": {"name": "SPLICER", "cost": 0, "kind": "gene", "rarity": "common", "green": false,
		"short": "+2 SPLICE", "desc": "+2 splices this turn. LINK: +1 Charge.",
		"fx": [{"t": "splice", "n": 2}], "link": [{"t": "charge", "n": 1}],
		"up": {"short": "+3 SPLICE", "desc": "+3 splices this turn. LINK: +1 Charge.",
			"fx": [{"t": "splice", "n": 3}]}},
	"invert": {"name": "INVERT", "cost": 0, "kind": "gene", "rarity": "rare", "green": false,
		"short": "REVERSE", "desc": "Reverse the unspent genes in the window. +1 splice.",
		"fx": [{"t": "invert"}, {"t": "splice", "n": 1}],
		"up": {"short": "REVERSE+2", "desc": "Reverse the unspent genes in the window. +2 splices.",
			"fx": [{"t": "invert"}, {"t": "splice", "n": 2}]}},
	"pull": {"name": "PULL", "cost": 0, "kind": "gene", "rarity": "common", "green": false,
		"short": "PULL 1", "desc": "Draw 1 extra gene into the window. Gain 2 Film.",
		"fx": [{"t": "pull", "n": 1}, {"t": "film", "n": 2}],
		"up": {"short": "PULL 2", "desc": "Draw 2 extra genes into the window. Gain 2 Film.",
			"fx": [{"t": "pull", "n": 2}, {"t": "film", "n": 2}]}},
	"spore": {"name": "SPORE", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "DMG 4", "desc": "Deal 4. DORMANT: +1 Charge next turn.",
		"fx": [{"t": "dmg", "n": 4}], "dormant": [{"t": "charge_next", "n": 1}],
		"up": {"short": "DMG 7", "desc": "Deal 7. DORMANT: +1 Charge next turn.",
			"fx": [{"t": "dmg", "n": 7}]}},
	"primer": {"name": "OPENER", "cost": 0, "kind": "gene", "rarity": "common", "green": false,
		"short": "FILM 3", "desc": "Gain 3 Film. FIRST: +1 Charge.",
		"fx": [{"t": "film", "n": 3}], "first": [{"t": "charge", "n": 1}],
		"up": {"short": "FILM 5", "desc": "Gain 5 Film. FIRST: +1 Charge.",
			"fx": [{"t": "film", "n": 5}]}},
	"echo": {"name": "ECHO", "cost": 1, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "REPEAT", "desc": "Repeat the last gene you expressed.",
		"fx": [{"t": "echo"}],
		"up": {"cost": 0}},
	"proofread": {"name": "PROOF", "cost": 1, "kind": "gene", "rarity": "common", "green": false,
		"short": "FRAY -2", "desc": "Fray -2. Gain 3 Film.",
		"fx": [{"t": "fray", "n": -2}, {"t": "film", "n": 3}],
		"up": {"short": "FRAY -3", "desc": "Fray -3. Gain 4 Film.",
			"fx": [{"t": "fray", "n": -3}, {"t": "film", "n": 4}]}},
	"ledger": {"name": "LEDGER", "cost": 1, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "RECORD", "desc": "Record the enemy's intent. It fizzles for the rest of this run. Max 3.",
		"fx": [{"t": "ledger"}],
		"up": {"cost": 0}},
	"tripwire": {"name": "TRIPWIRE", "cost": 0, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "TRAP", "desc": "Cancel the next enemy plant, uproot or drain. You lose 3 Colony.",
		"fx": [{"t": "tripwire"}],
		"up": {"short": "TRAP +F4", "desc": "Cancel the next enemy plant, uproot or drain. Lose 3. Gain 4 Film.",
			"fx": [{"t": "tripwire"}, {"t": "film", "n": 4}]}},
	"relay": {"name": "RELAY", "cost": 1, "kind": "gene", "rarity": "uncommon", "green": false,
		"short": "PULL2 +1C", "desc": "Gain 3 Film. Pull 2 genes. +1 Charge. BURN: once per fight.",
		"fx": [{"t": "film", "n": 3}, {"t": "pull", "n": 2}, {"t": "charge", "n": 1}], "burn": true,
		"up": {"short": "PULL2 +1C", "desc": "Gain 6 Film. Pull 2 genes. +1 Charge. BURN: once per fight.",
			"fx": [{"t": "film", "n": 6}, {"t": "pull", "n": 2}, {"t": "charge", "n": 1}]}},

	# ================================================================ PASSIVE
	"pact_coil": {"name": "PACT", "cost": 0, "kind": "passive", "rarity": "uncommon", "green": false,
		"short": "+1 CHARGE", "desc": "PASSIVE: +1 Charge each turn. PACT: if removed, lose 8 Colony.",
		"fx": [], "passive": {"charge": 1}, "pact": 8,
		"up": {"desc": "PASSIVE: +1 Charge each turn. PACT: if removed, lose 4 Colony.", "pact": 4}},
	"thick_wall": {"name": "RAMPART", "cost": 0, "kind": "passive", "rarity": "uncommon", "green": false,
		"short": "+3 FILM/T", "desc": "PASSIVE: gain 3 Film at the start of each turn.",
		"fx": [], "passive": {"film": 3},
		"up": {"short": "+5 FILM/T", "desc": "PASSIVE: gain 5 Film at the start of each turn.",
			"passive": {"film": 5}}},

	# ================================================================ GREEN (taken from the thing inside you)
	"g_lash": {"name": "G.LASH", "cost": 0, "kind": "gene", "rarity": "rare", "green": true,
		"short": "DMG 9", "desc": "GREEN. Deal 9. +1 UPTAKE. DEEP: deal 14.",
		"fx": [{"t": "dmg", "n": 9}], "deep": [{"t": "dmg", "n": 14}],
		"up": {"short": "DMG 12", "desc": "GREEN. Deal 12. +1 UPTAKE. DEEP: deal 18.",
			"fx": [{"t": "dmg", "n": 12}], "deep": [{"t": "dmg", "n": 18}]}},
	"g_root": {"name": "G.ROOT", "cost": 1, "kind": "gene", "rarity": "rare", "green": true,
		"short": "FILM10 +4", "desc": "GREEN. Gain 10 Film, regain 4 Colony. +1 UPTAKE.",
		"fx": [{"t": "film", "n": 10}, {"t": "heal", "n": 4}],
		"up": {"short": "FILM13 +6", "desc": "GREEN. Gain 13 Film, regain 6 Colony. +1 UPTAKE.",
			"fx": [{"t": "film", "n": 13}, {"t": "heal", "n": 6}]}},
	"g_chorus": {"name": "G.CHAIN", "cost": 0, "kind": "gene", "rarity": "rare", "green": true,
		"short": "CH+2 +1C", "desc": "GREEN. CHAIN +2. +1 Charge now. +1 UPTAKE.",
		"fx": [{"t": "chain", "n": 2}, {"t": "charge", "n": 1}],
		"up": {"short": "CH+2 +2C", "desc": "GREEN. CHAIN +2. +2 Charge now. +1 UPTAKE.",
			"fx": [{"t": "chain", "n": 2}, {"t": "charge", "n": 2}]}},
	"g_bloom": {"name": "G.BLOOM", "cost": 1, "kind": "gene", "rarity": "rare", "green": true,
		"short": "DMG 5x3", "desc": "GREEN. Deal 5 three times. +1 UPTAKE.",
		"fx": [{"t": "dmg", "n": 5, "k": 3}],
		"up": {"short": "DMG 6x3", "desc": "GREEN. Deal 6 three times. +1 UPTAKE.",
			"fx": [{"t": "dmg", "n": 6, "k": 3}]}},
	"g_weave": {"name": "G.WEAVE", "cost": 0, "kind": "gene", "rarity": "rare", "green": true,
		"short": "SPLC3 +1C", "desc": "GREEN. +3 splices this turn. +1 Charge now. +1 UPTAKE.",
		"fx": [{"t": "splice", "n": 3}, {"t": "charge", "n": 1}],
		"up": {"short": "SPLC3 +2C", "desc": "GREEN. +3 splices this turn. +2 Charge now. +1 UPTAKE.",
			"fx": [{"t": "splice", "n": 3}, {"t": "charge", "n": 2}]}},

	# ================================================================ JUNK
	"overgrowth": {"name": "OVERGROW", "cost": 1, "kind": "junk", "rarity": "common", "green": false,
		"short": "CLEAR", "desc": "Junk planted by the Green. Express to clear it from the Strand.",
		"fx": [{"t": "clear"}],
		"up": {"cost": 0}},
	"scab_plate": {"name": "PLATE", "cost": 0, "kind": "junk", "rarity": "common", "green": false,
		"unplayable": true, "dormant_enemy": true,
		"short": "UNREADABL", "desc": "Cannot be expressed. DORMANT: the enemy gains 3 Film.",
		"fx": [], "dormant": [{"t": "film", "n": 3}],
		"up": {"desc": "Cannot be expressed. DORMANT: the enemy gains 1 Film.",
			"dormant": [{"t": "film", "n": 1}]}},
}

const STRAINS := {
	"scrubber": {"name": "SCRUBBER", "desc": "Attrition. Film and steady damage.",
		"color": Color("58a8e8"),
		"strand": ["promoter", "spike", "lyse", "lyse", "film", "signal", "membrane", "film"]},
	"courier": {"name": "COURIER", "desc": "Openers, drifters and theft.",
		"color": Color("70c8a0"),
		"strand": ["signal", "lyse", "film", "drifter", "signal", "hopper", "ledger", "film"]},
	"lytic": {"name": "LYTIC", "desc": "Sleeps, then bursts. Skips pay; chains end hard.",
		"color": Color("e06048"),
		"strand": ["cyst", "needle", "lyse", "cascade", "clot", "spore", "film", "terminator"]},
	"weaver": {"name": "WEAVER", "desc": "Order. Open a chain, run it deep, hold it.",
		"color": Color("e8c840"),
		"strand": ["signal", "chant", "hymn", "drone", "lyse", "hush", "needle", "membrane"]},
}

## Reward pool available from day 1 (common and early genes).
const STARTING_POOL := ["lyse", "film", "swarm", "spike", "siphon", "rot", "needle", "drifter",
	"hopper", "membrane", "clot", "hush", "terminator", "divide", "signal", "hymn", "drone",
	"chant", "whisper", "lullaby", "quorum", "promoter", "catalyst", "splicer", "pull", "spore",
	"primer", "proofread"]
## Genes the bench can sequence into the pool (cost in reagent).
const SEQUENCEABLE := {"ledger": 3, "tripwire": 3, "pact_coil": 5, "thick_wall": 5,
	"sporewall": 4, "echo": 4, "crescendo": 5, "fever": 3, "relay": 4, "trace": 4}
## Found as sequence sheets in the lab; appended to Game.unlocked when picked up.
const LAB_FIND := ["cascade", "cyst", "invert", "bloom", "lance", "mirror"]
const GREEN_POOL := ["g_lash", "g_root", "g_chorus", "g_bloom", "g_weave"]
## Reward weight per rarity; rare and uncommon grow a little each infection stage.
const RARITY_WEIGHT := {"common": 60, "uncommon": 28, "rare": 9}

# ------------------------------------------------------------------ enemies
## Intent: {"id": unique-for-Ledger, "name": ≤12 chars, "fx": [...], "break": N (wind-up)}. Patterns cycle.
## Shared region intents use the same id so a Ledger entry keeps paying off.
## Enemy: name, colony, blurb (≤34), optional boss, trait {id,name,desc}, pattern (Array or
## "mimic_last" / "mimic_run"). ARCHIVIST: every `windup_every`-th intent is `windup` instead.
const T_SPINES := {"id": "spines", "name": "SPINES", "desc": "You take 1 for each damaging gene."}
const T_HARDENED := {"id": "hardened", "name": "HARDENED", "desc": "Gains 3 Film after each of its turns."}
const T_RIPOSTE := {"id": "riposte", "name": "RIPOSTE", "desc": "Hits you for 3 when your chain SNAPS."}
const T_SPLIT := {"id": "split", "name": "SPLIT", "desc": "First time under half: gains 12 Film."}
const T_REGROW := {"id": "regrow", "name": "REGROW", "desc": "Regains 3 at the start of its turn."}
const T_HOARDER := {"id": "hoarder", "name": "HOARDER", "desc": "+1 damage for each gene you skip."}
const T_DISCORD := {"id": "discord", "name": "DISCORD", "desc": "Heals 5 when your chain SNAPS."}
const T_BLANK := {"id": "blank", "name": "BLANK", "desc": "Your chain never HOLDS over END."}

const ENEMIES := {
	# THE WOUND
	"creeper": {"name": "CREEPER", "colony": 38, "blurb": "Gnaws a marked gene. Express it.",
		"pattern": [
			{"id": "w_gnaw", "name": "GNAW", "fx": [{"t": "gnaw", "n": 1}]},
			{"id": "w_lash", "name": "LASH 5", "fx": [{"t": "dmg", "n": 5}]},
			{"id": "w_crust", "name": "CRUST 4", "fx": [{"t": "film", "n": 4}]},
			{"id": "w_lash", "name": "LASH 5", "fx": [{"t": "dmg", "n": 5}]}]},
	"knot": {"name": "TENDRIL KNOT", "colony": 44, "blurb": "Knots NEXT genes. Thickens.",
		"pattern": [
			{"id": "w_thicken", "name": "THICKEN", "fx": [{"t": "grow", "n": 2}]},
			{"id": "w_knot", "name": "KNOT+LASH 4", "fx": [{"t": "knot", "n": 1}, {"t": "dmg", "n": 4}]},
			{"id": "w_lash", "name": "LASH 4", "fx": [{"t": "dmg", "n": 4}]}]},
	"fester": {"name": "FESTER", "colony": 72, "blurb": "Spined. Seeds junk, then bursts.",
		"trait": T_SPINES, "pattern": [
			{"id": "w_seed", "name": "SEED 1", "fx": [{"t": "plant", "n": 1}]},
			{"id": "w_lash", "name": "LASH 6", "fx": [{"t": "dmg", "n": 6}]},
			{"id": "w_burst", "name": "BURST 18", "break": 10, "fx": [{"t": "dmg", "n": 18}]}]},
	"scab": {"name": "THE SCAB", "colony": 125, "boss": true, "blurb": "Plates over. Plants plates in you.",
		"trait": T_HARDENED, "pattern": [
			{"id": "w_crust", "name": "CRUST 10", "fx": [{"t": "film", "n": 10}]},
			{"id": "w_plate", "name": "PLATE 2", "fx": [{"t": "plant", "n": 2, "id": "scab_plate"}]},
			{"id": "w_lash", "name": "LASH 8", "fx": [{"t": "dmg", "n": 8}]},
			{"id": "w_rake", "name": "RAKE 5x4", "break": 14, "fx": [{"t": "dmg", "n": 5, "k": 4}]}]},
	# THE RIVERS
	"pod": {"name": "DRIFT POD", "colony": 40, "blurb": "Severs a link. Splits.",
		"trait": T_SPLIT, "pattern": [
			{"id": "r_cut", "name": "SEVER+LASH 3", "fx": [{"t": "sever", "n": 1}, {"t": "dmg", "n": 3}]},
			{"id": "r_burst", "name": "BURST 7", "fx": [{"t": "dmg", "n": 7}]}]},
	"current": {"name": "CURRENT", "colony": 46, "blurb": "Sweeps NEXT away. Drains.",
		"pattern": [
			{"id": "r_tide", "name": "SWEEP 3x2", "fx": [{"t": "sweep"}, {"t": "dmg", "n": 3, "k": 2}]},
			{"id": "r_pull", "name": "PULL 4", "fx": [{"t": "drain", "n": 4}]},
			{"id": "r_eddy", "name": "EDDY 5", "fx": [{"t": "film", "n": 5}]}]},
	"leech": {"name": "CLOT LEECH", "colony": 76, "blurb": "Drinks, gnaws, regrows. Gorges.",
		"trait": T_REGROW, "pattern": [
			{"id": "r_drink", "name": "DRINK 6", "fx": [{"t": "drain", "n": 6}]},
			{"id": "r_gnaw", "name": "GNAW 2", "fx": [{"t": "gnaw", "n": 2}]},
			{"id": "r_gorge", "name": "GORGE 16", "break": 10, "fx": [{"t": "drain", "n": 16}]}]},
	"undertow": {"name": "UNDERTOW", "colony": 135, "boss": true, "blurb": "Churns and sweeps your window.",
		"trait": T_HOARDER, "pattern": [
			{"id": "r_churn", "name": "CHURN", "fx": [{"t": "scramble"}]},
			{"id": "r_sweep", "name": "SWEEP 10", "fx": [{"t": "sweep"}, {"t": "dmg", "n": 10}]},
			{"id": "r_pull", "name": "PULL 6", "fx": [{"t": "drain", "n": 6}]},
			{"id": "r_whirl", "name": "WHIRL 4x4", "break": 16, "fx": [{"t": "dmg", "n": 4, "k": 4}]}]},
	# THE HOLLOW
	"choir_cell": {"name": "SHEAR CELL", "colony": 42, "blurb": "Severs links. Bites on a snap.",
		"trait": T_RIPOSTE, "pattern": [
			{"id": "h_shear", "name": "SEVER2+LASH3", "fx": [{"t": "sever", "n": 2}, {"t": "dmg", "n": 3}]},
			{"id": "h_lash", "name": "LASH 9", "fx": [{"t": "dmg", "n": 9}]}]},
	"bellows": {"name": "BELLOWS", "colony": 48, "blurb": "Winds up an EXHALE. Break it.",
		"pattern": [
			{"id": "h_inhale", "name": "INHALE 8", "fx": [{"t": "film", "n": 8}]},
			{"id": "h_exhale", "name": "EXHALE 14", "break": 8, "fx": [{"t": "dmg", "n": 14}]}]},
	"shroud": {"name": "SHROUD", "colony": 74, "blurb": "Severs and hides. Knots.",
		"trait": T_RIPOSTE, "pattern": [
			{"id": "h_veil", "name": "SEVER 2+FILM", "fx": [{"t": "sever", "n": 2}, {"t": "film", "n": 5}]},
			{"id": "h_knot", "name": "KNOT 2", "fx": [{"t": "knot", "n": 2}, {"t": "dmg", "n": 3}]},
			{"id": "h_lash", "name": "LASH 9", "fx": [{"t": "dmg", "n": 9}]},
			{"id": "h_smother", "name": "SMOTHER 18", "break": 12, "fx": [{"t": "dmg", "n": 18}]}]},
	"choir": {"name": "THE LUNG", "colony": 140, "boss": true, "blurb": "Cuts your chains. Feeds on snaps.",
		"trait": T_DISCORD, "pattern": [
			{"id": "h_shear", "name": "SEVER2+LASH3", "fx": [{"t": "sever", "n": 2}, {"t": "dmg", "n": 3}]},
			{"id": "h_swell", "name": "SWELL 6x2", "fx": [{"t": "dmg", "n": 6, "k": 2}]},
			{"id": "h_tune", "name": "SEVER 2+GROW", "fx": [{"t": "sever", "n": 2}, {"t": "grow", "n": 2}]},
			{"id": "h_requiem", "name": "COLLAPSE 24", "break": 18, "fx": [{"t": "dmg", "n": 24}]}]},
	# THE ARCHIVE
	"mimic": {"name": "MIMIC", "colony": 44, "blurb": "Copies the last gene you used.",
		"pattern": "mimic_last"},
	"eraser": {"name": "ERASER", "colony": 42, "blurb": "Unsays links. Gnaws. Blanks holds.",
		"trait": T_BLANK, "pattern": [
			{"id": "a_gnaw", "name": "GNAW 2", "fx": [{"t": "gnaw", "n": 2}]},
			{"id": "a_blot", "name": "BLOT 2", "fx": [{"t": "plant", "n": 2}]},
			{"id": "a_unsay", "name": "UNSAY 2+4", "fx": [{"t": "sever", "n": 2}, {"t": "dmg", "n": 4}]},
			{"id": "a_strike", "name": "STRIKE 6", "fx": [{"t": "dmg", "n": 6}]}]},
	"palimpsest": {"name": "PALIMPSEST", "colony": 72, "blurb": "Copies you. Grows on your skips.",
		"trait": T_HOARDER, "pattern": [
			{"id": "a_smear", "name": "SMEAR", "fx": [{"t": "scramble"}, {"t": "dmg", "n": 4}]},
			{"id": "a_copy", "name": "COPY", "fx": [{"t": "mimic_last"}]},
			{"id": "a_gnaw", "name": "GNAW 1", "fx": [{"t": "gnaw", "n": 1}]},
			{"id": "a_rewrite", "name": "REWRITE 16", "break": 12, "fx": [{"t": "dmg", "n": 16}]}]},
	"archivist": {"name": "ARCHIVIST", "colony": 130, "boss": true, "blurb": "Reads your Strand back at you.",
		"trait": T_SPLIT, "pattern": "mimic_run", "windup_every": 4,
		"windup": {"id": "a_index", "name": "INDEX 22", "break": 16,
			"fx": [{"t": "dmg", "n": 22}]}},
	# THE ROOT
	"tendril": {"name": "ROOT TENDRIL", "colony": 52, "blurb": "Lashes, seeds, drinks. Regrows.",
		"trait": T_REGROW, "pattern": [
			{"id": "x_lash", "name": "LASH 7", "fx": [{"t": "dmg", "n": 7}]},
			{"id": "x_seed", "name": "SEED 1", "fx": [{"t": "plant", "n": 1}]},
			{"id": "x_drink", "name": "DRINK 5", "fx": [{"t": "drain", "n": 5}]}]},
	"core": {"name": "THE CORE", "colony": 170, "boss": true, "blurb": "The heart of it. Bind or burn.",
		"trait": T_SPLIT, "pattern": [
			{"id": "x_grow", "name": "SPREAD", "fx": [{"t": "grow", "n": 2}]},
			{"id": "x_lash", "name": "LASH 12", "fx": [{"t": "dmg", "n": 12}]},
			{"id": "x_seed", "name": "SEED 2", "fx": [{"t": "plant", "n": 2}]},
			{"id": "x_drink", "name": "DRINK 8", "fx": [{"t": "drain", "n": 8}]},
			{"id": "x_bark", "name": "BARK 15", "fx": [{"t": "film", "n": 15}]},
			{"id": "x_bloom", "name": "BLOOM 20", "break": 16, "fx": [{"t": "dmg", "n": 20}]}]},
}

const REGION_ENEMIES := {
	"wound": {"normal": ["creeper", "knot"], "elite": ["fester"], "boss": "scab"},
	"rivers": {"normal": ["pod", "current"], "elite": ["leech"], "boss": "undertow"},
	"hollow": {"normal": ["choir_cell", "bellows"], "elite": ["shroud"], "boss": "choir"},
	"archive": {"normal": ["mimic", "eraser"], "elite": ["palimpsest"], "boss": "archivist"},
	"root": {"normal": ["tendril"], "elite": ["tendril"], "boss": "core"},
}

## Visual palette per region (battle backdrop, body map tint).
const REGION_COLORS := {
	"wound": {"bg": Color("2a0c10"), "fog": Color("4a1418"), "floor": Color("6a2028"), "accent": Color("e06060")},
	"rivers": {"bg": Color("200810"), "fog": Color("501020"), "floor": Color("802030"), "accent": Color("ff7070")},
	"hollow": {"bg": Color("182028"), "fog": Color("3a4858"), "floor": Color("c09aa8"), "accent": Color("a8d0f0")},
	"archive": {"bg": Color("100c20"), "fog": Color("281c48"), "floor": Color("483870"), "accent": Color("b098f0")},
	"root": {"bg": Color("061008"), "fog": Color("0c2810"), "floor": Color("1c3a18"), "accent": Color("70d850")},
}

## One rule per region (CombatEngine implements the rules).
const REGION_MEDIUM := {
	"wound": {"name": "CLOTTING", "desc": "Film only half-clears each turn."},
	"rivers": {"name": "CURRENT", "desc": "Every 2nd turn SURGES: +1 READ."},
	"hollow": {"name": "BREATH", "desc": "INHALE Film x1.5. EXHALE dmg x1.5."},
	"archive": {"name": "FADING", "desc": "NEXT genes are unreadable until READ."},
	"root": {"name": "THE HEART", "desc": "Each LINK step adds +2, not +1."},
}

## Tissue dropped on a win (the root drops none).
const REGION_TISSUE := {"wound": "clot", "rivers": "plasma", "hollow": "alveoli", "archive": "myelin"}


var _up_cache: Dictionary = {}


func base_id(id: String) -> String:
	return id.trim_suffix("+")


func can_upgrade(id: String) -> bool:
	if id.ends_with("+") or not CARDS.has(id):
		return false
	var c: Dictionary = CARDS[id]
	return c.has("up")


func upgraded(id: String) -> String:
	return id + "+" if can_upgrade(id) else id


## Card data. "x+" ids merge the base's `up` over it and append "+" to the name.
func card(id: String) -> Dictionary:
	var b := base_id(id)
	if not CARDS.has(b):
		return CARDS["overgrowth"]
	var base: Dictionary = CARDS[b]
	if b == id or not base.has("up"):
		return base
	if _up_cache.has(id):
		return _up_cache[id]
	var c: Dictionary = base.duplicate(true)
	var up: Dictionary = c["up"]
	for k in up:
		c[k] = up[k]
	c.erase("up")
	c["name"] = String(c["name"]) + "+"
	c.make_read_only()
	_up_cache[id] = c
	return c


func is_green(id: String) -> bool:
	return bool(card(id).get("green", false)) if CARDS.has(base_id(id)) else false


func is_passive(id: String) -> bool:
	return CARDS.has(base_id(id)) and String(card(id).get("kind", "")) == "passive"


func is_junk(id: String) -> bool:
	return CARDS.has(base_id(id)) and String(card(id).get("kind", "")) == "junk"


func _rarity_weight(id: String, stage: int) -> int:
	var r: String = String(card(id).get("rarity", "common"))
	var w: int = int(RARITY_WEIGHT.get(r, 60))
	match r:
		"uncommon":
			w += 2 * stage
		"rare":
			w += 3 * stage
	return maxi(w, 1)


## Three reward offers, weighted by rarity. From stage 1 on, the last slot is a Green gene.
func reward_offers(unlocked: Array, stage: int) -> Array:
	var pool: Array = []
	for v in unlocked:
		var id := base_id(String(v))
		if CARDS.has(id) and not pool.has(id) and not is_junk(id) and not is_green(id):
			pool.append(id)
	var out: Array = []
	while out.size() < 3 and not pool.is_empty():
		var weights: Array[int] = []
		var total := 0
		for id in pool:
			var w := _rarity_weight(String(id), stage)
			weights.append(w)
			total += w
		var roll := randi() % maxi(total, 1)
		var pick := pool.size() - 1
		for i in pool.size():
			roll -= weights[i]
			if roll < 0:
				pick = i
				break
		out.append(pool[pick])
		pool.remove_at(pick)
	if stage >= 1 and out.size() > 0:
		out[out.size() - 1] = GREEN_POOL[randi() % GREEN_POOL.size()]
	return out


func enemy(id: String) -> Dictionary:
	return ENEMIES[id]


## Converts a card list into an intent pattern (MIMIC / ARCHIVIST / PALIMPSEST play your genes back at you).
func mimic_pattern(strand: Array) -> Array:
	var out: Array = []
	for v in strand:
		var id := String(v)
		var c := card(id)
		if String(c.get("kind", "")) != "gene" or c.get("unplayable", false):
			continue
		var fx := _mimic_fx(c.get("fx", []))
		if fx.is_empty():
			continue
		out.append({"id": "m_" + base_id(id), "name": String(c["name"]), "fx": fx})
	if out.is_empty():
		out = [{"id": "m_blank", "name": "SCRAWL 6", "fx": [{"t": "dmg", "n": 6}]}]
	return out


## Player-only effects make no sense for an enemy: swap each for something equivalent.
func _mimic_fx(src: Array) -> Array:
	var fx: Array = []
	for e in src:
		var d: Dictionary = e
		var t: String = String(d.get("t", ""))
		match t:
			"free_next", "promote", "charge", "charge_next", "ledger", "tripwire", "fray", "hop", "echo", "splice", "invert", "pull", "lull", "chain", "trace":
				fx.append({"t": "film", "n": 3})
			"clear", "self":
				pass
			"mirror":
				fx.append({"t": "film", "n": 6})
			"cap":
				if String(d.get("what", "dmg")) == "film":
					fx.append({"t": "film", "n": int(d.get("per", 3)) * 3})
				else:
					fx.append({"t": "dmg", "n": int(d.get("per", 4)) * 3})
			"stagger_dmg":
				fx.append({"t": "dmg", "n": int(d.get("n", 6))})
			"dmg_count":
				fx.append({"t": "dmg", "n": int(d.get("per", 4)) * 2})
			_:
				fx.append(d)
	return fx
