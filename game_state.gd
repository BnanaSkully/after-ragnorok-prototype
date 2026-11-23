class_name GameState
extends RefCounted

# The whole game: its state and its rules. Nothing in here draws, knows about
# buttons, or uses pixel positions; it only uses hex coordinates. The 2D view
# (main.gd) reads this and draws it, and calls the action functions below when
# the player clicks. A future 3D view could do the same without changing a line
# here. Other rule pieces live in their own files:
#   faction.gd          one side's city, units and resources
#   unit.gd             one army unit on the map
#   hex_map.gd          the hex grid (distances, neighbours)
#   skoll.gd            Sköll, the wolf boss
#   sun_daughter.gd     the Sun's Daughter
#   diplomacy.gd        the player's relationship with one AI faction (oaths, demands, Trust)
#   crossing_events.gd  the Crossing's events (text and choices)
#   turn_events.gd      small events every few turns after the Landing
#   discoveries.gd      ruins hidden in the fog (placing them, their rewards)
#   terrain.gd          the land: plains, forest, hills, mountains, water
#   buildings.gd        city buildings (Granary, Workshop, Watchtower, Forge)

const RISE_TURN := 20 # from this turn Sunna can rise (it used to be "the Doom" and a dead end)
const END_TURN := 40 # the game ends here: Dawn if Sunna rose with you, else Dominion (most land)
const DEVOURED_SHARE := 0.45 # Sköll wins once he has devoured this share of all factions
const AI_REQUEST_COST := 5 # Industry an AI pays to grant one of Sunna's requests
const ASH_PER_CYCLE := 8 # hexes that turn to ash each time Sköll comes through a rift
const WOLF_SUPPORT := 2 # each other army of yours or your allies next to Sköll adds this to an attack on him
const MIN_LANDING_DISTANCE := 4 # how many hexes away from every AI city you must land
const LANDING_INDUSTRY := 5 # Industry everyone unloads from the ark at the Landing (enough to build something on turn 1)
const UNIT_COST := 5 # Industry to build a new army unit
const SCOUT_COST := 3 # Industry to build a scout
const MAX_SCOUTS := 2 # scouts each faction may have at once
const QUEUE_MAX := 5 # items a city's production queue can hold
const CITY_FOOD := 2 # Food a city produces each turn
const CITY_INDUSTRY := 2 # Industry a city produces each turn
const UNIT_FOOD_UPKEEP := 1 # Food each army unit eats each turn (scouts eat nothing)
# Combat between units (standard 4X): both sides take damage. The damage
# shared out is COMBAT_DAMAGE split by Strength (each side's share = the
# other side's Strength / both together), then varied by up to DAMAGE_SPREAD.
# Equal units deal about 5 each: it takes two fights to kill one.
const COMBAT_DAMAGE := 10
const DAMAGE_SPREAD := 0.25
const HEAL_REST := 2 # HP a unit heals in a turn it didn't move or fight...
const HEAL_HOME := 4 # ...or this much in its own territory
const AI_REST_HP := 4 # an AI unit this hurt stays put to heal instead of attacking
# Army limits (standard 4X; Nathan's playtest: 17 units, Strength 100 by turn
# 20 made Sköll and diplomacy meaningless). Scouts don't count.
#  - Supply: at most SUPPLY_BASE + population armies (+2 with a Barracks)
#  - Rising Industry upkeep: the first FREE_ARMIES armies cost nothing; after
#    that each pair costs 1 more per army than the pair before (armies 3-4: 1
#    each, 5-6: 2 each, 7-8: 3 each...). Can't pay: the farthest army disbands.
const SUPPLY_BASE := 2
const FREE_ARMIES := 2
# Outposts (standard 4X): a small settlement that claims the hexes around it.
const OUTPOST_COST := 6 # Industry
const OUTPOST_RANGE := 5 # an outpost must be within this many hexes of your city...
const OUTPOST_MIN_DISTANCE := 3 # ...and at least this far from every city and other outpost
const OUTPOST_SIGHT := 2 # fog of war: an outpost sees this far
const MAX_OUTPOSTS := 3 # per faction
const AI_MAX_OUTPOSTS := 2 # the AI stops at this many
# Wars between AI factions (their wars with the player are in diplomacy.gd)
const AI_WAR_GAP := 4 # an AI may declare war on another AI whose army is this much weaker...
const AI_WAR_CHANCE := 0.05 # ...with this chance each turn
const AI_PEACE_AFTER := 4 # after this many turns of war, two AIs may make peace...
const AI_PEACE_CHANCE := 0.2 # ...with this chance each turn (twice as likely once Sköll howls)
# Taking cities in war: the city becomes the winner's tributary
const TRIBUTE_SHARE := 0.5 # a tributary pays this share of its Industry income to its overlord
const REBEL_CHANCE := 0.2 # each turn, a tributary AI whose army is stronger than its overlord's may rise up
const SIEGE_SUPPORT := 2 # each other army of the attacker's next to the city adds this to the attack
# City HP (standard 4X sieges): a city has CITY_MAX_HP and heals CITY_HEAL a
# turn. An attack damages it (the attack against the city's defence) and the
# attacker takes damage back. At 0 an army takes it (tributary; it restarts at
# half) and Sköll devours it.
const CITY_MAX_HP := 20
const CITY_HEAL := 3
const AI_MARCH_ARMIES := 2 # an AI at war sends spare armies at enemy cities once it has this many
const GROWTH_BASE := 10 # Food stored to grow from population 1 to 2...
const GROWTH_STEP := 5 # ...and each later growth costs this much more
# Population (city size): every point above 1 adds +1 Food, +1 Industry and
# +1 city defence a turn (bigger cities hold out better: the usual 4X rule).
const POP_DEFENCE := 1
const WALL_COST := 10 # Industry per wall level
const WALL_DEFENCE := 4 # city defence each wall level adds
const MAX_WALLS := 2
const CITY_SIGHT := 3 # fog of war: every faction sees this far around its city (units: see unit.gd)
const NO_CELL := HexMap.NO_CELL
const Crossing := preload("res://crossing_events.gd")
const TurnEvents := preload("res://turn_events.gd")
const Discoveries := preload("res://discoveries.gd")
const Buildings := preload("res://buildings.gd")

# The stages of a game, in order:
# CROSSING = journey events, LANDING = choosing where to found your city, PLAYING = the turns.
enum Phase { CROSSING, LANDING, PLAYING }

# The player has no city or units until they land (see try_land below).
var player := Faction.new("Norse", NO_CELL) # you
# The AI factions (placeholder names; one per pantheon). Each has its own word
# for a sworn agreement. Their cities start spread around the map.
var ais: Array[Faction] = [
	Faction.new("Japanese", Vector2i(12, 2), "pact"),
	Faction.new("Celtic", Vector2i(2, 8), "bond"),
	Faction.new("Greek", Vector2i(12, 8), "treaty"),
]
var factions: Array[Faction] = []
var daughter := SunDaughter.new()
var skoll: Skoll
var rifts: Rifts # the rifts in the void Sköll comes through (rifts.gd)
var relations: Array[Diplomacy] = [] # the player's relationship with each AI faction
var diplomacy_action_used := false # the player's one diplomatic action this turn (shared)
var diplomacy_log: Array[String] = [] # what the factions remember, newest last
const DIPLOMACY_LOG_SIZE := 5

var phase := Phase.CROSSING
var crossing_step := 0 # which Crossing event we're on
var turn := 1
var game_over := false
var end_title := "" # what the end screen says
var end_detail := "" # (can have several lines)
var messages: Array[String] = [] # what happened, newest last (the view shows these)
# Ruins hidden in the fog: [{"cell": Vector2i, "taken": bool}]. Placed at the Landing.
var ruins: Array[Dictionary] = []
# Choices waiting for the player's answer (ruins searched, small events), oldest
# first. Each is {"title", "text", "options": [{"label", "effects"}]}. The view
# shows the first as a pop-up; the turn can't end until all are answered.
var pending_choices: Array[Dictionary] = []
var next_event_turn := 0 # when the next small event happens
var event_deck: Array = [] # small events not yet seen this game, shuffled
var next_request_turn := SunDaughter.REQUEST_FROM # when Sunna next asks something of you (while you shelter her)
# Wars between AI factions: "Celtic|Greek" -> the turn it started. Every pair
# starts at peace. (The player's wars are in each Diplomacy, GameState.relations.)
var ai_war_since := {}
var ai_truce_until := {} # "Celtic|Greek" -> no new war between them before this turn
var terrain := {} # hex -> Terrain.Type, a new map every game (made in _init)
var ash := {} # hexes turned to ash by Sköll (hex -> true): dead land, see "Ash"

func _init() -> void:
	terrain = Terrain.generate(ais.map(func(f): return f.city_pos))
	skoll = Skoll.new(self)
	rifts = Rifts.new(self)
	player.is_player = true
	factions.append(player)
	for f in ais:
		factions.append(f)
		relations.append(Diplomacy.new(self, f))
		f.add_unit(f.city_pos) # each AI starts with one army unit in its city...
		f.add_unit(free_spot_near(f.city_pos), Unit.Kind.SCOUT) # ...and a scout next to it

# --- The Crossing -----------------------------------------------------------
func start_crossing() -> void:
	phase = Phase.CROSSING
	crossing_step = 0
	player.city_pos = NO_CELL
	player.units.clear()
	player.food = Crossing.START_FOOD
	player.industry = Crossing.START_INDUSTRY
	daughter.reset(player, ais)
	rifts.clear() # rolled on Rifts.RIFT_TURN, after every city exists
	messages.clear()

# Apply a choice's effects. Nothing can drop below 0 (Strength below 1).
func choose(effects: Dictionary) -> void:
	player.food = maxi(0, player.food + effects.get("food", 0))
	player.industry = maxi(0, player.industry + effects.get("industry", 0))
	player.strength = maxi(1, player.strength + effects.get("strength", 0))
	player.favour = clampi(player.favour + effects.get("favour", 0), 0, SunDaughter.MAX_FAVOUR)
	crossing_step += 1

func crossing_finished() -> bool:
	return crossing_step >= Crossing.EVENTS.size()

# --- The Landing ------------------------------------------------------------
# The player has no city or unit yet and must pick a hex to settle.
func start_landing() -> void:
	phase = Phase.LANDING
	daughter.choose_protector(factions)
	player.city_pos = NO_CELL
	player.units.clear()
	messages = ["Choose where to land: click a hex to found your city."]

func can_land_at(cell: Vector2i) -> bool:
	if not HexMap.in_bounds(cell) or not passable(cell):
		return false
	for f in ais:
		if HexMap.hex_distance(cell, f.city_pos) < MIN_LANDING_DISTANCE:
			return false
	return true

