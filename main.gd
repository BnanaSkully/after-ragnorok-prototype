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

# How each kind of land looks (index = Terrain.Type)
const TERRAIN_COLOURS := [Color(0.42, 0.58, 0.32), Color(0.2, 0.4, 0.22), Color(0.58, 0.5, 0.32), Color(0.5, 0.5, 0.53), Color(0.2, 0.36, 0.62)]

func territory_colour(f: Faction) -> Color:
	return FACTION_COLOURS[f.name][0]

func unit_colour(f: Faction) -> Color:
	return FACTION_COLOURS[f.name][1]

# What the player is doing on screen (not part of the game rules)
var hover_cell := NO_CELL # the hex under the mouse while landing
var selected: Unit = null # the player's unit chosen to move (null = none)
var break_warning_cell := NO_CELL # first click on a unit you've sworn an agreement with only warns
var placing_outpost := false # after clicking "Outpost": the next click on a hex founds it there

# Buttons and panels
var crossing_panel: VBoxContainer
var crossing_label: Label
var crossing_buttons: VBoxContainer
var end_turn_button: Button
var build_button: Button
var scout_button: Button
var outpost_button: Button
var walls_button: Button # "Build...": opens the city buildings panel (walls, granary...)
var city_panel: PanelContainer
var city_buttons: VBoxContainer
var faction_buttons := {} # AI faction -> {"pact": Button, "deal": Button}
var deal_panel: PanelContainer # every deal with one AI faction (demand, trade, gift, pay for peace)
var deal_heading: Label
var deal_buttons: VBoxContainer
var deal_with: Faction = null # whose deals the panel shows
var trade_button: Button # opens the "trade the Sun's Daughter" panel
var trade_panel: PanelContainer
var trade_label: Label
var trade_choices := {} # AI faction -> Button in the trade panel
var play_again_button: Button # shown on the end screen
var offer_panel: PanelContainer # an AI faction's Accept/Refuse pop-up
var offer_label: Label
var offer_heading: Label
var offer_accept_button: Button
var choice_panel: PanelContainer # a ruin or small event: one button per option
var choice_heading: Label
var choice_label: Label
var choice_buttons: VBoxContainer

func _ready() -> void:
	# Build options, each a different trade-off (costs are in Industry).
	end_turn_button = add_button("End Turn", Vector2(PANEL_X, 20), on_end_turn)
	build_button = add_button("Army (%d)" % GameState.UNIT_COST, Vector2(PANEL_X + 90, 20), on_build_unit)
	scout_button = add_button("Scout (%d)" % GameState.SCOUT_COST, Vector2(PANEL_X + 180, 20), on_build_scout)
	outpost_button = add_button("", Vector2(PANEL_X, 58), on_outpost_button)
	walls_button = add_button("Build...", Vector2(PANEL_X + 110, 58), on_open_city)
	trade_button = add_button("Trade her", Vector2(PANEL_X + 240, 58), on_open_trade)
	for b in [build_button, scout_button, outpost_button, walls_button, trade_button]:
		b.add_theme_font_size_override("font_size", 14)
	build_button.tooltip_text = "An army unit: Strength %d, 1 move, eats %d Food a turn." % [state.player.strength, GameState.UNIT_FOOD_UPKEEP]
	scout_button.tooltip_text = "A scout: 2 moves, sees 3 hexes, eats nothing, but Strength %d. Up to %d." % [Unit.SCOUT_STRENGTH, GameState.MAX_SCOUTS]
	outpost_button.tooltip_text = "Found an outpost on a hex you can see, within %d of your city. Income by land: plains +2 Food, forest +1 Food +1 Industry, hills +2 Industry. An enemy at war can take it if nobody guards it." % GameState.OUTPOST_RANGE
	for i in state.ais.size():
		var f: Faction = state.ais[i]
		var y := BLOCK_Y + i * BLOCK_H + 46
		var set := {
			"pact": add_button("", Vector2(PANEL_X, y), on_propose_pact.bind(f)),
			"deal": add_button("Deal...", Vector2(PANEL_X + 120, y), on_open_deals.bind(f)),
		}
		for b in set.values():
			b.add_theme_font_size_override("font_size", 13)
		faction_buttons[f] = set
	play_again_button = add_button("Play Again", Vector2.ZERO, restart)
	play_again_button.add_theme_font_size_override("font_size", 22)
	play_again_button.visible = false
	build_offer_ui()
	build_choice_ui()
	build_deal_ui()
	build_city_ui()
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
	if not state.can_act():
		placing_outpost = false
	update_buttons()
	if state.has_pending_choice():
		offer_panel.visible = false
		show_choice() # a ruin or event comes first; any offer waits behind it
	elif state.has_pending_offer() and not offer_panel.visible:
		show_offer()
	if state.game_over:
		show_end_screen()
	queue_redraw()

