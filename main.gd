extends Node2D

const HEX_SIZE := 32.0
const COLS := 12
const ROWS := 10
const OFFSET := Vector2(60, 115)
const DOOM_TURN := 20 # survive until this turn and Phase 3 (chaos) begins
const SKOLL_WARNING_TURN := 10 # howling warnings start on this turn
const SKOLL_TURN := 14 # Sköll arrives on this turn
const SKOLL_STRENGTH := 12 # his starting Strength
const SKOLL_SWALLOWED_STRENGTH := 20 # his Strength after swallowing the Sun's Daughter
const INDUSTRY_PER_DEFENCE := 5 # every 5 stored Industry adds 1 to a city's defence

# The Sun's Daughter: a refugee met during the Crossing. If the player takes her in
# she shelters in the player's city; if not, the rival's people take her in.
const DAUGHTER_NAME := "the Sun's Daughter" # change her name here
const DAUGHTER_FOOD := 2 # extra Food per turn for whoever shelters her
const DAUGHTER_INDUSTRY := 2 # extra Industry per turn
const DAUGHTER_DEFENCE := 3 # extra defence for the city sheltering her
enum Daughter { SHELTERED, SWALLOWED }
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
var end_title := "" # big text on the end screen
var end_detail := "" # smaller text under it (can have several lines)
var end_turn_button: Button
var messages: Array[String] = [] # shown at the bottom of the screen, e.g. combat results

# Sköll, the wolf who swallowed the sun. He can't be killed, only driven back.
var skoll_active := false
var skoll_pos := NO_CELL
var skoll_strength := SKOLL_STRENGTH

var daughter_state := Daughter.SHELTERED
var daughter_holder: Faction = null # who shelters her (decided during the Crossing)

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
	daughter_state = Daughter.SHELTERED
	daughter_holder = null
	end_turn_button.visible = false
	crossing_panel.visible = true
	messages.clear()
	show_crossing_step()

func show_crossing_step() -> void:
	for b in crossing_buttons.get_children():
		b.queue_free()
	var tally := "Your people carry:  Food %d    Industry %d    Strength %d" % [player.food, player.industry, player.strength]
	if daughter_holder == player:
		tally += "\nWith you:  %s" % DAUGHTER_NAME
	if crossing_step < Crossing.EVENTS.size():
		var event: Dictionary = Crossing.EVENTS[crossing_step]
		crossing_label.text = "THE CROSSING  (%d of %d)\n\n%s\n\n%s" % [crossing_step + 1, Crossing.EVENTS.size(), event["text"], tally]
		for choice in event["choices"]:
			var effects_text := describe_effects(choice["effects"])
			var label: String = choice["label"] if effects_text == "" else "%s   (%s)" % [choice["label"], effects_text]
			add_crossing_button(label, choose.bind(choice["effects"]))
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
		if key == "daughter":
			parts.append("she joins you")
		else:
			parts.append("%s %+d" % [String(key).capitalize(), effects[key]])
	return ", ".join(parts)

# Apply a choice's effects. Nothing can drop below 0 (Strength below 1).
func choose(effects: Dictionary) -> void:
	player.food = maxi(0, player.food + effects.get("food", 0))
	player.industry = maxi(0, player.industry + effects.get("industry", 0))
	player.strength = maxi(1, player.strength + effects.get("strength", 0))
	if effects.get("daughter", 0) > 0:
		daughter_holder = player
	crossing_step += 1
	show_crossing_step()

# --- The Landing ------------------------------------------------------------
# The player has no city or unit yet and must pick a hex to settle.
func start_landing() -> void:
	phase = Phase.LANDING
	if daughter_holder == null:
		daughter_holder = rival # the player let her pass; the rival's people took her in
	crossing_panel.visible = false
	end_turn_button.visible = true
	player.city_pos = NO_CELL
	player.unit_pos = NO_CELL
	player.unit_alive = false
	end_turn_button.disabled = true
	messages = ["Choose where to land: click a hex to found your city."]
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
	messages = ["Your people have landed. Click your unit to move it."]
	if daughter_holder == player:
		add_message("%s shelters in your city: +%d Food, +%d Industry a turn and +%d city defence." % [DAUGHTER_NAME.capitalize(), DAUGHTER_FOOD, DAUGHTER_INDUSTRY, DAUGHTER_DEFENCE])
	else:
		add_message("%s shelters in %s's city." % [DAUGHTER_NAME.capitalize(), daughter_holder.name])
	queue_redraw()

