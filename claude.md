\# Ragnarok Prototype



Turn-based 4X strategy prototype in Godot 4, written in GDScript.



\## The game

Survivors of Ragnarök cross the void on Yggdrasil (the Crossing), then land on a small hex map and build, scheme and survive until the Doom arrives. Politics first; combat is auto-resolved.



\## Current scope: prototype only

\- Two Norse factions, one small hex map, no art (shapes and colours only)

\- Do not add factions, pantheons, rogue factions or lore unless asked

\- Goal: a playable loop of Crossing, Landing, turns, cities, auto-resolve and the Doom



\## How Nathan works

\- He is self-taught and new to game code: explain changes in plain words

\- Keep changes small, and say exactly how to test each one (press F5, then click X)

\- He wants honest pushback if an idea will cause problems later

\- Commit after each working step with a clear message



\## Code notes

\- Everything is in main.gd for now; suggest splitting it into files when it gets too big

\- Pointy-top hexes, offset rows, drawn with code in \_draw()

