# Ragnarok Prototype

Turn-based 4X strategy prototype in Godot 4, written in GDScript.

## The game

Survivors of Ragnarök cross the void on Yggdrasil (the Crossing), then land on a small hex map and build, scheme and survive until the Doom arrives. Politics first; combat is auto-resolved.

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
- Game phases in order: CROSSING, LANDING, PLAYING
- Pointy-top hexes, offset rows, drawn with code in _draw()

## Later (parked until the full loop is playable)

- Combat: +1 strength when defending in your own territory, so it isn't a pure coin flip
- Respawning a destroyed unit should cost Industry (gives Industry a use)
- Politics between factions (truces, deals, betrayal) needs a design before it can be built
- Give the two factions real names
- What surviving the Doom means (win/lose conditions)
- The rival should choose its own landing spot instead of a fixed one
- Crossing event text is placeholder: rewrite in the game's own voice
