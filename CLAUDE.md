# Ragnarok Prototype

Turn-based 4X strategy prototype in Godot 4, written in GDScript.

## The game

Survivors of Ragnarök cross the void on Yggdrasil (the Crossing), then land on a small hex map and build, scheme and survive until the Doom arrives. Politics first; combat is auto-resolved.

## Game structure

- Phase 1: the Crossing (journey events) and the Landing (found your city). The Sun's Daughter (the new sun, unnamed in the myths) travels with the survivors and watches how each people behaves. She has a Favour score (0-10) toward each faction: Crossing choices that protect people raise it, abandoning them lowers it. Each AI faction's Favour is hidden and random (3-6). At the Landing she chooses to shelter with whichever faction she trusts most (ties random). The player doesn't choose her; she chooses
- Sheltering her gives +2 Food and +2 Industry a turn and +3 city defence, but she is what Sköll hunts
- Economy (standard 4X): a city starts at population 1 making 2 Food and 1 Industry a turn; each extra population adds +1 Food and +1 Industry. City growth: when stored Food reaches the growth cost (10, then 15, 20...) and Food isn't falling, the city grows and the Food is used up. Units cost 5 Industry and eat 1 Food a turn; walls cost 10 Industry per level. City defence = garrison unit's Strength + walls (+3 with the Daughter). Numbers: GROWTH_BASE, GROWTH_STEP etc. at the top of game_state.gd
- Phase 2: settle and survive. Sköll, the wolf who swallowed the sun at Ragnarök, followed the survivors through the void. He arrives on turn 14 and can't be killed, only driven back. Each time he appears (arrival, or after being driven back) he comes through one of 6 rifts in the void, chosen at random, and hunts the city nearest that rift (he doesn't know where the Daughter is). The map is split into 6 sections (3 x 2) and every section gets one rift on a random hex, at least 3 from every city (Skoll.place_rifts). Rifts are rolled on turn 2 (after the Landing) and stay hidden; when he comes through one, only that rift is revealed. Every time he is driven back, the rifts are rolled again. Over 1000 games his first attack is even between the cities. Once he is loose, AI units fall back to defend their cities. In Phase 2 he doesn't know which city hides the Daughter; he finds out only after attacking it. If he loses that battle, Phase 3 starts early. If he wins it, he swallows her: he becomes the sun (Strength 20, a blazing look) and the map goes dark. Lose if your city falls; survive to turn 20 (the Doom) to reach Phase 3
- Phase 3 (not built yet): Sköll spawns chaos factions and rogue factions join him. Her city is the first he attacks (he charges it straight away if he found her in Phase 2). Needs a design before it can be built: what the player does, how chaos factions behave, how Phase 3 is won or lost

## The Sun's Daughter: design in progress