# Returns true if the player landed there.
func try_land(cell: Vector2i) -> bool:
	if phase != Phase.LANDING or not can_land_at(cell):
		return false
	player.city_pos = cell
	player.add_unit(cell) # your first army unit starts standing on the new city...
	player.add_unit(free_spot_near(cell), Unit.Kind.SCOUT) # ...and a scout next to it
	# Everyone unloads the ark: enough Industry to build one thing on turn 1.
	player.industry += LANDING_INDUSTRY
	for f in ais:
		f.industry = Crossing.START_INDUSTRY + LANDING_INDUSTRY
	phase = Phase.PLAYING
	ruins = Discoveries.place_ruins(self)
	event_deck = TurnEvents.EVENTS.duplicate()
	event_deck.shuffle()
	next_event_turn = 1 + randi_range(TurnEvents.MIN_GAP, TurnEvents.MAX_GAP)
	messages = ["Your people have landed. Send your scout (2 moves) into the dark, and choose what to build."]
	update_sight()
	var parts: Array[String] = ["you %d" % player.favour]
	for f in ais:
		parts.append("%s %d" % [f.name, f.favour])
	var scores := "(her Favour: %s)" % ", ".join(parts)
	if daughter.holder == player:
		add_message("%s chose you %s: +%d Food, +%d Industry a turn, +%d city defence." % [SunDaughter.NAME.capitalize(), scores, SunDaughter.FOOD, SunDaughter.INDUSTRY, SunDaughter.DEFENCE])
	else:
		add_message("%s chose to shelter with %s %s." % [SunDaughter.NAME.capitalize(), daughter.holder.name, scores])
	return true

# --- Turns ------------------------------------------------------------------
func can_play() -> bool:
	return not game_over and phase == Phase.PLAYING

func end_turn() -> void:
	if game_over or phase != Phase.PLAYING or is_waiting():
		return # (answer the offer or choice first)
	messages.clear()
	ai_rebellions()
	for r in relations:
		r.rival_consider_war() # before its units move, so a war (or betrayal) can strike at once
	ai_wars_turn()
	for f in ais:
		ai_take_turn(f)
	turn += 1
	if turn == Rifts.RIFT_TURN:
		rifts.place() # hidden until Sköll comes through one
	skoll.take_turn()
	if game_over: # Sköll may have destroyed the player's city or found the Daughter
		eject_trespassers()
		update_sight()
		return
	rifts.walkers_turn() # Rift Walkers come out in the season and wander (rifts.gd)
	daughter_flee()
	for f in factions:
		if f.city_pos == NO_CELL:
			continue # this faction's city has fallen; it's out of the game
		f.food += food_change(f)
		f.city_hp = mini(CITY_MAX_HP, f.city_hp + CITY_HEAL) # the city repairs itself
		var stored := f.industry
		f.industry += industry_change(f)
		pay_tribute(f)
		if f.industry < 0:
			disband_for_upkeep(f)
		work_queue(f, f.industry - stored) # this turn's Industry goes into the queue, if any
		var starved := f.food < 0
		if starved:
			starve(f)
		else:
			grow(f)
		if daughter.shelters_with(f):
			var verdict := daughter.judge_feeding(starved)
			if verdict != "":
				add_message(verdict)
		for u in f.units:
			u.moves = 0 if turn < u.busy_until else u.max_moves() # (standing watch: can't move)
			if not u.acted and u.hp < Unit.MAX_HP: # resting: heal (faster at home)
				u.hp = mini(Unit.MAX_HP, u.hp + (HEAL_HOME if territory_owner(u.pos) == f else HEAL_REST))
			u.acted = false
	judge_readiness()
	rival_claims()
	check_daughter_leaving()
	for f in ais:
		ai_build(f)
	for r in relations:
		r.new_turn()
	diplomacy_action_used = false
	if not game_over and turn < END_TURN:
		# at most one AI faction makes an offer each turn (the view shows a pop-up)
		var order := relations.duplicate()
		order.shuffle()
		# a faction desperate to be rid of the Daughter gets to speak first
		order.sort_custom(func(a, b): return ai_wants_rid_of_daughter(a.other) and not ai_wants_rid_of_daughter(b.other))
		for r in order:
			r.rival_make_offer()
			if r.has_pending():
				break
		maybe_turn_event()
		rifts.announce_season()
		maybe_sunna_request()
	maybe_rise()
	eject_trespassers()
	update_sight()
	if turn >= END_TURN and not game_over:
		final_ending()

func end_game(title: String, detail: String) -> void:
	game_over = true
	end_title = title
	end_detail = detail

# --- Endings -------------------------------------------------------------------
# Sköll devoured faction f (its last, and only, city fell to him). Your city:
# you lose. Once he has devoured DEVOURED_SHARE of all factions, Sköll wins.
var devoured: Array[String] = []

func devour(f: Faction) -> void:
	devoured.append(f.name)
	if f == player:
		end_game("Devoured", "Sköll tore down your city on turn %d.\nYour people are gone." % turn)
	elif devoured.size() >= ceili(DEVOURED_SHARE * factions.size()):
		end_game("Sköll wins", "He has devoured %s.\nThe wolf rules the long night." % " and ".join(devoured))

# Land: every hex of a faction's territory (its city and outposts and the
# hexes around them) that isn't ash.
func land_count(f: Faction) -> int:
	var n := 0
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if territory_owner(c) == f and not is_ash(c):
				n += 1
	return n

# Turn END_TURN: Dawn if Sunna has risen (for whoever she chose), otherwise
# Dominion for whoever holds the most land (a tie counts as yours).
func final_ending() -> void:
	if daughter.is_risen() and daughter.holder != null and daughter.holder.is_alive():
		if daughter.holder == player:
			end_game("Dawn", "Sunna has risen, and she stands with you.\nThe long night is over.")
		else:
			end_game("Dawn for the %s" % daughter.holder.name, "Sunna has risen, but she chose the %s.\nTheirs is the new world." % daughter.holder.name)
		return
	var best: Faction = player
	for f in ais:
		if f.is_alive() and land_count(f) > land_count(best):
			best = f
	var tally := ", ".join(factions.filter(func(f): return f.is_alive()).map(func(f): return "%s %d" % [f.name, land_count(f)]))
	if best == player:
		end_game("Dominion", "Turn %d: you hold the most land.\n(%s hexes)" % [turn, tally])
	else:
		end_game("The %s hold the most land" % best.name, "Turn %d: Dominion goes to the %s.\n(%s hexes)" % [turn, best.name, tally])

# A unit's attack on Sköll: its Strength +WOLF_SUPPORT for every other army of
# its own faction (or the player's allies) standing next to him: the "large
# combined force" it takes to bring him down.
func wolf_attack(u: Unit) -> int:
	var attack := u.fighting_strength() # (a wounded unit attacks weaker)
	for f in factions:
		var with_us: bool = f == u.faction or (u.faction == player and f != player and relation(f).pact_active())
		if not with_us:
			continue
		for other in f.units:
			if other != u and not other.is_scout() and HexMap.is_neighbour(other.pos, skoll.pos):
				attack += WOLF_SUPPORT
	return attack

func wolf_slain(f: Faction) -> void:
	if f == null:
		end_game("The wolf is dead", "Sköll fell on turn %d." % turn)
	elif f == player:
		end_game("Slay the wolf", "On turn %d your people brought down Sköll.\nThe wolf is dead." % turn)
	else:
		end_game("The %s slew the wolf" % f.name, "Sköll is dead, but the glory is theirs.")

# --- Ash ----------------------------------------------------------------------
# Each time Sköll comes through a rift, ASH_PER_CYCLE hexes turn to ash,
# spreading in from the map's edges, from ash already there, and around the
# rift he used. Ash is dead land: no outposts (one standing there is lost),
# no ruins, and it counts as nobody's land for Dominion. Units can still walk
# on it. A city and the hexes next to it never turn to ash. It stops once
# Sunna has risen.
func spread_ash(origin: Vector2i) -> void:
	if daughter.is_risen():
		return
	var options: Array[Vector2i] = []
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if is_ash(c) or not passable(c) or next_to_a_city(c):
				continue
			var edge := col == 0 or row == 0 or col == HexMap.COLS - 1 or row == HexMap.ROWS - 1
			var near := HexMap.hex_distance(c, origin) <= 1 or HexMap.neighbours(c).any(func(n): return is_ash(n))
			if edge or near:
				options.append(c)
	options.shuffle()
	var lost_outposts := 0
	for c in options.slice(0, ASH_PER_CYCLE):
		ash[c] = true
		var owner := outpost_owner(c)
		if owner != null:
			owner.outposts.erase(c)
			if owner == player:
				lost_outposts += 1
		for r in ruins:
			if r["cell"] == c:
				r["taken"] = true # buried
	if lost_outposts > 0:
		add_message("Ash swallowed %d of your outposts." % lost_outposts)

func next_to_a_city(c: Vector2i) -> bool:
	for f in factions:
		if f.is_alive() and HexMap.hex_distance(c, f.city_pos) <= 1:
			return true
	return false

func add_message(text: String) -> void:
	messages.append(text)

# --- The Sun's Daughter going rogue --------------------------------------------
# If her Favour toward her protector falls too low, she walks out of the city.
func check_daughter_leaving() -> void:
	var holder := daughter.holder
	if daughter.state != SunDaughter.State.SHELTERED or holder == null or not holder.is_alive():
		return
	if holder.favour > SunDaughter.LEAVE_FAVOUR:
		return
	var spot := NO_CELL
	var best := -1
	for c in HexMap.neighbours(holder.city_pos):
		if is_blocked(c) or is_city(c):
			continue
		var away := HexMap.hex_distance(c, skoll.pos) if skoll.active else 0
		if away > best:
			best = away
			spot = c
	if spot == NO_CELL:
		return # nowhere to step out; she stays for now
	daughter.go_rogue(spot)
	var whose := "your" if holder == player else holder.name + "'s"
	add_message("%s has lost faith and walked out of %s city! She is alone in the open." % [SunDaughter.NAME.capitalize(), whose])

# Every people believes she is its own lost sun: every CLAIM_GAP turns, while
# you shelter her, each AI's Trust toward you falls (at most CLAIM_TRUST_MAX).
func rival_claims() -> void:
	if turn % SunDaughter.CLAIM_GAP != 0 or not daughter.shelters_with(player):
		return
	var who: Array[String] = []
	for r in relations:
		if r.other.is_alive() and r.claim_trust_lost < SunDaughter.CLAIM_TRUST_MAX:
			r.change_trust(SunDaughter.CLAIM_TRUST)
			r.claim_trust_lost -= SunDaughter.CLAIM_TRUST
			who.append("the %s (%s)" % [r.other.name, SunDaughter.claim_name(r.other)])
	if not who.is_empty():
		add_message("Each people says %s is its own lost sun and resents that you hold her: Trust %+d with %s." % [SunDaughter.NAME, SunDaughter.CLAIM_TRUST, ", ".join(who)])

# In the open she moves one hex away from Sköll each turn.
func daughter_flee() -> void:
	if not daughter.is_rogue() or not skoll.active:
		return
	var best := NO_CELL
	var best_d := HexMap.hex_distance(daughter.pos, skoll.pos)
	for c in HexMap.neighbours(daughter.pos):
		if is_blocked(c) or is_city(c):
			continue
		var d := HexMap.hex_distance(c, skoll.pos)
		if d > best_d:
			best_d = d
			best = c
	if best != NO_CELL:
		daughter.pos = best

# A unit moving into her hex tries to persuade her: chance = its faction's Favour x 10%.
func try_persuade(u: Unit) -> void:
	var f := u.faction
	var chance := daughter.persuade_chance(f)
	var who := "You" if f == player else f.name
	if randf() < chance:
		daughter.join(f)
		var where := "your city" if f == player else "%s's city" % f.name
		add_message("%s persuaded %s (%s). She shelters in %s." % [who, SunDaughter.NAME, odds_text(chance), where])
	else:
		add_message("%s tried to persuade %s, but she refused (%s)." % [who, SunDaughter.NAME, odds_text(chance)])

