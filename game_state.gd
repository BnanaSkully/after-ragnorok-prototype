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

const DOOM_TURN := 20 # survive until this turn and Phase 3 (chaos) begins
const MIN_LANDING_DISTANCE := 4 # how many hexes away from every AI city you must land
const LANDING_INDUSTRY := 5 # Industry everyone unloads from the ark at the Landing (enough to build something on turn 1)
const UNIT_COST := 5 # Industry to build a new army unit
const SCOUT_COST := 3 # Industry to build a scout
const MAX_SCOUTS := 2 # scouts each faction may have at once
const CITY_FOOD := 2 # Food a city produces each turn
const CITY_INDUSTRY := 2 # Industry a city produces each turn
const UNIT_FOOD_UPKEEP := 1 # Food each army unit eats each turn (scouts eat nothing)
# Outposts (standard 4X): a small settlement that claims the hexes around it.
const OUTPOST_COST := 6 # Industry
const OUTPOST_FOOD := 1 # income each outpost gives its owner every turn
const OUTPOST_INDUSTRY := 1
const OUTPOST_RANGE := 5 # an outpost must be within this many hexes of your city...
const OUTPOST_MIN_DISTANCE := 3 # ...and at least this far from every city and other outpost
const OUTPOST_SIGHT := 2 # fog of war: an outpost sees this far
const MAX_OUTPOSTS := 3 # per faction
const AI_MAX_OUTPOSTS := 2 # the AI stops at this many
const SPARE_OUTPOSTS_TRUST := 2 # an AI won't take your outposts while its Trust toward you is this high (or during an agreement)
const GROWTH_BASE := 10 # Food stored to grow from population 1 to 2...
const GROWTH_STEP := 5 # ...and each later growth costs this much more
const WALL_COST := 10 # Industry per wall level
const WALL_DEFENCE := 4 # city defence each wall level adds
const MAX_WALLS := 2
const CITY_SIGHT := 3 # fog of war: every faction sees this far around its city (units: see unit.gd)
const NO_CELL := HexMap.NO_CELL
const Crossing := preload("res://crossing_events.gd")
const TurnEvents := preload("res://turn_events.gd")
const Discoveries := preload("res://discoveries.gd")

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

func _init() -> void:
	skoll = Skoll.new(self)
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
	skoll.rifts.clear() # rolled on Skoll.RIFT_TURN, after both cities exist
	skoll.revealed_rift = NO_CELL
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
	if not HexMap.in_bounds(cell):
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
	for r in relations:
		r.rival_consider_breaking() # before its units move, so a betrayal can strike at once
	for f in ais:
		ai_take_turn(f)
	turn += 1
	if turn == Skoll.RIFT_TURN:
		skoll.place_rifts() # hidden until Sköll comes through one
	skoll.take_turn()
	if game_over: # Sköll may have destroyed the player's city or found the Daughter
		update_sight()
		return
	daughter_flee()
	for f in factions:
		if f.city_pos == NO_CELL:
			continue # this faction's city has fallen; it's out of the game
		f.food += food_change(f)
		f.industry += industry_change(f)
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
			u.moves = u.max_moves()
	judge_readiness()
	check_daughter_leaving()
	for f in ais:
		ai_build(f)
	for r in relations:
		r.new_turn()
	diplomacy_action_used = false
	if not game_over and turn < DOOM_TURN:
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
	update_sight()
	if turn >= DOOM_TURN:
		end_game("You survived until the Doom",
			"Sköll howls, and chaos pours out of the void.\nPHASE 3 BEGINS: chaos factions rise and rogues join Sköll.\n(Phase 3 is not built yet.)")

func end_game(title: String, detail: String) -> void:
	game_over = true
	end_title = title
	end_detail = detail

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
	var made := CITY_FOOD + (f.population - 1) # each extra population works more fields
	made += f.outposts.size() * OUTPOST_FOOD
	if daughter.shelters_with(f):
		made += SunDaughter.FOOD
	var eaten := 0
	for u in f.units:
		eaten += u.upkeep(UNIT_FOOD_UPKEEP)
	return made - eaten

