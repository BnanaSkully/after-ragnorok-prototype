# Ragnarok Prototype

Turn-based 4X strategy prototype in Godot 4, written in GDScript.

## The game

Survivors of Ragnarök cross the void on Yggdrasil (the Crossing), then land on a small hex map and build, scheme and survive until the Doom arrives. Politics first; combat is auto-resolved.

## Game structure

- Phase 1: the Crossing (journey events) and the Landing (found your city). The Sun's Daughter (the new sun, unnamed in the myths) travels with the survivors and watches how each people behaves. She has a Favour score (0-10) toward each faction: Crossing choices that protect people raise it, abandoning them lowers it. The rival's Favour is hidden and random (3-6). At the Landing she chooses to shelter with whoever she trusts most (ties random). The player doesn't choose her; she chooses
- Sheltering her gives +2 Food and +2 Industry a turn and +3 city defence, but she is what Sköll hunts
- Economy (standard 4X): a city makes 2 Food and 1 Industry a turn; units cost 5 Industry and eat 1 Food a turn; walls cost 10 Industry per level. City defence = garrison unit's Strength + walls (+3 with the Daughter)
- Phase 2: settle and survive. Sköll, the wolf who swallowed the sun at Ragnarök, followed the survivors through the void. He arrives on turn 14 and can't be killed, only driven back. Each time he appears (arrival, or after being driven back) he picks a standing city at random to hunt and appears on the map edge nearest it (at least 3 hexes away); random so it's fair, since he doesn't know where the Daughter is. Once he is loose, the rival's units fall back to defend their city. In Phase 2 he doesn't know which city hides the Daughter; he finds out only after attacking it. If he loses that battle, Phase 3 starts early. If he wins it, he swallows her: he becomes the sun (Strength 20, a blazing look) and the map goes dark. Lose if your city falls; survive to turn 20 (the Doom) to reach Phase 3
- Phase 3 (not built yet): Sköll spawns chaos factions and rogue factions join him. Her city is the first he attacks (he charges it straight away if he found her in Phase 2). Needs a design before it can be built: what the player does, how chaos factions behave, how Phase 3 is won or lost

## The Sun's Daughter: design in progress

Built so far: she chooses her protector at the Landing by Favour, and she judges her protector (step 1). Planned, in this order:
1. DONE (Step B): treating her well = how well you run your kingdom. Each turn her protector starves (a unit deserts): her Favour -2; every 3 turns in a row fed: +1. On turn 14 (Sköll arrives) she checks city defence 10+ and army Strength 6+: both +2, one 0, neither -3. From turn 10 she warns the player what she wants, and the line under the top bar shows progress. Only her protector is judged. Numbers at the top of sun_daughter.gd
2. If her Favour with her protector drops too low she leaves and goes rogue: she appears on the map and moves away from Sköll. If Sköll reaches her in the open he swallows her with no battle. A faction's unit that reaches her can persuade her to join (odds based on its Favour)
3. Trading her from turn 10: her protector can offer her to another faction. Factions afraid of Sköll refuse. She is a liability as much as a prize, so her trade value can be NEGATIVE: a powerful faction may not want her, and the giver may have to pay extra for someone to take her. Trading her costs Favour with whoever gave her away
- Trading only gets interesting with 3+ factions; with two, the rival's fear of Sköll is the only variable

### Step A: economy with costs (standard 4X), in this order
1. DONE: several units per faction, built with Industry from the city (one unit per hex, destroyed units are gone, no free respawn; the rival builds too)
2. DONE: food upkeep: a city makes 2 Food a turn (+2 with the Daughter), every unit eats 1. Running out keeps Food at 0 and the unit farthest from the city deserts. The rival only builds units it can feed. Numbers are constants at the top of main.gd (CITY_FOOD, UNIT_FOOD_UPKEEP, UNIT_COST)
3. DONE: walls: a city improvement, 10 Industry per level, +4 defence each, up to 2 levels. The rival builds walls from turn 10. City defence is now the standard garrison + walls (+3 with the Daughter); stored Industry no longer counts. Numbers: WALL_COST, WALL_DEFENCE, MAX_WALLS in main.gd

## Current scope: prototype only

- Two Norse factions, one small hex map, no art (shapes and colours only)
- Do not add factions, pantheons, rogue factions or lore unless asked
- Goal: a playable loop of Crossing, Landing, turns, cities, auto-resolve and the Doom
- Basic diplomacy with the rival: pacts, demands, and a memory of whether promises were kept. This is the core hook and should be built before more combat or Sköll features.

## Diplomacy: agreed design