func end_turn() -> void:
	if game_over or phase != Phase.PLAYING:
		return
	messages.clear()
	rival_take_turn()
	turn += 1
	skoll_take_turn()
	if game_over: # Sköll may have destroyed the player's city or found the Daughter
		return
	for f in factions:
		if f.city_pos == NO_CELL:
			continue # this faction's city has fallen; it's out of the game
		f.food += 2
		f.industry += 1
		if f == daughter_holder:
			f.food += DAUGHTER_FOOD
			f.industry += DAUGHTER_INDUSTRY
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
	if player.unit_alive and is_neighbour(rival.unit_pos, player.unit_pos):
		resolve_combat(rival, player)
		return
	var options: Array[Vector2i] = []
	for c in neighbours(rival.unit_pos):
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

# --- Sköll --------------------------------------------------------------------
# Warns from SKOLL_WARNING_TURN, arrives at the map edge on SKOLL_TURN, then
# walks one hex a turn toward the nearest city and attacks it.
func skoll_take_turn() -> void:
	if turn < SKOLL_WARNING_TURN:
		return
	if turn < SKOLL_TURN:
		var left := SKOLL_TURN - turn
		add_message("Howling in the void... Sköll arrives %s." % ("next turn" if left == 1 else "in %d turns" % left))
		return
	if not skoll_active:
		skoll_active = true
		skoll_pos = random_edge_cell()
		add_message("Sköll, the wolf who swallowed the sun, has followed you through the void!")
		return
	var target := nearest_city_to(skoll_pos)
	if target == null:
		return
	if is_neighbour(skoll_pos, target.city_pos):
		skoll_attacks_city(target)
		return
	# Step to the neighbouring hex that gets closest to the target city.
	var best := NO_CELL
	var best_d := 999
	for c in neighbours(skoll_pos):
		if is_city(c):
			continue
		var d := hex_distance(c, target.city_pos)
		if d < best_d:
			best_d = d
			best = c
	if best == NO_CELL:
		return
	var in_the_way := unit_at(best)
	if in_the_way:
		skoll_attacks_unit(in_the_way)
	else:
		skoll_pos = best

# A city's defence: its unit's Strength if the unit is standing in it,
# plus 1 for every INDUSTRY_PER_DEFENCE Industry stored,
# plus DAUGHTER_DEFENCE if it shelters the Sun's Daughter.
func city_defence(f: Faction) -> int:
	var defence := f.industry / INDUSTRY_PER_DEFENCE
	if f.unit_alive and f.unit_pos == f.city_pos:
		defence += f.strength
	if f == daughter_holder:
		defence += DAUGHTER_DEFENCE
	return defence

# Sköll doesn't know who shelters the Daughter. He only finds out after
# the battle, if she turns out to be in the city he attacked.
func skoll_attacks_city(f: Faction) -> void:
	var defence := city_defence(f)
	var chance := win_chance(skoll_strength, defence)
	var she_is_here := f == daughter_holder
	if randf() < chance:
		add_message("Sköll attacked %s's city (defence %d) and destroyed it (%s)." % [f.name, defence, odds_text(chance)])
		skoll_pos = f.city_pos
		for u in factions: # every unit inside the city dies, not just the owner's
			if u.unit_alive and u.unit_pos == f.city_pos:
				u.unit_alive = false
				u.unit_pos = NO_CELL
		f.city_pos = NO_CELL
		f.unit_alive = false
		f.unit_pos = NO_CELL
		if she_is_here:
			skoll_swallows_daughter()
		if f == player:
			var how := "and swallowed %s. The world goes dark." % DAUGHTER_NAME if she_is_here else "on turn %d." % turn
			end_game("Your city has fallen", "Sköll devoured your people %s" % how)
	else:
		add_message("%s's city (defence %d) drove Sköll back! (He had a %s.)" % [f.name, defence, odds_text(chance)])
		drive_skoll_back()
		if she_is_here:
			var whose := "your city" if f == player else "%s's city" % f.name
			end_game("Sköll has found %s" % DAUGHTER_NAME,
				"He lost the battle, but now he knows she hides in %s.\nPHASE 3 BEGINS EARLY on turn %d: he will charge there again.\n(Phase 3 is not built yet.)" % [whose, turn])