Built so far: she chooses her protector at the Landing by Favour, judges her protector (step 1), can go rogue (step 2) and can be traded (step 3):
1. DONE (Step B): treating her well = how well you run your kingdom. Each turn her protector starves (a unit deserts): her Favour -2; every 3 turns in a row fed: +1. On turn 14 (Sköll arrives) she checks city defence 10+ and army Strength 6+: both +2, one 0, neither -3. From turn 10 she warns the player what she wants, and the line under the top bar shows progress. Only her protector is judged. Numbers at the top of sun_daughter.gd
2. DONE: going rogue. When her Favour toward her protector is 2 or less she walks out onto a hex next to the city (the player is warned at 4 or less) and the protector loses her bonuses. In the open she moves 1 hex a turn away from Sköll. Fog of war: Sköll only sees 2 hexes (Skoll.SIGHT_RANGE); if he spots her he hunts her instead of a city and sprints 2 hexes a turn; reaching her, he swallows her with no battle. Beyond his sight she is hidden from him. Moving a unit onto her tries to persuade her: chance = that faction's Favour x 10%; success, she shelters in its city. The rival's units go after her too. Numbers: LEAVE_FAVOUR etc. in sun_daughter.gd, SIGHT_RANGE and SPRINT in skoll.gd
3. DONE: trading her, from turn 10, by whoever shelters her (uses the player's diplomatic action). Her value to a faction is a price in Industry (-10 to 10): 6, +/-1 per point of her Favour toward them above/below 5, -3 once the howling starts or -6 once Sköll is loose, -3 more if he's hunting their city, -1 per 3 points their army is stronger than the giver's. Positive: they pay the giver (up to what they have). Negative: the giver pays them. Below -8: they refuse. Being traded costs her Favour toward the giver (-2). An AI sheltering her wants her gone (from turn 10) if her value to it is negative or Sköll is hunting its city; then each turn it has a 50% chance to offer her to the player, before any other offer: for nothing, or paying the player if her value is negative (Take her / Refuse pop-up). In tests an AI offers her in about 31% of games where it holds her. "Trade her" button opens a panel with each faction's price. Numbers: TRADE_* and FEAR_* in sun_daughter.gd

### Step A: economy with costs (standard 4X), in this order
1. DONE: several units per faction, built with Industry from the city (one unit per hex, destroyed units are gone, no free respawn; the rival builds too)
2. DONE: food upkeep: a city makes 2 Food a turn (+2 with the Daughter), every unit eats 1. Running out keeps Food at 0 and the unit farthest from the city deserts. The rival only builds units it can feed. Numbers are constants at the top of game_state.gd (CITY_FOOD, UNIT_FOOD_UPKEEP, UNIT_COST)
3. DONE: walls: a city improvement, 10 Industry per level, +4 defence each, up to 2 levels. The rival builds walls from turn 10. City defence is now the standard garrison + walls (+3 with the Daughter); stored Industry no longer counts. Numbers: WALL_COST, WALL_DEFENCE, MAX_WALLS in game_state.gd

## Current scope: prototype only

- Four factions: the player (Norse) and three AI factions with placeholder names, one per pantheon: Japanese, Celtic, Greek. Each has its own word for a sworn agreement (Norse oath, Japanese pact, Celtic bond, Greek treaty: placeholders, not lore). AI cities start at fixed spots spread around the map; the player lands at least 4 hexes from all of them
- One 15 x 11 hex map, no art (shapes and colours only)
- Fog of war (standard 4X): the player sees 3 hexes around their city and 2 around each unit (GameState.player_can_see, CITY_SIGHT, UNIT_SIGHT). Elsewhere the map is dimmed and other factions' units, Sköll, the rogue Daughter and the revealed rift are hidden. Cities and territory stay visible everywhere (seen from the ark at the Landing, when the whole map is visible). Fog only changes what is drawn, not the rules
- Do not add more factions, pantheons, rogue factions or lore unless asked
- Goal: a playable loop of Crossing, Landing, turns, cities, auto-resolve and the Doom
- Basic diplomacy with the rival: pacts, demands, and a memory of whether promises were kept. This is the core hook and should be built before more combat or Sköll features.
- DONE: support for 3+ factions. Every AI faction runs the same AI (build, feed, walls from turn 10, guard its city, chase the Daughter, fight neighbours including other AIs). The player has a separate diplomatic relationship with each AI. Over 300 simulated games Sköll's first attack lands on the player about 26% of the time (fair share with 4 cities is 25%)

## Diplomacy: agreed design

- Each faction has its own word for a sworn agreement (Faction.pact_word). Norse factions swear "oaths"; other pantheons later may use other words
- The player has a separate relationship with each AI faction (its own Trust, agreement, oathbreaker status, demands and broken-promise count): one Diplomacy object per AI in GameState.relations. AI factions don't do diplomacy with each other yet
- One diplomatic action per turn in total, shared across all factions (for now)
- Each AI keeps a Trust score toward the player (-10 to 10); what all factions remember (who kept or broke their word) is shown on screen
- Each turn, each AI has a 15% chance to make the player an offer, and at most one offer is shown per turn
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

## Architecture rule (apply to all code)

Keep game rules separate from drawing. The game state and rules (map data, terrain, factions, units, food, combat, Favour, Sköll, the Doom) must not depend on how anything is drawn. Drawing code only reads the game state and shows it. Goal: the prototype stays 2D, but we can later replace the 2D drawing with a stylised low-poly 3D view without touching the game rules.

## Code notes

- game_state.gd (class GameState): the whole game state and its rules: phases, turns, economy, combat, the AI factions (ai_take_turn, ai_build), the Daughter going rogue, landing rules, and the player's actions (player_unit_act, player_build_unit, ...). No drawing, buttons or pixels. Holds the factions, Sköll, the Daughter and diplomacy
- main.gd: the 2D view. Draws the state (_draw), builds buttons and pop-ups (refresh keeps them in step), turns clicks into calls on the state. The right panel has a block per AI faction with its own agreement/demand buttons. Owns only screen things: selection, hover, the "click again to break your oath" warning, faction colours. A 3D view would replace this file
- hex_map.gd (class HexMap, static): the hex grid as the rules see it: map size, hex_distance, is_neighbour, neighbours. Hex coordinates only
- hex_view_2d.gd (class HexView2D, static): where hexes are on the 2D screen: hex size in pixels, hex_center, hex_points, cell_at (hex under the mouse). Only main.gd uses it
- faction.gd (class Faction): one side's city, list of units, resources, walls, population and the Daughter's Favour toward it
- unit.gd (class Unit): one army unit (position, moves, Strength). Holds a weak link to its faction to avoid a memory leak
- skoll.gd (class Skoll): everything Sköll does: warnings, rifts, arrival, walking, attacking cities and units, being driven back, hunting and swallowing the Daughter. Holds a weak link to the GameState ("game")
- sun_daughter.gd (class SunDaughter): her name, bonuses, Favour rules and state (who holds her, rogue, swallowed)
- diplomacy.gd (class Diplomacy): the player's relationship with ONE AI faction ("other"): agreements, demands, Trust, that faction's offers and betrayals; numbers are constants at its top. Holds a weak link to the GameState
- crossing_events.gd: the Crossing's events (text, choices, effects), kept separate so they can be edited without touching game logic
- Code phases in order: CROSSING, LANDING, PLAYING (PLAYING covers game Phase 2), in GameState.Phase
- Sköll's numbers (ARRIVAL_TURN, STRENGTH, ...) are constants at the top of skoll.gd; the Daughter's (NAME, FOOD, DEFENCE, Favour ranges) at the top of sun_daughter.gd
- Pointy-top hexes, offset rows, drawn with code in _draw()

## Later (parked until the full loop is playable)

- Combat: +1 strength when defending in your own territory, so it isn't a pure coin flip
- Deeper politics beyond the basic diplomacy in scope (betrayal schemes, three-way deals, AIs trading the Daughter between themselves)
- Give the four factions real names (placeholders now: Norse, Japanese, Celtic, Greek)
- AI factions should choose their own landing spots instead of fixed ones
- Diplomacy between AI factions (they currently only deal with the player)
- Crossing event text is placeholder: rewrite in the game's own voice
- Give the Sun's Daughter a real name
- Sköll's and the Daughter's numbers need tuning once played (in simulated games: building walls ~66% reach turn 20, building nothing ~54%)
- Mini-games: rare, high-stakes moments tied to politics only (e.g. a bluffing exchange during negotiation, a short tactical choice when Sköll hits a city). Never routine or repeatable. Main fix for dead turns is that every turn asks the player a real decision.