- Each faction has its own word for a sworn agreement (Faction.pact_word). Norse factions swear "oaths"; other pantheons later may use other words
- One diplomatic action per turn (for now)
- The rival keeps a Trust score toward the player (-10 to 10) and a short history of who kept or broke their word, shown on screen
- Steps, in order:
  1. DONE: oaths. Propose a 5-turn oath; the rival accepts by chance (50% + 10% per Trust, +20% once Sköll's howling starts, +10% if you have more units). During an oath neither side's units attack. Kept to the end: Trust +2. Breaking it (attacking the rival, which needs two clicks): Trust -5, oathbreaker for 8 turns (no new oaths), the Sun's Daughter's Favour -2
  2. DONE: demands. Demand 5 Food or 5 Industry (uses the turn's diplomatic action). The rival pays with chance 50% + 10% per point of army Strength you have over it (5-95%), 0% if it doesn't have 5. Paying: Trust -1 (resentment, as is usual in 4X). Refusing: Trust -2. Demanding something the rival doesn't have gets a rude reply (lines in diplomacy.gd, CANT_PAY_REPLIES) and costs nothing: no action used, no Trust change
  3. DONE: the rival's own diplomacy. At the start of a player turn (35% chance) it may propose an oath (if afraid of Sköll, weaker, or Trust 2+; never to an oathbreaker) or demand 5 Food/Industry (if its army is 3+ Strength stronger). A pop-up asks Accept/Pay or Refuse and blocks the turn until answered; answering doesn't use the player's own action. Accepting their oath Trust +1, refusing -1; paying their demand Trust +1, refusing -1. It may break an oath (25% a turn) when its army is 4+ stronger or it's starving: it can attack that same turn, the panel counts its broken oaths, and its Favour with the Sun's Daughter drops by 2
- Numbers for all of this are constants at the top of diplomacy.gd

## How Nathan works

- He is self-taught and new to game code: explain changes in plain words
- Keep changes small, and say exactly how to test each one (press F5, then click X)
- He wants honest pushback if an idea will cause problems later
- Commit after each working step with a clear message
- Default 4X mechanics, no need to ask: unit upkeep, production queues, city growth from food, fog of war, zone of control, healing when units rest, city walls and garrisons, starvation and desertion, movement costs by terrain. Pick the most common genre approach, mention it in the PR, and move on. Only ask about what is unique to this game: the Sun's Daughter, Sköll, the phases, politics, lore.

## Code notes

- main.gd: the flow of a game (Crossing, Landing, turns), the rival, combat odds, drawing and mouse clicks. Suggest splitting further when it gets too big (drawing and the Crossing screen are the next candidates)
- faction.gd (class Faction): one side's city, list of units, resources and the Daughter's Favour toward it
- unit.gd (class Unit): one army unit (position, moves, Strength). Holds a weak link to its faction to avoid a memory leak
- hex_map.gd (class HexMap, all static): hex maths: hex_center, hex_distance, is_neighbour, neighbours, cell_at, map size
- skoll.gd (class Skoll): everything Sköll does: warnings, arrival, walking, attacking cities and units, being driven back, swallowing the Daughter. Holds a reference to main.gd ("game")
- sun_daughter.gd (class SunDaughter): her name, bonuses, Favour rules and state (who holds her, swallowed or not)
- diplomacy.gd (class Diplomacy): oaths, Trust, the oathbreaker penalty and the history of promises; numbers are constants at its top
- crossing_events.gd: the Crossing's events (text, choices, effects), kept separate so they can be edited without touching game logic
- Code phases in order: CROSSING, LANDING, PLAYING (PLAYING covers game Phase 2)
- Sköll's numbers (ARRIVAL_TURN, STRENGTH, ...) are constants at the top of skoll.gd; the Daughter's (NAME, FOOD, DEFENCE, Favour ranges) at the top of sun_daughter.gd
- Pointy-top hexes, offset rows, drawn with code in _draw()

## Later (parked until the full loop is playable)

- Combat: +1 strength when defending in your own territory, so it isn't a pure coin flip
- Deeper politics beyond the basic diplomacy in scope (betrayal schemes, trading the Daughter, three-way deals)
- Give the two factions real names
- The rival should choose its own landing spot instead of a fixed one
- Crossing event text is placeholder: rewrite in the game's own voice
- Give the Sun's Daughter a real name
- Sköll's and the Daughter's numbers need tuning once played (in simulated games: building walls ~66% reach turn 20, building nothing ~54%)
- Mini-games: rare, high-stakes moments tied to politics only (e.g. a bluffing exchange during negotiation, a short tactical choice when Sköll hits a city). Never routine or repeatable. Main fix for dead turns is that every turn asks the player a real decision.
