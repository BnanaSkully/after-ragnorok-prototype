# Ragnarok Prototype

Turn-based 4X strategy prototype in Godot 4, written in GDScript.

## The game

Survivors of Ragnarök cross the void on Yggdrasil (the Crossing), then land on a small hex map and build, scheme and survive until the Doom arrives. Politics first; combat is auto-resolved.

## Game structure

- Phase 1: the Crossing (journey events) and the Landing (found your city). The last Crossing event is meeting the Sun's Daughter (the new sun, unnamed in the myths): take her in (she shelters in your city) or let her pass (the rival's people take her in). One side always holds her from the Landing on
- Sheltering her gives +2 Food and +2 Industry a turn and +3 city defence, but she is what Sköll hunts
- Phase 2: settle and survive. Sköll, the wolf who swallowed the sun at Ragnarök, followed the survivors through the void. He arrives on turn 14, hunts the nearest city, and can't be killed, only driven back. In Phase 2 he doesn't know which city hides the Daughter; he finds out only after attacking it. If he loses that battle, Phase 3 starts early. If he wins it, he swallows her: he becomes the sun (Strength 20, a blazing look) and the map goes dark. Lose if your city falls; survive to turn 20 (the Doom) to reach Phase 3
- Phase 3 (not built yet): Sköll spawns chaos factions and rogue factions join him. Her city is the first he attacks (he charges it straight away if he found her in Phase 2). Needs a design before it can be built: what the player does, how chaos factions behave, how Phase 3 is won or lost

## Current scope: prototype only

- Two Norse factions, one small hex map, no art (shapes and colours only)
- Do not add factions, pantheons, rogue factions or lore unless asked
- Goal: a playable loop of Crossing, Landing, turns, cities, auto-resolve and the Doom

## How Nathan works

- He is self-taught and new to game code: explain changes in plain words
- Keep changes small, and say exactly how to test each one (press F5, then click X)
- He wants honest pushback if an idea will cause problems later
- Commit after each working step with a clear message

## Code notes

- Game logic is in main.gd; suggest splitting it further when it gets too big
- Faction (one side's city, unit and resources) is in faction.gd, registered with class_name so any script can use it
- The Crossing's events (text, choices, effects) are in crossing_events.gd, kept separate so they can be edited without touching game logic
- Code phases in order: CROSSING, LANDING, PLAYING (PLAYING covers game Phase 2)
- Sköll's and the Daughter's numbers (SKOLL_TURN, SKOLL_STRENGTH, DAUGHTER_FOOD, etc.) and her name (DAUGHTER_NAME) are constants at the top of main.gd
- Pointy-top hexes, offset rows, drawn with code in _draw()

## Later (parked until the full loop is playable)

- Combat: +1 strength when defending in your own territory, so it isn't a pure coin flip
- Respawning a destroyed unit should cost Industry (gives Industry a use)
- Politics between factions (truces, deals, betrayal) needs a design before it can be built
- Give the two factions real names
- The rival should choose its own landing spot instead of a fixed one
- Crossing event text is placeholder: rewrite in the game's own voice
- Give the Sun's Daughter a real name
- Factions handing over, taking or jointly protecting the daughter: the first real politics
- Sköll's and the Daughter's numbers need tuning once played (in simulated games where the player stays home: taking her in, ~64% reach turn 20; letting her pass, ~54%)
- main.gd is ~650 lines: split Sköll and the Daughter into their own file next
