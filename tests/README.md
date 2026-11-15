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
| rift_timing_test.gd | Rifts: none before turn 2, hidden, reveal on arrival, re-roll on return |
| balance_state.gd | 1000 games: how often your city falls with/without her, first-attack fairness |

Screenshot scripts need a virtual screen and an output folder in `S`:

```bash
S=/tmp/shots xvfb-run -a -s "-screen 0 1152x648x24" /tmp/godot --rendering-driver opengl3 --script tests/fog_screenshot.gd
```

(fog_screenshot.gd, four_click_screenshot.gd: real clicks in a window; images go to $S.)

Gotchas:
- If a test script hits a script error it stops before quit() and Godot hangs until the timeout. Always run with `timeout`.
- Godot buffers output; if a run is killed you may see nothing. Write progress to a file to debug.
- ALSA/audio and V-Sync warnings in a virtual screen are harmless.
- Seeded comparisons (seed(N) then play the same moves) prove a refactor changed no behaviour: run the same script on the old and new code and diff the output.