func industry_change(f: Faction) -> int:
	var made := CITY_INDUSTRY + (f.population - 1) + f.outposts.size() * OUTPOST_INDUSTRY
	return made + (SunDaughter.INDUSTRY if daughter.shelters_with(f) else 0)

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
		add_message("Your city grew to population %d: +1 Food and +1 Industry a turn." % f.population)

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
		var target: Unit = null
		for c in HexMap.neighbours(u.pos):
			var other := unit_at(c)
			if other == null or other.faction == f:
				continue
			if other.faction == player and relation(f).pact_active():
				continue
			target = other
			break
		if target:
			resolve_combat(u, target)
			continue
		if u.pos == f.city_pos and f.units.size() > 1:
			continue # this one guards the city
		if daughter.is_rogue():
			if HexMap.is_neighbour(u.pos, daughter.pos):
				try_persuade(u)
				continue
			var toward := step_toward(u.pos, daughter.pos)
			if toward != NO_CELL:
				enter_hex(u, toward)
				continue
		if skoll.active and HexMap.hex_distance(u.pos, f.city_pos) > 1:
			# Sköll is loose: fall back toward the city to help defend it
			var home := step_toward(u.pos, f.city_pos)
			if home != NO_CELL:
				enter_hex(u, home)
				continue
		# An enemy outpost next door with nobody guarding it: take it.
		var grab := NO_CELL
		for c in HexMap.neighbours(u.pos):
			var owner := outpost_owner(c)
			if owner != null and owner != f and not is_blocked(c) and not (owner == player and spares_your_outposts(f)):
				grab = c
				break
		if grab != NO_CELL:
			enter_hex(u, grab)
			continue
		var options: Array[Vector2i] = []
		for c in HexMap.neighbours(u.pos):
			if not is_blocked(c) and not (is_city(c) and c != f.city_pos):
				options.append(c)
		if not options.is_empty():
			enter_hex(u, options.pick_random())

# An AI leaves the player's outposts alone during an agreement, or while it trusts them enough.
func spares_your_outposts(f: Faction) -> bool:
	var r := relation(f)
	return r.pact_active() or r.trust >= SPARE_OUTPOSTS_TRUST

# An AI scout: heads for the nearest ruins it has seen, otherwise for the
# nearest hex it hasn't explored yet; it never attacks.
func ai_scout(u: Unit) -> void:
	var f := u.faction
	while u.moves > 0:
		var goal := NO_CELL
		var best_d := 999
		for r in ruins:
			if not r["taken"] and f.explored.has(r["cell"]) and not is_blocked(r["cell"]):
				var d := HexMap.hex_distance(u.pos, r["cell"])
				if d < best_d:
					best_d = d
					goal = r["cell"]
		if goal == NO_CELL:
			goal = nearest_unexplored(f, u.pos)
		var step := step_toward(u.pos, goal) if goal != NO_CELL else NO_CELL
		if step == NO_CELL:
			var options: Array[Vector2i] = []
			for c in HexMap.neighbours(u.pos):
				if not is_blocked(c) and not is_city(c):
					options.append(c)
			if options.is_empty():
				return
			step = options.pick_random()
		enter_hex(u, step)
		u.moves -= 1
		update_sight_for(f)

# The closest hex this faction has never seen (NO_CELL if it has seen everything).
func nearest_unexplored(f: Faction, from: Vector2i) -> Vector2i:
	var best := NO_CELL
	var best_d := 999
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if f.explored.has(c):
				continue
			var d := HexMap.hex_distance(from, c)
			if d < best_d:
				best_d = d
				best = c
	return best

# The free neighbouring hex that gets closest to goal (NO_CELL if none is closer).
func step_toward(from: Vector2i, goal: Vector2i) -> Vector2i:
	var best := NO_CELL
	var best_d := HexMap.hex_distance(from, goal)
	for c in HexMap.neighbours(from):
		if is_blocked(c) or (is_city(c) and c != goal):
			continue
		var d := HexMap.hex_distance(c, goal)
		if d < best_d:
			best_d = d
			best = c
	return best

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
	if f.industry >= UNIT_COST and food_change(f) - UNIT_FOOD_UPKEEP >= 0:
		build_unit(f)

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
	remember("Turn %d: you handed %s to the %s (%s). Her Favour toward you %+d." % [turn, SunDaughter.NAME, f.name, deal, SunDaughter.TRADED_FAVOUR])
	return true

