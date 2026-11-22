# STRAIN

A sealed lab. A cut palm. Something green under the skin.

STRAIN is a low-poly, low-res roguelite deck-battler made in Godot 4.4. You play an unnamed human trapped in Wing B of Station Fallow, infected by SOWER, an engineered soil organism they made and unleashed. Each day you grow a culture at the bench and inject it into your own body to fight the Green in a deck-battle run. If a run fails, the culture dies but you don't. You wake up a day sicker.

## Play

Download `STRAIN-windows.zip` from [Releases](https://github.com/shrimpsooup2/STRAIN/releases), unzip it, and run `STRAIN.exe`.

You can also open this folder in Godot 4.4 and press F5.

| Key | Action |
|---|---|
| Arrows / WASD | Move, navigate menus |
| Z / Enter / Space | Interact, confirm, express a gene |
| X / Esc | Back |
| Tab / C | Menu (lab), Strand viewer (battle) |
| E | End turn |
| R | Mutate the selected gene (1 Charge, +1 Fray) |
| Q | Splice the selected gene with its right neighbour |
| F | Use a booster (battle), jump to the injector (bench) |
| H / F1 | Help and glossary |

## How a day works

1. **The lab.** Walk Wing B, read what was left behind, and spend BREATH on machines. A strip along the bottom of the screen shows the room you're in, what the room is for, and what Z does to whatever you're facing.
2. **The bench.** Grow the culture in the workshop, then INJECT.
3. **The injection.** Pick a region, an injection site and a dose.
4. **The run.** Follow a branching path through the body, ending in a boss.
5. **Waking.** The next morning you are a day sicker. Things in the lab have moved.

### Lab rooms

| Room | What it's for |
|---|---|
| Splice Lab | The culture bench. Also notes, a desk and the whiteboard. |
| Generator | Powers the whole wing. Start it first. |
| Corridor | Signed doors. Most rooms have a breaker on the back wall. |
| Medbay | Scan the hand. Treat the spread (3 reagent, 1 breath, once a day). |
| Break Room | The cot. Sleeping ends the day without an injection. |
| Supply Hatch | One supply drop a day. It gets smaller every few days. |
| Freezer, Security, Comms / Archive | Specimens, camera files, messages and station records. |
| Incubator | Culture lines on file. The first visit unlocks a second trait slot. |
| Garden | The trial beds. Its breaker is in Security. |
| Airlock | The way out. It needs a clean scan. |

### The culture bench

| Station | Use |
|---|---|
| Petri dish | Arrange and feed the Strand ring. |
| Vial rack | Tissue carried back from runs. |
| Sequencer | Spend reagent and breath on new genes. |
| Incubator | Grow traits from tissue, then equip them. |
| Strain stock | Pick the strain for this run. |
| Syringe tray | Pick the boosters you carry (two). |
| Primer | Each fight opens on a HELD chain (x1-x3). Costs 3 Colony per step, every fight. |
| Injector | Go in. |
| Door | Back to the lab. |

### Injection

Choose a **region**, then a **site** inside it, then a **dose**:

| Dose | Effect |
|---|---|
| Trace | Max Colony 24. |
| Dose | Max Colony 30. |
| Bolus | Max Colony 38, +1 Fray, +1 Uptake. |

Each region has its own rule (its medium) and gives something back when cleared:

| Region | Medium | Reward |
|---|---|---|
| The Wound | Clotting: Film only half-clears each turn | Steady hands, so bench work costs less |
| The Rivers | Current: every 2nd turn surges, READ +1 | Slows the clock |
| The Hollow | Breath: inhale and exhale turns | +1 BREATH; the first clear unlocks the WEAVER strain |
| The Archive | Fading: upcoming genes are unreadable until read | Memories |
| The Root | The Heart: each LINK step adds +2, not +1 | — |

Run nodes: fight, elite, rest, event, lesion, cyst, needle and boss.

## The cards

1. **Your deck is a Strand.** It's an ordered loop that never gets shuffled. The Reader shows the next 5 genes: 3 READ, 2 NEXT. At END the READ zone leaves and NEXT slides in, so the order you arrange is your strategy.
2. **Colony is your health.** It carries over between fights in a run.
3. **Order is the whole game.** Each effect cares where a gene sits and when it fires:

| Rule | What it does | Why it's there |
|---|---|---|
| LINK / CHAIN | Express the gene right of your last: +1 to its numbers per step. | The base reward for building the Strand in sequence. |
| DEEP | A DEEP gene expressed at CHAIN x3+ swaps to its DEEP text. | Pays off long sequences; you build toward it. |
| ALONE | An ALONE gene expressed unlinked swaps to its ALONE text. | Gives a reason to break order on purpose. |
| HOLD | END a chain whose next gene sits in NEXT: the chain survives into next turn. | Turns the READ/NEXT split into planning across turns. |
| SNAP | Break a chain of x2+ out of order: it SNAPS. Some hosts punish that. | Makes breaking order cost something. |
| REACH | BRIDGE (and SALTATORY) link across a one-slot gap. | Gets around a dead slot without a splice. |
| TRACE | Copies the base effect of the gene on its left. | Its value depends entirely on its neighbour. |
| QUORUM | Deals 4 per gene already expressed this turn. | Rewards playing it late in the turn. |
| SEVER | A host cuts a slot so it cannot LINK. SUTURE clears it. | Hosts attack your order, not just your Colony. |
| PRIMER | Bench setting: the fight's first gene starts HELD at xN. | Buys early DEEP access; that first gene gives up ALONE. |

Boosters: LIGASE adds CHAIN +2 (or primes the opener if nothing has fired yet); SUTURE clears SEVER, GNAW and KNOT marks. Adaptations hook the same rules: WHIPLASH (deal 6 on SNAP), TENDON (HELD chains resume 2 longer), TRIPLE HELIX (3rd gene fires twice), HIVE MIND (DEEP at x2), ECHO CHAMBER (Film on HOLD), CYST WALL (Film on ALONE), SALTATORY (everything has REACH). BIND, the third ending's lock, needs the core at 40% or less and CHAIN x4, three turns running.

Other keywords come in one at a time: Drifter, Hopper, Ledger, Tripwire, Pact, Latent, Fray, and Green genes. Green genes are strong, but every one you express speeds up the real infection.

## The clock

The infection advances by stage. You can see it in lines climbing the hand, tremor, shallow breath and colour draining away. Stages never reverse. Treatment and clearing the Rivers only slow the progress within a stage. Past stage 4 there is no way to purge.

There are four endings: purge, graft, root and fallow. Which ones you can reach depends on what you find in the lab and how far the infection has gone.

## Credits

- Font: [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) by CodeMan38 (SIL Open Font License, see `assets/fonts/OFL.txt`).
- All 3D, textures, UI and audio are procedural, built in code.

## Debug

Arguments go after `--`:

| Argument | Effect |
|---|---|
| `--setup=battle\|boss\|root\|run\|midgame\|rich\|late` | Preset game state |
| `--setup=shop\|event\|reward\|cyst\|needle\|rest` | Open a run-map screen (use with `--scene=run_map`) |
| `--scene=title\|lab\|culture\|body_map\|run_map\|battle\|dream\|ending` | Jump to a scene |
| `--region=wound` | Region for battle setups |
| `--enemy=<id>` | Force the enemy in battle setups |
| `--event=<id>` | Force an event with `--setup=event` |
| `--at=x,y` | Start the lab standing on that tile |
| `--tut` | Show the battle tutorial in battle setups |
| `--ending=purge` | Which ending to play |
| `--dream=1` | Which dream to play |
| `--shot=path.png --frames=N` | Save a screenshot after N frames |
| `--input=F:action,...` | Press actions on given frames |
| `--quit=N` | Quit after N frames |