func all_game_buttons() -> Array[Button]:
	var list: Array[Button] = [end_turn_button, build_button, scout_button, outpost_button, walls_button, trade_button]
	for set in faction_buttons.values():
		for b in set.values():
			list.append(b)
	return list

func update_buttons() -> void:
	var playing: bool = state.can_act()
	var p := state.player
	end_turn_button.disabled = not playing
	build_button.disabled = not playing or p.industry < GameState.UNIT_COST
	scout_button.disabled = not playing or not state.can_build_scout(p)
	outpost_button.disabled = not playing or (not placing_outpost and (p.industry < GameState.OUTPOST_COST or state.outpost_spots(p).is_empty()))
	outpost_button.text = "Cancel" if placing_outpost else "Outpost (%d)" % GameState.OUTPOST_COST
	walls_button.disabled = not playing
	walls_button.tooltip_text = "City buildings: walls, granary, workshop, watchtower, forge. Each costs Industry once and gives a permanent bonus."
	trade_button.disabled = not playing or not state.can_trade_daughter()
	for f in state.ais:
		var d: Diplomacy = state.relation(f)
		var set: Dictionary = faction_buttons[f]
		var pact: Button = set["pact"]
		var word: String = f.pact_word.capitalize()
		# One button for war and alliance: at war it asks for peace; at peace it
		# proposes the oath (a defensive alliance).
		if not f.is_alive():
			pact.text = "Fallen"
			pact.disabled = true
		elif d.at_war:
			pact.text = "Peace %d%%" % roundi(d.peace_chance() * 100)
			pact.disabled = not playing or not d.can_propose_peace()
		else:
			if d.pact_active():
				pact.text = "%s: %d turns" % [word, d.pact_turns_left]
			elif d.is_oathbreaker():
				pact.text = "They refuse"
			else:
				pact.text = "%s %d%%" % [word, roundi(d.accept_chance() * 100)]
			pact.disabled = not playing or not d.can_propose() or d.is_oathbreaker()
		pact.tooltip_text = "Ask for peace (uses your diplomatic action)." if d.at_war else "%s: a defensive alliance for %d turns. If anyone declares war on one of you, the other joins the war." % [word, Diplomacy.PACT_LENGTH]
		var deal: Button = set["deal"]
		deal.disabled = not playing or not d.can_deal()
		deal.tooltip_text = "Demand, trade, give gifts, or pay for peace (uses your diplomatic action)."

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

func on_build_scout() -> void:
	state.player_build_scout()
	refresh()

# First click: choose where (the possible hexes light up). Clicking again cancels.
func on_outpost_button() -> void:
	placing_outpost = not placing_outpost
	selected = null
	if placing_outpost:
		state.messages = ["Click a highlighted hex to found your outpost there (or click Cancel). You can only choose hexes you can see right now."]
	else:
		state.messages = []
	refresh()

func on_propose_pact(f: Faction) -> void:
	state.player_propose_pact(f)
	refresh()

func on_demand(f: Faction, resource: String) -> void:
	state.player_demand(f, resource)
	close_deals()