# The Sun's Daughter warns at the howling and judges her protector when Sköll arrives.
func judge_readiness() -> void:
	var holder := daughter.holder
	if holder == null or not holder.is_alive():
		return
	if turn == Skoll.WARNING_TURN and holder == player:
		add_message("%s is afraid. When Sköll comes (turn %d) she wants city defence %d+ and army Strength %d+." % [SunDaughter.NAME.capitalize(), Skoll.ARRIVAL_TURN, SunDaughter.READY_DEFENCE, SunDaughter.READY_ARMY])
	if turn == Skoll.ARRIVAL_TURN:
		add_message(daughter.judge_readiness(city_defence(holder), army_power(holder)))

# --- Food -------------------------------------------------------------------
# Food made by the city (and the Daughter's bonus) minus what the army eats.
func food_change(f: Faction) -> int:
	return sum_parts(food_parts(f))

func industry_change(f: Faction) -> int:
	return sum_parts(industry_parts(f))

# Where a faction's Food comes from and goes, as [what, amount] pairs. The
# totals above are made from these, so the view's breakdown can't disagree.
func food_parts(f: Faction) -> Array:
	var parts := [["city", CITY_FOOD]]
	if f.population > 1:
		parts.append(["population %d" % f.population, f.population - 1]) # each extra population works more fields
	var outposts := 0
	for o in f.outposts:
		outposts += Terrain.OUTPOST_FOOD[terrain_at(o)] # an outpost's income depends on its land
	if outposts != 0:
		parts.append(["outposts", outposts])
	if f.buildings.has("granary"):
		parts.append(["Granary", Buildings.GRANARY_FOOD])
	if daughter.shelters_with(f):
		parts.append([SunDaughter.NAME, SunDaughter.FOOD])
	elif daughter.risen_with(f):
		parts.append(["%s risen" % SunDaughter.NAME, SunDaughter.RISEN_FOOD])
	var eaten := 0
	for u in f.units:
		eaten += u.upkeep(UNIT_FOOD_UPKEEP)
	if eaten != 0:
		parts.append(["armies eat", -eaten])
	var walkers := rifts.walkers_on_land(f)
	if walkers > 0:
		parts.append(["Rift Walkers on your land" if f == player else "Rift Walkers on its land", -walkers * Rifts.WALKER_FOOD])
	return parts

# --- Army limits ---------------------------------------------------------------
func army_count(f: Faction) -> int:
	return f.units.filter(func(u): return not u.is_scout()).size()

func supply_cap(f: Faction) -> int:
	return SUPPLY_BASE + f.population + (Buildings.BARRACKS_SUPPLY if f.buildings.has("barracks") else 0)

# Industry a turn to keep n armies (see FREE_ARMIES).
func army_upkeep_for(n: int) -> int:
	var total := 0
	for k in range(FREE_ARMIES, n):
		@warning_ignore("integer_division") # pairs: armies 3-4 cost 1, 5-6 cost 2...
		total += (k - FREE_ARMIES) / 2 + 1
	return total

func army_upkeep(f: Faction) -> int:
	return army_upkeep_for(army_count(f))

# What one more army would add to the Industry upkeep.
func next_army_upkeep(f: Faction) -> int:
	return army_upkeep_for(army_count(f) + 1) - army_upkeep(f)

# Industry ran out paying upkeep: the army farthest from the city disbands.
func disband_for_upkeep(f: Faction) -> void:
	f.industry = 0
	var farthest: Unit = null
	for u in f.units:
		if not u.is_scout() and (farthest == null or HexMap.hex_distance(u.pos, f.city_pos) > HexMap.hex_distance(farthest.pos, f.city_pos)):
			farthest = u
	if farthest == null:
		return
	f.remove_unit(farthest)
	if f == player:
		add_message("You couldn't pay your armies' upkeep: a unit disbanded. (Armies cost more Industry the more you have.)")

func industry_parts(f: Faction) -> Array:
	var parts := [["city", CITY_INDUSTRY]]
	if f.population > 1:
		parts.append(["population %d" % f.population, f.population - 1])
	var outposts := 0
	for o in f.outposts:
		outposts += Terrain.OUTPOST_INDUSTRY[terrain_at(o)]
	if outposts != 0:
		parts.append(["outposts", outposts])
	if f.buildings.has("workshop"):
		parts.append(["Workshop", Buildings.WORKSHOP_INDUSTRY])
	if daughter.shelters_with(f):
		parts.append([SunDaughter.NAME, SunDaughter.INDUSTRY])
	elif daughter.risen_with(f):
		parts.append(["%s risen" % SunDaughter.NAME, SunDaughter.RISEN_INDUSTRY])
	if army_upkeep(f) > 0:
		parts.append(["army upkeep", -army_upkeep(f)])
	return parts

func sum_parts(parts: Array) -> int:
	var total := 0
	for p in parts:
		total += p[1]
	return total

# City growth (the usual 4X rule): when stored Food reaches the growth cost and
# the city isn't losing Food, the city grows by 1 and the cost is used up.
func growth_cost(f: Faction) -> int:
	return GROWTH_BASE + (f.population - 1) * GROWTH_STEP

func grow(f: Faction) -> void:
	if f.food < growth_cost(f) or food_change(f) < 0:
		return
	f.food -= growth_cost(f)
	f.population += 1
	if f == player:
		add_message("Your city grew to population %d: +1 Food, +1 Industry and +%d city defence." % [f.population, POP_DEFENCE])

# Not enough Food: stores stay at 0 and one army unit deserts (the one farthest
# from the city, so the garrison stays; scouts eat nothing so they stay).
func starve(f: Faction) -> void:
	f.food = 0
	var farthest: Unit = null
	for u in f.units:
		if u.is_scout():
			continue
		if farthest == null or HexMap.hex_distance(u.pos, f.city_pos) > HexMap.hex_distance(farthest.pos, f.city_pos):
			farthest = u
	if farthest == null:
		return
	f.remove_unit(farthest)
	if f == player:
		add_message("Your people are starving: a unit deserted. (Each unit eats %d Food a turn.)" % UNIT_FOOD_UPKEEP)
	else:
		add_message("%s is starving: one of its units deserted." % f.name)

# --- The AI factions ----------------------------------------------------------
# Placeholder AI, for each of a faction's units: attack an enemy unit next door
# (never the player's while an agreement with the player is in force); otherwise
# stay home if it's guarding the city and there are other units; otherwise
# chase the Daughter if she's in the open, fall back home if Sköll is loose, or
# step to a random free neighbouring hex.
func ai_take_turn(f: Faction) -> void:
	for u in f.units.duplicate(): # copy: units can die during the loop
		if not u in f.units:
			continue
		if u.is_scout():
			ai_scout(u)
			continue
		if u.hp <= AI_REST_HP and not (skoll.active and HexMap.hex_distance(u.pos, f.city_pos) > 1):
			continue # badly hurt: stays put to heal
		var target: Unit = null
		for c in HexMap.neighbours(u.pos):
			var other := unit_at(c)
			if other == null or not at_war(f, other.faction):
				continue # only enemies it is at war with
			if c == other.faction.city_pos and not ai_dares_siege(u, other.faction):
				continue # a garrison behind walls: too strong to attack
			target = other
			break
		if target:
			attack_hex(u, target.pos)
			continue
		var walker := ai_walker_target(u)
		if walker != null:
			attack_walker(u, walker)
			continue
		if u.pos == f.city_pos and f.units.size() > 1:
			continue # this one guards the city
		if daughter.is_rogue():
			if HexMap.is_neighbour(u.pos, daughter.pos):
				try_persuade(u)
				continue
			var toward := step_toward(u.pos, daughter.pos, f)
			if toward != NO_CELL:
				enter_hex(u, toward)
				continue
		if skoll.active and HexMap.hex_distance(u.pos, f.city_pos) > 1:
			# Sköll is loose: fall back toward the city to help defend it
			var home := step_toward(u.pos, f.city_pos, f)
			if home != NO_CELL:
				enter_hex(u, home)
				continue
		# At war: spare armies march on the nearest enemy city and attack it
		# when the odds are good enough (the city becomes their tributary).
		var siege := ai_siege_target(f)
		if siege != null and u.pos != f.city_pos:
			if HexMap.is_neighbour(u.pos, siege.city_pos):
				if ai_dares_siege(u, siege):
					attack_hex(u, siege.city_pos)
				continue # (otherwise it waits outside for help)
			var march := step_toward(u.pos, siege.city_pos, f)
			if march != NO_CELL:
				enter_hex(u, march)
				continue
		# An enemy outpost next door with nobody guarding it: take it.
		var grab := NO_CELL
		for c in HexMap.neighbours(u.pos):
			var owner := outpost_owner(c)
			if owner != null and at_war(f, owner) and not is_blocked(c) and not zoc_blocks(f, u.pos, c):
				grab = c
				break
		if grab != NO_CELL:
			enter_hex(u, grab)
			continue
		var options: Array[Vector2i] = []
		for c in HexMap.neighbours(u.pos):
			var o := outpost_owner(c)
			if not is_blocked(c) and not (is_city(c) and c != f.city_pos) and (o == null or o == f) and may_enter(f, c) and not zoc_blocks(f, u.pos, c):
				options.append(c)
		if not options.is_empty():
			enter_hex(u, options.pick_random())

# An AI scout: heads for the nearest ruins it has seen, otherwise for the
# nearest hex it hasn't explored yet; it never attacks.
func ai_scout(u: Unit) -> void:
	var f := u.faction
	while u.moves > 0:
		var goal := NO_CELL
		var best_d := 999
		for r in ruins:
			if not r["taken"] and f.explored.has(r["cell"]) and not is_blocked(r["cell"]) and may_enter(f, r["cell"]):
				var d := HexMap.hex_distance(u.pos, r["cell"])
				if d < best_d:
					best_d = d
					goal = r["cell"]
		if goal == NO_CELL:
			goal = nearest_unexplored(f, u.pos)
		var step := step_toward(u.pos, goal, f) if goal != NO_CELL else NO_CELL
		if step == NO_CELL:
			var options: Array[Vector2i] = []
			for c in HexMap.neighbours(u.pos):
				if not is_blocked(c) and not is_city(c) and may_enter(f, c) and not zoc_blocks(f, u.pos, c):
					options.append(c)
			if options.is_empty():
				return
			step = options.pick_random()
		if not can_afford_move(u, step):
			return # forest or hills ahead and only 1 move left: wait for next turn
		enter_hex(u, step)
		spend_move(u, step)
		update_sight_for(f)

# The closest hex this faction has never seen (NO_CELL if it has seen everything).
func nearest_unexplored(f: Faction, from: Vector2i) -> Vector2i:
	var best := NO_CELL
	var best_d := 999
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if f.explored.has(c) or not may_enter(f, c):
				continue
			var d := HexMap.hex_distance(from, c)
			if d < best_d:
				best_d = d
				best = c
	return best

# The first step on the shortest way from "from" to "goal" around mountains,
# water, units and cities (the goal itself may be occupied: you step next to
# it). With a faction, also around territory it may not enter (closed
# borders). NO_CELL if there's no way, or no step that gets any closer.
func step_toward(from: Vector2i, goal: Vector2i, f: Faction = null) -> Vector2i:
	if from == goal:
		return NO_CELL
	var came_from := {from: NO_CELL}
	var queue: Array[Vector2i] = [from]
	var reached := false
	while not queue.is_empty() and not reached:
		var c: Vector2i = queue.pop_front()
		for n in HexMap.neighbours(c):
			if came_from.has(n):
				continue
			if n == goal:
				came_from[n] = c
				reached = true
				break
			if is_blocked(n) or is_city(n) or (f != null and not may_enter(f, n)):
				continue
			if c == from and zoc_blocks(f, from, n):
				continue # zone of control: can't slip past an enemy army this turn
			came_from[n] = c
			queue.append(n)
	if not reached:
		return NO_CELL
	var step := goal
	while came_from[step] != from:
		step = came_from[step]
	if step == goal and (is_blocked(goal) or (f != null and not may_enter(f, goal)) or zoc_blocks(f, from, goal)):
		return NO_CELL # already next to it (or held there by an enemy's zone of control)
	return step

