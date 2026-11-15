extends Node2D

# The game's main script: runs the flow of a game (Crossing -> Landing -> turns),
# the rival, combat, drawing and mouse clicks.
# Other pieces live in their own files:
#   faction.gd          one side's city, units and resources
#   unit.gd             one army unit on the map
#   hex_map.gd          hex maths (positions, distances, neighbours)
#   skoll.gd            Sköll, the wolf boss
#   sun_daughter.gd     the Sun's Daughter
#   diplomacy.gd        oaths with the rival, trust and the memory of promises
#   crossing_events.gd  the Crossing's events (text and choices)

const DOOM_TURN := 20 # survive until this turn and Phase 3 (chaos) begins
const MIN_LANDING_DISTANCE := 4 # how many hexes away from the rival's city you must land
const UNIT_COST := 5 # Industry to build a new unit
const CITY_FOOD := 2 # Food a city produces each turn
const CITY_INDUSTRY := 1 # Industry a city produces each turn
const UNIT_FOOD_UPKEEP := 1 # Food each unit eats each turn
const WALL_COST := 10 # Industry per wall level
const WALL_DEFENCE := 4 # city defence each wall level adds
const MAX_WALLS := 2
const NO_CELL := HexMap.NO_CELL
const Crossing := preload("res://crossing_events.gd")

# The stages of a game, in order:
# CROSSING = journey events, LANDING = choosing where to found your city, PLAYING = the turns.
enum Phase { CROSSING, LANDING, PLAYING }

# The player has no city or units until they land (see try_land below).
var player := Faction.new("Player", Color(0.3, 0.4, 0.6), Color(0.2, 0.4, 0.9), NO_CELL)
var rival := Faction.new("Rival", Color(0.6, 0.3, 0.3), Color(0.85, 0.2, 0.2), Vector2i(9, 7))
var factions: Array[Faction] = [player, rival]
var daughter := SunDaughter.new()
var skoll: Skoll
var diplomacy: Diplomacy

var phase := Phase.CROSSING
var crossing_step := 0 # which Crossing event we're on
var crossing_panel: VBoxContainer
var crossing_label: Label
var crossing_buttons: VBoxContainer
var hover_cell := NO_CELL # the hex under the mouse while landing
var selected: Unit = null # the player's unit chosen to move (null = none)
var turn := 1
var game_over := false
var end_title := "" # big text on the end screen
var end_detail := "" # smaller text under it (can have several lines)
var end_turn_button: Button
var build_button: Button
var walls_button: Button
var oath_button: Button
var demand_food_button: Button
var demand_industry_button: Button
var break_warning_cell := NO_CELL # first click on a rival unit during an oath only warns
var messages: Array[String] = [] # shown at the bottom of the screen, e.g. combat results

func _init() -> void:
	skoll = Skoll.new(self)
	diplomacy = Diplomacy.new(self)
	rival.add_unit(Vector2i(8, 6))

func _ready() -> void:
	end_turn_button = Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.position = Vector2(820, 20)
	end_turn_button.pressed.connect(end_turn)
	add_child(end_turn_button)
	build_button = Button.new()
	build_button.text = "Build Unit (%d Industry)" % UNIT_COST
	build_button.position = Vector2(920, 20)
	build_button.pressed.connect(player_build_unit)
	add_child(build_button)
	walls_button = Button.new()
	walls_button.position = Vector2(920, 58)
	walls_button.pressed.connect(player_build_walls)
	add_child(walls_button)
	oath_button = Button.new()
	oath_button.position = Vector2(820, 96)
	oath_button.pressed.connect(player_propose_pact)
	add_child(oath_button)
	demand_food_button = Button.new()
	demand_food_button.position = Vector2(820, 134)
	demand_food_button.pressed.connect(player_demand.bind("food"))
	add_child(demand_food_button)
	demand_industry_button = Button.new()
	demand_industry_button.position = Vector2(820, 172)
	demand_industry_button.pressed.connect(player_demand.bind("industry"))
	add_child(demand_industry_button)
	build_crossing_ui()
	start_crossing()