# --- City buildings (panel) -------------------------------------------------------------
func build_city_ui() -> void:
	city_panel = PanelContainer.new()
	city_panel.position = Vector2(170, 150)
	city_panel.custom_minimum_size = Vector2(540, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.08)
	style.border_color = Color(0.85, 0.75, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	city_panel.add_theme_stylebox_override("panel", style)
	add_child(city_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	city_panel.add_child(box)
	var heading := Label.new()
	heading.text = "BUILD IN YOUR CITY   (each is bought once; costs are Industry)"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	box.add_child(heading)
	city_buttons = VBoxContainer.new()
	city_buttons.add_theme_constant_override("separation", 6)
	box.add_child(city_buttons)
	city_panel.visible = false

func add_city_option(text: String, enabled: bool, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 15)
	b.disabled = not enabled
	b.pressed.connect(action)
	city_buttons.add_child(b)

func on_open_city() -> void:
	if not state.can_act():
		return
	for b in city_buttons.get_children():
		city_buttons.remove_child(b)
		b.queue_free()
	var p := state.player
	if p.walls >= GameState.MAX_WALLS:
		add_city_option("Walls: complete (+%d defence)" % (GameState.MAX_WALLS * GameState.WALL_DEFENCE), false, func(): pass)
	else:
		add_city_option("Walls %d/%d (%d): +%d city defence" % [p.walls + 1, GameState.MAX_WALLS, GameState.WALL_COST, GameState.WALL_DEFENCE], p.industry >= GameState.WALL_COST, on_city_build.bind(func(): state.player_build_walls()))
	for key in GameState.Buildings.LIST:
		var info: Dictionary = GameState.Buildings.LIST[key]
		if p.buildings.has(key):
			add_city_option("%s: built (%s)" % [info["name"], info["text"]], false, func(): pass)
		else:
			var text := "%s (%d): %s" % [info["name"], info["cost"], info["text"]]
			if p.industry < info["cost"]:
				text += "  (you need %d Industry)" % info["cost"]
			add_city_option(text, state.can_build_building(p, key), on_city_build.bind(func(): state.player_build_building(key)))
	add_city_option("Never mind", true, close_city)
	city_panel.size = Vector2.ZERO
	city_panel.visible = true
	for b in all_game_buttons():
		b.disabled = true

func on_city_build(action: Callable) -> void:
	action.call()
	close_city()

func close_city() -> void:
	city_panel.visible = false
	refresh()

# --- Deals with one AI faction (panel) ------------------------------------------------
func build_deal_ui() -> void:
	deal_panel = PanelContainer.new()
	deal_panel.position = Vector2(170, 150)
	deal_panel.custom_minimum_size = Vector2(540, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.08)
	style.border_color = Color(0.6, 0.85, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	deal_panel.add_theme_stylebox_override("panel", style)
	add_child(deal_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	deal_panel.add_child(box)
	deal_heading = Label.new()
	deal_heading.add_theme_font_size_override("font_size", 16)
	deal_heading.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	box.add_child(deal_heading)
	deal_buttons = VBoxContainer.new()
	deal_buttons.add_theme_constant_override("separation", 6)
	box.add_child(deal_buttons)
	deal_panel.visible = false

func add_deal(text: String, enabled: bool, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 15)
	b.disabled = not enabled
	b.pressed.connect(action)
	deal_buttons.add_child(b)

# Every deal with faction f and its terms, worked out by the rules (diplomacy.gd).
func on_open_deals(f: Faction) -> void:
	var d: Diplomacy = state.relation(f)
	if not state.can_act() or not d.can_deal():
		return
	deal_with = f
	deal_heading.text = "DEALS WITH THE %s   (Trust %+d%s)   Each uses your diplomatic action." % [f.name.to_upper(), d.trust, ", AT WAR" if d.at_war else ""]
	for b in deal_buttons.get_children():
		deal_buttons.remove_child(b)
		b.queue_free()
	var p := state.player
	if d.at_war:
		add_deal("Offer %d Industry for peace (%d%% chance; you keep it if they refuse)" % [Diplomacy.PEACE_TRIBUTE, roundi(d.tribute_peace_chance() * 100)], d.can_offer_tribute(), on_deal.bind(func(): state.player_tribute_for_peace(f)))
	for res in ["food", "industry"]:
		var chance: float = d.demand_chance(res)
		var label := "Demand %d %s" % [Diplomacy.DEMAND_AMOUNT, res.capitalize()]
		label += "  (they have none to give)" if chance <= 0.0 else "  (%d%% they pay; Trust %+d if they pay, %+d if not)" % [roundi(chance * 100), Diplomacy.TRUST_DEMAND_PAID, Diplomacy.TRUST_DEMAND_REFUSED]
		add_deal(label, d.can_demand(), on_deal.bind(func(): state.player_demand(f, res)))
	if not d.at_war:
		if d.pact_active():
			add_deal("Borders: open while you are allies", false, func(): pass)
		elif d.borders_open():
			add_deal("Borders: open for %d more turns" % d.borders_turns_left(), false, func(): pass)
		else:
			add_deal("Ask for open borders for %d turns, both ways (%d%% chance)" % [Diplomacy.BORDERS_LENGTH, roundi(d.borders_chance() * 100)], d.can_ask_borders(), on_deal.bind(func(): state.player_ask_borders(f)))
		for give in ["food", "industry"]:
			var get := d.other_resource(give)
			var amount: int = d.trade_quote(give)
			var label := "Trade %d %s for %d %s" % [Diplomacy.TRADE_AMOUNT, give.capitalize(), amount, get.capitalize()]
			if amount <= 0:
				label = "Trade %d %s for %s  (they have none)" % [Diplomacy.TRADE_AMOUNT, give.capitalize(), get.capitalize()]
			elif p.get(give) < Diplomacy.TRADE_AMOUNT:
				label += "  (you don't have %d)" % Diplomacy.TRADE_AMOUNT
			add_deal(label, amount > 0 and p.get(give) >= Diplomacy.TRADE_AMOUNT, on_deal.bind(func(): state.player_trade(f, give)))
		for res in ["food", "industry"]:
			var gain := d.gift_trust_gain()
			var label := "Give %d %s as a gift (Trust %+d%s)" % [Diplomacy.GIFT_AMOUNT, res.capitalize(), gain, "" if gain > 0 else ": they already trust you enough"]
			add_deal(label, d.can_gift(res), on_deal.bind(func(): state.player_gift(f, res)))
	add_deal("Never mind", true, close_deals)
	deal_panel.size = Vector2.ZERO
	deal_panel.visible = true
	for b in all_game_buttons():
		b.disabled = true

func on_deal(action: Callable) -> void:
	action.call()
	close_deals()

func close_deals() -> void:
	deal_panel.visible = false
	deal_with = null
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
	offer_accept_button.text = {"demand": "Pay", "daughter": "Take her", "peace": "Make peace", "trade": "Trade", "borders": "Open borders"}.get(kind, "Accept")
	offer_panel.visible = true
	update_buttons()

func answer_offer(accept: bool) -> void:
	offer_panel.visible = false
	var r: Diplomacy = state.pending_relation()
	if r:
		r.answer(accept)
	refresh()

# --- Ruins and small events (pop-up with one button per option) -------------------
func build_choice_ui() -> void:
	choice_panel = PanelContainer.new()
	choice_panel.position = Vector2(150, 170)
	choice_panel.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1)
	style.border_color = Color(0.55, 0.75, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	choice_panel.add_theme_stylebox_override("panel", style)
	add_child(choice_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	choice_panel.add_child(box)
	choice_heading = Label.new()
	choice_heading.add_theme_font_size_override("font_size", 16)
	choice_heading.add_theme_color_override("font_color", Color(0.55, 0.75, 0.9))
	box.add_child(choice_heading)
	choice_label = Label.new()
	choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	choice_label.custom_minimum_size = Vector2(520, 0)
	choice_label.add_theme_font_size_override("font_size", 17)
	box.add_child(choice_label)
	choice_buttons = VBoxContainer.new()
	choice_buttons.add_theme_constant_override("separation", 8)
	box.add_child(choice_buttons)
	choice_panel.visible = false

func show_choice() -> void:
	var c: Dictionary = state.pending_choices[0]
	choice_heading.text = c["title"]
	choice_label.text = c["text"]
	for b in choice_buttons.get_children():
		choice_buttons.remove_child(b)
		b.queue_free()
	var options: Array = c["options"]
	for i in options.size():
		var b := Button.new()
		b.text = options[i]["label"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		var problem: String = state.option_problem(options[i]["effects"])
		if problem != "":
			b.text += "  (%s)" % problem
			b.disabled = true
		b.pressed.connect(on_choice.bind(i))
		choice_buttons.add_child(b)
	choice_panel.size = Vector2.ZERO # shrink to fit the new text
	choice_panel.visible = true

func on_choice(i: int) -> void:
	state.answer_choice(i)
	choice_panel.visible = false
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
	if state.game_over or state.phase == GameState.Phase.CROSSING or state.is_waiting() or trade_panel.visible or deal_panel.visible or city_panel.visible:
		return
	if event is InputEventMouseMotion:
		var cell := HexView2D.cell_at(get_local_mouse_position())
		if cell != hover_cell:
			hover_cell = cell # (the landing highlight and the land tooltip use this)
			queue_redraw()
		return
	if state.phase == GameState.Phase.LANDING:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if state.try_land(HexView2D.cell_at(get_local_mouse_position())):
				hover_cell = NO_CELL
			refresh()
		return
	if placing_outpost and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var spot := HexView2D.cell_at(get_local_mouse_position())
			if spot in state.outpost_spots(state.player):
				state.player_build_outpost(spot)
				placing_outpost = false
		else:
			placing_outpost = false # right-click cancels
			state.messages = []
		refresh()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := HexView2D.cell_at(get_local_mouse_position())
		var clicked := state.unit_at(cell)
		if clicked and clicked.faction == state.player:
			# click your unit to select it (again to deselect); units that already moved can't be picked
			selected = null if clicked == selected or clicked.moves <= 0 else clicked
		elif selected and HexMap.is_neighbour(selected.pos, cell):
			var them: Faction = state.war_target(cell)
			if them != null and break_warning_cell != cell:
				# first click only warns; a second click on the same hex declares war
				break_warning_cell = cell
				var d: Diplomacy = state.relation(them)
				if state.unit_at(cell) == null and state.city_owner(cell) == null and state.outpost_owner(cell) == null:
					state.messages = ["The %s borders are CLOSED to you. Entering their lands declares war" % them.name, "(their Trust %+d, everyone else's %+d). Ask for open borders under Deal... Click again to go ahead." % [Diplomacy.TRUST_DECLARED_WAR, Diplomacy.TRUST_WARMONGER]]
				elif state.player.overlord == them.name:
					state.messages = ["The %s are your overlords. Attacking RISES UP against them:" % them.name, "no more tribute, but you are at war with them (Trust %+d). Click again to go ahead." % Diplomacy.TRUST_DECLARED_WAR]
				elif d.pact_active():
					var word: String = them.pact_word
					state.messages = ["The %s are your ALLIES. This breaks your %s and declares war:" % [them.name, word], "Trust %+d, %sbreaker for %d turns, and she will see. Click again to go ahead." % [Diplomacy.TRUST_BROKEN, word, Diplomacy.OATHBREAKER_TURNS]]
				else:
					state.messages = ["You are at peace with the %s. This DECLARES WAR:" % them.name, "their Trust %+d, everyone else's %+d (warmonger). Click again to go ahead." % [Diplomacy.TRUST_DECLARED_WAR, Diplomacy.TRUST_WARMONGER]]
				queue_redraw()
				return
			break_warning_cell = NO_CELL
			var mover := selected
			state.player_unit_act(selected, cell)
			# a scout with a move left stays selected so you can click on again
			selected = mover if mover in state.player.units and mover.moves > 0 and not state.is_waiting() else null
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
	# Map: green by default, tinted for each faction's territory (cities and
	# outposts claim the hexes around them), yellow for hexes the selected
	# player unit can move to, orange-red for an enemy it can attack.
	# Fog of war: never explored = black; explored but out of sight = dimmed.
	var landing := s.phase == GameState.Phase.LANDING
	var outpost_spots: Array[Vector2i] = []
	if placing_outpost:
		outpost_spots = s.outpost_spots(player)
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			var pts := HexView2D.hex_points(HexView2D.hex_center(c))
			var land: int = s.terrain_at(c)
			var fill: Color = TERRAIN_COLOURS[land]
			var explored := landing or s.player_has_explored(c)
			if not landing:
				var owner := s.territory_owner(c)
				if owner != null:
					fill = fill.lerp(territory_colour(owner), 0.55) # territory tints the land
			if dark:
				fill = fill.darkened(0.7)
			if not explored:
				fill = Color(0.07, 0.07, 0.09) # never seen
			elif not landing and not s.player_can_see(c):
				fill = fill.darkened(0.45) # seen before, but you can't see what's here now
			if landing:
				# from the ark you see the shape of the land, not who is on it
				if not s.can_land_at(c):
					fill = fill.darkened(0.6) # too close to another people's fires
				elif c == hover_cell:
					fill = Color(0.9, 0.75, 0.3)
			if c in outpost_spots:
				fill = Color(0.55, 0.8, 0.95) # you could found an outpost here
			if selected and HexMap.is_neighbour(selected.pos, c):
				var other := s.unit_at(c)
				if daughter.is_rogue() and c == daughter.pos and s.player_can_see(c):
					fill = Color(1.0, 0.95, 0.55) # persuade her
				elif (skoll.is_at(c) or (other and other.faction != player)) and s.player_can_see(c):
					fill = Color(0.95, 0.45, 0.2) # something to attack
				elif s.is_city(c) and c != player.city_pos:
					fill = Color(0.95, 0.45, 0.2) # a city you could attack (it would become your tributary)
				elif not other and not (s.is_city(c) and c != player.city_pos) and s.passable(c) and s.can_afford_move(selected, c):
					if s.closed_border(c):
						fill = Color(0.75, 0.45, 0.55) # behind a closed border: entering declares war
					else:
						fill = Color(0.9, 0.75, 0.3) # free to move
			draw_colored_polygon(pts, fill)
			if explored:
				draw_terrain_mark(HexView2D.hex_center(c), land, fill)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.1, 0.1, 0.1), 2.0)
	# (During the Landing nothing below is drawn: you haven't explored anything yet.)

	# Rifts you have found (a dark swirl), and the one Sköll last came through.
	for rift in player.known_rifts:
		draw_rift(HexView2D.hex_center(rift))
	if skoll.revealed_rift != NO_CELL and s.player_can_see(skoll.revealed_rift) and not player.known_rifts.has(skoll.revealed_rift):
		draw_rift(HexView2D.hex_center(skoll.revealed_rift))

	# Ruins not yet searched, once you've seen them: broken columns.
	for r in s.ruins:
		if not r["taken"] and s.player_has_explored(r["cell"]):
			draw_ruins(HexView2D.hex_center(r["cell"]))

	# Outposts: a small flag-square in the owner's colour.
	for f in s.factions:
		for o in f.outposts:
			if not s.player_has_explored(o):
				continue
			var oc := HexView2D.hex_center(o)
			draw_rect(Rect2(oc - Vector2(10, 10) * k, Vector2(20, 20) * k), Color(0.85, 0.8, 0.65))
			draw_rect(Rect2(oc - Vector2(10, 10) * k, Vector2(20, 20) * k), unit_colour(f), false, 3.0)
			draw_line(oc + Vector2(-4, 6) * k, oc + Vector2(-4, -8) * k, Color(0.2, 0.15, 0.1), 2.0)
			draw_colored_polygon(PackedVector2Array([oc + Vector2(-4, -8) * k, oc + Vector2(6, -5) * k, oc + Vector2(-4, -2) * k]), unit_colour(f))

	for f in s.factions:
		if f.city_pos == NO_CELL or not s.player_has_explored(f.city_pos):
			continue # a city you haven't found yet is hidden in the fog
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
			if f != player and not s.player_can_see(u.pos):
				continue # hidden by fog of war
			var ring := Color.WHITE if u == selected else Color(0.1, 0.1, 0.1)
			var col := unit_colour(f) if u.moves > 0 or f != player else unit_colour(f).darkened(0.4) # dim = moved
			var uc := HexView2D.hex_center(u.pos)
			if u.is_scout(): # a scout: a smaller diamond
				var r := HexView2D.HEX_SIZE * 0.5
				var diamond := PackedVector2Array([uc + Vector2(0, -r), uc + Vector2(r * 0.8, 0), uc + Vector2(0, r), uc + Vector2(-r * 0.8, 0)])
				draw_colored_polygon(diamond, ring)
				var inner := PackedVector2Array()
				for v in diamond:
					inner.append(uc + (v - uc) * 0.75)
				draw_colored_polygon(inner, col)
			else:
				draw_circle(uc, HexView2D.HEX_SIZE * 0.55, ring)
				draw_circle(uc, HexView2D.HEX_SIZE * 0.45, col)

	# The Sun's Daughter alone in the open: a bright sun on her hex.
	if daughter.is_rogue() and s.player_can_see(daughter.pos):
		var dc := HexView2D.hex_center(daughter.pos)
		draw_circle(dc, HexView2D.HEX_SIZE * 0.7, Color(1.0, 0.85, 0.3, 0.25))
		draw_sun(dc, 11.0)

	# Sköll: a big black circle with fire inside and the swallowed sun at its heart.
	# After swallowing the Daughter he blazes: bigger, with a glow around him.
	if skoll.active and s.player_can_see(skoll.pos):
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
	var info := "Turn %d   Pop %d   Food %d/%d (%+d)   Industry %d (%+d)   Units %d   Outposts %d   Army %d   Doom in %d" % [s.turn, player.population, player.food, s.growth_cost(player), s.food_change(player), player.industry, s.industry_change(player) - s.tribute_amount(player), player.units.size(), player.outposts.size(), s.army_power(player), GameState.DOOM_TURN - s.turn]
	draw_string(font, Vector2(20, 35), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var line2: Array[String] = [] # second line: tribute you pay, and where Sköll is
	if player.overlord != "":
		line2.append("TRIBUTARY of the %s: %d Industry a turn to them (attack them to rise up)" % [player.overlord, s.tribute_amount(player)])
	if skoll.active and player.city_pos != NO_CELL:
		var where := "%d hexes from yours" % HexMap.hex_distance(skoll.pos, player.city_pos) if s.player_can_see(skoll.pos) else "out of sight"
		line2.append("Sköll hunts %s (%s)   Your defence: %d" % [skoll.target_text(), where, s.city_defence(player)])
	draw_string(font, Vector2(20, 60), "   ".join(line2), HORIZONTAL_ALIGNMENT_LEFT, 780, 16, Color(1.0, 0.6, 0.2))
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
		var seen := "" if s.player_can_see(daughter.pos) else " You can't see where she is."
		daughter_info = "She is ALONE IN THE OPEN! Move a unit onto her to persuade her (your chance %d%%).%s" % [roundi(daughter.persuade_chance(player) * 100), seen]
	draw_string(font, Vector2(20, 82), daughter_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.5))

	# Diplomacy panel (right side): a block per AI faction, then what they remember.
	for i in s.ais.size():
		var f: Faction = s.ais[i]
		var d: Diplomacy = s.relation(f)
		var y := BLOCK_Y + i * BLOCK_H
		var status := "City %d  Units %d  Food %d  Ind %d" % [f.population, f.units.size(), f.food, f.industry] if f.is_alive() else "city destroyed"
		draw_string(font, Vector2(PANEL_X, y + 12), "%s  %s" % [f.name.to_upper(), status], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, unit_colour(f).lightened(0.3))
		# Line 2: war or peace with you (coloured), Trust, and the AI's own wars.
		var stance := "AT WAR with you"
		var stance_col := Color(1.0, 0.4, 0.3)
		if not d.at_war:
			stance_col = Color(0.6, 0.9, 0.6)
			if d.pact_active():
				stance = "ALLIES" # (the button shows how long the oath lasts)
			elif d.in_truce():
				stance = "truce to turn %d" % d.truce_until
			else:
				stance = "at peace"
		if f.overlord == player.name:
			stance = "your TRIBUTARY"
		elif player.overlord == f.name:
			stance = "your OVERLORD"
			stance_col = Color(1.0, 0.6, 0.3)
		if not f.is_alive():
			stance = ""
		draw_string(font, Vector2(PANEL_X, y + 32), stance, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stance_col)
		var line := "Trust %+d" % d.trust
		if d.is_oathbreaker():
			line += "  you broke your %s" % f.pact_word
		if d.rival_broken_oaths > 0:
			line += "  they broke %d" % d.rival_broken_oaths
		var foes: Array[String] = []
		for g in s.ais:
			if s.at_war(f, g):
				foes.append(g.name)
		if not foes.is_empty():
			line += "  war: " + ", ".join(foes)
		if f.overlord != "" and f.overlord != player.name:
			line += "  pays " + f.overlord
		if not d.at_war and not d.pact_active() and d.borders_open():
			line += "  borders open"
		var stance_w := font.get_string_size(stance + "  ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x if stance != "" else 0.0
		draw_string(font, Vector2(PANEL_X + stance_w, y + 32), line, HORIZONTAL_ALIGNMENT_LEFT, 330 - stance_w, 13, Color(0.85, 0.85, 0.85))
	var hy := BLOCK_Y + s.ais.size() * BLOCK_H + 8
	draw_string(font, Vector2(PANEL_X, hy), "They remember:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.7))
	for i in s.diplomacy_log.size():
		draw_multiline_string(font, Vector2(PANEL_X, hy + 18 + i * 36), s.diplomacy_log[i], HORIZONTAL_ALIGNMENT_LEFT, 320, 12, 2, Color(0.8, 0.8, 0.75))

	# Messages, newest at the bottom.
	var screen := get_viewport_rect().size
	for i in s.messages.size():
		var y := screen.y - 18 - (s.messages.size() - 1 - i) * 22
		draw_string(font, Vector2(20, y), s.messages[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.4))

	draw_land_tooltip()
	if s.game_over:
		draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(0, screen.y / 2 - 60), s.end_title, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 40, Color(0.95, 0.45, 0.15))
		var lines := s.end_detail.split("\n")
		for i in lines.size():
			draw_string(font, Vector2(0, screen.y / 2 - 10 + i * 30), lines[i], HORIZONTAL_ALIGNMENT_CENTER, screen.x, 20)
		var totals := "Turn %d    Food %d    Industry %d    Units %d    Army Strength %d" % [s.turn, player.food, player.industry, player.units.size(), s.army_power(player)]
		draw_string(font, Vector2(0, screen.y / 2 + 10 + lines.size() * 30), totals, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 18, Color(0.7, 0.7, 0.7))

# A small mark for the kind of land, darker than its fill: trees, a hill,
# a peak, waves. (Plains have none.)
func draw_terrain_mark(c: Vector2, land: int, fill: Color) -> void:
	var ink := fill.darkened(0.35)
	match land:
		Terrain.Type.FOREST:
			for x in [-10.0, 6.0]:
				var b := c + Vector2(x, 12)
				draw_colored_polygon(PackedVector2Array([b + Vector2(0, -12), b + Vector2(5, 0), b + Vector2(-5, 0)]), ink)
		Terrain.Type.HILLS:
			draw_arc(c + Vector2(-6, 16), 9.0, PI, TAU, 10, ink, 2.5)
			draw_arc(c + Vector2(8, 18), 7.0, PI, TAU, 10, ink, 2.5)
		Terrain.Type.MOUNTAINS:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(13, 12), c + Vector2(-13, 12)]), ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(4, -6), c + Vector2(-4, -6)]), Color(0.92, 0.92, 0.95))
		Terrain.Type.WATER:
			for y in [-5.0, 5.0]:
				draw_arc(c + Vector2(-5, y), 5.0, 0.2, PI - 0.2, 8, fill.lightened(0.3), 1.5)
				draw_arc(c + Vector2(5, y), 5.0, 0.2, PI - 0.2, 8, fill.lightened(0.3), 1.5)

