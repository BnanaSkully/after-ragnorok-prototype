extends Node2D

# The 2D view of the game. It owns no rules: everything about the game lives
# in "state" (game_state.gd). This script only
#   - draws the state on screen (_draw),
#   - builds the buttons and pop-ups and keeps their text up to date,
#   - turns mouse clicks and button presses into calls on the state.
# Screen positions of hexes come from hex_view_2d.gd. To make a 3D view later,
# write a new view like this one; game_state.gd and the rule files stay as they are.

const Crossing := preload("res://crossing_events.gd")
const NO_CELL := HexMap.NO_CELL

var state := GameState.new()

# How each faction looks: [territory colour, unit colour]
const FACTION_COLOURS := {
	"Norse": [Color(0.3, 0.4, 0.6), Color(0.2, 0.4, 0.9)],
	"Japanese": [Color(0.6, 0.3, 0.3), Color(0.85, 0.2, 0.2)],
	"Celtic": [Color(0.25, 0.5, 0.5), Color(0.1, 0.75, 0.65)],
	"Greek": [Color(0.6, 0.52, 0.25), Color(0.95, 0.75, 0.15)],
}

# Right-hand panel: one block per AI faction
const PANEL_X := 820.0
const BLOCK_Y := 100.0 # top of the first faction's block
const BLOCK_H := 100.0 # height of each block

func territory_colour(f: Faction) -> Color:
	return FACTION_COLOURS[f.name][0]

func unit_colour(f: Faction) -> Color:
	return FACTION_COLOURS[f.name][1]

# What the player is doing on screen (not part of the game rules)
var hover_cell := NO_CELL # the hex under the mouse while landing
var selected: Unit = null # the player's unit chosen to move (null = none)
var break_warning_cell := NO_CELL # first click on a unit you've sworn an agreement with only warns

# Buttons and panels
var crossing_panel: VBoxContainer
var crossing_label: Label
var crossing_buttons: VBoxContainer
var end_turn_button: Button
var build_button: Button
var walls_button: Button
var faction_buttons := {} # AI faction -> {"pact": Button, "food": Button, "industry": Button}
var trade_button: Button # opens the "trade the Sun's Daughter" panel
var trade_panel: PanelContainer
var trade_label: Label
var trade_choices := {} # AI faction -> Button in the trade panel
var play_again_button: Button # shown on the end screen
var offer_panel: PanelContainer # an AI faction's Accept/Refuse pop-up
var offer_label: Label
var offer_heading: Label
var offer_accept_button: Button

func _ready() -> void:
	end_turn_button = add_button("End Turn", Vector2(820, 20), on_end_turn)
	build_button = add_button("Build Unit (%d Industry)" % GameState.UNIT_COST, Vector2(920, 20), on_build_unit)
	walls_button = add_button("", Vector2(820, 58), on_build_walls)
	trade_button = add_button("Trade her", Vector2(1055, 58), on_open_trade)
	for i in state.ais.size():
		var f: Faction = state.ais[i]
		var y := BLOCK_Y + i * BLOCK_H + 46
		var set := {
			"pact": add_button("", Vector2(PANEL_X, y), on_propose_pact.bind(f)),
			"food": add_button("", Vector2(PANEL_X + 108, y), on_demand.bind(f, "food")),
			"industry": add_button("", Vector2(PANEL_X + 216, y), on_demand.bind(f, "industry")),
		}
		for b in set.values():
			b.add_theme_font_size_override("font_size", 13)
		faction_buttons[f] = set
	play_again_button = add_button("Play Again", Vector2.ZERO, restart)
	play_again_button.add_theme_font_size_override("font_size", 22)
	play_again_button.visible = false
	build_offer_ui()
	build_trade_ui()
	build_crossing_ui()
	state.start_crossing()
	refresh()