# Sköll becomes the sun: much stronger, and the whole map goes dark.
func skoll_swallows_daughter() -> void:
	daughter_state = Daughter.SWALLOWED
	daughter_holder = null
	skoll_strength = SKOLL_SWALLOWED_STRENGTH
	add_message("Sköll swallowed %s! He is the sun now (Strength %d), and the world goes dark." % [DAUGHTER_NAME, skoll_strength])

func skoll_attacks_unit(f: Faction) -> void:
	var chance := win_chance(skoll_strength, f.strength)
	if randf() < chance:
		add_message("Sköll attacked %s's unit and destroyed it (%s)." % [f.name, odds_text(chance)])
		skoll_pos = f.unit_pos
		f.unit_alive = false
		f.unit_pos = NO_CELL
	else:
		add_message("%s's unit drove Sköll back! (He had a %s.)" % [f.name, odds_text(chance)])
		drive_skoll_back()

func player_attacks_skoll() -> void:
	var chance := win_chance(player.strength, skoll_strength)
	if randf() < chance:
		add_message("You drove Sköll back (%s)!" % odds_text(chance))
		drive_skoll_back()
	else:
		add_message("You attacked Sköll and your unit was destroyed (%s)." % odds_text(chance))
		player.unit_alive = false
		player.unit_pos = NO_CELL

# Sköll can't be killed: losing a fight sends him back to the edge of the map.
func drive_skoll_back() -> void:
	skoll_pos = random_edge_cell()

# A free hex on the edge of the map, at least 3 hexes from every city.
func random_edge_cell() -> Vector2i:
	var options: Array[Vector2i] = []
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			if col != 0 and col != COLS - 1 and row != 0 and row != ROWS - 1:
				continue
			if is_blocked(c) or is_city(c):
				continue
			var far_enough := true
			for f in factions:
				if f.city_pos != NO_CELL and hex_distance(c, f.city_pos) < 3:
					far_enough = false
			if far_enough:
				options.append(c)
	return options.pick_random() if not options.is_empty() else Vector2i(0, 0)

func nearest_city_to(cell: Vector2i) -> Faction:
	var best: Faction = null
	var best_d := 999
	for f in factions:
		if f.city_pos != NO_CELL and hex_distance(cell, f.city_pos) < best_d:
			best_d = hex_distance(cell, f.city_pos)
			best = f
	return best

# --- Map helpers ----------------------------------------------------------------
# Returns the faction whose living unit stands on this hex, or null if it's empty.
func unit_at(cell: Vector2i) -> Faction:
	for f in factions:
		if f.unit_alive and f.unit_pos == cell:
			return f
	return null

# True if a unit or Sköll is standing on this hex.
func is_blocked(cell: Vector2i) -> bool:
	return unit_at(cell) != null or (skoll_active and cell == skoll_pos)

func is_city(cell: Vector2i) -> bool:
	for f in factions:
		if f.city_pos == cell:
			return true
	return false