# Once the howling starts it builds walls first; otherwise a unit,
# but only if it can still feed its army afterwards.
func ai_build(f: Faction) -> void:
	if not f.is_alive():
		return
	if turn >= Skoll.WARNING_TURN and f.walls < MAX_WALLS:
		build_walls(f)
		return # saving up for walls
	if turn < Skoll.WARNING_TURN and f.outposts.size() < AI_MAX_OUTPOSTS and f.industry >= OUTPOST_COST:
		var spots := outpost_spots(f)
		if not spots.is_empty():
			build_outpost(f, spots.pick_random())
			return
	if f.scout_count() == 0 and turn < Skoll.WARNING_TURN and f.industry >= SCOUT_COST:
		build_scout(f)
		return
	if f.industry >= UNIT_COST and food_change(f) - UNIT_FOOD_UPKEEP >= 0 and industry_change(f) - next_army_upkeep(f) >= 1:
		if build_unit(f):
			return
	# It can't feed more armies: spare Industry goes into a city building.
	for key in Buildings.LIST:
		if not f.buildings.has(key) and f.industry >= Buildings.cost(key):
			build_building(f, key)
			return

# --- Trading the Sun's Daughter ---------------------------------------------------
# What she's worth to faction f, as a price in Industry (-10 to 10): positive,
# they'd pay the giver that much; negative, the giver must pay them to take her.
func daughter_value(f: Faction) -> int:
	var value := SunDaughter.TRADE_BASE_VALUE + (f.favour - 5)
	if skoll.active:
		value -= SunDaughter.FEAR_LOOSE
		if skoll.target == f:
			value -= SunDaughter.FEAR_HUNTED
	elif turn >= Skoll.WARNING_TURN:
		value -= SunDaughter.FEAR_HOWLING
	var giver: Faction = daughter.holder if daughter.holder != null else player
	var stronger := army_power(f) - army_power(giver)
	if stronger > 0:
		@warning_ignore("integer_division") # rounds down on purpose: -1 per full DISDAIN_PER
		value -= stronger / SunDaughter.DISDAIN_PER # a powerful faction needs her less
	return clampi(value, -SunDaughter.TRADE_MAX_PRICE, SunDaughter.TRADE_MAX_PRICE)

# An AI sheltering her wants her gone (from TRADE_TURN) if she's worth less than
# nothing to it, or if Sköll is hunting its city.
func ai_wants_rid_of_daughter(f: Faction) -> bool:
	if not daughter.shelters_with(f) or turn < SunDaughter.TRADE_TURN:
		return false
	return daughter_value(f) < 0 or (skoll.active and skoll.target == f)

func can_trade_daughter() -> bool:
	return can_act() and daughter.shelters_with(player) and turn >= SunDaughter.TRADE_TURN and not diplomacy_action_used

# What would happen if the player offered her to f.
func trade_quote(f: Faction) -> Dictionary:
	var value := daughter_value(f)
	var quote := {"value": value, "refuses": value < SunDaughter.TRADE_REFUSE_BELOW or not f.is_alive(), "they_pay": 0, "you_pay": 0}
	if value >= 0:
		quote["they_pay"] = mini(value, f.industry) # they can only pay what they have
	else:
		quote["you_pay"] = -value
	quote["possible"] = not quote["refuses"] and player.industry >= quote["you_pay"]
	return quote

# The player offers her to f (uses the turn's diplomatic action). Returns true if done.
func player_trade_daughter(f: Faction) -> bool:
	if not can_trade_daughter():
		return false
	var q := trade_quote(f)
	if not q["possible"]:
		return false
	diplomacy_action_used = true
	messages.clear()
	f.industry += q["you_pay"] - q["they_pay"]
	player.industry += q["they_pay"] - q["you_pay"]
	hand_over_daughter(player, f)
	var deal := "you paid them %d Industry" % q["you_pay"]
	if q["you_pay"] == 0:
		deal = "they paid you %d Industry" % q["they_pay"] if q["they_pay"] > 0 else "for nothing"
	remember("Turn %d: you handed %s to the %s (%s), who call her %s. Her Favour toward you %+d. Their Trust %+d, and they accept your next %s or deal." % [turn, SunDaughter.NAME, f.name, deal, SunDaughter.claim_name(f), SunDaughter.TRADED_FAVOUR, SunDaughter.GIVEN_TRUST, f.pact_word])
	return true

# She moves from giver's city to receiver's. Being traded costs Favour toward the giver.
# You giving her to an AI (a trade, or its claim): its Trust +GIVEN_TRUST and it
# accepts your next oath or deal (contested Sunna, step 4).
func hand_over_daughter(giver: Faction, receiver: Faction) -> void:
	daughter.join(receiver)
	giver.favour = clampi(giver.favour + SunDaughter.TRADED_FAVOUR, 0, SunDaughter.MAX_FAVOUR)
	if giver == player and receiver != player:
		var r := relation(receiver)
		r.change_trust(SunDaughter.GIVEN_TRUST)
		r.owes_you = true

# --- Diplomacy helpers -----------------------------------------------------------
# The player's relationship with this AI faction.
func relation(f: Faction) -> Diplomacy:
	for r in relations:
		if r.other == f:
			return r
	return null

# The relationship whose offer is waiting for the player's answer (or null).
func pending_relation() -> Diplomacy:
	for r in relations:
		if r.has_pending():
			return r
	return null

func has_pending_offer() -> bool:
	return pending_relation() != null

# Army strength: the total Strength of a faction's units.
func army_power(f: Faction) -> int:
	var power := 0
	for u in f.units:
		power += u.strength
	return power

func remember(event: String) -> void:
	diplomacy_log.append(event)
	if diplomacy_log.size() > DIPLOMACY_LOG_SIZE:
		diplomacy_log.pop_front()
	add_message(event)

# --- Player actions (the view calls these) -----------------------------------
func player_propose_pact(f: Faction) -> void:
	if not can_act():
		return
	messages.clear()
	if relation(f).at_war:
		relation(f).propose_peace() # posts its own message
	else:
		relation(f).propose_pact()

func player_demand(f: Faction, resource: String) -> void:
	if not can_act():
		return
	messages.clear()
	relation(f).demand(resource) # posts its own message

# Deals (each uses the turn's diplomatic action; see diplomacy.gd).
func player_trade(f: Faction, give: String) -> void:
	if can_act():
		messages.clear()
		relation(f).trade(give)

func player_gift(f: Faction, res: String) -> void:
	if can_act():
		messages.clear()
		relation(f).gift(res)

func player_ask_borders(f: Faction) -> void:
	if can_act():
		messages.clear()
		relation(f).ask_open_borders()

func player_tribute_for_peace(f: Faction) -> void:
	if can_act():
		messages.clear()
		relation(f).offer_tribute_for_peace()

func player_build_walls() -> void:
	if not can_act():
		return
	if build_walls(player):
		messages = ["You built walls (level %d): your city's defence +%d." % [player.walls, WALL_DEFENCE]]
	else:
		messages = ["Can't build walls: you need %d Industry (and walls go up to level %d)." % [WALL_COST, MAX_WALLS]]

func player_build_unit() -> void:
	if not can_act():
		return
	if build_unit(player):
		messages = ["You built a new army unit (%d Industry). It can move next turn. Armies: %d/%d, upkeep now %d Industry a turn." % [UNIT_COST, army_count(player), supply_cap(player), army_upkeep(player)]]
		if food_change(player) < 0:
			add_message("Warning: your army now eats more Food than you make (%+d a turn). If your stores run out, a unit will desert." % food_change(player))
		player.units[-1].moves = 0 # a freshly built unit waits a turn, as is usual
	else:
		if army_count(player) >= supply_cap(player):
			messages = ["Can't build: your supply is full (%d armies: %d + population, +%d with a Barracks)." % [supply_cap(player), SUPPLY_BASE, Buildings.BARRACKS_SUPPLY]]
		else:
			messages = ["Can't build: you need %d Industry and a free hex at your city." % UNIT_COST]

func player_build_scout() -> void:
	if not can_act():
		return
	if build_scout(player):
		messages = ["You built a scout (%d Industry): 2 moves, sees 3 hexes, eats nothing, but weak (Strength %d). It can move next turn." % [SCOUT_COST, Unit.SCOUT_STRENGTH]]
		player.units[-1].moves = 0
	else:
		messages = ["Can't build a scout: you need %d Industry, a free hex at your city, and at most %d scouts." % [SCOUT_COST, MAX_SCOUTS]]

# Found an outpost on a hex chosen by the player (see outpost_spots for where).
func player_build_outpost(cell: Vector2i) -> bool:
	if not can_act():
		return false
	if not build_outpost(player, cell):
		messages = ["Can't found an outpost there."]
		return false
	var t := terrain_at(cell)
	messages = ["You founded an outpost on %s (%d Industry): +%d Food and +%d Industry a turn. It claims the hexes around it; in a war, guard it or lose it." % [Terrain.NAMES[t].to_lower(), OUTPOST_COST, Terrain.OUTPOST_FOOD[t], Terrain.OUTPOST_INDUSTRY[t]]]
	update_sight()
	return true

# The faction the player would DECLARE WAR on by acting on this hex: attacking
# its unit, or walking into its outpost, while at peace with it (null if none).
# The view asks for a second click before it does.
func war_target(cell: Vector2i) -> Faction:
	if rifts.walker_at(cell) != null:
		return null # a Rift Walker belongs to nobody: attacking it is never an act of war
	var other := unit_at(cell)
	if other != null:
		return other.faction if other.faction != player and not at_war(player, other.faction) else null
	var owner_city := city_owner(cell)
	if owner_city != null and owner_city != player and not at_war(player, owner_city):
		return owner_city
	var land_owner := territory_owner(cell)
	if land_owner != null and not may_enter(player, cell):
		return land_owner # closed borders: crossing them is an act of war
	var owner := outpost_owner(cell)
	if owner != null and owner != player and not at_war(player, owner):
		return owner
	return null

# One of the player's units acts on a neighbouring hex: attack Sköll, persuade
# the Daughter, attack an enemy unit (breaking an oath if one is in force), or
# move there (searching ruins, or taking an enemy outpost). Uses one move.
# Returns false if it can't act there.
func player_unit_act(u: Unit, cell: Vector2i) -> bool:
	if not can_act() or u.faction != player or u.moves <= 0 or not HexMap.is_neighbour(u.pos, cell):
		return false
	if not passable(cell) and not skoll.is_at(cell):
		return false # mountains and water
	if not can_afford_move(u, cell):
		return false # not enough moves left for forest or hills
	var other := unit_at(cell)
	if other and other.faction == player:
		return false # can't move onto your own unit
	var walker := rifts.walker_at(cell)
	var attacking := skoll.is_at(cell) or other != null or walker != null or (is_city(cell) and cell != player.city_pos)
	if not attacking and not (daughter.is_rogue() and cell == daughter.pos) and zoc_blocks(player, u.pos, cell):
		var holder := zoc_holder(player, u.pos)
		messages = ["Zone of control: your unit is next to a %s army and can't slip past it." % holder.faction.name, "Attack it, step away from it, or stay."]
		return false
	messages.clear()
	u.acted = true # (moving or fighting: no healing this turn)
	if skoll.is_at(cell):
		skoll.attacked_by(u)
	elif walker != null:
		attack_walker(u, walker)
	elif daughter.is_rogue() and cell == daughter.pos:
		try_persuade(u)
	else:
		var enemy := war_target(cell)
		if enemy != null:
			relation(enemy).player_declare_war() # (breaks your oath if you were allies)
		if other or (is_city(cell) and cell != player.city_pos):
			attack_hex(u, cell) # moving into an enemy (or its city) = attack
		else:
			enter_hex(u, cell)
			spend_move(u, cell)
			update_sight()
			return true
	u.moves = 0 # attacking (or talking to her) ends the unit's turn, as is usual
	update_sight()
	return true

