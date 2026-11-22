# Tests

Headless Godot scripts that play the game through its rules (GameState) and
print results. They don't change anything. Run from the project folder.

Get a Godot 4.7 binary (in cloud sessions it is not installed; download it):

```bash
curl -sSL -o /tmp/g.zip https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip && unzip -oq /tmp/g.zip -d /tmp && mv /tmp/Godot_v4.7-stable_linux.x86_64 /tmp/godot
```

Once per fresh checkout (registers class_name scripts):

```bash
/tmp/godot --headless --import
```

Check a script parses:

```bash
/tmp/godot --headless --check-only --script game_state.gd
```

Run every test, 4 at a time (about 26 seconds with GAMES=20; the full 300-game runs take several minutes):

```bash
GODOT=/tmp/godot tests/run_all.sh
```

```bash
GAMES=50 GODOT=/tmp/godot tests/run_all.sh war_test deal_test
```

(GAMES=N makes every simulation play N games instead of its usual 300; give test names to run only those.)

Run a test:

```bash
/tmp/godot --headless --script tests/four_test.gd
```

| Script | What it checks |
|---|---|
| four_test.gd | 300 full four-faction games: impossible states, endings, Sköll fairness, AI fights, offers |
| trade_test.gd | Trading the Sun's Daughter: price rules, all outcomes, AI offering her, 200 games |
| scared_test.gd | How often a scared AI offers her to the player |
| sight_test.gd | Sköll's 2-hex sight (fog of war) on a rogue Daughter |
| seed_fingerprint.gd | refactor check: 12 seeded games, one line per turn (Sköll, rifts, ash, every faction). Run before and after a refactor and diff the output: it must be identical |
| season_test.gd | the season calendar for turns 1-40 and a real game's messages (warning, start, end) |
| season_screenshot.gd | (screenshot) the season: goal line, rift tooltip, glowing rifts in 2D and 3D, the 3D light off after it |
| walker_test.gd | Rift Walkers: come out when the season begins, -1 Food on your land, block, never attack first, a fight is no war, AIs attack them, the cap per rift; 300 games for numbers and impossible states |
| walker_screenshot.gd | (screenshot) Rift Walkers in 2D and 3D (figure and pin), tooltip, attack mark, Food breakdown |
| rift_timing_test.gd | Rifts: none before turn 2, hidden, reveal on arrival, re-roll on return |
| balance_state.gd | 1000 games: how often your city falls with/without her, first-attack fairness |
| early_game_test.gd | 300 games with a player who explores and builds: impossible states (units, outposts, fog), decisions on turns 1-10, ruins, outposts taken, events |
| war_test.gd | war and peace and defensive alliances: each rule on a set-up game, then 300 games (no fights at peace, wars, peace, allies) |
| terrain_test.gd | 300 random maps (connected, cities on open land), move costs, defence, outpost income by land, paths round a lake |
| deal_test.gd | trading: quotes, trades, gifts (Trust cap), paying for peace, AI trade offers; 300 games |
| tribute_test.gd | taking cities: tributary, tribute paid, no wars between them, uprisings (AI and you), siege odds, Sköll freeing tributaries; 300 games |
| border_test.gd | closed borders: who may enter, AIs stay out, crossing declares war, walking out after peace, open borders both ways and expiry, allies/overlords; 300 games: no unit inside closed borders after a turn |
| skoll_spawn_test.gd | where Sköll comes out: distance to cities, one rift per city, who he hunts first (fairness) |
| choices_test.gd | ruins and events: nothing useless offered (Favour at 10), every event option costs something, every event can always be answered |
| buildings_test.gd | each city building's effect exactly; 300 games: buildings the AIs own and Industry left unspent on turn 15 |
| health_test.gd | unit health: damage both ways over 1000 fights, wounded units weaker, healing at rest and at home, AI resting; full games (HP in range) |
| army_test.gd | the army snowball: a strong player's armies, Strength, Food/Industry and Sköll's fate at the end |
| midgame_test.gd | Part 2: Sköll returning stronger, wounds and driving him back, ash, support against him, Sunna's requests and rising, swallowing, the endings; full 40-turn games (returns, ash, rising, endings, impossible states) |
| zoc_test.gd | zone of control: each rule on a set-up game (stop next to an enemy army, no slipping past, attack allowed, peace, scouts, own city, the AI obeys it); full games with the rule off and on |
| hud_screenshot.gd | (screenshot) the HUD at 1152x648: landing, turn 1 and turn 16 with every panel open in turn, a pop-up put aside with its badge, toasts, 2D and 3D. Takes about 4 minutes (3D on a software renderer) |
| active_sunna.gd | not in run_all: full games with a player who chases Sunna's rising (grants her requests, keeps an oath): Dawn with you (target about 15%) |
| helpers.gd | not a test: shared helpers (answer every pop-up, list landing hexes) |

Screenshot scripts need a virtual screen and an output folder in `S`:

```bash
S=/tmp/shots xvfb-run -a -s "-screen 0 1152x648x24" /tmp/godot --rendering-driver opengl3 --script tests/fog_screenshot.gd
```

(fog_screenshot.gd, four_click_screenshot.gd, early_screenshot.gd, war_screenshot.gd, deal_screenshot.gd, tribute_screenshot.gd, border_screenshot.gd, city_screenshot.gd, tooltip_screenshot.gd, health_screenshot.gd, supply_screenshot.gd, midgame_screenshot.gd, zoc_screenshot.gd, view3d_screenshot.gd, touch_screenshot.gd: real clicks (tooltip_screenshot hovers the mouse and prints each tooltip) in a window; images go to $S. touch_screenshot.gd taps the 3D button, drags one finger and pinches two, printing the camera after each. early_screenshot.gd saves the Landing, turn 1, a scout move, choosing an outpost, a pop-up and turn 9.)

Gotchas:
- The map's terrain is random. A test that puts units on fixed hexes must call `H.flatten(s)` before the Landing, or a hex may be water.
- Ruins and small events open a pop-up that blocks End Turn. A test that loops over end_turn must answer them first (`H.answer_choices(s)`), or it never ends.
- If a test script hits a script error it stops before quit() and Godot hangs until the timeout. Always run with `timeout`.
- Godot buffers output; if a run is killed you may see nothing. Write progress to a file to debug.
- ALSA/audio and V-Sync warnings in a virtual screen are harmless.
- Seeded comparisons (seed(N) then play the same moves) prove a refactor changed no behaviour: run the same script on the old and new code and diff the output.