func add_button(text: String, pos: Vector2, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.pressed.connect(action)
	add_child(b)
	return b

# --- Keeping the screen in step with the state --------------------------------
# Called after anything changes: updates panels and buttons, shows the rival's
# pop-up or the end screen if needed, and redraws the map.
func refresh() -> void:
	var crossing := state.phase == GameState.Phase.CROSSING
	crossing_panel.visible = crossing
	for b in all_game_buttons():
		b.visible = not crossing
	if crossing:
		show_crossing_step()
	update_buttons()
	if state.has_pending_offer() and not offer_panel.visible:
		show_offer()
	if state.game_over:
		show_end_screen()
	queue_redraw()

func all_game_buttons() -> Array[Button]:
	var list: Array[Button] = [end_turn_button, build_button, walls_button, trade_button]
	for set in faction_buttons.values():
		for b in set.values():
			list.append(b)
	return list

func update_buttons() -> void:
	var playing: bool = state.can_play() and not state.has_pending_offer()
	var p := state.player
	end_turn_button.disabled = not playing
	build_button.disabled = not playing or p.industry < GameState.UNIT_COST
	walls_button.disabled = not playing or p.industry < GameState.WALL_COST or p.walls >= GameState.MAX_WALLS
	if p.walls >= GameState.MAX_WALLS:
		walls_button.text = "Walls complete (+%d defence)" % (GameState.MAX_WALLS * GameState.WALL_DEFENCE)
	else:
		walls_button.text = "Build Walls %d/%d (%d Industry)" % [p.walls + 1, GameState.MAX_WALLS, GameState.WALL_COST]
	trade_button.disabled = not playing or not state.can_trade_daughter()
	for f in state.ais:
		var d: Diplomacy = state.relation(f)
		var set: Dictionary = faction_buttons[f]
		var pact: Button = set["pact"]
		var word: String = f.pact_word.capitalize()
		if not f.is_alive():
			pact.text = "Fallen"
		elif d.pact_active():
			pact.text = "%s: %d turns" % [word, d.pact_turns_left]
		elif d.is_oathbreaker():
			pact.text = "They refuse"
		else:
			pact.text = "%s %d%%" % [word, roundi(d.accept_chance() * 100)]
		pact.disabled = not playing or not d.can_propose() or d.is_oathbreaker()
		for resource in ["food", "industry"]:
			var button: Button = set[resource]
			var chance: float = d.demand_chance(resource)
			var short := "Food" if resource == "food" else "Industry"
			button.text = "%s: none" % short if chance <= 0.0 else "%s %d%%" % [short, roundi(chance * 100)]
			button.disabled = not playing or not d.can_demand()

func show_end_screen() -> void:
	# The Play Again button sits under the end-screen text (see _draw).
	var screen := get_viewport_rect().size
	var lines := state.end_detail.split("\n").size()
	play_again_button.visible = true
	play_again_button.position = Vector2(screen.x / 2 - 70, screen.y / 2 + 40 + lines * 30)
	selected = null

# Start a fresh game by reloading the scene from scratch.
func restart() -> void:
	get_tree().reload_current_scene()

# --- Button handlers: ask the state to act, then refresh ----------------------
func on_end_turn() -> void:
	state.end_turn()
	selected = null
	break_warning_cell = NO_CELL
	refresh()

func on_build_unit() -> void:
	state.player_build_unit()
	refresh()

func on_build_walls() -> void:
	state.player_build_walls()
	refresh()

func on_propose_pact(f: Faction) -> void:
	state.player_propose_pact(f)
	refresh()

func on_demand(f: Faction, resource: String) -> void:
	state.player_demand(f, resource)
	refresh()

# --- The Crossing screen ------------------------------------------------------
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

func show_crossing_step() -> void:
	for b in crossing_buttons.get_children():
		b.queue_free()
	var p := state.player
	var tally := "Your people carry:  Food %d    Industry %d    Strength %d" % [p.food, p.industry, p.strength]
	tally += "\n%s's Favour toward you: %d    (the other factions' is unknown)" % [SunDaughter.NAME.capitalize(), p.favour]
	if not state.crossing_finished():
		var event: Dictionary = Crossing.EVENTS[state.crossing_step]
		crossing_label.text = "THE CROSSING  (%d of %d)\n\n%s\n\n%s" % [state.crossing_step + 1, Crossing.EVENTS.size(), event["text"], tally]
		for choice in event["choices"]:
			var effects_text := describe_effects(choice["effects"])
			var label: String = choice["label"] if effects_text == "" else "%s   (%s)" % [choice["label"], effects_text]
			add_crossing_button(label, on_choose.bind(choice["effects"]))
	else:
		crossing_label.text = "THE CROSSING\n\nThe branches of Yggdrasil give way. Land lies below.\nWhen you land, %s will choose whose city to shelter in.\n\n%s" % [SunDaughter.NAME, tally]
		add_crossing_button("Begin the Landing", on_begin_landing)

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

func on_choose(effects: Dictionary) -> void:
	state.choose(effects)
	refresh()

func on_begin_landing() -> void:
	state.start_landing()
	refresh()

# --- The rival's offers (pop-up) -----------------------------------------------
func build_offer_ui() -> void:
	offer_panel = PanelContainer.new()
	offer_panel.position = Vector2(170, 190)
	offer_panel.custom_minimum_size = Vector2(520, 0)
	var style := StyleBoxFlat.new() # solid dark box with a gold border, so the map doesn't show through
	style.bg_color = Color(0.1, 0.09, 0.08)
	style.border_color = Color(0.85, 0.7, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	offer_panel.add_theme_stylebox_override("panel", style)
	add_child(offer_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	offer_panel.add_child(box)
	offer_heading = Label.new()
	offer_heading.add_theme_font_size_override("font_size", 16)
	offer_heading.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	box.add_child(offer_heading)
	offer_label = Label.new()
	offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	offer_label.add_theme_font_size_override("font_size", 18)
	box.add_child(offer_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	for accept in [true, false]:
		var b := Button.new()
		b.text = "Accept" if accept else "Refuse"
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(answer_offer.bind(accept))
		row.add_child(b)
		if accept:
			offer_accept_button = b
	offer_panel.visible = false

# While the pop-up is open the player must answer before doing anything else.
func show_offer() -> void:
	var r: Diplomacy = state.pending_relation()
	offer_heading.text = "A MESSAGE FROM THE %s" % r.other.name.to_upper()
	offer_label.text = r.pending_text()
	var kind: String = r.pending.get("type")
	offer_accept_button.text = "Pay" if kind == "demand" else ("Take her" if kind == "daughter" else "Accept")
	offer_panel.visible = true
	update_buttons()

func answer_offer(accept: bool) -> void:
	offer_panel.visible = false
	var r: Diplomacy = state.pending_relation()
	if r:
		r.answer(accept)
	refresh()

# --- Trading the Sun's Daughter (panel) -------------------------------------------
func build_trade_ui() -> void:
	trade_panel = PanelContainer.new()
	trade_panel.position = Vector2(170, 170)
	trade_panel.custom_minimum_size = Vector2(540, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.08)
	style.border_color = Color(1.0, 0.85, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	trade_panel.add_theme_stylebox_override("panel", style)
	add_child(trade_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	trade_panel.add_child(box)
	var heading := Label.new()
	heading.text = "OFFER %s TO ANOTHER FACTION" % SunDaughter.NAME.to_upper()
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(heading)
	trade_label = Label.new()
	trade_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	trade_label.add_theme_font_size_override("font_size", 15)
	box.add_child(trade_label)
	for f in state.ais:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(on_trade.bind(f))
		box.add_child(b)
		trade_choices[f] = b
	var cancel := Button.new()
	cancel.text = "Keep her"
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.pressed.connect(close_trade)
	box.add_child(cancel)
	trade_panel.visible = false

func on_open_trade() -> void:
	if not state.can_trade_daughter():
		return
	trade_label.text = "Her worth depends on her Favour toward them, their fear of Sköll and how strong they already are. If she's worth too little, you must pay them to take her. Being traded costs her Favour toward you (%+d). Uses your diplomatic action." % SunDaughter.TRADED_FAVOUR
	for f in state.ais:
		var b: Button = trade_choices[f]
		var q := state.trade_quote(f)
		if not f.is_alive():
			b.text = "%s: fallen" % f.name
		elif q["refuses"]:
			b.text = "%s: refuses, too afraid of Sköll" % f.name
		elif q["you_pay"] > 0:
			b.text = "%s: you pay them %d Industry to take her" % [f.name, q["you_pay"]]
			if not q["possible"]:
				b.text += " (you can't afford it)"
		elif q["they_pay"] == 0:
			b.text = "%s: they take her, but pay nothing" % f.name
		else:
			b.text = "%s: they pay you %d Industry" % [f.name, q["they_pay"]]
		b.disabled = not q["possible"]
	trade_panel.visible = true
	for b in all_game_buttons():
		b.disabled = true

func on_trade(f: Faction) -> void:
	state.player_trade_daughter(f)
	close_trade()

func close_trade() -> void:
	trade_panel.visible = false
	refresh()

# --- Mouse clicks: turn screen positions into hexes, then ask the state ---------
func _unhandled_input(event: InputEvent) -> void:
	if state.game_over or state.phase == GameState.Phase.CROSSING or state.has_pending_offer() or trade_panel.visible:
		return
	if state.phase == GameState.Phase.LANDING:
		if event is InputEventMouseMotion:
			var cell := HexView2D.cell_at(get_local_mouse_position())
			if cell != hover_cell:
				hover_cell = cell
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if state.try_land(HexView2D.cell_at(get_local_mouse_position())):
				hover_cell = NO_CELL
			refresh()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := HexView2D.cell_at(get_local_mouse_position())
		var clicked := state.unit_at(cell)
		if clicked and clicked.faction == state.player:
			# click your unit to select it (again to deselect); units that already moved can't be picked
			selected = null if clicked == selected or clicked.moves <= 0 else clicked
		elif selected and HexMap.is_neighbour(selected.pos, cell):
			if state.would_break_pact(cell) and break_warning_cell != cell:
				# first click only warns; a second click on the same unit breaks the oath
				break_warning_cell = cell
				var word: String = state.unit_at(cell).faction.pact_word
				state.messages = ["This breaks your %s (Trust %+d, %sbreaker for %d turns, she will see). Click again to attack." % [word, Diplomacy.TRUST_BROKEN, word, Diplomacy.OATHBREAKER_TURNS]]
				queue_redraw()
				return
			break_warning_cell = NO_CELL
			state.player_unit_act(selected, cell)
			selected = null
		else:
			selected = null
		refresh()

# --- Drawing: only reads the state ----------------------------------------------
func _draw() -> void:
	var s := state
	if s.phase == GameState.Phase.CROSSING:
		return # the Crossing panel is shown instead of the map
	var player := s.player
	var k := HexView2D.HEX_SIZE / 32.0 # city drawings were designed for 32-pixel hexes
	var daughter := s.daughter
	var skoll := s.skoll
	var dark := daughter.is_swallowed() # Sköll swallowed the new sun
	if dark:
		draw_rect(get_viewport_rect(), Color(0.03, 0.03, 0.05))
	# Map: green by default, tinted for each faction's city territory,
	# yellow for hexes the selected player unit can move to,
	# orange-red for an enemy it can attack.
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			var pts := HexView2D.hex_points(HexView2D.hex_center(c))
			var fill := Color(0.25, 0.45, 0.3)
			for f in s.factions:
				if f.city_pos != NO_CELL and (c == f.city_pos or HexMap.is_neighbour(f.city_pos, c)):
					fill = territory_colour(f)
			if dark:
				fill = fill.darkened(0.7)
			if s.phase == GameState.Phase.LANDING:
				if not s.can_land_at(c):
					fill = fill.darkened(0.6) # too close to another faction's city
				elif c == hover_cell:
					fill = Color(0.9, 0.75, 0.3)
			if selected and HexMap.is_neighbour(selected.pos, c):
				var other := s.unit_at(c)
				if daughter.is_rogue() and c == daughter.pos:
					fill = Color(1.0, 0.95, 0.55) # persuade her
				elif skoll.is_at(c) or (other and other.faction != player):
					fill = Color(0.95, 0.45, 0.2) # something to attack
				elif not other:
					fill = Color(0.9, 0.75, 0.3) # free to move
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.1, 0.1, 0.1), 2.0)

	# The rift Sköll last came through (a dark swirl). The others stay hidden.
	if skoll.revealed_rift != NO_CELL:
		var rc := HexView2D.hex_center(skoll.revealed_rift)
		draw_circle(rc, HexView2D.HEX_SIZE * 0.5, Color(0.12, 0.05, 0.18))
		draw_arc(rc, HexView2D.HEX_SIZE * 0.5, 0, TAU, 24, Color(0.6, 0.3, 0.8), 2.0)
		draw_arc(rc, HexView2D.HEX_SIZE * 0.28, 0.5, TAU * 0.8, 16, Color(0.6, 0.3, 0.8), 2.0)

	for f in s.factions:
		if f.city_pos == NO_CELL:
			continue
		var cc := HexView2D.hex_center(f.city_pos)
		var half := 20.0 * k
		if f.walls > 0: # a grey ring around the city, thicker for higher walls
			draw_rect(Rect2(cc - Vector2(half + 5, half + 5), Vector2(half * 2 + 10, half * 2 + 10)), Color(0.55, 0.55, 0.6), false, 2.5 * f.walls)
		draw_rect(Rect2(cc - Vector2(half, half), Vector2(half * 2, half * 2)), Color(0.95, 0.95, 0.85))
		draw_rect(Rect2(cc - Vector2(half, half), Vector2(half * 2, half * 2)), unit_colour(f), false, 3.0)
		# city size: a small badge on the bottom-left corner, so a unit in the city doesn't hide it
		draw_circle(cc + Vector2(-half, half), 8.0, Color(0.15, 0.15, 0.15))
		draw_string(ThemeDB.fallback_font, cc + Vector2(-half - 9, half + 5), str(f.population), HORIZONTAL_ALIGNMENT_CENTER, 18, 13, Color.WHITE)
		if daughter.shelters_with(f):
			draw_sun(cc + Vector2(half, -half), 6.0) # a little sun on the city sheltering her

	for f in s.factions:
		for u in f.units:
			var ring := Color.WHITE if u == selected else Color(0.1, 0.1, 0.1)
			var col := unit_colour(f) if u.moves > 0 or f != player else unit_colour(f).darkened(0.4) # dim = moved
			draw_circle(HexView2D.hex_center(u.pos), HexView2D.HEX_SIZE * 0.55, ring)
			draw_circle(HexView2D.hex_center(u.pos), HexView2D.HEX_SIZE * 0.45, col)

	# The Sun's Daughter alone in the open: a bright sun on her hex.
	if daughter.is_rogue():
		var dc := HexView2D.hex_center(daughter.pos)
		draw_circle(dc, HexView2D.HEX_SIZE * 0.7, Color(1.0, 0.85, 0.3, 0.25))
		draw_sun(dc, 11.0)

	# Sköll: a big black circle with fire inside and the swallowed sun at its heart.
	# After swallowing the Daughter he blazes: bigger, with a glow around him.
	if skoll.active:
		var sc := HexView2D.hex_center(skoll.pos)
		var r := HexView2D.HEX_SIZE
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
	var info := "Turn %d   City %d   Food %d/%d (%+d)   Industry %d (%+d)   Units %d   Army Strength %d   Doom in %d" % [s.turn, player.population, player.food, s.growth_cost(player), s.food_change(player), player.industry, s.industry_change(player), player.units.size(), s.army_power(player), GameState.DOOM_TURN - s.turn]
	draw_string(font, Vector2(20, 35), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	if skoll.active and player.city_pos != NO_CELL:
		var skoll_info := "Sköll hunts %s (%d hexes from yours)   Your defence: %d" % [skoll.target_text(), HexMap.hex_distance(skoll.pos, player.city_pos), s.city_defence(player)]
		draw_string(font, Vector2(20, 60), skoll_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.6, 0.2))
	var daughter_info := ""
	if daughter.is_swallowed():
		daughter_info = "Sköll swallowed %s. He is the sun now (Strength %d)." % [SunDaughter.NAME, skoll.strength]
	elif daughter.holder != null:
		var note := "(Sköll doesn't know which city)"
		if daughter.holder == player and player.favour <= SunDaughter.WARN_FAVOUR:
			note = "(UNHAPPY: at Favour %d she leaves)" % SunDaughter.LEAVE_FAVOUR
		elif daughter.holder == player and s.turn < Skoll.ARRIVAL_TURN:
			note = "(for turn %d: defence %d/%d, army %d/%d)" % [Skoll.ARRIVAL_TURN, s.city_defence(player), SunDaughter.READY_DEFENCE, s.army_power(player), SunDaughter.READY_ARMY]
		daughter_info = "%s %s %s    Her Favour toward you: %d" % ["You shelter" if daughter.holder == player else "The " + daughter.holder.name + " shelter", SunDaughter.NAME, note, player.favour]
	if daughter.is_rogue():
		daughter_info = "She is ALONE IN THE OPEN! Move a unit onto her to persuade her (your chance %d%%)." % roundi(daughter.persuade_chance(player) * 100)
	draw_string(font, Vector2(20, 82), daughter_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.5))

	# Diplomacy panel (right side): a block per AI faction, then what they remember.
	for i in s.ais.size():
		var f: Faction = s.ais[i]
		var d: Diplomacy = s.relation(f)
		var y := BLOCK_Y + i * BLOCK_H
		var status := "City %d  Units %d  Food %d  Ind %d" % [f.population, f.units.size(), f.food, f.industry] if f.is_alive() else "city destroyed"
		draw_string(font, Vector2(PANEL_X, y + 12), "%s  %s" % [f.name.to_upper(), status], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, unit_colour(f).lightened(0.3))
		var line := "Trust %+d" % d.trust
		if d.pact_active():
			line += "   %s in force: %d turns" % [f.pact_word, d.pact_turns_left]
		elif d.is_oathbreaker():
			line += "   you broke your %s (until turn %d)" % [f.pact_word, d.oathbreaker_until]
		if d.rival_broken_oaths > 0:
			line += "   they broke %d" % d.rival_broken_oaths
		draw_string(font, Vector2(PANEL_X, y + 32), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.85, 0.85))
	var hy := BLOCK_Y + s.ais.size() * BLOCK_H + 8
	draw_string(font, Vector2(PANEL_X, hy), "They remember:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.7))
	for i in s.diplomacy_log.size():
		draw_multiline_string(font, Vector2(PANEL_X, hy + 18 + i * 36), s.diplomacy_log[i], HORIZONTAL_ALIGNMENT_LEFT, 320, 12, 2, Color(0.8, 0.8, 0.75))

	# Messages, newest at the bottom.
	var screen := get_viewport_rect().size
	for i in s.messages.size():
		var y := screen.y - 18 - (s.messages.size() - 1 - i) * 22
		draw_string(font, Vector2(20, y), s.messages[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.4))

	if s.game_over:
		draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(0, screen.y / 2 - 60), s.end_title, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 40, Color(0.95, 0.45, 0.15))
		var lines := s.end_detail.split("\n")
		for i in lines.size():
			draw_string(font, Vector2(0, screen.y / 2 - 10 + i * 30), lines[i], HORIZONTAL_ALIGNMENT_CENTER, screen.x, 20)
		var totals := "Turn %d    Food %d    Industry %d    Units %d    Army Strength %d" % [s.turn, player.food, player.industry, player.units.size(), s.army_power(player)]
		draw_string(font, Vector2(0, screen.y / 2 + 10 + lines.size() * 30), totals, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 18, Color(0.7, 0.7, 0.7))

# A small sun: a gold circle with rays.
func draw_sun(center: Vector2, radius: float) -> void:
	for i in 8:
		var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		draw_line(center + dir * radius * 1.2, center + dir * radius * 1.9, Color(1.0, 0.85, 0.3), 2.0)
	draw_circle(center, radius, Color(1.0, 0.9, 0.4))
	draw_circle(center, radius * 0.6, Color(1.0, 1.0, 0.85))
