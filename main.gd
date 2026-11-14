extends Node2D

const HEX_SIZE := 32.0
const COLS := 12
const ROWS := 10
const OFFSET := Vector2(60, 100)
const DOOM_TURN := 20 # the turn the Doom arrives and the game ends
const NO_CELL := Vector2i(-1, -1)
const MIN_LANDING_DISTANCE := 4 # how many hexes away from the rival's city you must land
const Crossing := preload("res://crossing_events.gd") # the Crossing's events live in this file

# The stages of a game, in order:
# CROSSING = journey events, LANDING = choosing where to found your city, PLAYING = the turns.
enum Phase { CROSSING, LANDING, PLAYING }

# Faction (a side's city, unit and resources) is defined in faction.gd.
# The player has no city or unit until they land (see try_land below).
var player := Faction.new("Player", Color(0.3, 0.4, 0.6), Color(0.2, 0.4, 0.9), NO_CELL, NO_CELL)
var rival := Faction.new("Rival", Color(0.6, 0.3, 0.3), Color(0.85, 0.2, 0.2), Vector2i(9, 7), Vector2i(8, 6))
var factions: Array[Faction] = [player, rival]

var phase := Phase.CROSSING
var crossing_step := 0 # which Crossing event we're on
var crossing_panel: VBoxContainer
var crossing_label: Label
var crossing_buttons: VBoxContainer
var hover_cell := NO_CELL # the hex under the mouse while landing
var unit_selected := false
var turn := 1
var game_over := false
var end_turn_button: Button
var message := "" # shown at the bottom of the screen, e.g. combat results

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
	end_turn_button.visible = false
	crossing_panel.visible = true
	message = ""
	show_crossing_step()

func show_crossing_step() -> void:
	for b in crossing_buttons.get_children():
		b.queue_free()
	var tally := "Your people carry:  Food %d    Industry %d    Strength %d" % [player.food, player.industry, player.strength]
	if crossing_step < Crossing.EVENTS.size():
		var event: Dictionary = Crossing.EVENTS[crossing_step]
		crossing_label.text = "THE CROSSING  (%d of %d)\n\n%s\n\n%s" % [crossing_step + 1, Crossing.EVENTS.size(), event["text"], tally]
		for choice in event["choices"]:
			add_crossing_button("%s   (%s)" % [choice["label"], describe_effects(choice["effects"])], choose.bind(choice["effects"]))
	else:
		crossing_label.text = "THE CROSSING\n\nThe branches of Yggdrasil give way. Land lies below.\n\n%s" % tally
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
	crossing_step += 1
	show_crossing_step()

# --- The Landing ------------------------------------------------------------
# The player has no city or unit yet and must pick a hex to settle.
func start_landing() -> void:
	phase = Phase.LANDING
	crossing_panel.visible = false
	end_turn_button.visible = true
	player.city_pos = NO_CELL
	player.unit_pos = NO_CELL
	player.unit_alive = false
	end_turn_button.disabled = true
	message = "Choose where to land: click a hex to found your city."
	queue_redraw()

func can_land_at(cell: Vector2i) -> bool:
	return in_bounds(cell) and hex_distance(cell, rival.city_pos) >= MIN_LANDING_DISTANCE

func try_land(cell: Vector2i) -> void:
	if phase != Phase.LANDING or not can_land_at(cell):
		return
	player.city_pos = cell
	player.unit_pos = cell # the unit starts standing on the new city
	player.unit_alive = true
	phase = Phase.PLAYING
	hover_cell = NO_CELL
	end_turn_button.disabled = false
	message = "Your people have landed. Click your unit to move it."
	queue_redraw()

func end_turn() -> void:
	if game_over or phase != Phase.PLAYING:
		return
	message = ""
	rival_take_turn()
	turn += 1
	for f in factions:
		f.food += 2
		f.industry += 1
		f.unit_moves = 1
		# A destroyed unit returns at its city, as long as the city hex is free.
		if not f.unit_alive and f.city_pos != NO_CELL and not unit_at(f.city_pos):
			f.unit_alive = true
			f.unit_pos = f.city_pos
	unit_selected = false
	if turn >= DOOM_TURN:
		game_over = true
		end_turn_button.disabled = true
	queue_redraw()

# Placeholder rival behaviour: attack the player's unit if it's next door,
# otherwise step to a random free neighbouring hex.
func rival_take_turn() -> void:
	if not rival.unit_alive:
		return
	if player.unit_alive and is_neighbour(rival.unit_pos, player.unit_pos):
		resolve_combat(rival, player)
		return
	var options: Array[Vector2i] = []
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			if is_neighbour(rival.unit_pos, c) and not unit_at(c):
				options.append(c)
	if not options.is_empty():
		rival.unit_pos = options.pick_random()

# Auto-resolve: the attacker wins with chance attacker / (attacker + defender).
# The loser's unit is destroyed; a winning attacker moves into the hex.
func resolve_combat(attacker: Faction, defender: Faction) -> void:
	var chance := float(attacker.strength) / (attacker.strength + defender.strength)
	var target := defender.unit_pos
	var odds := "%d%% chance" % roundi(chance * 100)
	if randf() < chance:
		defender.unit_alive = false
		defender.unit_pos = NO_CELL
		attacker.unit_pos = target
		message = "%s attacked %s and won (%s)." % [attacker.name, defender.name, odds]
	else:
		attacker.unit_alive = false
		attacker.unit_pos = NO_CELL
		message = "%s attacked %s and lost (%s)." % [attacker.name, defender.name, odds]