# What the hovered hex's land does, in a small box by the mouse.
func draw_land_tooltip() -> void:
	var s := state
	if hover_cell == NO_CELL or not (s.phase == GameState.Phase.LANDING or s.player_has_explored(hover_cell)):
		return
	var land: int = s.terrain_at(hover_cell)
	var text: String = Terrain.NAMES[land]
	if not Terrain.passable(land):
		text += ": can't be crossed"
	else:
		var bits: Array[String] = []
		if Terrain.MOVE_COST[land] > 1:
			bits.append("%d moves" % Terrain.MOVE_COST[land])
		if Terrain.DEFENCE[land] > 0:
			bits.append("+%d defence" % Terrain.DEFENCE[land])
		bits.append("outpost +%d Food +%d Industry" % [Terrain.OUTPOST_FOOD[land], Terrain.OUTPOST_INDUSTRY[land]])
		text += ": " + ", ".join(bits)
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var at := HexView2D.hex_center(hover_cell) + Vector2(18, -26)
	at.x = minf(at.x, get_viewport_rect().size.x - size.x - 12)
	draw_rect(Rect2(at - Vector2(5, 14), size + Vector2(10, 8)), Color(0.08, 0.08, 0.08, 0.85))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.95, 0.85))

# A rift in the void: a dark swirl.
func draw_rift(rc: Vector2) -> void:
	draw_circle(rc, HexView2D.HEX_SIZE * 0.5, Color(0.12, 0.05, 0.18))
	draw_arc(rc, HexView2D.HEX_SIZE * 0.5, 0, TAU, 24, Color(0.6, 0.3, 0.8), 2.0)
	draw_arc(rc, HexView2D.HEX_SIZE * 0.28, 0.5, TAU * 0.8, 16, Color(0.6, 0.3, 0.8), 2.0)

# Ruins: three broken grey columns on a slab.
func draw_ruins(c: Vector2) -> void:
	var stone := Color(0.72, 0.68, 0.6)
	draw_rect(Rect2(c + Vector2(-13, 7), Vector2(26, 4)), stone)
	for i in 3:
		var h: float = [14.0, 9.0, 12.0][i]
		draw_rect(Rect2(c + Vector2(-11 + i * 8, 7 - h), Vector2(5, h)), stone)
		draw_rect(Rect2(c + Vector2(-11 + i * 8, 7 - h), Vector2(5, h)), Color(0.2, 0.18, 0.15), false, 1.0)

# A small sun: a gold circle with rays.
func draw_sun(center: Vector2, radius: float) -> void:
	for i in 8:
		var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		draw_line(center + dir * radius * 1.2, center + dir * radius * 1.9, Color(1.0, 0.85, 0.3), 2.0)
	draw_circle(center, radius, Color(1.0, 0.9, 0.4))
	draw_circle(center, radius * 0.6, Color(1.0, 1.0, 0.85))
