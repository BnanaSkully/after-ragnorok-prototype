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
- Phase 3 (chaos factions, rogues join Sköll) needs design before building.

## Things learnt (bugs found and fixed)

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

## Ideas parked (see CLAUDE.md "Later")

Faction names, the Daughter's name, Crossing text, AI landing choice, AI-to-AI diplomacy and trading, combat defence bonus, mini-games, full rifts (Doom-creatures, seasons, underground travel), Phase 3 design.