# She moves from giver's city to receiver's. Being traded costs Favour toward the giver.
func hand_over_daughter(giver: Faction, receiver: Faction) -> void:
	daughter.join(receiver)
	giver.favour = clampi(giver.favour + SunDaughter.TRADED_FAVOUR, 0, SunDaughter.MAX_FAVOUR)

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
	relation(f).propose_pact() # posts its own message

func player_demand(f: Faction, resource: String) -> void:
	if not can_act():
		return
	messages.clear()
	relation(f).demand(resource) # posts its own message

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
		messages = ["You built a new army unit (%d Industry). It can move next turn." % UNIT_COST]
		if food_change(player) < 0:
			add_message("Warning: your army now eats more Food than you make (%+d a turn). If your stores run out, a unit will desert." % food_change(player))
		player.units[-1].moves = 0 # a freshly built unit waits a turn, as is usual
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
	messages = ["You founded an outpost (%d Industry): +%d Food and +%d Industry a turn, and it claims the hexes around it. Leave a unit on it, or anyone can walk in and take it." % [OUTPOST_COST, OUTPOST_FOOD, OUTPOST_INDUSTRY]]
	update_sight()
	return true

# True if acting on this hex would break an oath: attacking a unit, or taking
# an outpost, of a faction you have an agreement with (the view asks for a
# second click before it does).
func would_break_pact(cell: Vector2i) -> bool:
	var other := unit_at(cell)
	if other != null:
		return other.faction != player and relation(other.faction).pact_active()
	var owner := outpost_owner(cell)
	return owner != null and owner != player and relation(owner).pact_active()

# One of the player's units acts on a neighbouring hex: attack Sköll, persuade
# the Daughter, attack an enemy unit (breaking an oath if one is in force), or
# move there (searching ruins, or taking an enemy outpost). Uses one move.
# Returns false if it can't act there.
func player_unit_act(u: Unit, cell: Vector2i) -> bool:
	if not can_act() or u.faction != player or u.moves <= 0 or not HexMap.is_neighbour(u.pos, cell):
		return false
	var other := unit_at(cell)
	if other and other.faction == player:
		return false # can't move onto your own unit
	if other == null and is_city(cell) and cell != player.city_pos:
		return false # you can't walk into another faction's city
	messages.clear()
	if skoll.is_at(cell):
		skoll.attacked_by(u)
	elif daughter.is_rogue() and cell == daughter.pos:
		try_persuade(u)
	elif other:
		var r := relation(other.faction)
		if r.pact_active():
			r.break_pact()
		resolve_combat(u, other) # moving into an enemy = attack
	else:
		var owner := outpost_owner(cell)
		if owner != null and owner != player and relation(owner).pact_active():
			relation(owner).break_pact()
		enter_hex(u, cell)
	u.moves -= 1
	update_sight()
	return true

# A unit steps onto a hex: it searches ruins there and takes an enemy
# outpost with nobody standing on it. Every move on the map goes through here.
func enter_hex(u: Unit, cell: Vector2i) -> void:
	u.pos = cell
	var f := u.faction
	var owner := outpost_owner(cell)
	if owner != null and owner != f:
		owner.outposts.erase(cell)
		f.outposts.append(cell)
		if f == player:
			add_message("You took the %s outpost! It now gives you +%d Food and +%d Industry a turn." % [owner.name, OUTPOST_FOOD, OUTPOST_INDUSTRY])
		elif owner == player:
			add_message("The %s took your outpost!" % f.name)
		elif player_can_see(cell):
			add_message("The %s took the %s outpost." % [f.name, owner.name])
	for r in ruins:
		if r["cell"] == cell and not r["taken"]:
			r["taken"] = true
			if f == player:
				pending_choices.append(Discoveries.ruin_choice())
			else:
				Discoveries.ai_take_ruin(self, f)
				if player_can_see(cell):
					add_message("The %s searched the ruins you spotted and carried something off." % f.name)