# --- The Crossing -----------------------------------------------------------
# A panel with the event text and one button per choice. Built once, then
# its text and buttons are swapped for each event.
func build_crossing_ui() -> void:
	crossing_panel = VBoxContainer.new()
	crossing_panel.position = Vector2(150, 120)
	crossing_panel.custom_minimum_size = Vector2(850, 0)
	crossing_panel.add_theme_constant_override("separation", 16)
	add_child(crossing_panel)
	crossing_label = Label.new()
	crossing_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	crossing_label.add_theme_font_size_override("font_size", 22)
	crossing_panel.add_child(crossing_label)
	crossing_buttons = VBoxContainer.new()
	crossing_buttons.add_theme_constant_override("separation", 10)
	crossing_panel.add_child(crossing_buttons)

func start_crossing() -> void:
	phase = Phase.CROSSING
	crossing_step = 0
	player.city_pos = NO_CELL
	player.units.clear()
	player.food = Crossing.START_FOOD
	player.industry = Crossing.START_INDUSTRY
	daughter.reset(player, rival)
	end_turn_button.visible = false
	build_button.visible = false
	walls_button.visible = false
	oath_button.visible = false
	demand_food_button.visible = false
	demand_industry_button.visible = false
	crossing_panel.visible = true
	messages.clear()
	show_crossing_step()

func show_crossing_step() -> void:
	for b in crossing_buttons.get_children():
		b.queue_free()
	var tally := "Your people carry:  Food %d    Industry %d    Strength %d" % [player.food, player.industry, player.strength]
	tally += "\n%s's Favour toward you: %d    (the rival's is unknown)" % [SunDaughter.NAME.capitalize(), player.favour]
	if crossing_step < Crossing.EVENTS.size():
		var event: Dictionary = Crossing.EVENTS[crossing_step]
		crossing_label.text = "THE CROSSING  (%d of %d)\n\n%s\n\n%s" % [crossing_step + 1, Crossing.EVENTS.size(), event["text"], tally]
		for choice in event["choices"]:
			var effects_text := describe_effects(choice["effects"])
			var label: String = choice["label"] if effects_text == "" else "%s   (%s)" % [choice["label"], effects_text]
			add_crossing_button(label, choose.bind(choice["effects"]))
	else:
		crossing_label.text = "THE CROSSING\n\nThe branches of Yggdrasil give way. Land lies below.\nWhen you land, %s will choose whose city to shelter in.\n\n%s" % [SunDaughter.NAME, tally]
		add_crossing_button("Begin the Landing", start_landing)
	queue_redraw()

func add_crossing_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	crossing_buttons.add_child(b)