func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			if is_neighbour(cell, c):
				result.append(c)
	return result

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
	var dark := daughter_state == Daughter.SWALLOWED # Sköll swallowed the new sun
	if dark:
		draw_rect(get_viewport_rect(), Color(0.03, 0.03, 0.05))
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
			if dark:
				fill = fill.darkened(0.7)
			if phase == Phase.LANDING:
				if not can_land_at(c):
					fill = fill.darkened(0.6) # too close to the rival
				elif c == hover_cell:
					fill = Color(0.9, 0.75, 0.3)
			if unit_selected and is_neighbour(player.unit_pos, c):
				var other := unit_at(c)
				if (skoll_active and c == skoll_pos) or (other and other != player):
					fill = Color(0.95, 0.45, 0.2) # something to attack
				elif not other:
					fill = Color(0.9, 0.75, 0.3) # free to move
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.1, 0.1, 0.1), 2.0)

	for f in factions:
		if f.city_pos == NO_CELL:
			continue
		var cc := hex_center(f.city_pos)
		draw_rect(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), Color(0.95, 0.95, 0.85))
		draw_rect(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), f.unit_color, false, 3.0)
		if f == daughter_holder:
			draw_sun(cc + Vector2(20, -20), 7.0) # a little sun on the city sheltering her

	for f in factions:
		if not f.unit_alive:
			continue
		var selected := f == player and unit_selected
		var ring := Color.WHITE if selected else Color(0.1, 0.1, 0.1)
		draw_circle(hex_center(f.unit_pos), HEX_SIZE * 0.55, ring)
		draw_circle(hex_center(f.unit_pos), HEX_SIZE * 0.45, f.unit_color)

	# Sköll: a big black circle with fire inside and the swallowed sun at its heart.
	# After swallowing the Daughter he blazes: bigger, with a glow around him.
	if skoll_active:
		var sc := hex_center(skoll_pos)
		if daughter_state == Daughter.SWALLOWED:
			draw_circle(sc, HEX_SIZE * 1.4, Color(1.0, 0.5, 0.1, 0.18))
			draw_circle(sc, HEX_SIZE * 1.1, Color(1.0, 0.6, 0.1, 0.3))
			draw_circle(sc, HEX_SIZE * 0.9, Color(0.05, 0.05, 0.05))
			draw_circle(sc, HEX_SIZE * 0.75, Color(1.0, 0.45, 0.05))
			draw_circle(sc, HEX_SIZE * 0.45, Color(1.0, 0.95, 0.6))
		else:
			draw_circle(sc, HEX_SIZE * 0.75, Color(0.05, 0.05, 0.05))
			draw_circle(sc, HEX_SIZE * 0.6, Color(0.95, 0.4, 0.05))
			draw_circle(sc, HEX_SIZE * 0.28, Color(1.0, 0.9, 0.3))

	var font := ThemeDB.fallback_font
	var info := "Turn %d    Food %d    Industry %d    Strength %d    Moves %d    Doom in %d" % [turn, player.food, player.industry, player.strength, player.unit_moves, DOOM_TURN - turn]
	draw_string(font, Vector2(20, 35), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var rival_info := "Rival:  Food %d    Industry %d" % [rival.food, rival.industry]
	if rival.city_pos == NO_CELL:
		rival_info = "Rival:  city destroyed"
	draw_string(font, Vector2(20, 60), rival_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.6, 0.6))
	if skoll_active and player.city_pos != NO_CELL:
		var skoll_info := "Sköll is %d hexes from your city    Your city's defence: %d" % [hex_distance(skoll_pos, player.city_pos), city_defence(player)]
		draw_string(font, Vector2(260, 60), skoll_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.6, 0.2))
	var daughter_info := ""
	match daughter_state:
		Daughter.SHELTERED when daughter_holder != null:
			daughter_info = "%s %s (Sköll doesn't know which city)" % ["You shelter" if daughter_holder == player else daughter_holder.name + " shelters", DAUGHTER_NAME]
		Daughter.SWALLOWED:
			daughter_info = "Sköll swallowed %s. He is the sun now (Strength %d)." % [DAUGHTER_NAME, skoll_strength]
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
			messages.clear()
			var other := unit_at(cell)
			if skoll_active and cell == skoll_pos:
				player_attacks_skoll()
			elif other and other != player:
				resolve_combat(player, other) # moving into an enemy = attack
			else:
				player.unit_pos = cell
			player.unit_moves -= 1
			unit_selected = false
		else:
			unit_selected = false
		queue_redraw()

# A small sun: a gold circle with rays.
func draw_sun(center: Vector2, radius: float) -> void:
	for i in 8:
		var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		draw_line(center + dir * radius * 1.2, center + dir * radius * 1.9, Color(1.0, 0.85, 0.3), 2.0)
	draw_circle(center, radius, Color(1.0, 0.9, 0.4))
	draw_circle(center, radius * 0.6, Color(1.0, 1.0, 0.85))