# A unit steps onto a hex: it searches ruins there and takes an enemy
# outpost with nobody standing on it. Every move on the map goes through here.
func enter_hex(u: Unit, cell: Vector2i) -> void:
	u.pos = cell
	u.acted = true
	var f := u.faction
	if in_enemy_zoc(f, cell):
		u.moves = 0 # zone of control: stepping next to an enemy army ends its move
	var owner := outpost_owner(cell)
	if owner != null and owner != f and at_war(f, owner): # (at peace you just pass through)
		owner.outposts.erase(cell)
		f.outposts.append(cell)
		if f == player:
			add_message("You took the %s outpost! Its income is yours now." % owner.name)
		elif owner == player:
			add_message("The %s took your outpost!" % f.name)
		elif player_can_see(cell):
			add_message("The %s took the %s outpost." % [f.name, owner.name])
	for r in ruins:
		if r["cell"] == cell and not r["taken"]:
			r["taken"] = true
			if f == player:
				pending_choices.append(Discoveries.ruin_choice(self))
			else:
				Discoveries.ai_take_ruin(self, f)
				if player_can_see(cell):
					add_message("The %s searched the ruins you spotted and carried something off." % f.name)

# --- War and peace ------------------------------------------------------------
# Every pair of factions starts at peace. At peace their units can't attack
# each other or take each other's outposts. Sköll is everyone's enemy anyway.
func at_war(a: Faction, b: Faction) -> bool:
	if a == null or b == null or a == b:
		return false
	if a == player:
		return relation(b).at_war
	if b == player:
		return relation(a).at_war
	return ai_war_since.has(pair_key(a, b))

func pair_key(a: Faction, b: Faction) -> String:
	return a.name + "|" + b.name if a.name < b.name else b.name + "|" + a.name

# Wars between the AI factions: a much stronger AI may declare war on a weaker
# one; after a few turns of war they may make peace (more often once Sköll howls).
func ai_wars_turn() -> void:
	for a in ais:
		for b in ais:
			if a == b or not a.is_alive() or not b.is_alive():
				continue
			var key := pair_key(a, b)
			if ai_war_since.has(key):
				if a.name < b.name and turn - ai_war_since[key] >= AI_PEACE_AFTER:
					var chance := AI_PEACE_CHANCE * (2.0 if turn >= Skoll.WARNING_TURN else 1.0)
					if randf() < chance:
						ai_war_since.erase(key)
						ai_truce_until[key] = turn + Diplomacy.TRUCE_TURNS
						add_message("The %s and the %s made peace." % [a.name, b.name])
			elif turn >= ai_truce_until.get(key, 0) and not tribute_bound(a, b) and randf() < AI_WAR_CHANCE:
				var gap := army_power(a) - army_power(b)
				# a much weaker neighbour, or one holding the sun a believes is its own
				if gap >= AI_WAR_GAP:
					ai_declare_war(a, b)
				elif daughter.shelters_with(b) and gap >= 0:
					ai_declare_war(a, b, "they want %s, their lost sun" % SunDaughter.claim_name(a))

func ai_declare_war(a: Faction, b: Faction, why := "") -> void:
	if tribute_bound(a, b):
		return
	ai_war_since[pair_key(a, b)] = turn
	add_message("The %s declared war on the %s%s." % [a.name, b.name, " (%s)" % why if why != "" else ""])
	# Your ally was attacked: your oath says you join the war. You decide (pop-up).
	var r := relation(b)
	if r.pact_active() and not at_war(player, a):
		pending_choices.append({
			"title": "YOUR ALLY IS ATTACKED",
			"text": "The %s have declared war on the %s, your allies. Your %s says you join the war against the %s." % [a.name, b.name, b.pact_word, a.name],
			"options": [
				{"label": "Honour it: war on the %s (%s Trust %+d, %s %+d)" % [a.name, b.name, Diplomacy.TRUST_JOINED_ALLY, a.name, Diplomacy.TRUST_DEFENDED_WAR], "effects": {"join_war": a.name, "ally": b.name}},
				{"label": "Stay out: break your %s (%s Trust %+d, her Favour %+d)" % [b.pact_word, b.name, Diplomacy.TRUST_BROKEN, Diplomacy.BROKEN_OATH_FAVOUR], "effects": {"abandon_ally": b.name}},
			],
		})

# An AI declared war on the player: every other AI allied with the player
# keeps its oath and declares war on the aggressor, unless the aggressor is far
# stronger, in which case it breaks its word.
func player_attacked(aggressor: Faction) -> void:
	for r in relations:
		var ally := r.other
		if ally == aggressor or not ally.is_alive() or not r.pact_active() or at_war(ally, aggressor):
			continue
		if tribute_bound(ally, aggressor):
			continue # it can't go to war with its own overlord (or tributary)
		if army_power(ally) - army_power(aggressor) <= Diplomacy.ALLY_ABANDON_GAP:
			r.pact_turns_left = 0
			r.rival_broken_oaths += 1
			ally.favour = clampi(ally.favour + Diplomacy.RIVAL_BROKEN_OATH_FAVOUR, 0, SunDaughter.MAX_FAVOUR)
			remember("Turn %d: the %s BROKE THEIR %s: too afraid of the %s to join your war." % [turn, ally.name, r.pact_word().to_upper(), aggressor.name])
		else:
			ai_war_since[pair_key(ally, aggressor)] = turn
			remember("Turn %d: the %s honour their %s and declare war on the %s!" % [turn, ally.name, r.pact_word(), aggressor.name])

# --- Borders ----------------------------------------------------------------
# Closed borders (standard 4X): at peace, a faction's units may not enter
# another faction's territory (its city and outposts and the hexes around
# them) unless they're at war, allied (an oath), have an open-borders
# agreement (diplomacy.gd), or one is the other's overlord. AIs keep their
# borders closed to each other unless at war.
func may_enter(f: Faction, cell: Vector2i) -> bool:
	var owner := territory_owner(cell)
	if owner == null or owner == f or at_war(f, owner) or tribute_bound(f, owner):
		return true
	if f == player:
		return relation(owner).borders_open()
	if owner == player:
		return relation(f).borders_open()
	return false

# Is this hex behind a border the player may not cross right now?
func closed_border(cell: Vector2i) -> bool:
	return not may_enter(player, cell)

# --- Zone of control (standard 4X) ---------------------------------------------
# Every army holds the 6 hexes around it against the factions at war with it
# (scouts are too weak to hold anything; Sköll and the Daughter ignore it).
# Two rules, as in classic 4X games:
#   1. a unit that steps into an enemy's zone stops there (its moves end), and
#   2. a unit already in an enemy's zone can't step to another hex in an enemy
#      zone: it can attack, step back out, or stay. So an army can't slip past
#      an enemy army to an outpost or city behind it.
# Stepping into your own city is always allowed. Attacking isn't a move, so
# it isn't limited. (Armies have 1 move, so rule 1 only slows scouts; rule 2
# is what stops armies walking past each other.)

var zoc_on := true # always on in the game; tests switch it off to measure what it changes

# The enemy army (at war with f) whose zone covers this hex, or null.
func zoc_holder(f: Faction, cell: Vector2i) -> Unit:
	if not zoc_on:
		return null
	for n in HexMap.neighbours(cell):
		var other := unit_at(n)
		if other != null and not other.is_scout() and at_war(f, other.faction):
			return other
	return null

func in_enemy_zoc(f: Faction, cell: Vector2i) -> bool:
	return zoc_holder(f, cell) != null

# Would rule 2 stop faction f stepping from "from" to the neighbouring hex "to"?
func zoc_blocks(f: Faction, from: Vector2i, to: Vector2i) -> bool:
	if f == null or to == f.city_pos:
		return false
	return in_enemy_zoc(f, from) and in_enemy_zoc(f, to)

# Units standing where they may no longer be (peace was made, an agreement
# ran out, a city became a tributary) walk out to the nearest hex they may use.
func eject_trespassers() -> void:
	for f in factions:
		for u in f.units:
			if may_enter(f, u.pos):
				continue
			var land_owner := territory_owner(u.pos)
			var spot := nearest_allowed(f, u.pos)
			if spot != NO_CELL:
				u.pos = spot
				if f == player:
					add_message("Your unit left the %s lands: their borders are closed to you." % land_owner.name)

func nearest_allowed(f: Faction, from: Vector2i) -> Vector2i:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for n in HexMap.neighbours(c):
			if seen.has(n) or not passable(n):
				continue
			seen[n] = true
			if may_enter(f, n) and not is_blocked(n) and not is_city(n):
				return n
			queue.append(n)
	return NO_CELL

# --- Taking cities: tributaries ----------------------------------------------
# A unit attacks a hex next to it: a city (its garrison, walls, land and the
# Daughter all defend it) or a unit in the open.
func attack_hex(u: Unit, cell: Vector2i) -> void:
	var owner := city_owner(cell)
	if owner != null and owner != u.faction:
		attack_city(u, owner)
	else:
		resolve_combat(u, unit_at(cell))

# The attacker against the whole city defence. Winning: the garrison dies,
# the walls lose a level, and the city becomes the attacker's tributary (the
# attacker stays outside). Losing: the attacking unit is destroyed.
func attack_city(u: Unit, f: Faction) -> void:
	var conqueror := u.faction
	var attack := siege_strength(u, f)
	var defence := city_defence(f)
	var dealt := combat_damage(attack, defence)
	var taken := combat_damage(defence, attack)
	var whose := "your city" if f == player else "the %s city" % f.name
	var who := "You" if conqueror == player else "The " + conqueror.name
	u.acted = true
	f.city_hp -= dealt
	u.hp -= taken
	add_message("%s attacked %s (attack %d against defence %d): the city lost %d HP (%d left), the attacker %d." % [who, whose, attack, defence, dealt, maxi(0, f.city_hp), taken])
	if u.hp <= 0:
		conqueror.remove_unit(u)
		add_message("The attacking unit died.")
	if f.city_hp > 0:
		return
	var garrison := unit_at(f.city_pos)
	if garrison and garrison.faction == f:
		f.remove_unit(garrison)
	f.walls = maxi(0, f.walls - 1)
	@warning_ignore("integer_division")
	f.city_hp = CITY_MAX_HP / 2 # it restarts at half
	make_tributary(f, conqueror)
	remember("Turn %d: %s took %s. It pays them tribute now." % [turn, who, whose])

# An AI unit attacks a city only if it expects to survive the hit.
func ai_dares_siege(u: Unit, f: Faction) -> bool:
	return roundi(COMBAT_DAMAGE * float(city_defence(f)) / (siege_strength(u, f) + city_defence(f))) < u.hp