# Turns {"food": 3, "strength": -1} into "Food +3, Strength -1".
func describe_effects(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key in effects:
		parts.append("%s %+d" % [String(key).capitalize(), effects[key]])
	return ", ".join(parts)

# Apply a choice's effects. Nothing can drop below 0 (Strength below 1).
func choose(effects: Dictionary) -> void:
	player.food = maxi(0, player.food + effects.get("food", 0))
	player.industry = maxi(0, player.industry + effects.get("industry", 0))
	player.strength = maxi(1, player.strength + effects.get("strength", 0))
	player.favour = clampi(player.favour + effects.get("favour", 0), 0, SunDaughter.MAX_FAVOUR)
	crossing_step += 1
	show_crossing_step()

# --- The Landing ------------------------------------------------------------
# The player has no city or unit yet and must pick a hex to settle.
func start_landing() -> void:
	phase = Phase.LANDING
	daughter.choose_protector(player, rival)
	crossing_panel.visible = false
	end_turn_button.visible = true
	build_button.visible = true
	walls_button.visible = true
	oath_button.visible = true
	demand_food_button.visible = true
	demand_industry_button.visible = true
	player.city_pos = NO_CELL
	player.units.clear()
	end_turn_button.disabled = true
	update_build_button() # build buttons stay disabled until you've landed
	messages = ["Choose where to land: click a hex to found your city."]
	queue_redraw()

func can_land_at(cell: Vector2i) -> bool:
	return HexMap.in_bounds(cell) and HexMap.hex_distance(cell, rival.city_pos) >= MIN_LANDING_DISTANCE

func try_land(cell: Vector2i) -> void:
	if phase != Phase.LANDING or not can_land_at(cell):
		return
	player.city_pos = cell
	player.add_unit(cell) # your first unit starts standing on the new city
	phase = Phase.PLAYING
	hover_cell = NO_CELL
	end_turn_button.disabled = false
	update_build_button()
	messages = ["Your people have landed. Click a unit to move it, or build more."]
	var scores := "(her Favour: you %d, %s %d)" % [player.favour, rival.name, rival.favour]
	if daughter.holder == player:
		add_message("%s chose you %s: +%d Food, +%d Industry a turn, +%d city defence." % [SunDaughter.NAME.capitalize(), scores, SunDaughter.FOOD, SunDaughter.INDUSTRY, SunDaughter.DEFENCE])
	else:
		add_message("%s chose to shelter with %s %s." % [SunDaughter.NAME.capitalize(), daughter.holder.name, scores])
	queue_redraw()

# --- Turns ------------------------------------------------------------------
func end_turn() -> void:
	if game_over or phase != Phase.PLAYING:
		return
	messages.clear()
	rival_take_turn()
	turn += 1
	skoll.take_turn()
	if game_over: # Sköll may have destroyed the player's city or found the Daughter
		return
	for f in factions:
		if f.city_pos == NO_CELL:
			continue # this faction's city has fallen; it's out of the game
		f.food += food_change(f)
		f.industry += CITY_INDUSTRY
		if daughter.shelters_with(f):
			f.industry += SunDaughter.INDUSTRY
		if f.food < 0:
			starve(f)
		for u in f.units:
			u.moves = 1
	rival_build()
	diplomacy.new_turn()
	selected = null
	break_warning_cell = NO_CELL
	update_build_button()
	if turn >= DOOM_TURN:
		end_game("You survived until the Doom",
			"Sköll howls, and chaos pours out of the void.\nPHASE 3 BEGINS: chaos factions rise and rogues join Sköll.\n(Phase 3 is not built yet.)")
	queue_redraw()

# --- Food -------------------------------------------------------------------
# Food made by the city (and the Daughter's bonus) minus what the army eats.
func food_change(f: Faction) -> int:
	var made := CITY_FOOD
	if daughter.shelters_with(f):
		made += SunDaughter.FOOD
	return made - f.units.size() * UNIT_FOOD_UPKEEP

# Not enough Food: stores stay at 0 and one unit deserts (the one farthest
# from the city, so the garrison stays).
func starve(f: Faction) -> void:
	f.food = 0
	if f.units.is_empty():
		return
	var farthest: Unit = f.units[0]
	for u in f.units:
		if HexMap.hex_distance(u.pos, f.city_pos) > HexMap.hex_distance(farthest.pos, f.city_pos):
			farthest = u
	f.remove_unit(farthest)
	if f == player:
		add_message("Your people are starving: a unit deserted. (Each unit eats %d Food a turn.)" % UNIT_FOOD_UPKEEP)
	else:
		add_message("%s is starving: one of its units deserted." % f.name)

func end_game(title: String, detail: String) -> void:
	game_over = true
	end_turn_button.disabled = true
	build_button.disabled = true
	walls_button.disabled = true
	oath_button.disabled = true
	demand_food_button.disabled = true
	demand_industry_button.disabled = true
	selected = null
	end_title = title
	end_detail = detail
	queue_redraw()

func add_message(text: String) -> void:
	messages.append(text)

# Placeholder rival behaviour, for each of its units: attack a player unit
# next door; otherwise stay home if it's guarding the city and there are other
# units; otherwise step to a random free neighbouring hex.
func rival_take_turn() -> void:
	for u in rival.units.duplicate(): # copy: units can die during the loop
		if not u in rival.units:
			continue
		var target: Unit = null
		for c in HexMap.neighbours(u.pos):
			var other := unit_at(c)
			if other and other.faction == player and not diplomacy.pact_active():
				target = other
				break
		if target:
			resolve_combat(u, target)
			continue
		if u.pos == rival.city_pos and rival.units.size() > 1:
			continue # this one guards the city
		var options: Array[Vector2i] = []
		for c in HexMap.neighbours(u.pos):
			if not is_blocked(c):
				options.append(c)
		if not options.is_empty():
			u.pos = options.pick_random()

# The rival builds a new unit whenever it can afford one.
# Once the howling starts it builds walls first; otherwise a unit,
# but only if it can still feed its army afterwards.
func rival_build() -> void:
	if not rival.is_alive():
		return
	if turn >= Skoll.WARNING_TURN and rival.walls < MAX_WALLS:
		build_walls(rival)
		return # saving up for walls
	if rival.industry >= UNIT_COST and food_change(rival) - UNIT_FOOD_UPKEEP >= 0:
		build_unit(rival)

# --- Diplomacy --------------------------------------------------------------
func player_propose_pact() -> void:
	if game_over or phase != Phase.PLAYING:
		return
	messages.clear()
	diplomacy.propose_pact() # posts its own message
	update_build_button()
	queue_redraw()

func player_demand(resource: String) -> void:
	if game_over or phase != Phase.PLAYING:
		return
	messages.clear()
	diplomacy.demand(resource) # posts its own message
	update_build_button()
	queue_redraw()

func update_oath_button() -> void:
	var word: String = rival.pact_word
	if diplomacy.pact_active():
		oath_button.text = "%s in force: %d turns left" % [word.capitalize(), diplomacy.pact_turns_left]
	elif diplomacy.is_oathbreaker():
		oath_button.text = "%s refuses: you broke your %s" % [rival.name, word]
	elif diplomacy.action_used:
		oath_button.text = "Diplomacy used this turn"
	else:
		oath_button.text = "Swear %s (%d%% they accept)" % [diplomacy.a_pact(), roundi(diplomacy.accept_chance() * 100)]
	oath_button.disabled = game_over or phase != Phase.PLAYING or not diplomacy.can_propose() or diplomacy.is_oathbreaker()
	for pair in [[demand_food_button, "food"], [demand_industry_button, "industry"]]:
		var button: Button = pair[0]
		var resource: String = pair[1]
		var chance := diplomacy.demand_chance(resource)
		if chance <= 0.0:
			button.text = "Demand %s: they don't have %d" % [resource.capitalize(), Diplomacy.DEMAND_AMOUNT]
		else:
			button.text = "Demand %d %s (%d%% they pay)" % [Diplomacy.DEMAND_AMOUNT, resource.capitalize(), roundi(chance * 100)]
		button.disabled = game_over or phase != Phase.PLAYING or not diplomacy.can_demand() or chance <= 0.0

# --- Walls ------------------------------------------------------------------
# A city improvement: each level costs WALL_COST Industry and adds WALL_DEFENCE.
func build_walls(f: Faction) -> bool:
	if not f.is_alive() or f.walls >= MAX_WALLS or f.industry < WALL_COST:
		return false
	f.industry -= WALL_COST
	f.walls += 1
	return true

func player_build_walls() -> void:
	if game_over or phase != Phase.PLAYING:
		return
	if build_walls(player):
		messages = ["You built walls (level %d): your city's defence +%d." % [player.walls, WALL_DEFENCE]]
	else:
		messages = ["Can't build walls: you need %d Industry (and walls go up to level %d)." % [WALL_COST, MAX_WALLS]]
	update_build_button()
	queue_redraw()

# --- Building units -----------------------------------------------------------
# A new unit appears on the city, or on a free hex next to it if the city is occupied.
# Returns false if there's no room or not enough Industry.
func build_unit(f: Faction) -> bool:
	if not f.is_alive() or f.industry < UNIT_COST:
		return false
	var spot := NO_CELL
	if not is_blocked(f.city_pos):
		spot = f.city_pos
	else:
		for c in HexMap.neighbours(f.city_pos):
			if not is_blocked(c) and not is_city(c):
				spot = c
				break
	if spot == NO_CELL:
		return false
	f.industry -= UNIT_COST
	f.add_unit(spot)
	return true

func player_build_unit() -> void:
	if game_over or phase != Phase.PLAYING:
		return
	if build_unit(player):
		messages = ["You built a new unit (%d Industry). It can move next turn." % UNIT_COST]
		if food_change(player) < 0:
			add_message("Warning: your army now eats more Food than you make (%+d a turn). If your stores run out, a unit will desert." % food_change(player))
		player.units[-1].moves = 0 # a freshly built unit waits a turn, as is usual
	else:
		messages = ["Can't build: you need %d Industry and a free hex at your city." % UNIT_COST]
	update_build_button()
	queue_redraw()

func update_build_button() -> void:
	build_button.disabled = game_over or phase != Phase.PLAYING or player.industry < UNIT_COST
	walls_button.disabled = game_over or phase != Phase.PLAYING or player.industry < WALL_COST or player.walls >= MAX_WALLS
	update_oath_button()
	if player.walls >= MAX_WALLS:
		walls_button.text = "Walls complete (+%d defence)" % (MAX_WALLS * WALL_DEFENCE)
	else:
		walls_button.text = "Build Walls %d/%d (%d Industry)" % [player.walls + 1, MAX_WALLS, WALL_COST]

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
		defender.faction.remove_unit(defender)
		attacker.pos = defender.pos
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

# --- Who is where -----------------------------------------------------------
# The unit standing on this hex (any faction), or null if there's none.
func unit_at(cell: Vector2i) -> Unit:
	for f in factions:
		for u in f.units:
			if u.pos == cell:
				return u
	return null

# True if a unit or Sköll is standing on this hex.
func is_blocked(cell: Vector2i) -> bool:
	return unit_at(cell) != null or skoll.is_at(cell)

func is_city(cell: Vector2i) -> bool:
	for f in factions:
		if f.city_pos == cell:
			return true
	return false

# --- Drawing ----------------------------------------------------------------
func _draw() -> void:
	if phase == Phase.CROSSING:
		return # the Crossing panel is shown instead of the map
	var dark := daughter.is_swallowed() # Sköll swallowed the new sun
	if dark:
		draw_rect(get_viewport_rect(), Color(0.03, 0.03, 0.05))
	# Map: green by default, tinted for each faction's city territory,
	# yellow for hexes the selected player unit can move to,
	# orange-red for an enemy it can attack.
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			var pts := HexMap.hex_points(HexMap.hex_center(c))
			var fill := Color(0.25, 0.45, 0.3)
			for f in factions:
				if f.city_pos != NO_CELL and (c == f.city_pos or HexMap.is_neighbour(f.city_pos, c)):
					fill = f.territory_color
			if dark:
				fill = fill.darkened(0.7)
			if phase == Phase.LANDING:
				if not can_land_at(c):
					fill = fill.darkened(0.6) # too close to the rival
				elif c == hover_cell:
					fill = Color(0.9, 0.75, 0.3)
			if selected and HexMap.is_neighbour(selected.pos, c):
				var other := unit_at(c)
				if skoll.is_at(c) or (other and other.faction != player):
					fill = Color(0.95, 0.45, 0.2) # something to attack
				elif not other:
					fill = Color(0.9, 0.75, 0.3) # free to move
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.1, 0.1, 0.1), 2.0)

	for f in factions:
		if f.city_pos == NO_CELL:
			continue
		var cc := HexMap.hex_center(f.city_pos)
		if f.walls > 0: # a grey ring around the city, thicker for higher walls
			draw_rect(Rect2(cc - Vector2(25, 25), Vector2(50, 50)), Color(0.55, 0.55, 0.6), false, 3.0 * f.walls)
		draw_rect(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), Color(0.95, 0.95, 0.85))
		draw_rect(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), f.unit_color, false, 3.0)
		if daughter.shelters_with(f):
			draw_sun(cc + Vector2(20, -20), 7.0) # a little sun on the city sheltering her

	for f in factions:
		for u in f.units:
			var ring := Color.WHITE if u == selected else Color(0.1, 0.1, 0.1)
			var col := f.unit_color if u.moves > 0 or f != player else f.unit_color.darkened(0.4) # dim = moved
			draw_circle(HexMap.hex_center(u.pos), HexMap.HEX_SIZE * 0.55, ring)
			draw_circle(HexMap.hex_center(u.pos), HexMap.HEX_SIZE * 0.45, col)

	# Sköll: a big black circle with fire inside and the swallowed sun at its heart.
	# After swallowing the Daughter he blazes: bigger, with a glow around him.
	if skoll.active:
		var sc := HexMap.hex_center(skoll.pos)
		var r := HexMap.HEX_SIZE
		if daughter.is_swallowed():
			draw_circle(sc, r * 1.4, Color(1.0, 0.5, 0.1, 0.18))
			draw_circle(sc, r * 1.1, Color(1.0, 0.6, 0.1, 0.3))
			draw_circle(sc, r * 0.9, Color(0.05, 0.05, 0.05))
			draw_circle(sc, r * 0.75, Color(1.0, 0.45, 0.05))
			draw_circle(sc, r * 0.45, Color(1.0, 0.95, 0.6))
		else:
			draw_circle(sc, r * 0.75, Color(0.05, 0.05, 0.05))
			draw_circle(sc, r * 0.6, Color(0.95, 0.4, 0.05))
			draw_circle(sc, r * 0.28, Color(1.0, 0.9, 0.3))

	var font := ThemeDB.fallback_font
	var info := "Turn %d    Food %d (%+d/turn)    Industry %d    Units %d    Strength %d    Doom in %d" % [turn, player.food, food_change(player), player.industry, player.units.size(), player.strength, DOOM_TURN - turn]
	draw_string(font, Vector2(20, 35), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var rival_info := "Rival:  Food %d    Industry %d    Units %d" % [rival.food, rival.industry, rival.units.size()]
	if rival.city_pos == NO_CELL:
		rival_info = "Rival:  city destroyed"
	draw_string(font, Vector2(20, 60), rival_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.6, 0.6))
	if skoll.active and player.city_pos != NO_CELL:
		var skoll_info := "Sköll is %d hexes from your city    Your city's defence: %d" % [HexMap.hex_distance(skoll.pos, player.city_pos), city_defence(player)]
		draw_string(font, Vector2(330, 60), skoll_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.6, 0.2))
	var daughter_info := ""
	if daughter.is_swallowed():
		daughter_info = "Sköll swallowed %s. He is the sun now (Strength %d)." % [SunDaughter.NAME, skoll.strength]
	elif daughter.holder != null:
		daughter_info = "%s %s (Sköll doesn't know which city)    Her Favour: you %d, %s %d" % ["You shelter" if daughter.holder == player else daughter.holder.name + " shelters", SunDaughter.NAME, player.favour, rival.name, rival.favour]
	draw_string(font, Vector2(20, 82), daughter_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.5))

	# Diplomacy panel (right side): trust, the oath, and the memory of promises.
	var dx := 820.0
	var dy := 228.0
	draw_string(font, Vector2(dx, dy), "DIPLOMACY with %s" % rival.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.85, 0.7))
	draw_string(font, Vector2(dx, dy + 22), "Their trust in you: %+d" % diplomacy.trust, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.85))
	if diplomacy.pact_active():
		draw_string(font, Vector2(dx, dy + 42), "%s in force: %d turns left" % [rival.pact_word.capitalize(), diplomacy.pact_turns_left], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.9, 0.6))
	elif diplomacy.is_oathbreaker():
		draw_string(font, Vector2(dx, dy + 42), "You are an %sbreaker until turn %d" % [rival.pact_word, diplomacy.oathbreaker_until], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.5, 0.4))
	draw_string(font, Vector2(dx, dy + 70), "They remember:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))
	for i in diplomacy.history.size():
		draw_multiline_string(font, Vector2(dx, dy + 92 + i * 44), diplomacy.history[i], HORIZONTAL_ALIGNMENT_LEFT, 320, 13, 2, Color(0.8, 0.8, 0.75))

	# Messages, newest at the bottom.
	var screen := get_viewport_rect().size
	for i in messages.size():
		var y := screen.y - 18 - (messages.size() - 1 - i) * 22
		draw_string(font, Vector2(20, y), messages[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.4))

	if game_over:
		draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(0, screen.y / 2 - 60), end_title, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 40, Color(0.95, 0.45, 0.15))
		var lines := end_detail.split("\n")
		for i in lines.size():
			draw_string(font, Vector2(0, screen.y / 2 - 10 + i * 30), lines[i], HORIZONTAL_ALIGNMENT_CENTER, screen.x, 20)
		var totals := "Turn %d    Food %d    Industry %d    Strength %d" % [turn, player.food, player.industry, player.strength]
		draw_string(font, Vector2(0, screen.y / 2 + 10 + lines.size() * 30), totals, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 18, Color(0.7, 0.7, 0.7))