# --- Choices (ruins, small events) ---------------------------------------------
func has_pending_choice() -> bool:
	return not pending_choices.is_empty()

# Anything the player must answer before playing on (a choice or an AI's offer).
func is_waiting() -> bool:
	return has_pending_choice() or has_pending_offer()

# The player can act right now: playing, and nothing waiting for an answer.
func can_act() -> bool:
	return can_play() and not is_waiting()

# Can the player pay for these effects? (Only costs count: negative Food or Industry.)
func can_afford(effects: Dictionary) -> bool:
	return player.food + effects.get("food", 0) >= 0 and player.industry + effects.get("industry", 0) >= 0

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
	if effects.get("reveal", false):
		var hidden := ais.filter(func(f): return f.is_alive() and not player.explored.has(f.city_pos))
		if hidden.is_empty():
			add_message("He has nothing to tell you that you don't already know.")
		else:
			var f: Faction = hidden.pick_random()
			reveal_area(player, f.city_pos, 2)
			add_message("He leads your mapmakers to where the %s landed." % f.name)

# Every few turns after the Landing, a small event asks the player to choose.
func maybe_turn_event() -> void:
	if turn < next_event_turn or event_deck.is_empty():
		return
	next_event_turn = turn + randi_range(TurnEvents.MIN_GAP, TurnEvents.MAX_GAP)
	var event: Dictionary = event_deck.pop_back()
	pending_choices.append({"title": event["title"], "text": event["text"], "options": event["options"]})

# --- Walls ------------------------------------------------------------------
# A city improvement: each level costs WALL_COST Industry and adds WALL_DEFENCE.
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
	if not f.is_alive() or f.industry < UNIT_COST:
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
	if not HexMap.in_bounds(c) or not can_see(f, c):
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
	var u := unit_at(c)
	return (u == null or u.faction == f) and not skoll.is_at(c) and not (daughter.is_rogue() and daughter.pos == c)

func build_outpost(f: Faction, cell: Vector2i) -> bool:
	if f.industry < OUTPOST_COST or f.outposts.size() >= MAX_OUTPOSTS or not can_place_outpost(f, cell):
		return false
	f.industry -= OUTPOST_COST
	f.outposts.append(cell)
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
func resolve_combat(attacker: Unit, defender: Unit) -> void:
	var chance := win_chance(attacker.strength, defender.strength)
	if randf() < chance:
		var cell := defender.pos
		defender.faction.remove_unit(defender)
		if not is_city(cell): # beating a city's garrison doesn't put you inside the city
			enter_hex(attacker, cell)
		add_message("%s attacked %s and won (%s)." % [attacker.faction.name, defender.faction.name, odds_text(chance)])
	else:
		attacker.faction.remove_unit(attacker)
		add_message("%s attacked %s and lost (%s)." % [attacker.faction.name, defender.faction.name, odds_text(chance)])

# A city's defence (the usual 4X rule): the Strength of its own unit standing
# in it (the garrison), plus its walls, plus the Daughter's bonus if it shelters her.
func city_defence(f: Faction) -> int:
	var defence := f.walls * WALL_DEFENCE
	var garrison := unit_at(f.city_pos)
	if garrison and garrison.faction == f:
		defence += garrison.strength
	if daughter.shelters_with(f):
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
	if f.is_alive() and HexMap.hex_distance(cell, f.city_pos) <= CITY_SIGHT:
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
			if c in skoll.rifts and not f.known_rifts.has(c):
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

# The rifts were rolled again: nobody knows where the new ones are.
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

# True if a unit, Sköll or the Daughter (in the open) is standing on this hex.
func is_blocked(cell: Vector2i) -> bool:
	return unit_at(cell) != null or skoll.is_at(cell) or (daughter.is_rogue() and cell == daughter.pos)

func is_city(cell: Vector2i) -> bool:
	for f in factions:
		if f.city_pos == cell:
			return true
	return false
