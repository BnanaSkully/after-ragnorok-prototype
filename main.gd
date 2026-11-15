extends Node2D

# The game's main script: runs the flow of a game (Crossing -> Landing -> turns),
# the rival, combat, drawing and mouse clicks.
# Other pieces live in their own files:
#   faction.gd          one side's city, unit and resources
#   hex_map.gd          hex maths (positions, distances, neighbours)
#   skoll.gd            Sköll, the wolf boss
#   sun_daughter.gd     the Sun's Daughter
#   crossing_events.gd  the Crossing's events (text and choices)

const DOOM_TURN := 20 # survive until this turn and Phase 3 (chaos) begins
const INDUSTRY_PER_DEFENCE := 5 # every 5 stored Industry adds 1 to a city's defence
const MIN_LANDING_DISTANCE := 4 # how many hexes away from the rival's city you must land
const NO_CELL := HexMap.NO_CELL
const Crossing := preload("res://crossing_events.gd")

# The stages of a game, in order:
# CROSSING = journey events, LANDING = choosing where to found your city, PLAYING = the turns.
enum Phase { CROSSING, LANDING, PLAYING }

# The player has no city or unit until they land (see try_land below).
var player := Faction.new("Player", Color(0.3, 0.4, 0.6), Color(0.2, 0.4, 0.9), NO_CELL, NO_CELL)
var rival := Faction.new("Rival", Color(0.6, 0.3, 0.3), Color(0.85, 0.2, 0.2), Vector2i(9, 7), Vector2i(8, 6))
var factions: Array[Faction] = [player, rival]
var daughter := SunDaughter.new()
var skoll: Skoll

var phase := Phase.CROSSING
var crossing_step := 0 # which Crossing event we're on
var crossing_panel: VBoxContainer
var crossing_label: Label
var crossing_buttons: VBoxContainer
var hover_cell := NO_CELL # the hex under the mouse while landing
var unit_selected := false
var turn := 1
var game_over := false
var end_title := "" # big text on the end screen
var end_detail := "" # smaller text under it (can have several lines)
var end_turn_button: Button
var messages: Array[String] = [] # shown at the bottom of the screen, e.g. combat results

func _init() -> void:
	skoll = Skoll.new(self)

func _ready() -> void:
	end_turn_button = Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.position = Vector2(700, 20)
	end_turn_button.pressed.connect(end_turn)
	add_child(end_turn_button)
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
	player.unit_pos = NO_CELL
	player.unit_alive = false
	player.food = Crossing.START_FOOD
	player.industry = Crossing.START_INDUSTRY
	daughter.reset(player, rival)
	end_turn_button.visible = false
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
	player.city_pos = NO_CELL
	player.unit_pos = NO_CELL
	player.unit_alive = false
	end_turn_button.disabled = true
	messages = ["Choose where to land: click a hex to found your city."]
	queue_redraw()

func can_land_at(cell: Vector2i) -> bool:
	return HexMap.in_bounds(cell) and HexMap.hex_distance(cell, rival.city_pos) >= MIN_LANDING_DISTANCE

func try_land(cell: Vector2i) -> void:
	if phase != Phase.LANDING or not can_land_at(cell):
		return
	player.city_pos = cell
	player.unit_pos = cell # the unit starts standing on the new city
	player.unit_alive = true
	phase = Phase.PLAYING
	hover_cell = NO_CELL
	end_turn_button.disabled = false
	messages = ["Your people have landed. Click your unit to move it."]
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
		f.food += 2
		f.industry += 1
		if daughter.shelters_with(f):
			f.food += SunDaughter.FOOD
			f.industry += SunDaughter.INDUSTRY
		f.unit_moves = 1
		# A destroyed unit returns at its city, as long as the city hex is free.
		if not f.unit_alive and not is_blocked(f.city_pos):
			f.unit_alive = true
			f.unit_pos = f.city_pos
	unit_selected = false
	if turn >= DOOM_TURN:
		end_game("You survived until the Doom",
			"Sköll howls, and chaos pours out of the void.\nPHASE 3 BEGINS: chaos factions rise and rogues join Sköll.\n(Phase 3 is not built yet.)")
	queue_redraw()

func end_game(title: String, detail: String) -> void:
	game_over = true
	end_turn_button.disabled = true
	unit_selected = false
	end_title = title
	end_detail = detail
	queue_redraw()

func add_message(text: String) -> void:
	messages.append(text)

# Placeholder rival behaviour: attack the player's unit if it's next door,
# otherwise step to a random free neighbouring hex.
func rival_take_turn() -> void:
	if not rival.unit_alive:
		return
	if player.unit_alive and HexMap.is_neighbour(rival.unit_pos, player.unit_pos):
		resolve_combat(rival, player)
		return
	var options: Array[Vector2i] = []
	for c in HexMap.neighbours(rival.unit_pos):
		if not is_blocked(c):
			options.append(c)
	if not options.is_empty():
		rival.unit_pos = options.pick_random()