# A small sun: a gold circle with rays.
func draw_sun(center: Vector2, radius: float) -> void:
	for i in 8:
		var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		draw_line(center + dir * radius * 1.2, center + dir * radius * 1.9, Color(1.0, 0.85, 0.3), 2.0)
	draw_circle(center, radius, Color(1.0, 0.9, 0.4))
	draw_circle(center, radius * 0.6, Color(1.0, 1.0, 0.85))

# --- Mouse clicks -----------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if game_over or phase == Phase.CROSSING:
		return
	if phase == Phase.LANDING:
		if event is InputEventMouseMotion:
			var cell := HexMap.cell_at(get_local_mouse_position())
			if cell != hover_cell:
				hover_cell = cell
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			try_land(HexMap.cell_at(get_local_mouse_position()))
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := HexMap.cell_at(get_local_mouse_position())
		var clicked := unit_at(cell)
		if clicked and clicked.faction == player:
			# click your unit to select it (again to deselect); units that already moved can't be picked
			selected = null if clicked == selected or clicked.moves <= 0 else clicked
		elif selected and HexMap.is_neighbour(selected.pos, cell):
			messages.clear()
			if skoll.is_at(cell):
				skoll.attacked_by(selected)
			elif clicked and clicked.faction != player:
				if diplomacy.pact_active() and break_warning_cell != cell:
					# first click only warns; a second click on the same unit breaks the oath
					break_warning_cell = cell
					messages = ["This breaks your %s (Trust %+d, %sbreaker for %d turns, she will see). Click again to attack." % [rival.pact_word, Diplomacy.TRUST_BROKEN, rival.pact_word, Diplomacy.OATHBREAKER_TURNS]]
					queue_redraw()
					return
				if diplomacy.pact_active():
					diplomacy.break_pact()
				break_warning_cell = NO_CELL
				resolve_combat(selected, clicked) # moving into an enemy = attack
			elif not clicked:
				selected.pos = cell
			selected.moves -= 1
			selected = null
		else:
			selected = null
		queue_redraw()