# What attacking city f with unit u would do (for the view): damage to the city, to the unit.
func expected_siege(u: Unit, f: Faction) -> Vector2i:
	var a := siege_strength(u, f)
	var d := city_defence(f)
	return Vector2i(roundi(COMBAT_DAMAGE * float(a) / (a + d)), roundi(COMBAT_DAMAGE * float(d) / (a + d)))

# f becomes conqueror's tributary: their war ends and f pays tribute. If the
# conqueror was f's own tributary, it is free again.
func make_tributary(f: Faction, conqueror: Faction) -> void:
	if conqueror.overlord == f.name:
		conqueror.overlord = ""
	f.overlord = conqueror.name
	if daughter.shelters_with(f):
		daughter.join(conqueror) # she goes with the city's new overlord
		add_message("%s carried %s off from %s. They call her %s." % ["You" if conqueror == player else "The " + conqueror.name, SunDaughter.NAME, "your city" if f == player else "the %s city" % f.name, SunDaughter.claim_name(conqueror)])
	if f == player or conqueror == player:
		var r := relation(conqueror if f == player else f)
		r.at_war = false
		r.pact_turns_left = 0
	else:
		ai_war_since.erase(pair_key(f, conqueror))

# A unit attacking a city: its own Strength, +SIEGE_SUPPORT for every other
# army of its faction next to that city (the usual 4X flanking bonus), so
# taking a city takes several units.
func siege_strength(u: Unit, f: Faction) -> int:
	var attack := u.fighting_strength()
	for other in u.faction.units:
		if other != u and not other.is_scout() and HexMap.is_neighbour(other.pos, f.city_pos):
			attack += SIEGE_SUPPORT
	return attack

func overlord_of(f: Faction) -> Faction:
	var o := faction_named(f.overlord) if f.overlord != "" else null
	return o if o != null and o.is_alive() else null

# Overlord and tributary: no war between them except an uprising.
func tribute_bound(a: Faction, b: Faction) -> bool:
	return a.overlord == b.name or b.overlord == a.name

# Half its Industry income goes to its overlord (after the turn's income).
func pay_tribute(f: Faction) -> void:
	var lord := overlord_of(f)
	if lord == null:
		f.overlord = "" # the overlord's city is gone: free
		return
	var pay := tribute_amount(f)
	f.industry -= pay
	lord.industry += pay

func tribute_amount(f: Faction) -> int:
	return int(maxi(0, industry_change(f)) * TRIBUTE_SHARE) if overlord_of(f) != null else 0

# A tributary AI stronger than its overlord may rise up: it is free and at war.
func ai_rebellions() -> void:
	for f in ais:
		var lord := overlord_of(f)
		if lord == null or army_power(f) <= army_power(lord) or randf() >= REBEL_CHANCE:
			continue
		f.overlord = ""
		if lord == player:
			relation(f).rival_declare_war("they rose up against your rule")
		else:
			ai_war_since[pair_key(f, lord)] = turn
			add_message("The %s rose up against the %s." % [f.name, lord.name])

# The nearest enemy city (at war) for this AI's spare armies to march on, or
# null if it isn't at war or has too few armies to spare.
func ai_siege_target(f: Faction) -> Faction:
	var armies := f.units.filter(func(x): return not x.is_scout()).size()
	if armies < AI_MARCH_ARMIES:
		return null
	var best: Faction = null
	var best_d := 999
	for g in factions:
		if g.is_alive() and at_war(f, g):
			var d := HexMap.hex_distance(f.city_pos, g.city_pos)
			if daughter.shelters_with(g):
				d -= SunDaughter.CLAIM_SIEGE_PULL # take her holder's city and she is yours
			if d < best_d:
				best_d = d
				best = g
	return best

func city_owner(cell: Vector2i) -> Faction:
	for f in factions:
		if f.is_alive() and f.city_pos == cell:
			return f
	return null

func faction_named(n: String) -> Faction:
	for f in factions:
		if f.name == n:
			return f
	return null

# --- Choices (ruins, small events) ---------------------------------------------
func has_pending_choice() -> bool:
	return not pending_choices.is_empty()

# Anything the player must answer before playing on (a choice or an AI's offer).
func is_waiting() -> bool:
	return has_pending_choice() or has_pending_offer()

# The player can act right now: playing, and nothing waiting for an answer.
func can_act() -> bool:
	return can_play() and not is_waiting()

# Can the player pick an option with these effects? (See option_problem.)
func can_afford(effects: Dictionary) -> bool:
	return option_problem(effects) == ""

# Why the player can't pick an option with these effects ("" = they can): a
# cost they can't pay, or Favour they can't gain (already at the top).
func option_problem(effects: Dictionary) -> String:
	if player.food + effects.get("food", 0) < 0 or player.industry + effects.get("industry", 0) < 0:
		return "you can't afford it"
	if effects.get("favour", 0) > 0 and player.favour >= SunDaughter.MAX_FAVOUR:
		return "her Favour is already at its highest"
	if effects.has("guard_turns") and guard_unit() == null:
		return "you have no army unit"
	return ""

# The army unit that stands watch for an event: the one in the city, or the nearest to it.
func guard_unit() -> Unit:
	var best: Unit = null
	for u in player.units:
		if u.is_scout():
			continue
		if best == null or HexMap.hex_distance(u.pos, player.city_pos) < HexMap.hex_distance(best.pos, player.city_pos):
			best = u
	return best

# The player picks option i of the first waiting choice.
func answer_choice(i: int) -> void:
	if not has_pending_choice():
		return
	var choice: Dictionary = pending_choices[0]
	var option: Dictionary = choice["options"][i]
	if not can_afford(option["effects"]):
		return
	pending_choices.pop_front()
	var effects: Dictionary = option["effects"]
	if effects.has("gamble"):
		var g: Dictionary = effects["gamble"]
		apply_effects(effects)
		if randf() < g["chance"]:
			add_message(g["good_text"])
			apply_effects(g.get("good", {}))
		else:
			add_message(g["bad_text"])
			apply_effects(g.get("bad", {}))
	else:
		apply_effects(effects)
		if option.get("result", "") != "":
			add_message(option["result"])

# Adds the effects to the player. Losses can't drop anything below 0
# (population below 1); "reveal" uncovers the land around an AI city you haven't found.
func apply_effects(effects: Dictionary) -> void:
	player.food = maxi(0, player.food + effects.get("food", 0))
	player.industry = maxi(0, player.industry + effects.get("industry", 0))
	player.population = maxi(1, player.population + effects.get("population", 0))
	player.favour = clampi(player.favour + effects.get("favour", 0), 0, SunDaughter.MAX_FAVOUR)
	if effects.has("join_war"): # answering your ally's call to arms
		var enemy := faction_named(effects["join_war"])
		var r_ally := relation(faction_named(effects["ally"]))
		if enemy.is_alive() and not at_war(player, enemy):
			relation(enemy).player_declare_war(true)
		r_ally.change_trust(Diplomacy.TRUST_JOINED_ALLY)
		remember("Turn %d: you kept your %s with the %s and went to war. Their Trust %+d." % [turn, r_ally.pact_word(), r_ally.other.name, Diplomacy.TRUST_JOINED_ALLY])
	if effects.has("abandon_ally"):
		var r_ally := relation(faction_named(effects["abandon_ally"]))
		if r_ally.pact_active():
			r_ally.break_pact()
	if effects.has("guard_turns"):
		var g := guard_unit()
		if g != null:
			g.busy_until = turn + effects["guard_turns"]
			g.moves = 0
	if effects.has("her_favour"): # granting or refusing Sunna's request
		daughter.change_favour(player, effects["her_favour"])
	if effects.has("spoil"):
		player.food = maxi(0, player.food - effects["spoil"])
	if effects.has("trust_all"):
		for r in relations:
			r.change_trust(effects["trust_all"])
	if effects.get("reveal", false):
		var hidden := ais.filter(func(f): return f.is_alive() and not player.explored.has(f.city_pos))
		if hidden.is_empty():
			add_message("He has nothing to tell you that you don't already know.")
		else:
			var f: Faction = hidden.pick_random()
			reveal_area(player, f.city_pos, 2)
			add_message("He leads your mapmakers to where the %s landed." % f.name)

# Sunna asks something of you every REQUEST_GAP turns while you shelter her.
func maybe_sunna_request() -> void:
	if turn >= next_request_turn and daughter.state == SunDaughter.State.SHELTERED and daughter.holder != null and daughter.holder != player:
		# An AI sheltering her is asked too: it grants if it has the Industry, else refuses.
		next_request_turn = turn + SunDaughter.REQUEST_GAP
		var ai := daughter.holder
		if ai.industry >= AI_REQUEST_COST:
			ai.industry -= AI_REQUEST_COST
			daughter.change_favour(ai, SunDaughter.REQUEST_GRANTED)
		else:
			daughter.change_favour(ai, SunDaughter.REQUEST_REFUSED)
		return
	if not daughter.shelters_with(player):
		next_request_turn = maxi(next_request_turn, turn + 1)
		return
	if turn < next_request_turn:
		return
	next_request_turn = turn + SunDaughter.REQUEST_GAP
	var r: Dictionary = TurnEvents.SUNNA_REQUESTS.pick_random()
	var grant: Dictionary = r["effects"].duplicate()
	grant["her_favour"] = SunDaughter.REQUEST_GRANTED
	pending_choices.append({"title": r["title"], "text": r["text"], "options": [
		{"label": "%s: her Favour %+d" % [r["grant"], SunDaughter.REQUEST_GRANTED], "effects": grant, "result": "Sunna smiles."},
		{"label": "Refuse: her Favour %+d" % SunDaughter.REQUEST_REFUSED, "effects": {"her_favour": SunDaughter.REQUEST_REFUSED}, "result": "Sunna turns away."},
	]})

# From RISE_TURN: if she shelters with a faction that has earned RISE_FAVOUR,
# she rises as the new sun and stands with them.
func maybe_rise() -> void:
	if turn < RISE_TURN or daughter.state != SunDaughter.State.SHELTERED or daughter.holder == null or not daughter.holder.is_alive():
		return
	if not rise_missing(daughter.holder).is_empty():
		return # Favour, another people's recognition, and a city that has held against Sköll
	daughter.state = SunDaughter.State.RISEN
	# Mortal now, but enraged (Nathan's playtest: "the game just ends with Sunna
	# rising"): he keeps his Strength, knows where she is and runs at her city.
	# Dawn still needs her city to stand on turn END_TURN.
	skoll.wounds = 0
	skoll.knows_her = true
	var who := "you" if daughter.holder == player else "the " + daughter.holder.name
	diplomacy_log.append("Turn %d: SUNNA HAS RISEN with %s. Sköll is mortal." % [turn, who])
	if diplomacy_log.size() > DIPLOMACY_LOG_SIZE:
		diplomacy_log.pop_front()
	add_message("Turn %d: SUNNA HAS RISEN and stands with %s (+%d Food, +%d Industry a turn). The ash stops." % [turn, who, SunDaughter.RISEN_FOOD, SunDaughter.RISEN_INDUSTRY])
	add_message("Sköll is MORTAL now, but enraged (Strength %d): he runs %d hexes a turn at her city. If it stands on turn %d it is Dawn; if it falls, he swallows her." % [skoll.strength, Skoll.RAGE_SPEED, END_TURN])

