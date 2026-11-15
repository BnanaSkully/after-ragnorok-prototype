# Ragnarok Prototype

Turn-based 4X strategy prototype in Godot 4, written in GDScript.

## The game

Survivors of Ragnarök cross the void on Yggdrasil (the Crossing), then land on a small hex map and build, scheme and survive until the Doom arrives. Politics first; combat is auto-resolved.

## Game structure

- Phase 1: the Crossing (journey events) and the Landing (found your city). The Sun's Daughter (the new sun, unnamed in the myths) travels with the survivors and watches how each people behaves. She has a Favour score (0-10) toward each faction: Crossing choices that protect people raise it, abandoning them lowers it. Each AI faction's Favour is hidden and random (3-6). At the Landing she chooses to shelter with whichever faction she trusts most (ties random). The player doesn't choose her; she chooses
- Sheltering her gives +2 Food and +2 Industry a turn and +3 city defence, but she is what Sköll hunts
- Economy (standard 4X): a city starts at population 1 making 2 Food and 2 Industry a turn; each extra population adds +1 Food, +1 Industry and +1 city defence (POP_DEFENCE; Nathan's playtest: population's effect was unclear, so it now also defends and every message about it says what it gives; the top bar shows "Pop"). Everyone unloads 5 Industry from the ark at the Landing (LANDING_INDUSTRY), enough to build something on turn 1. City growth: when stored Food reaches the growth cost (10, then 15, 20...) and Food isn't falling, the city grows and the Food is used up. Build options, each a trade-off: army unit 5 Industry (eats 1 Food a turn), scout 3, outpost 6, walls 10 per level. City defence = garrison unit's Strength + walls + land + population above 1 (+3 with the Daughter). Numbers: GROWTH_BASE, GROWTH_STEP etc. at the top of game_state.gd
- Early game (turns 1-10, see "Early game" below): every faction starts with an army unit and a scout, explores through fog of war, searches ruins, founds outposts, and the player gets a small event every 2-3 turns. Goal: every early turn asks the player a decision
- Phase 2: settle and survive. Sköll, the wolf who swallowed the sun at Ragnarök, followed the survivors through the void. He arrives on turn 14 and can't be killed, only driven back. Each time he appears (arrival, or after being driven back) he comes through one of the rifts in the void, chosen at random, and hunts the city that rift belongs to (he doesn't know where the Daughter is). Every standing city gets one rift, 4-7 hexes from it and at least 4 from every city (Skoll.place_rifts, RIFT_MIN_CITY_DISTANCE; was 3, and Nathan's playtest had him appear "right next to my city"). Rifts are rolled on turn 2 (after the Landing) and stay hidden; when he comes through one, only that rift is revealed. Every time he is driven back, the rifts are rolled again. Fair by design: over 300 games he first hunts each city about 25% (yours 25%); he comes out 4 hexes from the nearest city 52% of the time, 5+ the rest. (Rifts by map section, the old rule, put him on the player 41% of the time once the minimum distance was raised.) Once he is loose, AI units fall back to defend their cities. In Phase 2 he doesn't know which city hides the Daughter; he finds out only after attacking it. If he loses that battle, Phase 3 starts early. If he wins it, he swallows her: he becomes the sun (Strength 20, a blazing look) and the map goes dark. Lose if your city falls; survive to turn 20 (the Doom) to reach Phase 3
- Phase 3 (not built yet): the Long Night. Design agreed, see "Phase 3: agreed design" below

## Phase 3: agreed design (not built yet)

Goal: Sköll can't be killed, but he can be bound with a chain (like Fenrir and Gleipnir). One city can't forge it alone, so winning needs other factions: politics first. Numbers below are starting points; measure them with simulated games before trusting them.

- Start: on turn 20 (the Doom), or early if Sköll attacks the Daughter's city and loses (he now knows where she is). Code phase CHAOS after PLAYING. He goes straight for her city (or hunts her by sight if she's rogue)
- The Long Night: Phase 3 lasts 10 turns from its start (LONG_NIGHT_TURNS). If the chain isn't finished by then, the world freezes and everyone loses
- The chain: 3 links, each forged by a DIFFERENT faction, 15 Industry each (10 if Sköll swallowed the Daughter, but he is Strength 20 then). The player forges their own link with a "Forge link" button (like walls). When the 3rd link is done Sköll is bound: the player wins. If he had swallowed her, binding him frees her and the sun returns
- Chain oaths: the player asks an AI to forge a link (uses the turn's diplomatic action). Accept chance: 30% + 10% per Trust, +20% if Sköll is hunting its city, +10% if the Daughter's Favour toward the player is 7+ (she speaks for you), 0% if the player is its oathbreaker. Once sworn, the AI puts its spare Industry into its link each turn. Breaking a chain oath is the worst betrayal: Trust -5, its half-forged link is lost
- Rogue factions = existing AIs kneeling to Sköll (no new factions). Each Phase 3 turn, an AI without a chain oath that is desperate (starving, or Sköll hunts it and its city defence is under 6, or its Trust toward the player is -5 or less) has a 25% chance to go rogue. Rogue: Sköll and warbands leave it alone, its units attack everyone else, no diplomacy, can't forge a link, permanent. A rogue AI sheltering the Daughter hands her to Sköll (he swallows her)
- Chaos warbands (Sköll's chaos factions): every 3 turns 2 warbands (Strength 3, move 1) come out of a random rift (that rift is revealed). No city, no diplomacy. They walk to the nearest non-rogue territory (a city and its 6 neighbouring hexes) and sit there draining it: -1 Food and -1 Industry a turn to that city for each warband on its territory. They fight back when attacked (normal auto-resolve). A light version of the parked Doom-creatures
- Lose: your city falls; the Long Night ends with the chain unfinished; or the chain can no longer be finished (fewer than 3 factions left that could still forge a link, counting finished links)
- Win: Sköll is bound. The end screen shows the survivor score: the population of every standing city that didn't go rogue, +5 if the Daughter is alive and free, and lists who made it
- Build steps, in order (each playable and tested):
  1. Phase 3 starts (turn 20 or early), the Long Night clock, Sköll charges her city
  2. The chain: forging your link, chain oaths, binding, the survivor score (first playable win)
  3. AIs going rogue
  4. Chaos warbands and draining (territory is already a rule: GameState.territory_owner)

## Early game: built (standard 4X, from Nathan's playtest "turns 1-10 are dead")

- Fog of war with memory, for every faction (GameState.can_see, Faction.explored): each faction sees CITY_SIGHT (3) around its city, OUTPOST_SIGHT (2) around outposts, 2 around army units and 3 around scouts. Hexes once seen stay explored (land, cities, outposts, ruins stay known; units, Sköll and the Daughter only while in sight). Never-seen hexes are black. During the Landing the ark sees the shape of the land and where you may land, but not cities. The AIs explore and choose ruins/outposts by their own fog (they still always know where a rogue Daughter is: unchanged)
- Scouts (unit.gd, Unit.Kind.SCOUT): 2 moves, Strength 1, sight 3, eat no Food, 3 Industry, at most 2 per faction. A scout keeps its selection while it has a move left. Starving never makes a scout desert. AI scouts head for the nearest ruins they've seen, then the nearest unexplored hex; they never attack
- Discoveries (discoveries.gd): 8 ruins hidden at least 4 hexes from every city (out of sight at the start), placed at the Landing. The first unit to step on ruins searches them: the player chooses Food +6, Industry +4 or the Daughter's Favour +1 (pop-up; if her Favour is already 10, old maps that reveal where another people landed instead); any option that would raise Favour above 10 is greyed out with the reason (GameState.option_problem); an AI takes Food if short of it, else Industry. Rifts (Sköll's, still rolled on turn 2) become visible to a faction when it sees them and stay shown until they're re-rolled (Faction.known_rifts). No choice on finding a rift yet (sealing rifts would change Sköll: ask Nathan first)
- Outposts (GameState.outpost_spots, build_outpost): 6 Industry; on a hex you can see right now, within 5 of your city, at least 3 from every city and outpost, not on unsearched ruins. Income depends on the land (see Terrain below: plains +2 Food, forest +1/+1, hills +2 Industry), sight 2, claim their hex and the 6 around it as territory. Only a faction AT WAR with the owner can take an outpost: a unit stepping onto one nobody stands on takes it (at peace you just pass through; the player walking onto a peaceful faction's outpost declares war, with the two-click warning). Up to 3 founded per faction (captured ones can go over). The AI founds up to 2 before turn 10 and takes enemy outposts next to its units. A city that falls loses its outposts. Territory is a rule now (GameState.territory_owner); the view only colours it
- Small events (turn_events.gd): from turn 3-4, one every 2-3 turns (random), each at most once a game, player only. Every option costs something (Food, Industry, Favour, population, a coin flip, a unit standing watch for 2 turns ("guard_turns"), every AI's Trust ("trust_all"), or Food lost ("spoil", never below 0)); no option is free (Nathan's playtest: "post guards" was free, elk/traveller/merchants had free outs). Options you can't take are greyed out with the reason, and every event has an option that's always possible (tests/choices_test.gd checks both). Placeholder text
- Pop-ups: ruins and events go in GameState.pending_choices and are shown before any AI offer; the turn can't end until they're answered (GameState.is_waiting, can_act)
- Combat fix: beating a city's garrison no longer moves the attacker into the city
- Measured (tests/early_game_test.gd, 300 games, a test player that explores and builds): turns 1-10 with no decision 0 of 3000; pop-up on 33% of early turns; something affordable to build on 83%. Per game: 6.7 events, ruins searched 2.2 by you and 5.6 by the three AIs, you found 3.0 outposts, lost about 2 and took about 1.4 (before war and peace; since then outposts are only taken in a war: lost about 0.3-0.4 a game). Endings 225 survived / 49 city fell / 26 Daughter found
- Side effect to watch: the AIs expand too, so on turn 10 each AI has about 6 units (was 2.7). Against a player who doesn't expand, AI demands go from 0.5 to 1.25 a game

## Terrain, trading and tributaries: built (Nathan: "terrain first, then trading, cities become tributaries")

- Terrain (terrain.gd, GameState.terrain; standard 4X): plains, forest, hills, mountains, water, a new random map every game (weighted, clumped, always connected; AI cities on plains with passable neighbours). Forest and hills cost 2 moves, but a unit with all its moves can always take one step (armies still move 1 hex a turn; scouts are slowed). Mountains and water can't be crossed or stood on (Sköll ignores terrain). Defence: forest +1, hills +2, for units and for a city standing on them. Outposts earn by land: plains +2 Food, forest +1/+1, hills +2 Industry. Units find paths around obstacles (GameState.step_toward). Hovering a hex shows what its land does. Map ~53% plains, 21% forest, 14% hills, 6% mountains, 6% water
- Trading (diplomacy.gd; "Deal..." button per AI opens a panel; each deal uses the diplomatic action): demand 5 Food/Industry (as before); trade 5 of one for N of the other, where N = 4, +1 if they need what you give, -1 if they need what they give up, +1 at Trust 3+, -1 at Trust -3 or less (at least 1, at most what they have); gift 5 Food/Industry for Trust +1 (until Trust 5); at war, offer 6 Industry for peace (+30% chance, paid only if accepted). No trading at war. An AI short of one resource with enough of the other offers a trade (pop-up). Numbers TRADE_*, GIFT_*, PEACE_TRIBUTE* in diplomacy.gd
- Tributaries (game_state.gd "Taking cities"): a unit at war with a city's owner can attack the city from next to it: its Strength +2 for every other army of its own next to the city (siege support) against the whole city defence (garrison + walls + land + the Daughter). Win: the garrison dies, walls -1, and the city becomes the winner's TRIBUTARY (Faction.overlord); the attacker stays outside. Lose: the attacker dies. A tributary pays half its Industry income each turn to its overlord, their war ends, and neither can declare war on the other (nor be dragged into one by an alliance). Ways out: an AI tributary whose army is stronger than its overlord's rises up (20% a turn, then they're at war); the player rises up by attacking their overlord (two-click warning); taking your overlord's city frees you; if Sköll destroys the overlord's city its tributaries go free. Losing your city to an AI does NOT end the game (only Sköll destroying it does). AIs at war with 2+ armies send spare ones at the nearest enemy city and attack at 40%+ odds. Numbers TRIBUTE_SHARE, REBEL_CHANCE, SIEGE_SUPPORT, AI_SIEGE_ODDS in game_state.gd
- Closed borders (Nathan: "territory that needs politics to allow a border crossing, or war"; GameState.may_enter): at peace, units may not enter another faction's territory (its city and outposts and the 6 hexes around each). Allowed if at war, allied (an oath), with an open-borders agreement, or overlord/tributary. AIs keep borders closed to each other unless at war. The player stepping across a closed border declares war (two-click warning; the hex shows pink when a unit is selected). AI units path around closed territory. Open borders: a deal ("Ask for open borders", 40% + 10% per Trust, 10 turns, both ways; ends if war breaks out); an AI with Trust 1+ offers it (40% of its offers). Units left inside when borders close (peace made, agreement or oath ended, a city became a tributary) walk out to the nearest allowed hex at the end of the turn. Numbers BORDERS_LENGTH, RIVAL_BORDERS_TRUST in diplomacy.gd. Measured (border_test, 300 games): open-borders agreements 1.4 a game when the player asks often, AI offers 0.2, units walked out 0.3, never a unit inside closed borders at the end of a turn
- Measured (300 games each): trading about 3 trades and 1 gift a game, AIs offer 0.3 trades; cities taken about 0.07-0.1 a game (almost always an AI taking yours; you were a tributary on 0.4-0.6 turns a game); endings about 235-240 survived / 35-45 fell / 21-26 Daughter found. Siege odds: Strength 3 alone against defence 7 wins 30%, with two armies beside it 45-50%

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
- Fog of war (standard 4X) with memory, for every faction: see "Early game" above. Never-seen hexes are black; seen-before hexes are dimmed, with units, Sköll and the Daughter hidden. Cities are hidden until found. The diplomacy panel still lists every AI faction from the start (they were met on the Crossing)
- Do not add more factions, pantheons, rogue factions or lore unless asked (Phase 3's rogues are the existing AIs; its chaos warbands are not factions)
- Every move on the map goes through GameState.enter_hex (ruins, taking outposts); after anything moves call update_sight
- Goal: a playable loop of Crossing, Landing, turns, cities, auto-resolve and the Doom
- Basic diplomacy with the rival: pacts, demands, and a memory of whether promises were kept. This is the core hook and should be built before more combat or Sköll features.
- DONE: support for 3+ factions. Every AI faction runs the same AI (build, feed, walls from turn 10, guard its city, chase the Daughter, fight neighbours including other AIs). The player has a separate diplomatic relationship with each AI. Over 300 simulated games Sköll's first attack lands on the player about 26% of the time (fair share with 4 cities is 25%)

## Diplomacy: agreed design

### War and peace (built; Nathan: "you forgot an important factor of 4X games")
- Every pair of factions starts at PEACE. At peace, units can't attack each other or take each other's outposts (GameState.at_war). Sköll is everyone's enemy regardless
- The player declares war by attacking a unit or walking onto an outpost of a faction they're at peace with (two clicks: the first warns). Doesn't use the diplomatic action. Their Trust -3, every other AI's -1 (warmonger). Attacking an ally also breaks the oath (Trust -5 instead, oathbreaker, her Favour -2)
- Peace: the player asks (the diplomatic action; the agreement button becomes "Peace N%" during a war). Chance 30% + 10% per Trust + 5% per point of army Strength you have over them, +20% once Sköll howls (5-95%). An AI at war offers peace (25% a turn) when it's weaker, afraid of Sköll, or the war has lasted 5+ turns. Peace: Trust +1 and a 5-turn truce in which they won't declare war
- An AI declares war on the player (10% a turn, never in a truce) if its Trust is -5 or less, or its army is 4+ stronger and its Trust under 2, or it's starving. An ally only does so when 4+ stronger or starving (25%), and that breaks its oath
- AIs fight each other too: an AI may declare war on another AI whose army is 4+ weaker (5% a turn); after 4 turns of war they make peace at 20% a turn (40% once Sköll howls), then a 5-turn truce. AIs still don't make alliances with each other
- Numbers: TRUST_DECLARED_WAR, TRUCE_TURNS, RIVAL_WAR_* etc. in diplomacy.gd; AI_WAR_* and AI_PEACE_* in game_state.gd
- Measured (tests/war_test.gd, 300 games, a player using diplomacy at random): per game the AIs declare war on you 1.3 times, on each other 0.6, peace is made 1.5 times; allies honoured their oath 0.48 and broke it 0.44 times; your ally was attacked (pop-up) 0.18 times. Your outposts taken per game fell from 2.0 to 0.4, AI-vs-AI fights from 6 to 1 (early_game_test). Endings 251 survived / 29 fell / 20 Daughter found

- Each faction has its own word for a sworn agreement (Faction.pact_word). Norse factions swear "oaths"; other pantheons later may use other words
- The player has a separate relationship with each AI faction (its own Trust, agreement, oathbreaker status, demands and broken-promise count): one Diplomacy object per AI in GameState.relations. AI factions don't do diplomacy with each other yet
- One diplomatic action per turn in total, shared across all factions (for now)
- Each AI keeps a Trust score toward the player (-10 to 10); what all factions remember (who kept or broke their word) is shown on screen
- Each turn, each AI has a 15% chance to make the player an offer, and at most one offer is shown per turn
- Steps, in order:
  1. DONE: oaths = DEFENSIVE ALLIANCES (Nathan's choice once war and peace existed). Propose a 10-turn oath, only at peace; the rival accepts by chance (50% + 10% per Trust, +20% once Sköll's howling starts, +10% if you have more units). If an AI declares war on the player, every AI ally declares war on the aggressor, unless the aggressor's army is 4+ stronger than the ally's: then the ally breaks its oath (ALLY_ABANDON_GAP). If an AI declares war on the player's ally, a pop-up asks the player: honour it (declare war on the aggressor: ally Trust +2, aggressor Trust -2, no warmonger penalty) or stay out (breaks the oath: Trust -5, oathbreaker, her Favour -2). Kept to the end: Trust +2. Breaking it by attacking the ally (two clicks): Trust -5, oathbreaker for 8 turns (no new oaths), the Sun's Daughter's Favour -2
  2. DONE: demands. Demand 5 Food or 5 Industry (uses the turn's diplomatic action). The rival pays with chance 50% + 10% per point of army Strength you have over it (5-95%), 0% if it doesn't have 5. Paying: Trust -1 (resentment, as is usual in 4X). Refusing: Trust -2. Demanding something the rival doesn't have gets a rude reply (lines in diplomacy.gd, CANT_PAY_REPLIES) and costs nothing: no action used, no Trust change
  3. DONE: the rival's own diplomacy. At the start of a player turn (15% chance per AI) it may propose an oath (if at peace and afraid of Sköll, weaker, or Trust 2+; never to an oathbreaker), demand 5 Food/Industry (if its army is 3+ Strength stronger), or, at war, offer peace. A pop-up asks Accept/Pay/Make peace or Refuse and blocks the turn until answered; answering doesn't use the player's own action. Accepting their oath Trust +1, refusing -1; paying their demand Trust +1, refusing -1. An ally may betray you by declaring war (see War and peace): it can attack that same turn, the panel counts its broken oaths, and its Favour with the Sun's Daughter drops by 2
- Numbers for all of this are constants at the top of diplomacy.gd

## How Nathan works

- He is self-taught and new to game code: explain changes in plain words
- Keep changes small, and say exactly how to test each one (press F5, then click X)
- He wants honest pushback if an idea will cause problems later
- Commit after each working step with a clear message
- Default 4X mechanics, no need to ask: unit upkeep, production queues, city growth from food, fog of war, zone of control, healing when units rest, city walls and garrisons, starvation and desertion, movement costs by terrain. Pick the most common genre approach, mention it in the PR, and move on. Only ask about what is unique to this game: the Sun's Daughter, Sköll, the phases, politics, lore.

## Architecture rule (apply to all code)

Keep game rules separate from drawing. The game state and rules (map data, terrain, factions, units, food, combat, Favour, Sköll, the Doom) must not depend on how anything is drawn. Drawing code only reads the game state and shows it. Goal: the prototype stays 2D, but we can later replace the 2D drawing with a stylised low-poly 3D view without touching the game rules.

## How to test (see tests/README.md)

- Download Godot 4.7 (not installed in cloud sessions), run `--headless --import` once, then `--check-only --script <file>` for every changed script
- Test rules with headless scripts in tests/ (they use GameState directly); screenshots with xvfb-run; look at every screenshot for text running off screen or overlapping
- For refactors: seeded before/after comparison must be identical
- For balance changes: measure over hundreds of games and report the numbers
- Always run Godot with `timeout`: a script error in a test stops it before quit() and it hangs
- Keep rounds fast: the full suite (12 scripts, most play 300 games) takes 12-15 minutes. While building, run only the tests the change touches, with fewer games (e.g. 50); run the full suite once before pushing, in the background, and don't edit game scripts while it runs (each test loads them when it starts). tests/run_all.sh runs them 4 at a time; GAMES=50 makes every simulation play 50 games (quick mode). Not done yet: profiling the AI's pathfinding
- Before blaming the game for a failed check, make sure the test checks at the moment the rule promises (e.g. end of turn), has answered every pop-up, and didn't land on water
- NOTES.md has the history, Nathan's decisions and the bugs we learnt from

## Code notes

- game_state.gd (class GameState): the whole game state and its rules: phases, turns, economy, combat, the AI factions (ai_take_turn, ai_build), the Daughter going rogue, landing rules, and the player's actions (player_unit_act, player_build_unit, ...). No drawing, buttons or pixels. Holds the factions, Sköll, the Daughter and diplomacy
- main.gd: the 2D view. Draws the state (_draw), builds buttons and pop-ups (refresh keeps them in step), turns clicks into calls on the state. The right panel has a block per AI faction with its own agreement/demand buttons. Owns only screen things: selection, hover, the "click again to break your oath" warning, faction colours. A 3D view would replace this file
- hex_map.gd (class HexMap, static): the hex grid as the rules see it: map size, hex_distance, is_neighbour, neighbours (computed directly from the 6 offsets). Hex coordinates only
- terrain.gd (class Terrain, static): land types, move costs, defence, outpost income, and making a random connected map
- hex_view_2d.gd (class HexView2D, static): where hexes are on the 2D screen: hex size in pixels, hex_center, hex_points, cell_at (hex under the mouse). Only main.gd uses it
- faction.gd (class Faction): one side's city, units, outposts, resources, walls, population, the Daughter's Favour toward it, and what it has explored (fog of war) and which rifts it knows
- unit.gd (class Unit): one unit, an army or a scout (Unit.Kind): position, moves, Strength, sight, Food upkeep. Holds a weak link to its faction to avoid a memory leak
- discoveries.gd: ruins (placing them, the pop-up, what an AI takes); turn_events.gd: the small events (text, options, effects). Both are data plus small static helpers, edited without touching game logic
- skoll.gd (class Skoll): everything Sköll does: warnings, rifts, arrival, walking, attacking cities and units, being driven back, hunting and swallowing the Daughter. Holds a weak link to the GameState ("game")
- sun_daughter.gd (class SunDaughter): her name, bonuses, Favour rules and state (who holds her, rogue, swallowed)
- diplomacy.gd (class Diplomacy): the player's relationship with ONE AI faction ("other"): war and peace, alliances (oaths), demands, Trust, that faction's offers, wars and betrayals; numbers are constants at its top. Holds a weak link to the GameState. Wars between AIs, allies answering the call, and the call-to-arms pop-up are in game_state.gd ("War and peace")
- tests/: headless test scripts (see tests/README.md); NOTES.md: development history and decisions
- crossing_events.gd: the Crossing's events (text, choices, effects), kept separate so they can be edited without touching game logic
- Code phases in order: CROSSING, LANDING, PLAYING (PLAYING covers game Phase 2), in GameState.Phase; Phase 3 will add CHAOS
- Sköll's numbers (ARRIVAL_TURN, STRENGTH, ...) are constants at the top of skoll.gd; the Daughter's (NAME, FOOD, DEFENCE, Favour ranges) at the top of sun_daughter.gd
- Pointy-top hexes, offset rows, drawn with code in _draw()

## What's next (agreed order, as of the session that added borders)

Claude's recommendation, waiting on Nathan's choice:
1. Nathan plays a few games. He hasn't played since the early-game fix; war and peace, alliances, terrain, trading, tributaries and borders were only tested by simulation. His last playtest found what simulations missed
2. Phase 3, build step 1 (the Long Night starts, the clock runs, Sköll charges her city), so a game actually ends instead of stopping at "Phase 3 is not built yet"
3. Zone of control and healing (cheapest of the defaults still missing)

## Missing 4X mechanics (backlog)

Defaults from "How Nathan works" not built yet (build without asking):
- Zone of control: a unit must stop when it moves next to an enemy (now enemies can walk past an army to an outpost or city)
- Healing when resting, which needs unit health: today every fight kills one side outright; the standard is damage, so a winner comes out hurt. Resting heals, faster in your own territory
- Production queue: today things are bought instantly with stored Industry; standard is the city working on one item until it's finished
Other standard 4X mechanics (ask Nathan before building, they change the game's shape):
- Territory that grows with the city (borders pushing against each other: friction and reasons for war, now that borders are closed)
- Resources on the map (iron, horses, fertile land): worth fighting over, and more for trading than Food and Industry
- Espionage: a spy that sees inside a city, steals Industry or stirs trouble; caught = Trust falls. Fits a scheming, politics-first game
- AI-to-AI diplomacy beyond war and peace (alliances, trades, ganging up on the leader)
- A shared reputation: breaking your word with one AI makes every AI wary (today each AI judges you on its own)
- Unit experience (winners get a little stronger): nice to have
Deliberately left out of the prototype (big systems that don't serve "politics first" in 20 turns): tech tree, settlers and new cities (outposts do that job), happiness, culture, religion, more unit types, naval units

## Later (parked until the full loop is playable)

- Combat: +1 strength when defending in your own territory (terrain defence now exists: forest +1, hills +2)
- Asking an AI to join your war (for a payment): the next trading step
- AI-to-AI open borders and alliances
- Should the player be able to demand tribute without a war (vassalage by diplomacy)? Ask Nathan
- Deeper politics beyond the basic diplomacy in scope (betrayal schemes, three-way deals, AIs trading the Daughter between themselves)
- Give the four factions real names (placeholders now: Norse, Japanese, Celtic, Greek)
- AI factions should choose their own landing spots instead of fixed ones
- Diplomacy between AI factions beyond war and peace (alliances, demands, trading the Daughter between themselves)
- Should declaring war (not only breaking an oath) cost the Sun's Daughter's Favour? Ask Nathan
- Crossing event text is placeholder: rewrite in the game's own voice
- Give the Sun's Daughter a real name
- Sköll's and the Daughter's numbers need tuning once played (in simulated games: building walls ~66% reach turn 20, building nothing ~54%)
- Mini-games: rare, high-stakes moments tied to politics only (e.g. a bluffing exchange during negotiation, a short tactical choice when Sköll hits a city). Never routine or repeatable. Main fix for dead turns is that every turn asks the player a real decision.
- Rifts, full version: openings into the roots of Yggdrasil, which tore through the new world when the ark landed.
  - Players discover rifts by exploring; once found they stay visible.
  - During a recurring dangerous season, Doom-creatures emerge from rifts and roam nearby (non-hostile unless provoked, but they settle in territory and drain it, like a corruption that removes colour and output).
  - Armies can travel underground between discovered rifts, but only during the dangerous season, so using the shortcut means braving the creatures.
  - Sköll keeps using rifts as his way in.
  - Build only after the current prototype has been played end to end.
  - Phase 3's chaos warbands (drain territory) are the light version of the Doom-creatures; grow them into this rather than building it twice.
