# Ragnarok Prototype

Turn-based 4X strategy prototype in Godot 4, written in GDScript.

## The game

Survivors of Ragnarök cross the void on Yggdrasil (the Crossing), then land on a small hex map and build, scheme and survive until the Doom arrives. Politics first; combat is auto-resolved.

## Game structure

- Phase 1: the Crossing (journey events) and the Landing (found your city). The Sun's Daughter (the new sun, unnamed in the myths) travels with the survivors and watches how each people behaves. She has a Favour score (0-10) toward each faction: Crossing choices that protect people raise it, abandoning them lowers it. The rival's Favour is hidden and random (3-6). At the Landing she chooses to shelter with whoever she trusts most (ties random). The player doesn't choose her; she chooses
- Sheltering her gives +2 Food and +2 Industry a turn and +3 city defence, but she is what Sköll hunts
- Phase 2: settle and survive. Sköll, the wolf who swallowed the sun at Ragnarök, followed the survivors through the void. He arrives on turn 14, hunts the nearest city, and can't be killed, only driven back. In Phase 2 he doesn't know which city hides the Daughter; he finds out only after attacking it. If he loses that battle, Phase 3 starts early. If he wins it, he swallows her: he becomes the sun (Strength 20, a blazing look) and the map goes dark. Lose if your city falls; survive to turn 20 (the Doom) to reach Phase 3
- Phase 3 (not built yet): Sköll spawns chaos factions and rogue factions join him. Her city is the first he attacks (he charges it straight away if he found her in Phase 2). Needs a design before it can be built: what the player does, how chaos factions behave, how Phase 3 is won or lost

## The Sun's Daughter: design in progress

Built so far: she chooses her protector at the Landing by Favour. Planned, in this order:
1. Treating her well: her Favour with her protector changes each turn. HOW is not decided yet (ideas: a Food offering each turn, keeping her city safe). Don't build steps 2 and 3 until Nathan decides
2. If her Favour with her protector drops too low she leaves and goes rogue: she appears on the map and moves away from Sköll. If Sköll reaches her in the open he swallows her with no battle. A faction's unit that reaches her can persuade her to join (odds based on its Favour)
3. Trading her from turn 10: her protector can offer her to another faction. Factions afraid of Sköll refuse. She is a liability as much as a prize, so her trade value can be NEGATIVE: a powerful faction may not want her, and the giver may have to pay extra for someone to take her. Trading her costs Favour with whoever gave her away
- Trading only gets interesting with 3+ factions; with two, the rival's fear of Sköll is the only variable

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
- Sköll's and the Daughter's numbers need tuning once played (in simulated games where the player stays home: taking her in, ~64% reach turn 20; letting her pass, ~54%)
- main.gd is ~650 lines: split Sköll and the Daughter into their own file next