# Returns the faction whose living unit stands on this hex, or null if it's empty.
func unit_at(cell: Vector2i) -> Faction:
	for f in factions:
		if f.unit_alive and f.unit_pos == cell:
			return f
	return null

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS

func hex_center(cell: Vector2i) -> Vector2:
	var w := sqrt(3.0) * HEX_SIZE
	var h := 1.5 * HEX_SIZE
	return Vector2(w * (cell.x + 0.5 * (cell.y % 2)), h * cell.y) + OFFSET

func hex_points(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(a), sin(a)) * HEX_SIZE)
	return pts

# How many steps apart two hexes are. Converts our offset rows into
# "cube" hex coordinates, where distance is easy to work out.
func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var aq := a.x - (a.y - (a.y & 1)) / 2
	var bq := b.x - (b.y - (b.y & 1)) / 2
	var dq := aq - bq
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2

func is_neighbour(a: Vector2i, b: Vector2i) -> bool:
	return in_bounds(b) and a != b and hex_center(a).distance_to(hex_center(b)) < HEX_SIZE * 1.9

func cell_at(pos: Vector2) -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			var d := pos.distance_to(hex_center(c))
			if d < best_d:
				best_d = d
				best = c
	return best if best_d <= HEX_SIZE else NO_CELL

func _draw() -> void:
	if phase == Phase.CROSSING:
		return # the Crossing panel is shown instead of the map
	# Map: green by default, tinted for each faction's city territory,
	# yellow for hexes the selected player unit can move to,
	# orange-red for an enemy it can attack.
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			var pts := hex_points(hex_center(c))
			var fill := Color(0.25, 0.45, 0.3)
			for f in factions:
				if f.city_pos != NO_CELL and (c == f.city_pos or is_neighbour(f.city_pos, c)):
					fill = f.territory_color
			if phase == Phase.LANDING:
				if not can_land_at(c):
					fill = fill.darkened(0.6) # too close to the rival
				elif c == hover_cell:
					fill = Color(0.9, 0.75, 0.3)
			if unit_selected and is_neighbour(player.unit_pos, c):
				var other := unit_at(c)
				if not other:
					fill = Color(0.9, 0.75, 0.3)
				elif other != player:
					fill = Color(0.95, 0.45, 0.2)
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.1, 0.1, 0.1), 2.0)

	for f in factions:
		if f.city_pos == NO_CELL:
			continue
		var cc := hex_center(f.city_pos)
		draw_rect(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), Color(0.95, 0.95, 0.85))
		draw_rect(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), f.unit_color, false, 3.0)

	for f in factions:
		if not f.unit_alive:
			continue
		var selected := f == player and unit_selected
		var ring := Color.WHITE if selected else Color(0.1, 0.1, 0.1)
		draw_circle(hex_center(f.unit_pos), HEX_SIZE * 0.55, ring)
		draw_circle(hex_center(f.unit_pos), HEX_SIZE * 0.45, f.unit_color)

	var font := ThemeDB.fallback_font
	var info := "Turn %d    Food %d    Industry %d    Strength %d    Moves %d    Doom in %d" % [turn, player.food, player.industry, player.strength, player.unit_moves, DOOM_TURN - turn]
	draw_string(font, Vector2(20, 35), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var rival_info := "Rival:  Food %d    Industry %d" % [rival.food, rival.industry]
	draw_string(font, Vector2(20, 60), rival_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.6, 0.6))
	if message != "":
		draw_string(font, Vector2(20, get_viewport_rect().size.y - 30), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.4))

	if game_over:
		var screen := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.75))
		draw_string(font, Vector2(0, screen.y / 2 - 20), "The Doom has come", HORIZONTAL_ALIGNMENT_CENTER, screen.x, 40, Color(0.9, 0.2, 0.2))
		var totals := "You survived %d turns.    Food %d    Industry %d" % [turn, player.food, player.industry]
		draw_string(font, Vector2(0, screen.y / 2 + 30), totals, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 20)

func _unhandled_input(event: InputEvent) -> void:
	if game_over or phase == Phase.CROSSING:
		return
	if phase == Phase.LANDING:
		if event is InputEventMouseMotion:
			var cell := cell_at(get_local_mouse_position())
			if cell != hover_cell:
				hover_cell = cell
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			try_land(cell_at(get_local_mouse_position()))
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := cell_at(get_local_mouse_position())
		if player.unit_alive and cell == player.unit_pos and player.unit_moves > 0:
			unit_selected = not unit_selected
		elif unit_selected and is_neighbour(player.unit_pos, cell):
			var other := unit_at(cell)
			if other and other != player:
				resolve_combat(player, other) # moving into an enemy = attack
			else:
				player.unit_pos = cell
			player.unit_moves -= 1
			unit_selected = false
		else:
			unit_selected = false
		queue_redraw()