# Does another people recognise her as f's? (Trust RECOGNISE_TRUST+ or an oath.)
# AIs keep no Trust toward each other, so for an AI holder it is you who
# recognise it: its relationship with you.
func recognised(f: Faction) -> bool:
	if f == player:
		for r in relations:
			if r.other.is_alive() and (r.trust >= SunDaughter.RECOGNISE_TRUST or r.pact_active()):
				return true
		return false
	var rel := relation(f)
	return rel != null and (rel.trust >= SunDaughter.RECOGNISE_TRUST or rel.pact_active())

# What she still needs before she can rise with f (empty = ready, from RISE_TURN).
func rise_missing(f: Faction) -> Array[String]:
	var missing: Array[String] = []
	if f.favour < SunDaughter.RISE_FAVOUR:
		missing.append("Favour %d/%d" % [f.favour, SunDaughter.RISE_FAVOUR])
	if not recognised(f):
		missing.append("recognition (Trust %d+ or an oath)" % SunDaughter.RECOGNISE_TRUST)
	if f.skoll_held < 1:
		missing.append("her city to hold off Sköll")
	return missing

# Every few turns after the Landing, a small event asks the player to choose.
func maybe_turn_event() -> void:
	if turn < next_event_turn or event_deck.is_empty():
		return
	next_event_turn = turn + randi_range(TurnEvents.MIN_GAP, TurnEvents.MAX_GAP)
	var event: Dictionary = event_deck.pop_back()
	pending_choices.append({"title": event["title"], "text": event["text"], "options": event["options"]})

# --- Walls ------------------------------------------------------------------
# A city improvement: each level costs WALL_COST Industry and adds WALL_DEFENCE.
func city_sight(f: Faction) -> int:
	return CITY_SIGHT + (Buildings.WATCHTOWER_SIGHT if f.buildings.has("watchtower") else 0)

# --- City buildings (buildings.gd) -------------------------------------------
func can_build_building(f: Faction, key: String) -> bool:
	return f.is_alive() and not f.buildings.has(key) and f.industry >= Buildings.cost(key)

func build_building(f: Faction, key: String) -> bool:
	if not can_build_building(f, key):
		return false
	f.industry -= Buildings.cost(key)
	f.buildings[key] = true
	if key == "forge":
		f.strength += Buildings.FORGE_STRENGTH # new army units copy their faction's Strength
	return true

func player_build_building(key: String) -> void:
	if not can_act():
		return
	if build_building(player, key):
		messages = ["You built a %s (%d Industry): %s." % [Buildings.LIST[key]["name"], Buildings.cost(key), Buildings.LIST[key]["text"]]]
		update_sight()
	else:
		messages = ["Can't build the %s." % Buildings.LIST[key]["name"]]

func build_walls(f: Faction) -> bool:
	if not f.is_alive() or f.walls >= MAX_WALLS or f.industry < WALL_COST:
		return false
	f.industry -= WALL_COST
	f.walls += 1
	return true

# --- Building units -----------------------------------------------------------
# A new unit appears on the city, or on a free hex next to it if the city is occupied.
# Returns false if there's no room or not enough Industry.
func build_unit(f: Faction) -> bool:
	if not f.is_alive() or f.industry < UNIT_COST or army_count(f) >= supply_cap(f):
		return false
	var spot := free_spot_near(f.city_pos)
	if spot == NO_CELL:
		return false
	f.industry -= UNIT_COST
	f.add_unit(spot)
	return true

func can_build_scout(f: Faction) -> bool:
	return f.is_alive() and f.industry >= SCOUT_COST and f.scout_count() < MAX_SCOUTS and free_spot_near(f.city_pos) != NO_CELL

func build_scout(f: Faction) -> bool:
	if not can_build_scout(f):
		return false
	f.industry -= SCOUT_COST
	f.add_unit(free_spot_near(f.city_pos), Unit.Kind.SCOUT)
	return true

# --- Production queue (standard 4X) --------------------------------------------
# The city works through its queue in order. At the end of each turn the
# Industry the turn brought in (after upkeep and tribute) goes into the queue
# instead of the store; once enough is in for an item, it is finished (a unit
# appears at the city, ready to move) and any extra goes on to the next item.
# An item that can't be finished right now (supply full, no free hex) waits
# and the next one is worked on; if nothing can be finished the Industry goes
# to the store as usual. The Industry in the queue can't be spent on anything
# else (deals, Sunna's requests); taking the last item out gives it back to the
# store. "Finish now" pays what the front item still needs from the store.
# Buying at once (Build) still works as before. The AIs keep buying at once.
func item_cost(key: String) -> int:
	match key:
		"army":
			return UNIT_COST
		"scout":
			return SCOUT_COST
		"walls":
			return WALL_COST
	return Buildings.cost(key)

func item_name(key: String) -> String:
	match key:
		"army":
			return "Army"
		"scout":
			return "Scout"
		"walls":
			return "Walls"
	return Buildings.LIST[key]["name"]

# Why the item can't be added to the queue ("" = it can).
func queue_problem(f: Faction, key: String) -> String:
	var queued := f.queue.count(key)
	if not f.is_alive():
		return "your city has fallen"
	if f.queue.size() >= QUEUE_MAX:
		return "the queue is full (%d items)" % QUEUE_MAX
	match key:
		"army":
			if army_count(f) + queued >= supply_cap(f):
				return "your supply is full (%d armies)" % supply_cap(f)
		"scout":
			if f.scout_count() + queued >= MAX_SCOUTS:
				return "at most %d scouts" % MAX_SCOUTS
		"walls":
			if f.walls + queued >= MAX_WALLS:
				return "walls go up to level %d" % MAX_WALLS
		_:
			if f.buildings.has(key):
				return "already built"
			if queued > 0:
				return "already in the queue"
	return ""

# Why a queued item can't be finished right now, whatever its cost ("" = it can).
func item_blocked(f: Faction, key: String) -> String:
	match key:
		"army":
			if army_count(f) >= supply_cap(f):
				return "supply full"
			if free_spot_near(f.city_pos) == NO_CELL:
				return "no free hex at the city"
		"scout":
			if f.scout_count() >= MAX_SCOUTS:
				return "at most %d scouts" % MAX_SCOUTS
			if free_spot_near(f.city_pos) == NO_CELL:
				return "no free hex at the city"
		"walls":
			if f.walls >= MAX_WALLS:
				return "walls complete"
		_:
			if f.buildings.has(key):
				return "already built"
	return ""

# The queued item the city works on now: the first one it could finish (-1 = none).
func queue_front(f: Faction) -> int:
	for i in f.queue.size():
		if item_blocked(f, f.queue[i]) == "":
			return i
	return -1

# Turns until the front item is done at this turn's income (-1 = never at this rate).
func queue_turns(f: Faction) -> int:
	var i := queue_front(f)
	if i < 0:
		return -1
	var left := item_cost(f.queue[i]) - f.production
	if left <= 0:
		return 1
	var income := industry_change(f) - tribute_amount(f)
	if income <= 0:
		return -1
	return ceili(float(left) / income)

# Makes the item (its cost is paid by the caller).
func make_item(f: Faction, key: String) -> void:
	match key:
		"army":
			f.add_unit(free_spot_near(f.city_pos))
		"scout":
			f.add_unit(free_spot_near(f.city_pos), Unit.Kind.SCOUT)
		"walls":
			f.walls += 1
		_:
			f.buildings[key] = true
			if key == "forge":
				f.strength += Buildings.FORGE_STRENGTH

func finished_message(f: Faction, key: String) -> String:
	var text := "Your city finished: %s." % item_name(key)
	match key:
		"army":
			text = "Your city finished an army unit. Armies: %d/%d, upkeep now %d Industry a turn." % [army_count(f), supply_cap(f), army_upkeep(f)]
			if food_change(f) < 0:
				text += " Warning: your army now eats more Food than you make (%+d a turn)." % food_change(f)
		"scout":
			text = "Your city finished a scout."
		"walls":
			text = "Your city finished walls (level %d): defence +%d." % [f.walls, WALL_DEFENCE]
		_:
			text = "Your city finished the %s: %s." % [item_name(key), Buildings.LIST[key]["text"]]
	return text

# End of turn: put this turn's Industry (gain) into the queue and finish what it pays for.
func work_queue(f: Faction, gain: int) -> void:
	if f.queue.is_empty() or queue_front(f) < 0:
		return # nothing it could finish: the Industry stays in the store
	var take := clampi(gain, 0, f.industry)
	f.industry -= take
	f.production += take
	while true:
		var i := queue_front(f)
		if i < 0 or f.production < item_cost(f.queue[i]):
			break
		var key: String = f.queue[i]
		f.production -= item_cost(key)
		f.queue.remove_at(i)
		make_item(f, key)
		if f == player:
			add_message(finished_message(f, key))
	if f.queue.is_empty() and f.production > 0:
		f.industry += f.production # nothing left to work on: the rest goes back to the store
		f.production = 0

func player_queue(key: String) -> void:
	if not can_act():
		return
	var problem := queue_problem(player, key)
	if problem != "":
		messages = ["Can't add %s to the queue: %s." % [item_name(key), problem]]
		return
	player.queue.append(key)
	messages = ["%s added to your city's queue. Each turn your Industry goes into the queue instead of your store." % item_name(key)]

func player_unqueue(index: int) -> void:
	if not can_act() or index < 0 or index >= player.queue.size():
		return
	var key: String = player.queue[index]
	player.queue.remove_at(index)
	messages = ["%s taken out of the queue." % item_name(key)]
	if player.queue.is_empty() and player.production > 0:
		add_message("The %d Industry already in the queue goes back to your store." % player.production)
		player.industry += player.production
		player.production = 0

# Pays what the item the city is working on still needs, and finishes it now.
func hurry_cost(f: Faction) -> int:
	var i := queue_front(f)
	return -1 if i < 0 else maxi(0, item_cost(f.queue[i]) - f.production)

func player_hurry() -> void:
	if not can_act():
		return
	var i := queue_front(player)
	if i < 0:
		messages = ["Nothing in the queue can be finished right now."]
		return
	var pay := hurry_cost(player)
	if player.industry < pay:
		messages = ["Can't finish it now: it needs %d more Industry and you have %d." % [pay, player.industry]]
		return
	var key: String = player.queue[i]
	player.industry -= pay
	player.production = maxi(0, player.production - item_cost(key))
	player.queue.remove_at(i)
	make_item(player, key)
	if key == "army" or key == "scout":
		player.units[-1].moves = 0 # bought this turn: it waits a turn, like buying at once
	messages = [finished_message(player, key) + " (finished now for %d Industry)" % pay]
	if player.queue.is_empty() and player.production > 0:
		player.industry += player.production
		player.production = 0
	update_sight()

# The city hex if it's free, otherwise a free hex next to it (NO_CELL if none).
func free_spot_near(cell: Vector2i) -> Vector2i:
	if not is_blocked(cell):
		return cell
	for c in HexMap.neighbours(cell):
		if not is_blocked(c) and not is_city(c):
			return c
	return NO_CELL

# --- Outposts and territory ------------------------------------------------------
# Where faction f could found an outpost right now: a hex it can SEE (so
# scouting matters), within OUTPOST_RANGE of its city, at least
# OUTPOST_MIN_DISTANCE from every city and outpost, not on ruins still to be
# searched, and with no other faction's unit on it.
func outpost_spots(f: Faction) -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	if not f.is_alive() or f.outposts.size() >= MAX_OUTPOSTS:
		return spots
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if can_place_outpost(f, c):
				spots.append(c)
	return spots

