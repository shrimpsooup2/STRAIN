# STRAIN

A sealed lab. A cut palm. Something green under the skin.

STRAIN is a low-poly, low-res roguelite deck-battler made in Godot 4.4. You play an unnamed human trapped in Wing B of Station Fallow, infected by SOWER, an engineered soil organism they made and unleashed. Each day you build a culture at the bench and inject it into your own body to fight the Green in a deck-battle run. If a run fails, the culture dies but you don't. You wake up a day sicker.

## Play

Download `STRAIN-windows.zip` from [Releases](https://github.com/shrimpsooup2/STRAIN/releases), unzip it, and run `STRAIN.exe`.

You can also open this folder in Godot 4.4 and press F5.

| Key | Action |
|---|---|
| Arrows / WASD | Move, navigate menus |
| Z / Enter / Space | Interact, confirm, express a gene |
| X / Esc | Back |
| Tab / C | Menu (lab), Strand viewer (run) |
| E | End turn |
| R | Mutate the selected gene (1 Charge, +1 Fray) |

## How a day works

- **The lab:** walk around, inspect things, and spend BREATH on machines: generator, room breakers, medbay treatment and gene sequencing. Collect the supply drop. There is less in it every few days.
- **The bench:** arrange your starting Strand, sequence new genes into the reward pool, pick a strain, and fill the gene bank. Then INJECT.
- **The body map:** choose a region. Each one gives something back when cleared:

| Region | Reward |
|---|---|
| The Wound | Steady hands |
| The Rivers | Slows the clock |
| The Hollow | Breath |
| The Archive | Memories |

- **The run:** a short branching path of fights, rests and events, ending in a boss.

## The cards (three rules)

1. **Your deck is a Strand.** It's an ordered loop that never gets shuffled. The Reader shows the next 4 genes, and you spend 3 Charge to express them. The Reader then moves on 4, so the order you arrange is your strategy.
2. **Colony is your health.** It carries over between fights in a run.
3. **Chorus is a shared 0-10 track.** Genes marked "Chorus X" get stronger once the track reaches X, whichever side pushed it there.

Keywords come in one at a time: Drifter, Hopper, Ledger, Tripwire, Pact, Fray, and Green genes. Green genes are strong, but every one you express speeds up the real infection.

## The clock

The infection advances by stage. You can see it: lines climbing the hand, tremor, shallow breath, colour draining away. Stages never reverse. Treatment and clearing the Rivers only slow the progress inside a stage. Past stage 4 there is no way to purge.

There are four endings. Which ones you can reach depends on what you find in the lab and how far the infection has gone.

## Credits

- Font: [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) by CodeMan38 (SIL Open Font License, see `assets/fonts/OFL.txt`).
- All 3D, textures and UI are procedural, built in code.

## Debug

Arguments go after `--`:

| Argument | Effect |
|---|---|
| `--setup=battle\|boss\|root\|run\|midgame\|late` | Preset game state |
| `--scene=title\|lab\|body_map\|run_map\|battle\|dream\|ending` | Jump to a scene |
| `--region=wound` | Region for battle setups |
| `--ending=purge` | Which ending to play |
| `--dream=1` | Which dream to play |
| `--shot=path.png --frames=N` | Save a screenshot after N frames |
| `--input=F:action,...` | Press actions on given frames |
| `--quit=N` | Quit after N frames |