# --- Combat -----------------------------------------------------------------
# Every fight uses the same rule: the attacker wins with chance
# attack / (attack + defence). A defence of 0 means the attacker always wins.
func win_chance(attack: int, defence: int) -> float:
	if defence <= 0:
		return 1.0
	return float(attack) / (attack + defence)

func odds_text(chance: float) -> String:
	return "%d%% chance" % roundi(chance * 100)

# Unit against unit. The loser's unit is destroyed; a winning attacker moves into the hex.
func resolve_combat(attacker: Faction, defender: Faction) -> void:
	var chance := win_chance(attacker.strength, defender.strength)
	var target := defender.unit_pos
	if randf() < chance:
		defender.unit_alive = false
		defender.unit_pos = NO_CELL
		attacker.unit_pos = target
		add_message("%s attacked %s and won (%s)." % [attacker.name, defender.name, odds_text(chance)])
	else:
		attacker.unit_alive = false
		attacker.unit_pos = NO_CELL
		add_message("%s attacked %s and lost (%s)." % [attacker.name, defender.name, odds_text(chance)])

# A city's defence: its unit's Strength if the unit is standing in it,
# plus 1 for every INDUSTRY_PER_DEFENCE Industry stored,
# plus the Daughter's bonus if it shelters her.
func city_defence(f: Faction) -> int:
	var defence := f.industry / INDUSTRY_PER_DEFENCE
	if f.unit_alive and f.unit_pos == f.city_pos:
		defence += f.strength
	if daughter.shelters_with(f):
		defence += SunDaughter.DEFENCE
	return defence

# --- Who is where -----------------------------------------------------------
# Returns the faction whose living unit stands on this hex, or null if it's empty.
func unit_at(cell: Vector2i) -> Faction:
	for f in factions:
		if f.unit_alive and f.unit_pos == cell:
			return f
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
			if unit_selected and HexMap.is_neighbour(player.unit_pos, c):
				var other := unit_at(c)
				if skoll.is_at(c) or (other and other != player):
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
		draw_rect(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), Color(0.95, 0.95, 0.85))
		draw_rect(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), f.unit_color, false, 3.0)
		if daughter.shelters_with(f):
			draw_sun(cc + Vector2(20, -20), 7.0) # a little sun on the city sheltering her

	for f in factions:
		if not f.unit_alive:
			continue
		var selected := f == player and unit_selected
		var ring := Color.WHITE if selected else Color(0.1, 0.1, 0.1)
		draw_circle(HexMap.hex_center(f.unit_pos), HexMap.HEX_SIZE * 0.55, ring)
		draw_circle(HexMap.hex_center(f.unit_pos), HexMap.HEX_SIZE * 0.45, f.unit_color)

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
	var info := "Turn %d    Food %d    Industry %d    Strength %d    Moves %d    Doom in %d" % [turn, player.food, player.industry, player.strength, player.unit_moves, DOOM_TURN - turn]
	draw_string(font, Vector2(20, 35), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var rival_info := "Rival:  Food %d    Industry %d" % [rival.food, rival.industry]
	if rival.city_pos == NO_CELL:
		rival_info = "Rival:  city destroyed"
	draw_string(font, Vector2(20, 60), rival_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.6, 0.6))
	if skoll.active and player.city_pos != NO_CELL:
		var skoll_info := "Sköll is %d hexes from your city    Your city's defence: %d" % [HexMap.hex_distance(skoll.pos, player.city_pos), city_defence(player)]
		draw_string(font, Vector2(260, 60), skoll_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.6, 0.2))
	var daughter_info := ""
	if daughter.is_swallowed():
		daughter_info = "Sköll swallowed %s. He is the sun now (Strength %d)." % [SunDaughter.NAME, skoll.strength]
	elif daughter.holder != null:
		daughter_info = "%s %s (Sköll doesn't know which city)    Her Favour: you %d, %s %d" % ["You shelter" if daughter.holder == player else daughter.holder.name + " shelters", SunDaughter.NAME, player.favour, rival.name, rival.favour]
	draw_string(font, Vector2(20, 82), daughter_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.5))

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
		if player.unit_alive and cell == player.unit_pos and player.unit_moves > 0:
			unit_selected = not unit_selected
		elif unit_selected and HexMap.is_neighbour(player.unit_pos, cell):
			messages.clear()
			var other := unit_at(cell)
			if skoll.is_at(cell):
				skoll.attacked_by_player()
			elif other and other != player:
				resolve_combat(player, other) # moving into an enemy = attack
			else:
				player.unit_pos = cell
			player.unit_moves -= 1
			unit_selected = false
		else:
			unit_selected = false
		queue_redraw()
