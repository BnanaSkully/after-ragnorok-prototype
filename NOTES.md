# Development notes

A log of what has been built, decisions made with Nathan, and things learnt.
CLAUDE.md holds the rules for working; this file holds the history.

## Built so far (in order)

1. Doom countdown and end screen; later a Play Again button on every end screen.
2. Factions, auto-resolve combat (attacker wins with attack / (attack + defence)).
3. The Landing (click a hex to found your city), the Crossing (journey events in crossing_events.gd).
4. Sköll: Phase 2 boss. Can't be killed, only driven back. Arrives turn 14, warnings from turn 10.
5. The Sun's Daughter: chooses a protector by Favour at the Landing; judges her protector (fed people, ready walls/army on turn 14); goes rogue at Favour 2; can be persuaded back (Favour x 10%); can be traded from turn 10 (price can be negative; scared AIs offer her to you).
6. Economy (standard 4X): several units built with Industry, food upkeep and desertion, walls, garrisons, city growth from Food.
7. Diplomacy: oaths/pacts (each faction its own word), demands, Trust, memory of broken promises, the AIs' own offers and betrayals. One diplomatic action per turn.
8. Four factions: Norse (player), Japanese, Celtic, Greek (placeholder names). 15 x 11 map.
9. Rifts: rolled on turn 2, hidden, one per map section; Sköll comes through one at random, only that one is revealed; re-rolled each time he's driven back.
10. Fog of war: player sees 3 around city, 2 around units; Sköll sees 2 (only spots a rogue Daughter within 2).
11. Code split: game_state.gd (rules) vs main.gd (2D view); hex_map.gd (grid rules) vs hex_view_2d.gd (pixels).
12. Phase 3 designed (not built): bind Sköll with a 3-link chain; see CLAUDE.md.
13. Early game fix (Nathan's playtest: "turns 1-10 are dead, I just press End Turn"): fog of war with memory for every faction, scouts, ruins, rifts found by exploring, outposts (capturable), 2 Industry a turn + 5 at the Landing, small events every 2-3 turns, and a choice pop-up. All standard 4X, chosen without asking as CLAUDE.md says.
14. War and peace: everyone starts at peace; attacking declares war (Trust costs, warmonger); peace by agreement with a truce; AIs declare war on you and on each other. Oaths became defensive alliances with a call-to-arms pop-up.
15. Terrain (plains, forest, hills, mountains, water: move costs, defence, outpost income, pathfinding), trading (a Deal panel: demands, trades, gifts, paying for peace; AI trade offers), and taking cities in war: they become tributaries paying half their Industry, until they rise up.
16. Closed borders: at peace you can't enter another faction's land without an oath or an open-borders agreement; crossing declares war; units left inside walk out at the end of the turn.

## Decisions Nathan made (and why)

- Sköll (Fenrir's son who swallowed the sun) instead of Fenrir: the myths never say Sköll died, so he can survive Ragnarök without contradicting them. "Fire wolf" = the sun burning inside him.
- The Sun's Daughter is a refugee, not a pantheon: she's the prize everyone makes decisions about. She chooses her protector; you don't choose her.
- "Treated well" = how well you run your kingdom (fed, ready for Sköll).
- Her trade value can be negative: she's a liability as much as a prize.
- Sköll: random rifts (not "nearest city", which was unfair: it hit the player 2:1). Rifts hidden until used, re-rolled on return.
- Fog of war for Sköll too: he can't see her beyond his sight.
- Pacts are faction-specific words (Norse oath).
- Breaking an oath costs the Daughter's Favour ("you can't be trusted").
- Generic 4X mechanics: use the genre default without asking.
- Rules separate from drawing so a low-poly 3D view can replace the 2D one later.
- War and peace (Nathan: "you forgot an important factor of 4X games"): without it every faction was always at war, so outposts changed hands constantly and AIs fought every neighbour. Oaths became defensive alliances, since plain peace now does what the old oath did.
- Asked "what other 4X rules are we missing": Nathan chose terrain first, then trading, and that taken cities become tributaries (not destroyed, not captured outright). Losing your only city would otherwise end the game, so tribute keeps a lost war survivable.
- Phase 3 design agreed (session of 2026-11-15, Nathan went with all of Claude's picks):
  - Win by binding Sköll with a 3-link chain, each link from a different faction: survival-only would repeat Phase 2, and the chain makes politics the only way to win.
  - Rogue factions are the existing AIs kneeling to Sköll when desperate or betrayed, so Phase 2 diplomacy pays off; no new factions.
  - Chaos factions are warbands from rifts that drain territory: cheap to build, and the first step toward the parked Doom-creatures.
  - The Long Night (10 turns) is the clock; losing also happens when the chain can no longer be finished (covers "everyone else went rogue").
  - Survivor score on a win: population of standing non-rogue cities, +5 if the Daughter is free. Makes saving allies a real choice.
  - If Sköll swallowed her: links are cheaper but he's Strength 20; binding him frees her.

## Things learnt (bugs found and fixed)

- Godot's editor warnings (integer division, names shadowing get/set/owner) don't show with --check-only; run the game with --debug --quit-after 5 to see them. Nathan saw 11 in his Debugger; now 0.
- The army snowball only showed with a test player that plays like a person (outposts on plains, a Granary, armies while Food allows): a naive one starved at 2 armies and hid the problem.

- A pop-up that blocks end_turn makes every headless test loop forever (the turn never advances). Tests must answer pop-ups (tests/helpers.gd answer_choices), and early_game_test checks the turn always advances.
- Beating a city's garrison used to move the attacker INTO the city (an old bug, found by the new "unit in someone else's city" check).
- Two tests (balance_state, rift_timing_test) still used the two-faction names (s.rival, s.diplomacy) and had silently stopped working. Run every test after big changes, not only the new one.
- A test that places units on fixed hexes breaks once terrain is random (the hex may be water): rule tests call H.flatten(s) to make the map plains; full-game simulations keep random terrain.
- Assigning a plain list to a typed array (faction.outposts = [...]) is a script error, and a test that hits a script error hangs until its timeout with NO output (Godot buffers it). If a test seems to hang, run it with a timeout and read the end of its output.
- An AI ally answered your call to arms even when it was the aggressor's tributary (at war with its own overlord): found by the "at war with overlord" check.
- One army alone almost never takes a walled city (Strength 3 vs defence 7-11), so cities were taken 0.06 times a game: siege support (+2 per extra army next to the city) is the usual 4X answer.
- HexMap.neighbours used to check all 165 hexes on every call; pathfinding made that too slow, so it now computes the 6 offsets (checked identical on every hex).
- A turn can't end while a pop-up waits, so a test that moves units (which can find ruins) must answer pop-ups again right before End Turn, or end_turn silently does nothing and later checks run on a turn that never ended.
- Check rules at the moment they're promised: units are walked out of closed borders at the END of the turn, so checking right after answering a peace offer (mid-turn) reports false problems.
- An AI offer that comes after another in the same "if" chain may never be reached: AI open-borders offers were 0 a game until they were checked before oath offers.
- Count a message once: the same messages can still be on screen after the player's moves and again after End Turn (the outpost-capture count was doubled at first).
- Sköll's "nearest city" targeting was biased by map geometry (2:1 against the player). Measure fairness with many simulated games before trusting a rule.
- Without the Daughter, a city made +0 Food with two units and could never grow: added standard city growth.
- Stored Industry counting as defence (an invented rule) made walls worth only +2. Removed; use genre standards.
- Equal speeds meant Sköll could never catch a fleeing Daughter: he sprints 2 hexes when he spots her.
- Units holding their faction and the faction holding its units leaked memory: Unit, Skoll and Diplomacy hold weak links back.
- "is_neighbour" used to measure screen pixels: a rule depending on drawing. Now uses hex coordinates.
- With three AIs at 35% each, offers popped up most turns: per-AI chance lowered to 15%, at most one per turn.
- Long text runs under the buttons on the right: check screenshots after adding any text.
- Nathan's playtest found what simulations missed (Strength not changing, no restart). Ask him to play after big changes.

## Measured numbers (simulated games)

- Four factions: Sköll's first attack hits the player ~26% (fair share 25%); player's city falls ~17%.
- With hidden rifts (two factions, earlier): city falls ~21% with the Daughter, ~29% without.
- A scared AI offers her in ~31% of games where it holds her.
- About 4 AI offers per game; AIs break agreements ~1 per game.
- War and peace (war_test, 300 games): AIs declare war on you 1.3 times a game, on each other 0.6; 1.5 peaces; allies honour their oath about as often as they break it (0.48 vs 0.44). Your outposts taken 2.0 -> 0.4 a game, AI-vs-AI fights 6 -> 1.
- Terrain, trading, tributaries (300 games each): about 3 trades a game; cities taken about 0.1 a game; endings 239 survived / 35 fell / 26 Daughter found. Siege: alone 30%, with two armies beside it 45-50%.
- Early game (300 games, a test player that explores and builds): 0 of 3000 early turns without a decision; endings 225 survived / 49 fell / 26 Daughter found (before the change, four_test: 229 / 50 / 21).
- Before vs after the early-game change, same simple player that never expands: each AI's units on turn 10 2.7 -> 6.0, AI demands per game 0.5 -> 1.25, oath offers 4.9 -> 5.0.

## Where we stopped (end of the borders session)

- Nathan asked why the last round took long. Answer: mostly testing. The full suite takes 12-15 minutes and ran several times, border_test ran about 5 times, and three rounds went on false alarms from the tests themselves (checking mid-turn, a ruin pop-up stopping End Turn) rather than the game. Fixes offered: quick runs with fewer games while building, the full suite once at the end, parallel test runs (not set up yet)
- Nathan asked what other mechanics are missing: the list is in CLAUDE.md "Missing 4X mechanics". Claude's honest pushback: the biggest gap is the end of the game (Phase 3 isn't built), and nothing since the early-game fix has been played by a human. Recommended order: Nathan plays, then Phase 3 step 1, then zone of control and healing. Nathan hasn't chosen yet
- Open questions for Nathan (also in CLAUDE.md "Later"): should declaring war cost the Daughter's Favour; tribute by diplomacy without a war; a choice when finding a rift (sealing it changes Sköll)

## Part 2 (middle and late game), finished

- Nathan merged the Part 2 branch into main himself (with his concept art) before it was finished; the last commit on top fixed the stale tests and the docs
- The old "Phase 3: the Long Night" design was replaced by Nathan's Part 2 spec: 40 turns, Sköll returning stronger, ash, Sunna's requests and rising, four endings. Parked in CLAUDE.md "Later"
- Balance lessons from simulations: once mortal, Sköll died to AI cities ~90% of the time (now only an ATTACK can kill him; a city that holds just drives him back). He never devoured anyone until he hit cities twice as hard (CITY_DAMAGE 2.0). Sunna rose 92% because AIs' Favour climbed by itself (now feeding stops at 7 and the AIs pay for her requests): 51%
- Tests that read message text break when the text changes: four_test, balance_state and army_test counted Sköll's attacks by old messages; rift_timing_test expected him back the moment he was driven off (now he's away 3 turns)
- The memory list ("They remember") shows 2 lines per entry: keep remembered lines short and put the detail in the message

## Zone of control (2026-11-18)

- Nathan said "continue" without picking; read as the recommended next build, zone of control. Built in the cloud
- Pushback recorded: the backlog's wording ("a unit must stop when it moves next to an enemy") does nothing for armies, which have 1 move. So the classic Civ 1-3 rule was added too: from an enemy army's zone you can't step to another hex in an enemy zone. That is what stops armies walking past each other
- Effect is small (zoc_test: outposts lost 0.62 -> 0.53, fights 7.8 -> 6.7): it matters more once Nathan plays wars by hand

## Sunna, the contested sun (2026-11-22)

- Nathan's design (agreed 22 Nov), built in 4 steps, one commit and one 300-game midgame_test run each. Full numbers in CLAUDE.md "Sunna, the contested sun"
- Interpretations made while building (AIs keep no Trust toward each other): the Trust drain only applies when you hold her; for an AI holder, "another people recognises her" means its relationship with you (Trust 2+ or an oath); AIs at war with her holder march on that city first; "accepts your next oath or deal" covers an oath, open borders, a demand and peace
- Result: with every step in, a passive test player gets Dawn under 1% (target about 15%), and an active one (grants every request, keeps an oath; scratch test, 150 games) about 9%. The biggest single blocker for the active player is Sköll never attacking her city (10% of games). Tuning options were offered to Nathan with the PR
- Nathan picked the tuning: driving Sköll off near your city counts as holding. A player who chases her now reaches Dawn 15%; a passive one 3%. tests/active_sunna.gd measures the chasing player
- The first baseline run used the stale local main branch (79 commits behind origin/main): always worktree from origin/main. Also: don't edit game scripts while a test runs from the same folder; run measurements from a copy

## Full rifts (started 2026-11-22)

- Plan written 2026-11-18 (https://claude.ai/artifact/KeBmGLExp4SuRjLBjj27oZ). Nathan's answers on 22 Nov: rifts become permanent; the season runs on a fixed calendar for now; the creatures are "Rift Walkers" and kept simple (his words on the first design: "confusing, maybe too much"), so their only land effect is -1 Food per Walker on your land; then "yes" to starting now
- Step 1: the rifts moved out of skoll.gd into rifts.gd (class Rifts, GameState.rifts), since the season, Rift Walkers and travel will all use them, not only Sköll. No change in play: tests/seed_fingerprint.gd (12 seeded games, 428 turns) printed identical lines before and after

## Ideas parked (see CLAUDE.md "Later")

Faction names, the Daughter's name, Crossing text, small-event and ruin text, a choice when you find a rift (e.g. seal it: changes Sköll, ask first), AIs using fog of war to chase a rogue Daughter, AI landing choice, AI-to-AI diplomacy and trading, combat defence bonus, paying an AI to join your war, mini-games, full rifts (Doom-creatures, seasons, underground travel). The old Long Night design (chain, rogues, warbands) is parked in CLAUDE.md "Later".
