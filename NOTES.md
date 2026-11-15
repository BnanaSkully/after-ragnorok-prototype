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
- Phase 3 design agreed (session of 2026-11-15, Nathan went with all of Claude's picks):
  - Win by binding Sköll with a 3-link chain, each link from a different faction: survival-only would repeat Phase 2, and the chain makes politics the only way to win.
  - Rogue factions are the existing AIs kneeling to Sköll when desperate or betrayed, so Phase 2 diplomacy pays off; no new factions.
  - Chaos factions are warbands from rifts that drain territory: cheap to build, and the first step toward the parked Doom-creatures.
  - The Long Night (10 turns) is the clock; losing also happens when the chain can no longer be finished (covers "everyone else went rogue").
  - Survivor score on a win: population of standing non-rogue cities, +5 if the Daughter is free. Makes saving allies a real choice.
  - If Sköll swallowed her: links are cheaper but he's Strength 20; binding him frees her.

## Things learnt (bugs found and fixed)

- A pop-up that blocks end_turn makes every headless test loop forever (the turn never advances). Tests must answer pop-ups (tests/helpers.gd answer_choices), and early_game_test checks the turn always advances.
- Beating a city's garrison used to move the attacker INTO the city (an old bug, found by the new "unit in someone else's city" check).
- Two tests (balance_state, rift_timing_test) still used the two-faction names (s.rival, s.diplomacy) and had silently stopped working. Run every test after big changes, not only the new one.
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
- Early game (300 games, a test player that explores and builds): 0 of 3000 early turns without a decision; endings 225 survived / 49 fell / 26 Daughter found (before the change, four_test: 229 / 50 / 21).
- Before vs after the early-game change, same simple player that never expands: each AI's units on turn 10 2.7 -> 6.0, AI demands per game 0.5 -> 1.25, oath offers 4.9 -> 5.0.

## Ideas parked (see CLAUDE.md "Later")

Faction names, the Daughter's name, Crossing text, small-event and ruin text, a choice when you find a rift (e.g. seal it: changes Sköll, ask first), AIs using fog of war to chase a rogue Daughter, AI landing choice, AI-to-AI diplomacy and trading, combat defence bonus, mini-games, full rifts (Doom-creatures, seasons, underground travel). Phase 3 is designed (CLAUDE.md), not built.