func can_place_outpost(f: Faction, c: Vector2i) -> bool:
	if not HexMap.in_bounds(c) or not can_see(f, c) or not passable(c) or is_ash(c):
		return false
	if HexMap.hex_distance(c, f.city_pos) > OUTPOST_RANGE:
		return false
	for other in factions:
		if other.is_alive() and HexMap.hex_distance(c, other.city_pos) < OUTPOST_MIN_DISTANCE:
			return false
		for o in other.outposts:
			if HexMap.hex_distance(c, o) < OUTPOST_MIN_DISTANCE:
				return false
	for r in ruins:
		if r["cell"] == c and not r["taken"]:
			return false
	if f.known_rifts.has(c) or c == rifts.revealed:
		return false # never on a rift you know of (a hidden one moves away: build_outpost)
	var u := unit_at(c)
	return (u == null or u.faction == f) and not skoll.is_at(c) and rifts.walker_at(c) == null and not (daughter.is_rogue() and daughter.pos == c)

func build_outpost(f: Faction, cell: Vector2i) -> bool:
	if f.industry < OUTPOST_COST or f.outposts.size() >= MAX_OUTPOSTS or not can_place_outpost(f, cell):
		return false
	f.industry -= OUTPOST_COST
	f.outposts.append(cell)
	rifts.move(cell) # a hidden rift under it tears open elsewhere
	return true

# Whose outpost stands on this hex (null if none).
func outpost_owner(cell: Vector2i) -> Faction:
	for f in factions:
		if cell in f.outposts:
			return f
	return null

# Territory (standard 4X): a city or outpost claims its own hex and the 6
# around it. Returns whose territory this hex is (null if nobody's).
func territory_owner(cell: Vector2i) -> Faction:
	for f in factions:
		if f.is_alive() and HexMap.hex_distance(cell, f.city_pos) <= 1:
			return f
	for f in factions:
		for o in f.outposts:
			if HexMap.hex_distance(cell, o) <= 1:
				return f
	return null

# --- Combat -----------------------------------------------------------------
# Every fight uses the same rule: the attacker wins with chance
# attack / (attack + defence). A defence of 0 means the attacker always wins.
func win_chance(attack: int, defence: int) -> float:
	if defence <= 0:
		return 1.0
	return float(attack) / (attack + defence)

func odds_text(chance: float) -> String:
	return "%d%% chance" % roundi(chance * 100)

# Unit against unit. The loser is destroyed; a winning attacker moves into the hex.
# Unit against unit: both take damage (see COMBAT_DAMAGE); a unit at 0 HP
# dies. If the defender dies and the attacker lives, the attacker moves in
# (never into a city).
func resolve_combat(attacker: Unit, defender: Unit) -> void:
	var dealt := combat_damage(attacker.fighting_strength(), defender_strength(defender))
	var taken := combat_damage(defender_strength(defender), attacker.fighting_strength())
	var cell := defender.pos
	attacker.acted = true
	defender.acted = true
	defender.hp -= dealt
	attacker.hp -= taken
	var what := "%s attacked %s: dealt %d, took %d" % [attacker.faction.name, defender.faction.name, dealt, taken]
	if defender.hp <= 0:
		defender.faction.remove_unit(defender)
		what += ". The %s unit was destroyed" % defender.faction.name
	if attacker.hp <= 0:
		attacker.faction.remove_unit(attacker)
		what += ". The %s attacker was destroyed" % attacker.faction.name
	elif defender.hp <= 0 and not is_city(cell):
		enter_hex(attacker, cell)
	add_message(what + ".")

# A unit attacks a Rift Walker (rift_walker.gd): the same HP fight as unit
# against unit, both sides take damage. It fights back but never attacks
# first. If it dies and the attacker lives, the attacker moves in (where it
# may go). Never an act of war: Walkers belong to nobody.
func attack_walker(u: Unit, w: RiftWalker) -> void:
	var dealt := combat_damage(u.fighting_strength(), walker_defence(w))
	var taken := combat_damage(walker_defence(w), u.fighting_strength())
	u.acted = true
	w.acted = true
	w.hp -= dealt
	u.hp -= taken
	var who := "Your unit" if u.faction == player else "A %s unit" % u.faction.name
	var what := "%s attacked a Rift Walker: dealt %d, took %d" % [who, dealt, taken]
	var cell := w.pos
	if w.hp <= 0:
		rifts.remove_walker(w)
		what += ". The Walker sank back into the roots"
	if u.hp <= 0:
		u.faction.remove_unit(u)
		what += ". The attacker was destroyed"
	elif w.hp <= 0 and may_enter(u.faction, cell):
		enter_hex(u, cell)
	if u.faction == player or player_can_see(cell):
		add_message(what + ".")

# A Walker's Strength when attacked: weakened by wounds; forest and hills help.
func walker_defence(w: RiftWalker) -> int:
	return w.fighting_strength() + Terrain.DEFENCE[terrain_at(w.pos)]

# Expected damage both ways if u attacks Walker w (for the view).
func expected_walker_combat(u: Unit, w: RiftWalker) -> Vector2i:
	var a := u.fighting_strength()
	var d := walker_defence(w)
	return Vector2i(roundi(COMBAT_DAMAGE * float(a) / (a + d)), roundi(COMBAT_DAMAGE * float(d) / (a + d)))

# An AI army attacks a Walker next to it that stands on its own land (eating
# its Food), unless the army is hurt.
func ai_walker_target(u: Unit) -> RiftWalker:
	if u.hp <= AI_REST_HP:
		return null
	for c in HexMap.neighbours(u.pos):
		var w := rifts.walker_at(c)
		if w != null and territory_owner(c) == u.faction:
			return w
	return null

# The damage one side deals the other: its share of COMBAT_DAMAGE, varied.
func combat_damage(mine: int, theirs: int) -> int:
	var share := float(mine) / (mine + theirs)
	return maxi(1, roundi(COMBAT_DAMAGE * share * randf_range(1.0 - DAMAGE_SPREAD, 1.0 + DAMAGE_SPREAD)))

# Expected damage both ways if attacker attacks defender (for the view).
func expected_combat(attacker: Unit, defender: Unit) -> Vector2i:
	var a := attacker.fighting_strength()
	var d := defender_strength(defender)
	return Vector2i(roundi(COMBAT_DAMAGE * float(a) / (a + d)), roundi(COMBAT_DAMAGE * float(d) / (a + d)))

# A unit's Strength when attacked: weakened by its wounds; forest and hills help.
func defender_strength(u: Unit) -> int:
	return u.fighting_strength() + Terrain.DEFENCE[terrain_at(u.pos)]

# A city's defence (the usual 4X rule): the Strength of its own unit standing
# in it (the garrison), plus its walls, its land, its population above 1, plus
# the Daughter's bonus if it shelters her.
func city_defence(f: Faction) -> int:
	var defence: int = f.walls * WALL_DEFENCE + Terrain.DEFENCE[terrain_at(f.city_pos)] # a city on hills is harder to take
	defence += (f.population - 1) * POP_DEFENCE # bigger cities hold out better
	if f.buildings.has("watchtower"):
		defence += Buildings.WATCHTOWER_DEFENCE
	var garrison := unit_at(f.city_pos)
	if garrison and garrison.faction == f:
		defence += garrison.fighting_strength() # (a wounded garrison defends weaker)
	if daughter.shelters_with(f) or daughter.risen_with(f):
		defence += SunDaughter.DEFENCE
	return defence

# --- Fog of war -------------------------------------------------------------
# Standard 4X fog. Every faction sees CITY_SIGHT around its city,
# OUTPOST_SIGHT around its outposts, and each unit's sight around it (scouts
# see further). Hexes it has ever seen stay "explored": the land, cities,
# outposts and ruins there stay known, but units, Sköll and the Daughter on
# them are only seen while in sight. The AI plays by the same fog for
# exploring, ruins and outposts.
func can_see(f: Faction, cell: Vector2i) -> bool:
	if f.is_alive() and HexMap.hex_distance(cell, f.city_pos) <= city_sight(f):
		return true
	for o in f.outposts:
		if HexMap.hex_distance(cell, o) <= OUTPOST_SIGHT:
			return true
	for u in f.units:
		if HexMap.hex_distance(cell, u.pos) <= u.sight():
			return true
	return false

# What the player sees right now. During the Landing the ark is still in the
# sky: the player sees the shape of the land but not what's on it.
func player_can_see(cell: Vector2i) -> bool:
	return phase == Phase.PLAYING and can_see(player, cell)

func player_has_explored(cell: Vector2i) -> bool:
	return player.explored.has(cell)

# Marks everything each faction can see as explored (call after anything moves).
func update_sight() -> void:
	for f in factions:
		update_sight_for(f)

func update_sight_for(f: Faction) -> void:
	if phase != Phase.PLAYING:
		return
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if not can_see(f, c):
				continue
			if not f.explored.has(c):
				f.explored[c] = true
				if f == player:
					discover(c)
			if rifts.has(c) and not f.known_rifts.has(c):
				f.known_rifts[c] = true
				if f == player:
					add_message("You found a rift in the void: torn earth that hums at night. Sköll could come through here.")

# The player sees a hex for the first time: tell them if something is there.
func discover(c: Vector2i) -> void:
	for r in ruins:
		if r["cell"] == c and not r["taken"]:
			add_message("Ruins spotted in the dark! Move a unit onto them to search them.")
	for f in ais:
		if f.city_pos == c:
			add_message("You found the %s city." % f.name)

# Uncovers the land around a hex for faction f (an event can do this).
func reveal_area(f: Faction, center: Vector2i, radius: int) -> void:
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if HexMap.hex_distance(c, center) <= radius:
				f.explored[c] = true

# Rifts are placed (once, on Rifts.RIFT_TURN): nobody knows where they are yet.
func forget_rifts() -> void:
	for f in factions:
		f.known_rifts.clear()

# --- Who is where -----------------------------------------------------------
# The unit standing on this hex (any faction), or null if there's none.
func unit_at(cell: Vector2i) -> Unit:
	for f in factions:
		for u in f.units:
			if u.pos == cell:
				return u
	return null

# True if a unit, Sköll, a Rift Walker or the Daughter (in the open) is standing
# on this hex. (Mountains and water count as blocked: nothing can stand there except Sköll.)
func is_blocked(cell: Vector2i) -> bool:
	return not passable(cell) or unit_at(cell) != null or skoll.is_at(cell) or rifts.walker_at(cell) != null or (daughter.is_rogue() and cell == daughter.pos)

# --- Terrain ------------------------------------------------------------------
func terrain_at(cell: Vector2i) -> int:
	return terrain.get(cell, Terrain.Type.PLAINS)

func is_ash(cell: Vector2i) -> bool:
	return ash.has(cell)

func passable(cell: Vector2i) -> bool:
	return HexMap.in_bounds(cell) and Terrain.passable(terrain_at(cell))

# Moves it takes to enter this hex (forest and hills 2).
func move_cost(cell: Vector2i) -> int:
	return Terrain.MOVE_COST[terrain_at(cell)]

# Can unit u step into this hex now? Rough land costs 2 moves, but a unit
# with all its moves left can always take one step (so armies, with 1 move,
# still move 1 hex a turn; scouts are slowed down).
func can_afford_move(u: Unit, cell: Vector2i) -> bool:
	return u.moves >= move_cost(cell) or u.moves == u.max_moves()

func spend_move(u: Unit, cell: Vector2i) -> void:
	u.moves = maxi(0, u.moves - move_cost(cell))

func is_city(cell: Vector2i) -> bool:
	for f in factions:
		if f.city_pos == cell:
			return true
	return false
