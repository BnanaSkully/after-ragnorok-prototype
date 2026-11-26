extends Node2D

# The 2D view of the game. It owns no rules: everything about the game lives
# in "state" (game_state.gd). This script only
#   - draws the state on screen (_draw),
#   - builds the buttons and pop-ups and keeps their text up to date,
#   - turns mouse clicks and button presses into calls on the state.
# Screen positions of hexes come from hex_view_2d.gd. To make a 3D view later,
# write a new view like this one; game_state.gd and the rule files stay as they are.
#
# The HUD (Nathan's mockup, Endless Legend 2 style): the map fills the screen and
# the HUD sits at its edges. Top left: your banner and ONE goal line (hover it for
# the full status). Left edge: round buttons that each open one panel (Diplomacy,
# Build, Sunna, Chronicle, Settings) and the 2D/3D switch. Right edge: Pop, Food,
# Industry, Army, Land. Bottom right: the End Turn ring with red badges for
# anything waiting for an answer. New messages pop up as short toasts at the top
# and are kept in the Chronicle.

const Crossing := preload("res://crossing_events.gd")
const View3DScene := preload("res://view_3d.tscn")
const NO_CELL := HexMap.NO_CELL

var state := GameState.new()

# How each faction looks: [territory colour, unit colour]
const FACTION_COLOURS := {
	"Norse": [Color(0.3, 0.4, 0.6), Color(0.2, 0.4, 0.9)],
	"Japanese": [Color(0.6, 0.3, 0.3), Color(0.85, 0.2, 0.2)],
	"Celtic": [Color(0.25, 0.5, 0.5), Color(0.1, 0.75, 0.65)],
	"Greek": [Color(0.6, 0.52, 0.25), Color(0.95, 0.75, 0.15)],
}

# HUD look: dark see-through boxes with thin gold lines, round icon buttons.
const HUD_BG := Color(0.05, 0.05, 0.07, 0.86)
const GOLD := Color(0.86, 0.7, 0.4)
const GOLD_DIM := Color(0.55, 0.45, 0.28)
const TEXT := Color(0.93, 0.9, 0.82)
const BADGE_RED := Color(0.8, 0.12, 0.1)
const TOP_BAR_BOTTOM := 56.0 # the goal line ends here: hex tooltips stay below it
const ICON_X := 14.0 # left edge of the icon column
const ICON_SIZE := 52.0
const ICON_Y := 84.0 # top of the first icon
const ICON_GAP := 62.0
const PANEL_POS := Vector2(78, 76) # where a left-edge panel opens (right of the icons)
const PANEL_W := 372.0
const POPUP_POS := Vector2(512, 84) # deals, trading her, city buildings: beside the open panel
const RES_RECT := Rect2(1030, 6, 118, 231) # the resource column (top right)
const END_RING := Rect2(998, 494, 150, 150) # the End Turn button (bottom right), drawn on end_turn_ring.png
const BADGE_SIZE := 34.0
const BADGE_X := 958.0 # badges sit left of the End Turn ring
const TOAST_CENTRE_X := 660.0 # toasts appear here at the top (clear of the goal line and the resource column)
const TOAST_W := 460.0
const TOAST_TIME := 4.0 # seconds a toast stays (it fades in its last second)
const TOAST_TIME_BUSY := 2.5 # ...when more are waiting behind it
const TOAST_SHOWN := 2 # at most this many at once
const TOAST_QUEUE := 6 # older ones are dropped (they are still in the Chronicle)
const CHRONICLE_MAX := 400 # entries kept

# Nathan's UI art (assets/ui, cut from his asset sheet) and the art pass: Cinzel for
# titles, game-icons.net icons (CC BY 3.0, see assets/ui/icons/CREDITS.txt), edge mist.
const UI_DIR := "res://assets/ui/"
const FRAME_MARGIN := 78.0 # panel_frame_plain.png: the knotwork corners, never stretched
const FRAME_PAD := 13.0 # its transparent border
const PANEL_FRAME_SCALE := 0.62 # the frame at this size around the HUD panels
const SMALL_FRAME_SCALE := 0.26 # ...and around the goal line, toasts and the resource column
var ui_tex := {} # name -> Texture2D (frames, rings, medallion, banners)
var icons := {} # name -> Texture2D (assets/ui/icons/*.svg)
var frame_styles := {} # scale -> StyleBoxTexture
var title_font: Font = ThemeDB.fallback_font # Cinzel, once loaded
var mist: ColorRect # the edge mist and void glow (above the map, below the HUD)
var ov: Node2D # the layer the HUD overlay is drawn on (draw_overlay), above the mist
var active_icons := {} # icon button -> it shows the open panel

const ASH_COLOUR := Color(0.36, 0.34, 0.33) # land Sköll turned to ash
const SEASON_COLOUR := Color(0.55, 0.75, 1.0) # the season (Rifts.season_on): rifts glow cold blue
# How each kind of land looks (index = Terrain.Type)
const TERRAIN_COLOURS := [Color(0.42, 0.58, 0.32), Color(0.2, 0.4, 0.22), Color(0.58, 0.5, 0.32), Color(0.5, 0.5, 0.53), Color(0.2, 0.36, 0.62)]

func territory_colour(f: Faction) -> Color:
	return FACTION_COLOURS[f.name][0]

func unit_colour(f: Faction) -> Color:
	return FACTION_COLOURS[f.name][1]

# What the player is doing on screen (not part of the game rules)
const CLICK_SLOP_3D := 12.0 # pixels the pointer may move between press and release and still click (3D view)
var press_pos_3d := Vector2.ZERO # where the last left press started (3D view)
var hover_cell := NO_CELL # the hex under the mouse (landing highlight, tooltips)
var hover_pos := Vector2(-1, -1) # the mouse, for tooltips on the HUD
var top_bar_tips: Array = [] # [Rect2, tooltip text] for each HUD part that explains itself (filled by _draw)
var selected: Unit = null # the player's unit chosen to move (null = none)
var break_warning_cell := NO_CELL # first click on a unit you've sworn an agreement with only warns
var placing_outpost := false # after clicking "Outpost": the next click on a hex founds it there
var view_3d: Node3D = null # the 3D view (view_3d.tscn), made the first time V is pressed
var showing_3d := false # V switches; the 2D map is the default. Buttons and pop-ups stay in both
var open_panel := "" # which left-edge panel is open ("" = none): diplomacy, build, sunna, chronicle, settings
var popups_hidden := false # the player put the waiting pop-up aside to look at the map
var popup_prefer := "" # "offer": a badge asked for the AI's offer rather than the ruin/event first
var chronicle: Array[String] = [] # every message this game, oldest first ("Turn 5: ...")
var toasts: Array = [] # [{"text", "age"}], oldest first: the first TOAST_SHOWN are on screen
var seen_messages: Array[String] = [] # state.messages as last seen (to spot new ones)
var seen_messages_ref: Array = [] # ...and which array that was (the rules sometimes replace it)
var new_game_armed := false # Settings: the first click on "New game" only asks again
var view_chosen := false # the remembered view (3D by default) was applied at the Landing
const SETTINGS_FILE := "user://settings.cfg" # remembered between games: the view (3D or 2D)

# Buttons and panels
var hud: Control # holds every HUD control, so the Crossing can hide them all at once
var crossing_panel: VBoxContainer
var crossing_label: Label
var crossing_buttons: VBoxContainer
var end_turn_button: Button
var view_button: Button # switches between the 2D and 3D views, like V (for phones, which have no keyboard)
var icon_buttons := {} # panel name -> its round button on the left edge
var panels := {} # panel name -> PanelContainer
var badges := {} # "offer" / "request" / "popup" -> round red-badged Button
var build_button: Button
var scout_button: Button
var outpost_button: Button
var queue_army_button: Button # "Queue": adds an army to the city's production queue
var queue_scout_button: Button
var queue_box: VBoxContainer # the production queue (rebuilt by update_queue)
var walls_button: Button # "City buildings...": opens the city buildings panel (walls, granary...)
var build_info: Label
var city_panel: PanelContainer
var city_buttons: VBoxContainer
var faction_buttons := {} # AI faction -> {"pact": Button, "deal": Button}
var faction_labels := {} # AI faction -> {"name", "trust", "extra", "stance": Label}
var remember_label: Label
var sunna_icon: Control
var sunna_status: Label
var sunna_rise: Label
var sunna_requests: Label
var chronicle_label: Label
var chronicle_scroll: ScrollContainer
var new_game_button: Button
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
	load_art()
	mist = ColorRect.new()
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = load("res://assets/shaders/edge_mist.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mist.material = mat
	else:
		mist.color = Color(0, 0, 0, 0)
	add_child(mist)
	ov = Node2D.new()
	ov.draw.connect(draw_overlay)
	add_child(ov)
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE # clicks between the HUD's buttons reach the map
	add_child(hud)
	build_icon_column()
	build_end_turn()
	build_diplomacy_panel()
	build_build_panel()
	build_sunna_panel()
	build_chronicle_panel()
	build_settings_panel()
	play_again_button = add_button("Play Again", Vector2.ZERO, restart)
	play_again_button.add_theme_font_size_override("font_size", 22)
	play_again_button.visible = false
	build_offer_ui()
	build_choice_ui()
	build_deal_ui()
	build_city_ui()
	build_trade_ui()
	build_crossing_ui()
	for panel in [offer_panel, choice_panel, deal_panel, city_panel, trade_panel]:
		panel.add_theme_stylebox_override("panel", frame_style(PANEL_FRAME_SCALE, 40.0))
	for heading in [offer_heading, choice_heading, deal_heading]:
		heading.add_theme_font_override("font", title_font)
	state.start_crossing()
	refresh()

# Nathan's UI pictures, the icons and the title font. Anything missing falls back
# to the shapes drawn in code.
func load_art() -> void:
	for key in ["panel_frame_plain", "end_turn_ring", "icon_button_ring", "sunna_medallion", "banner_norse", "banner_japanese", "banner_celtic", "banner_greek"]:
		var path: String = UI_DIR + key + ".png"
		if ResourceLoader.exists(path):
			ui_tex[key] = load(path)
	for key in ["diplomacy", "build", "chronicle", "settings", "pop", "food", "industry", "army", "land", "offer", "request", "popup", "peace"]:
		var path: String = UI_DIR + "icons/" + key + ".svg"
		if ResourceLoader.exists(path):
			icons[key] = load(path)
	if ResourceLoader.exists("res://assets/fonts/Cinzel.ttf"):
		title_font = load("res://assets/fonts/Cinzel.ttf")

# The panel frame as a 9-slice at a given size: its knotwork corners keep their
# shape (texture margins), only the plain edges and the dark centre stretch.
func frame_style(frame_scale: float, content: float) -> StyleBox:
	var key := "%.2f/%d" % [frame_scale, content]
	if frame_styles.has(key):
		return frame_styles[key]
	var style: StyleBox
	if ui_tex.has("panel_frame_plain"):
		var tex: Texture2D = ui_tex["panel_frame_plain"]
		if frame_scale != 1.0:
			var img: Image = tex.get_image()
			img.resize(roundi(img.get_width() * frame_scale), roundi(img.get_height() * frame_scale), Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
		var st := StyleBoxTexture.new()
		st.texture = tex
		st.set_texture_margin_all(FRAME_MARGIN * frame_scale)
		st.set_expand_margin_all(FRAME_PAD * frame_scale) # the frame's own transparent border sits outside the box
		st.set_content_margin_all(content)
		if content > 20: # wide frames: clear of the knotwork corners at the sides, less tall
			st.content_margin_top = content - 8
			st.content_margin_bottom = content - 8
		style = st
	else:
		var flat := box_style(GOLD, 6, 1)
		flat.set_content_margin_all(content)
		style = flat
	frame_styles[key] = style
	return style

# A texture drawn to fit inside r, keeping its shape (centred).
func draw_fitted(ci: CanvasItem, tex: Texture2D, r: Rect2, tint := Color.WHITE) -> void:
	var size := tex.get_size()
	var k := minf(r.size.x / size.x, r.size.y / size.y)
	var d := size * k
	ci.draw_texture_rect(tex, Rect2(r.position + (r.size - d) / 2, d), false, tint)

# One of the game-icons.net icons, tinted (gold by default), in r.
func draw_game_icon(ci: CanvasItem, key: String, r: Rect2, tint := GOLD) -> bool:
	if not icons.has(key):
		return false
	draw_fitted(ci, icons[key], r, tint)
	return true

func add_button(text: String, pos: Vector2, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.pressed.connect(action)
	add_child(b)
	return b

# --- HUD building blocks ------------------------------------------------------
# A rounded box style: dark, with a thin gold line.
func box_style(border := GOLD_DIM, radius := 6, width := 1, bg := HUD_BG) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style

# A round button whose picture is drawn in code (draw_icon), the size given.
# "active" styles (a gold ring) are swapped in by update_buttons for the open panel.
func round_button(kind: String, rect: Rect2, action: Callable, parent: Node = null) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.custom_minimum_size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	var r := int(rect.size.x / 2)
	if ui_tex.has("icon_button_ring"): # the ring picture is drawn by draw_icon
		for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	else:
		b.add_theme_stylebox_override("normal", box_style(GOLD_DIM, r, 2))
		b.add_theme_stylebox_override("hover", box_style(GOLD, r, 2, Color(0.1, 0.09, 0.08, 0.92)))
		b.add_theme_stylebox_override("pressed", box_style(GOLD, r, 3, Color(0.14, 0.11, 0.07, 0.95)))
		b.add_theme_stylebox_override("disabled", box_style(Color(0.3, 0.28, 0.25), r, 1))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.draw.connect(draw_icon.bind(b, kind))
	b.pressed.connect(action)
	(parent if parent else hud).add_child(b)
	return b

func set_active(b: Button, active: bool) -> void:
	active_icons[b] = active
	if ui_tex.has("icon_button_ring"):
		return # (draw_icon shows it as a glow)
	var r := int(b.size.x / 2)
	b.add_theme_stylebox_override("normal", box_style(GOLD if active else GOLD_DIM, r, 3 if active else 2, Color(0.14, 0.11, 0.07, 0.95) if active else HUD_BG))

# A left-edge panel: a gold-lined box with a title and a close (x) button.
# Returns its content box (a VBoxContainer) to fill.
func make_panel(key: String, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = PANEL_POS
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_theme_stylebox_override("panel", frame_style(PANEL_FRAME_SCALE, 40.0))
	hud.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var label := heading_label(title, 17)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.add_theme_color_override("font_color", GOLD)
	close.pressed.connect(toggle_panel.bind(key))
	head.add_child(close)
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", line_style())
	box.add_child(line)
	panel.visible = false
	panels[key] = panel
	return box

func line_style() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = GOLD_DIM
	s.thickness = 1
	return s

func heading_label(text: String, size := 15) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	return l

func text_label(size := 13, colour := TEXT, wraps := true) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if wraps:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func panel_button(text: String, action: Callable, parent: Node, size := 14) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

# A small Control that draws itself with a function (an emblem, an icon...).
func drawn(size: Vector2, painter: Callable, parent: Node) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): painter.call(c))
	parent.add_child(c)
	return c

# --- The icon column (left edge) ------------------------------------------------
const PANEL_ICONS := [["diplomacy", "Diplomacy: every people, their Trust, war and peace, agreements and deals."], ["build", "Build: armies, scouts, outposts, city buildings, trading Sunna."], ["sunna", "Sunna: her Favour toward you, what she still needs to rise, her requests."], ["chronicle", "Chronicle: everything that has happened this game."], ["settings", "Settings: new game, controls."]]

func build_icon_column() -> void:
	for i in PANEL_ICONS.size():
		var key: String = PANEL_ICONS[i][0]
		var b := round_button(key, Rect2(ICON_X, ICON_Y + i * ICON_GAP, ICON_SIZE, ICON_SIZE), toggle_panel.bind(key))
		b.tooltip_text = PANEL_ICONS[i][1]
		icon_buttons[key] = b

# Only one panel at a time: opening one closes the others; its own button closes it.
func toggle_panel(key: String) -> void:
	open_panel = "" if open_panel == key else key
	new_game_armed = false
	if open_panel == "chronicle":
		scroll_chronicle_down.call_deferred()
	refresh()

func scroll_chronicle_down() -> void:
	chronicle_scroll.scroll_vertical = int(chronicle_scroll.get_v_scroll_bar().max_value)

# --- End Turn (bottom right) and its badges -----------------------------------------
func build_end_turn() -> void:
	end_turn_button = round_button("end_turn", END_RING, on_end_turn)
	end_turn_button.text = "End Turn"
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		end_turn_button.add_theme_color_override(c, Color(0, 0, 0, 0)) # (drawn by draw_icon)
	for kind in ["offer", "request", "popup"]:
		var b := round_button(kind, Rect2(BADGE_X, 0, BADGE_SIZE, BADGE_SIZE), on_badge.bind(kind))
		b.tooltip_text = {"offer": "An offer from another people is waiting for your answer.", "request": "Sunna asks something of you.", "popup": "A discovery or event is waiting for your choice."}[kind]
		badges[kind] = b

# How many of each kind of question wait for the player.
func badge_count(kind: String) -> int:
	match kind:
		"offer":
			return state.relations.filter(func(r): return r.has_pending()).size()
		"request":
			return state.pending_choices.filter(is_sunna_request).size()
		_:
			return state.pending_choices.filter(func(c): return not is_sunna_request(c)).size()

func is_sunna_request(c: Dictionary) -> bool:
	return c["options"].any(func(o): return o["effects"].has("her_favour"))

func on_badge(kind: String) -> void:
	popups_hidden = false
	popup_prefer = "offer" if kind == "offer" else ""
	refresh()

# --- Diplomacy panel ---------------------------------------------------------------
func build_diplomacy_panel() -> void:
	var box := make_panel("diplomacy", "DIPLOMACY")
	for f in state.ais:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		drawn(Vector2(36, 50), func(c: Control): draw_banner(c, Rect2(0, 0, 36, 50), f), row)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name_label := text_label(15, unit_colour(f).lightened(0.35), false)
		name_label.text = f.name.to_upper()
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS # (for its tooltip)
		info.add_child(name_label)
		var trust := text_label(13, TEXT, false)
		info.add_child(trust)
		var extra := text_label(11, Color(0.7, 0.7, 0.68))
		extra.custom_minimum_size = Vector2(110, 0)
		info.add_child(extra)
		var stance_box := VBoxContainer.new()
		stance_box.custom_minimum_size = Vector2(64, 0)
		stance_box.add_theme_constant_override("separation", 0)
		row.add_child(stance_box)
		var stance := text_label(11, TEXT, false)
		var icon := drawn(Vector2(64, 26), func(c: Control): draw_stance(c, f), stance_box)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stance_box.add_child(stance)
		var actions := VBoxContainer.new()
		actions.custom_minimum_size = Vector2(108, 0)
		actions.add_theme_constant_override("separation", 4)
		row.add_child(actions)
		var pact := panel_button("", on_propose_pact.bind(f), actions, 12)
		pact.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var deal := panel_button("Deal...", on_open_deals.bind(f), actions, 12)
		deal.alignment = HORIZONTAL_ALIGNMENT_CENTER
		faction_buttons[f] = {"pact": pact, "deal": deal}
		faction_labels[f] = {"name": name_label, "trust": trust, "extra": extra, "stance": stance}
		var line := HSeparator.new()
		line.add_theme_stylebox_override("separator", line_style())
		box.add_child(line)
	box.add_child(heading_label("THEY REMEMBER", 13))
	remember_label = text_label(12, Color(0.82, 0.8, 0.74))
	box.add_child(remember_label)

func update_diplomacy_panel(playing: bool) -> void:
	var p := state.player
	for f in state.ais:
		var d: Diplomacy = state.relation(f)
		var labels: Dictionary = faction_labels[f]
		var buttons: Dictionary = faction_buttons[f]
		var pact: Button = buttons["pact"]
		var word: String = f.pact_word.capitalize()
		(labels["name"] as Label).tooltip_text = "City %d  Units %d  Food %d  Industry %d" % [f.population, f.units.size(), f.food, f.industry] if f.is_alive() else "Their city was destroyed."
		var trust: Label = labels["trust"]
		trust.text = "TRUST %+d" % d.trust
		trust.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if d.trust > 0 else (Color(1.0, 0.45, 0.35) if d.trust < 0 else TEXT))
		var notes: Array[String] = []
		if d.is_oathbreaker():
			notes.append("you broke your %s" % f.pact_word)
		if d.rival_broken_oaths > 0:
			notes.append("they broke %d" % d.rival_broken_oaths)
		var foes: Array[String] = []
		for g in state.ais:
			if state.at_war(f, g):
				foes.append(g.name)
		if not foes.is_empty():
			notes.append("war: " + ", ".join(foes))
		if f.overlord != "" and f.overlord != p.name:
			notes.append("pays " + f.overlord)
		if not d.at_war and not d.pact_active() and d.borders_open():
			notes.append("borders open")
		(labels["extra"] as Label).text = ", ".join(notes)
		(labels["extra"] as Label).visible = not notes.is_empty()
		var stance: Label = labels["stance"]
		stance.text = stance_text(f)
		stance.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3) if d.at_war or p.overlord == f.name else Color(0.55, 0.85, 0.6))
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
		pact.tooltip_text = "Ask for peace (uses your diplomatic action)." if d.at_war else "%s: a defensive alliance for %d turns. If anyone declares war on one of you, the other joins the war. Uses your diplomatic action." % [word, Diplomacy.PACT_LENGTH]
		var deal: Button = buttons["deal"]
		deal.disabled = not playing or not d.can_deal()
		deal.tooltip_text = "Demand, trade, give gifts, ask for open borders, or pay for peace (uses your diplomatic action)."
	remember_label.text = "\n".join(state.diplomacy_log.map(func(e): return "◆ " + e)) if not state.diplomacy_log.is_empty() else "Nothing yet."

func stance_text(f: Faction) -> String:
	var d: Diplomacy = state.relation(f)
	if not f.is_alive():
		return "FALLEN"
	if f.overlord == state.player.name:
		return "TRIBUTARY"
	if state.player.overlord == f.name:
		return "OVERLORD"
	if d.at_war:
		return "WAR"
	if d.pact_active():
		return "ALLIES"
	if d.in_truce():
		return "TRUCE T%d" % d.truce_until
	return "PEACE"

# --- Build panel -----------------------------------------------------------------------
func build_build_panel() -> void:
	var box := make_panel("build", "BUILD")
	build_info = text_label(13, Color(0.8, 0.78, 0.7))
	box.add_child(build_info)
	var row := buy_row(box)
	build_button = panel_button("Army (%d)" % GameState.UNIT_COST, on_build_unit, row)
	build_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_army_button = panel_button("Queue", on_queue.bind("army"), row)
	row = buy_row(box)
	scout_button = panel_button("Scout (%d)" % GameState.SCOUT_COST, on_build_scout, row)
	scout_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_scout_button = panel_button("Queue", on_queue.bind("scout"), row)
	outpost_button = panel_button("", on_outpost_button, box)
	walls_button = panel_button("City buildings...", on_open_city, box)
	trade_button = panel_button("Trade %s..." % SunDaughter.NAME, on_open_trade, box)
	scout_button.tooltip_text = "A scout: 2 moves, sees 3 hexes, costs %d Gold a turn, but Strength %d. Up to %d." % [GameState.SCOUT_GOLD, Unit.SCOUT_STRENGTH, GameState.MAX_SCOUTS]
	outpost_button.tooltip_text = "Found an outpost on a hex you can see, within %d of your city. Income by land: plains +2 Food, forest +1 Food +1 Industry, hills +2 Industry. An enemy at war can take it if nobody guards it." % GameState.OUTPOST_RANGE
	walls_button.tooltip_text = "City buildings: walls, granary, workshop, watchtower, forge, barracks. Each costs Industry once and gives a permanent bonus."
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", line_style())
	box.add_child(line)
	box.add_child(heading_label("QUEUE", 14))
	queue_box = VBoxContainer.new()
	queue_box.add_theme_constant_override("separation", 0)
	box.add_child(queue_box)
	trade_button.tooltip_text = "Offer %s to another people (from turn %d, while she shelters with you). Uses your diplomatic action." % [SunDaughter.NAME, SunDaughter.TRADE_TURN]

func buy_row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row

# The production queue in the Build panel: what the city works on, how far
# along it is, each item with an x to take it out, and Finish now.
func update_queue(playing: bool) -> void:
	for c in queue_box.get_children():
		queue_box.remove_child(c)
		c.queue_free()
	var p := state.player
	var head := buy_row(queue_box)
	var info := text_label(13, Color(0.8, 0.78, 0.7))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	if p.queue.is_empty():
		info.text = "Empty. Queue lets your city build over the next turns: each turn's Industry goes into the queue instead of your store."
		return
	var front := state.queue_front(p)
	if front < 0:
		info.text = "Waiting (%s): Industry goes to the store." % state.item_blocked(p, p.queue[0])
	else:
		var key: String = p.queue[front]
		var turns := state.queue_turns(p)
		info.text = "%s %d/%d, %s" % [state.item_name(key), mini(p.production, state.item_cost(key)), state.item_cost(key), "done in %d turn%s" % [turns, "" if turns == 1 else "s"] if turns > 0 else "no Industry coming in"]
		var cost := state.hurry_cost(p)
		var hurry := panel_button("Finish now (%d)" % cost, on_hurry, head, 13)
		hurry.disabled = not playing or p.industry < cost
		hurry.tooltip_text = "Pay the %d Industry the %s still needs from your store (%d) and finish it this turn." % [cost, state.item_name(key), p.industry]
	for i in p.queue.size():
		var key: String = p.queue[i]
		var row := buy_row(queue_box)
		var l := text_label(14, GOLD if i == front else TEXT, false)
		var blocked := state.item_blocked(p, key)
		l.text = "%d. %s (%d)%s" % [i + 1, state.item_name(key), state.item_cost(key), "  waits: %s" % blocked if blocked != "" else ""]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var x := panel_button("×", on_unqueue.bind(i), row, 14)
		x.flat = true
		x.tooltip_text = "Take it out of the queue (the Industry already in stays for the next item; taking the last one out gives it back to your store)."
		x.disabled = not playing

func on_queue(key: String) -> void:
	state.player_queue(key)
	refresh()

func on_unqueue(index: int) -> void:
	state.player_unqueue(index)
	refresh()

func on_hurry() -> void:
	state.player_hurry()
	refresh()

# --- Sunna panel -------------------------------------------------------------------------
func build_sunna_panel() -> void:
	var box := make_panel("sunna", SunDaughter.NAME.to_upper())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	sunna_icon = drawn(Vector2(64, 64), func(c: Control): draw_favour_sun(c, c.size / 2, 26.0, 13), row)
	sunna_status = text_label(13)
	sunna_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sunna_status)
	box.add_child(heading_label("TO RISE", 13))
	sunna_rise = text_label(13)
	box.add_child(sunna_rise)
	box.add_child(heading_label("HER REQUESTS", 13))
	sunna_requests = text_label(13)
	box.add_child(sunna_requests)

func update_sunna_panel() -> void:
	var s := state
	var p := s.player
	var daughter := s.daughter
	sunna_status.text = sunna_line()
	var rise: Array[String] = []
	if daughter.is_risen() or daughter.is_swallowed():
		rise.append("It is too late for that." if daughter.is_swallowed() else "She has risen.")
	else:
		rise.append("From turn %d, her protector needs:" % GameState.RISE_TURN)
		rise.append("• her Favour %d+ (feeding your people raises it only to %d)" % [SunDaughter.RISE_FAVOUR, SunDaughter.FED_FAVOUR_CAP])
		rise.append("• another people to recognise her (Trust %d+ or an oath)" % SunDaughter.RECOGNISE_TRUST)
		rise.append("• her city to hold against one of Sköll's attacks")
		if daughter.holder == p:
			var missing := s.rise_missing(p)
			rise.append("Still missing: %s." % ", ".join(missing) if not missing.is_empty() else "You have all three.")
		if daughter.holder == p and s.turn < Skoll.ARRIVAL_TURN:
			rise.append("For turn %d she wants: defence %d/%d, army %d/%d." % [Skoll.ARRIVAL_TURN, s.city_defence(p), SunDaughter.READY_DEFENCE, s.army_power(p), SunDaughter.READY_ARMY])
	sunna_rise.text = "\n".join(rise)
	if daughter.holder == p and daughter.state == SunDaughter.State.SHELTERED:
		sunna_requests.text = "Every %d turns from turn %d she asks something of you (next: turn %d). Grant it: Favour %+d. Refuse: %+d." % [SunDaughter.REQUEST_GAP, SunDaughter.REQUEST_FROM, maxi(s.next_request_turn, s.turn), SunDaughter.REQUEST_GRANTED, SunDaughter.REQUEST_REFUSED]
	else:
		sunna_requests.text = "She asks things only of the people who shelter her."

# --- Chronicle and Settings panels ---------------------------------------------------------
func build_chronicle_panel() -> void:
	var box := make_panel("chronicle", "CHRONICLE")
	chronicle_scroll = ScrollContainer.new()
	chronicle_scroll.custom_minimum_size = Vector2(PANEL_W - 80, 390)
	chronicle_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(chronicle_scroll)
	chronicle_label = text_label(13, Color(0.88, 0.85, 0.76))
	chronicle_label.custom_minimum_size = Vector2(PANEL_W - 96, 0)
	chronicle_scroll.add_child(chronicle_label)

func build_settings_panel() -> void:
	var box := make_panel("settings", "SETTINGS")
	view_button = panel_button("", toggle_3d, box)
	new_game_button = panel_button("New game", on_new_game, box)
	var help := text_label(13, Color(0.8, 0.78, 0.7))
	help.text = "V also switches the view (remembered for your next game; 2D is lighter on slow phones).\nIn 3D: drag (or WASD, or one finger) to move, the wheel or a pinch to zoom.\nHover anything to see what it is; on a phone, press and hold."
	box.add_child(help)
	var credits := text_label(11, Color(0.65, 0.63, 0.58))
	credits.text = "Credits. Icons: game-icons.net (Lorc, Delapouite and others), CC BY 3.0. Font: Cinzel, SIL Open Font License. UI art: Nathan."
	box.add_child(credits)

func on_new_game() -> void:
	if new_game_armed:
		restart()
		return
	new_game_armed = true
	new_game_button.text = "Click again to give up this game and start anew"

# --- Messages: toasts and the Chronicle ---------------------------------------------------
# New lines in state.messages become toasts and Chronicle entries. (The rules
# replace or clear the list; whatever wasn't there last time is new.)
func capture_messages() -> void:
	var now: Array[String] = state.messages
	var fresh: Array[String] = []
	if is_same(now, seen_messages_ref) and now.size() >= seen_messages.size() and now.slice(0, seen_messages.size()) == seen_messages:
		fresh = now.slice(seen_messages.size())
	elif not (is_same(now, seen_messages_ref) and now == seen_messages):
		fresh = now.duplicate()
	seen_messages_ref = now
	seen_messages = now.duplicate()
	# a sentence split over two lines (some warnings) becomes one entry
	var joined: Array[String] = []
	for line in fresh:
		if line.strip_edges() == "":
			continue
		if not joined.is_empty() and not joined[-1].strip_edges().right(1) in [".", "!", "?", ")", "\""]:
			joined[-1] += " " + line.strip_edges()
		else:
			joined.append(line.strip_edges())
	for line in joined:
		var when := "Landing" if state.phase == GameState.Phase.LANDING else "Turn %d" % state.turn
		chronicle.append("%s: %s" % [when, line])
		toasts.append({"text": line, "age": 0.0})
	if chronicle.size() > CHRONICLE_MAX:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_MAX)
	if toasts.size() > TOAST_QUEUE:
		toasts = toasts.slice(toasts.size() - TOAST_QUEUE)
	if not joined.is_empty():
		chronicle_label.text = "\n".join(chronicle)
		queue_redraw()

func _process(delta: float) -> void:
	capture_messages()
	var screen := get_viewport_rect().size
	if mist.size != screen:
		mist.size = screen
		if mist.material:
			(mist.material as ShaderMaterial).set_shader_parameter("aspect", screen.x / maxf(1.0, screen.y))
	if not toasts.is_empty():
		var life := TOAST_TIME_BUSY if toasts.size() > TOAST_SHOWN else TOAST_TIME
		for i in mini(TOAST_SHOWN, toasts.size()):
			toasts[i]["age"] += delta
		toasts = toasts.filter(func(t): return t["age"] < life)
		queue_redraw()
	elif showing_3d:
		queue_redraw() # the borders and banners follow the 3D camera

# --- Keeping the screen in step with the state --------------------------------
# Called after anything changes: updates panels and buttons, shows the rival's
# pop-up or the end screen if needed, and redraws the map.
func refresh() -> void:
	var crossing := state.phase == GameState.Phase.CROSSING
	crossing_panel.visible = crossing
	hud.visible = not crossing
	if crossing:
		show_crossing_step()
	if not state.can_act():
		placing_outpost = false
	if not state.is_waiting():
		popups_hidden = false
		popup_prefer = ""
	if not view_chosen and not crossing:
		view_chosen = true
		if is_real_game() and remembered_3d() and not showing_3d:
			toggle_3d() # 3D is the default view; Settings (or V) switches, and it's remembered
			return
	capture_messages()
	show_popup()
	for key in panels:
		panels[key].visible = key == open_panel and not crossing
	update_buttons()
	if state.game_over:
		show_end_screen()
	queue_redraw()

# The waiting ruin/event or AI offer as a pop-up (unless the player put it aside).
func show_popup() -> void:
	var want_offer := state.has_pending_offer() and (popup_prefer == "offer" or not state.has_pending_choice())
	if popups_hidden or state.game_over or not state.is_waiting():
		offer_panel.visible = false
		choice_panel.visible = false
		return
	open_panel = "" # a question takes the stage
	if want_offer:
		choice_panel.visible = false
		if not offer_panel.visible:
			show_offer()
	else:
		offer_panel.visible = false
		show_choice() # a ruin or event comes first; any offer waits behind it

# Puts the waiting pop-up aside to look at the map (its badge opens it again).
func hide_popup() -> void:
	popups_hidden = true
	refresh()

# The buttons that act in the game (disabled while a deal/trade/city panel is open).
func all_game_buttons() -> Array[Button]:
	var list: Array[Button] = [end_turn_button, build_button, scout_button, queue_army_button, queue_scout_button, outpost_button, walls_button, trade_button, view_button]
	for buttons in faction_buttons.values():
		for b in buttons.values():
			list.append(b)
	return list

func modal_open() -> bool:
	return deal_panel.visible or trade_panel.visible or city_panel.visible

func update_buttons() -> void:
	var playing: bool = state.can_act() and not modal_open()
	var p := state.player
	end_turn_button.disabled = not state.can_play() or modal_open()
	end_turn_button.tooltip_text = "End the turn (Turn %d of %d)." % [state.turn, GameState.END_TURN] if not state.is_waiting() else "Answer what is waiting first (click to see it)."
	view_button.text = "View: 3D   (switch to 2D)" if showing_3d else "View: 2D   (switch to 3D)"
	view_button.tooltip_text = "The flat 2D map is lighter on slow phones (or press V)." if showing_3d else "Show the map in 3D (or press V). Drag or WASD to move, pinch or the wheel to zoom."
	view_button.disabled = modal_open()
	for key in icon_buttons:
		set_active(icon_buttons[key], key == open_panel)
		icon_buttons[key].queue_redraw()
	var armies: int = state.army_count(p)
	var cap: int = state.supply_cap(p)
	build_info.text = "Industry %d stored, %+d a turn." % [p.industry, state.industry_change(p) - state.tribute_amount(p)]
	build_info.tooltip_text = "Buy at once with stored Industry, or Queue it: your city builds it over the next turns with each turn's Industry."
	build_info.mouse_filter = Control.MOUSE_FILTER_PASS
	for pair in [[queue_army_button, "army"], [queue_scout_button, "scout"]]:
		var problem := state.queue_problem(p, pair[1])
		pair[0].disabled = not playing or problem != ""
		pair[0].tooltip_text = "Add to the production queue: your city builds it with the next turns' Industry." if problem == "" else "Can't queue: %s." % problem
	update_queue(playing)
	build_button.text = "Army (%d) %d/%d" % [GameState.UNIT_COST, armies, cap]
	build_button.disabled = not playing or p.industry < GameState.UNIT_COST or armies >= cap
	build_button.tooltip_text = "An army unit: Strength %d, 1 move, costs %d Gold a turn. Supply %d/%d (%d + population, +%d with a Barracks).\nYour troops cost %d Gold a turn now; you make %+d Gold a turn after upkeep." % [p.strength, GameState.ARMY_GOLD, armies, cap, GameState.SUPPLY_BASE, GameState.Buildings.BARRACKS_SUPPLY, state.army_upkeep(p), state.gold_change(p)]
	scout_button.disabled = not playing or not state.can_build_scout(p)
	outpost_button.disabled = not playing or (not placing_outpost and (p.industry < GameState.OUTPOST_COST or state.outpost_spots(p).is_empty()))
	outpost_button.text = "Cancel the outpost" if placing_outpost else "Outpost (%d)" % GameState.OUTPOST_COST
	walls_button.disabled = not playing
	trade_button.disabled = not playing or not state.can_trade_daughter()
	update_diplomacy_panel(playing)
	update_sunna_panel()
	icon_buttons["sunna"].queue_redraw()
	# badges: one per kind of waiting question, stacked up from the bottom left of the ring
	var y := END_RING.end.y - BADGE_SIZE
	for kind in ["popup", "request", "offer"]:
		var b: Button = badges[kind]
		b.visible = badge_count(kind) > 0 and not state.game_over
		if b.visible:
			b.position = Vector2(BADGE_X, y)
			y -= BADGE_SIZE + 8
			b.queue_redraw()
	end_turn_button.queue_redraw()

func show_end_screen() -> void:
	# The Play Again button sits under the end-screen text (see _draw).
	var screen := get_viewport_rect().size
	var lines := state.end_detail.split("\n").size()
	play_again_button.visible = true
	play_again_button.position = Vector2(screen.x / 2 - 70, screen.y / 2 + 40 + lines * 30)
	selected = null
	open_panel = ""
	for key in panels:
		panels[key].visible = false

# Start a fresh game by reloading the scene from scratch.
func restart() -> void:
	get_tree().reload_current_scene()

# --- Button handlers: ask the state to act, then refresh ----------------------
func on_end_turn() -> void:
	if state.is_waiting():
		popups_hidden = false # End Turn with a question waiting: show it
		refresh()
		return
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
		state.messages = ["Click a highlighted hex to found your outpost there (or Cancel). Only hexes you can see right now."]
		open_panel = "" # out of the map's way
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
	city_panel.position = POPUP_POS
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

# One line of the city buildings panel; with a queue key it gets a Queue button too.
func add_city_option(text: String, enabled: bool, action: Callable, queue_key := "") -> void:
	var row := buy_row(city_buttons)
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 15)
	b.disabled = not enabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	row.add_child(b)
	if queue_key != "":
		var problem := state.queue_problem(state.player, queue_key)
		var q := panel_button("Queue", on_city_queue.bind(queue_key), row, 15)
		q.disabled = problem != ""
		q.tooltip_text = "Add to the production queue (Build panel)." if problem == "" else "Can't queue: %s." % problem

func on_city_queue(key: String) -> void:
	state.player_queue(key)
	refresh() # (shows the message)
	on_open_city() # stays open, so several can be queued

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
		add_city_option("Walls %d/%d (%d): +%d city defence" % [p.walls + 1, GameState.MAX_WALLS, GameState.WALL_COST, GameState.WALL_DEFENCE], p.industry >= GameState.WALL_COST, on_city_build.bind(func(): state.player_build_walls()), "walls")
	for key in GameState.Buildings.LIST:
		var info: Dictionary = GameState.Buildings.LIST[key]
		if p.buildings.has(key):
			add_city_option("%s: built (%s)" % [info["name"], info["text"]], false, func(): pass)
		else:
			var text := "%s (%d): %s" % [info["name"], info["cost"], info["text"]]
			if p.industry < info["cost"]:
				text += "  (you need %d Industry)" % info["cost"]
			add_city_option(text, state.can_build_building(p, key), on_city_build.bind(func(): state.player_build_building(key)), key)
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
	deal_panel.position = POPUP_POS
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
			var back := d.other_resource(give)
			var amount: int = d.trade_quote(give)
			var label := "Trade %d %s for %d %s" % [Diplomacy.TRADE_AMOUNT, give.capitalize(), amount, back.capitalize()]
			if amount <= 0:
				label = "Trade %d %s for %s  (they have none)" % [Diplomacy.TRADE_AMOUNT, give.capitalize(), back.capitalize()]
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
	offer_panel.position = Vector2(316, 110)
	offer_panel.custom_minimum_size = Vector2(520, 0)
	var style := box_style(GOLD, 6, 2, Color(0.08, 0.07, 0.06, 0.97)) # nearly solid, so the map doesn't show through
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
	add_map_button(row)
	offer_panel.visible = false

# While the pop-up is open the player must answer before doing anything else.
func show_offer() -> void:
	var r: Diplomacy = state.pending_relation()
	offer_heading.text = "A MESSAGE FROM THE %s" % r.other.name.to_upper()
	offer_label.text = r.pending_text()
	var kind: String = r.pending.get("type")
	offer_accept_button.text = {"demand": "Pay", "claim": "Hand her over", "daughter": "Take her", "peace": "Make peace", "trade": "Trade", "borders": "Open borders"}.get(kind, "Accept")
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
	choice_panel.position = Vector2(296, 100)
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
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	add_map_button(row)
	choice_panel.visible = false

# "Look at the map": puts the pop-up aside (its red badge by End Turn opens it again).
func add_map_button(parent: Node) -> void:
	var b := Button.new()
	b.text = "Look at the map first"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", GOLD)
	b.tooltip_text = "Hide this for now. The red badge beside End Turn brings it back."
	b.pressed.connect(hide_popup)
	parent.add_child(b)

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
	trade_panel.position = POPUP_POS
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
	trade_label.text = "Her worth depends on her Favour toward them, their fear of Sköll and how strong they already are. If she's worth too little, you must pay them to take her. Being traded costs her Favour toward you (%+d); whoever takes her trusts you more (%+d) and accepts your next oath or deal. Uses your diplomatic action." % [SunDaughter.TRADED_FAVOUR, SunDaughter.GIVEN_TRUST]
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		toggle_3d()
		return
	if state.game_over or state.phase == GameState.Phase.CROSSING:
		return
	if event is InputEventMouseMotion:
		hover_pos = get_local_mouse_position()
		hover_cell = cell_under_mouse() # (the landing highlight and the tooltips use this)
		queue_redraw()
		return
	if state.is_waiting() or modal_open():
		return # (a pop-up put aside with "Look at the map first": hovering works, acting waits for the answer)
	if showing_3d and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# In 3D a press may start dragging the map (one finger on a phone): it only
		# counts as a click when it's let go about where it started.
		if event.pressed:
			press_pos_3d = event.position
			return
		if event.position.distance_to(press_pos_3d) > CLICK_SLOP_3D:
			return
		var click := event.duplicate() as InputEventMouseButton
		click.pressed = true
		event = click
	if state.phase == GameState.Phase.LANDING:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if state.try_land(cell_under_mouse()):
				hover_cell = NO_CELL
			refresh()
		return
	if placing_outpost and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var spot := cell_under_mouse()
			if spot in state.outpost_spots(state.player):
				state.player_build_outpost(spot)
				placing_outpost = false
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			placing_outpost = false # right-click cancels
			state.messages = []
		refresh()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := cell_under_mouse()
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

# The colour a hex is marked with for what you can do there right now (the 2D view
# fills the hex with it, the 3D view lays it over the tile), or transparent for none:
# where you may land, where an outpost could go, and where the selected unit can
# move (yellow), attack (orange-red), persuade her (pale yellow) or would cross a
# closed border (pink).
func highlight_of(c: Vector2i, outpost_spots: Array[Vector2i]) -> Color:
	var s := state
	var none := Color(0, 0, 0, 0)
	if s.phase == GameState.Phase.LANDING:
		return Color(0.9, 0.75, 0.3) if c == hover_cell and s.can_land_at(c) else none
	var mark := none
	if c in outpost_spots:
		mark = Color(0.55, 0.8, 0.95) # you could found an outpost here
	if selected and HexMap.is_neighbour(selected.pos, c):
		var player := s.player
		var daughter := s.daughter
		var other := s.unit_at(c)
		if daughter.is_rogue() and c == daughter.pos and s.player_can_see(c):
			mark = Color(1.0, 0.95, 0.55) # persuade her
		elif (s.skoll.is_at(c) or (other and other.faction != player) or s.rifts.walker_at(c) != null) and s.player_can_see(c):
			mark = Color(0.95, 0.45, 0.2) # something to attack
		elif s.is_city(c) and c != player.city_pos:
			mark = Color(0.95, 0.45, 0.2) # a city you could attack (it would become your tributary)
		elif not other and s.rifts.walker_at(c) == null and not (s.is_city(c) and c != player.city_pos) and s.passable(c) and s.can_afford_move(selected, c):
			if s.closed_border(c):
				mark = Color(0.75, 0.45, 0.55) # behind a closed border: entering declares war
			elif s.zoc_blocks(player, selected.pos, c):
				pass # zone of control: an enemy army next to both hexes holds it here
			else:
				mark = Color(0.9, 0.75, 0.3) # free to move
	return mark

# Every marked hex (hex -> colour), for the 3D view: only hexes that can be marked
# are checked (the landing spot under the mouse, outpost spots, the selected unit's neighbours).
func marked_hexes() -> Dictionary:
	var spots: Array[Vector2i] = []
	if placing_outpost:
		spots = state.outpost_spots(state.player)
	var cells: Array[Vector2i] = spots.duplicate()
	if hover_cell != NO_CELL:
		cells.append(hover_cell)
	if selected:
		cells.append_array(HexMap.neighbours(selected.pos))
	var marks := {}
	for c in cells:
		var mark := highlight_of(c, spots)
		if mark.a > 0.0:
			marks[c] = mark
	return marks

# The hex under the mouse, in whichever view is showing.
func cell_under_mouse() -> Vector2i:
	if showing_3d:
		return view_3d.cell_at_screen(get_viewport().get_mouse_position())
	return HexView2D.cell_at(get_local_mouse_position())

# --- Switching between the 2D and 3D views (V, or View in Settings) ---------------
func toggle_3d() -> void:
	if state.phase == GameState.Phase.CROSSING:
		return # no map yet
	showing_3d = not showing_3d
	if view_3d == null:
		view_3d = View3DScene.instantiate()
		view_3d.state = state
		view_3d.terrain_colours = TERRAIN_COLOURS
		view_3d.colour_of = unit_colour
		view_3d.territory_colour_of = territory_colour
		view_3d.marks_of = marked_hexes
		view_3d.selected_of = func(): return selected
	if showing_3d:
		add_child(view_3d)
		move_child(view_3d, 0) # behind the buttons
		hover_cell = NO_CELL
		selected = null
		placing_outpost = false
	else:
		remove_child(view_3d) # kept, so the camera stays where you left it
	if is_real_game():
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_FILE)
		cfg.set_value("view", "3d", showing_3d)
		cfg.save(SETTINGS_FILE)
	refresh()

# The game itself, not a test script that loaded main.tscn (tests start in 2D and
# never touch the remembered settings).
func is_real_game() -> bool:
	return is_inside_tree() and get_tree().current_scene == self

# The view chosen last time (3D unless the player switched to 2D).
func remembered_3d() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return true
	return cfg.get_value("view", "3d", true)

# The 3D view is kept out of the tree while the 2D view shows: free it ourselves on quit.
func _exit_tree() -> void:
	if view_3d != null and not view_3d.is_inside_tree():
		view_3d.free()

# --- Drawing: only reads the state ----------------------------------------------
func _draw() -> void:
	if state.phase == GameState.Phase.CROSSING:
		return # the Crossing panel is shown instead of the map
	if not showing_3d:
		draw_map() # in the 3D view, view_3d.gd shows the map instead
	ov.queue_redraw() # the HUD drawn over the map (and over the edge mist), see draw_overlay

# The hex map and everything on it.
func draw_map() -> void:
	var s := state
	var player := s.player
	var k := HexView2D.HEX_SIZE / 32.0 # city drawings were designed for 32-pixel hexes
	var daughter := s.daughter
	var skoll := s.skoll
	var dark := daughter.is_swallowed() # Sköll swallowed the new sun
	draw_rect(get_viewport_rect(), Color(0.03, 0.03, 0.05) if dark else Color(0.08, 0.08, 0.1)) # the void around the map
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
			var fill: Color = ASH_COLOUR if s.is_ash(c) else TERRAIN_COLOURS[land]
			var explored := landing or s.player_has_explored(c)
			if not landing:
				var land_owner := s.territory_owner(c)
				if land_owner != null:
					fill = fill.lerp(territory_colour(land_owner), 0.35) # territory tints the land (its border is a line, see draw_borders)
			if dark:
				fill = fill.darkened(0.7)
			if not explored:
				fill = Color(0.07, 0.07, 0.09) # never seen
			elif not landing and not s.player_can_see(c):
				fill = fill.darkened(0.45) # seen before, but you can't see what's here now
			if landing and not s.can_land_at(c):
				fill = fill.darkened(0.6) # too close to another people's fires
			var mark := highlight_of(c, outpost_spots)
			if mark.a > 0.0:
				fill = mark
			draw_colored_polygon(pts, fill)
			if explored and s.is_ash(c):
				draw_ash_mark(HexView2D.hex_center(c))
			elif explored:
				draw_terrain_mark(HexView2D.hex_center(c), land, fill)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.1, 0.1, 0.1), 2.0)
	# (During the Landing nothing below is drawn: you haven't explored anything yet.)

	# Rifts you have found (a dark swirl), and the one Sköll last came through.
	for rift in player.known_rifts:
		draw_rift(HexView2D.hex_center(rift))
	if s.rifts.revealed != NO_CELL and s.player_can_see(s.rifts.revealed) and not player.known_rifts.has(s.rifts.revealed):
		draw_rift(HexView2D.hex_center(s.rifts.revealed))

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
		if f.city_hp < GameState.CITY_MAX_HP: # (a city at full health shows no bar)
			draw_hp_bar(cc + Vector2(0, half + 6), roundi(float(f.city_hp) / GameState.CITY_MAX_HP * Unit.MAX_HP))

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
			draw_hp_bar(uc + Vector2(0, HexView2D.HEX_SIZE * 0.62), u.hp)

	# Rift Walkers you can see: a dark knot of roots with a cold blue rim.
	for w in s.rifts.walkers:
		if s.player_can_see(w.pos):
			draw_walker(HexView2D.hex_center(w.pos))
			draw_hp_bar(HexView2D.hex_center(w.pos) + Vector2(0, HexView2D.HEX_SIZE * 0.62), roundi(float(w.hp) / RiftWalker.MAX_HP * Unit.MAX_HP))

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

# The HUD drawn over the map (the same in both views): territory borders and city
# banners, your banner and goal line, the resource column, toasts, tooltips and
# the end screen. (Buttons and panels are Controls: they draw themselves on top.)
func draw_overlay() -> void:
	var s := state
	var player := s.player
	var font := ThemeDB.fallback_font
	var screen := get_viewport_rect().size
	top_bar_tips.clear()
	if s.phase == GameState.Phase.PLAYING:
		draw_borders()
		draw_city_banners(font)
	draw_goal(font)
	draw_resources(font)
	draw_toasts(font)
	draw_tooltip()
	if s.game_over:
		ov.draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.8))
		ov.draw_string(font, Vector2(0, screen.y / 2 - 60), s.end_title, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 40, Color(0.95, 0.45, 0.15))
		var lines := s.end_detail.split("\n")
		for i in lines.size():
			ov.draw_string(font, Vector2(0, screen.y / 2 - 10 + i * 30), lines[i], HORIZONTAL_ALIGNMENT_CENTER, screen.x, 20)
		var totals := "Turn %d    Food %d    Industry %d    Units %d    Army Strength %d" % [s.turn, player.food, player.industry, player.units.size(), s.army_power(player)]
		ov.draw_string(font, Vector2(0, screen.y / 2 + 10 + lines.size() * 30), totals, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 18, Color(0.7, 0.7, 0.7))

# --- Territory borders and city banners (on the map, in 2D and 3D) -----------------
const HEX_RADIUS_3D := 1.0 # view_3d.gd's HEX_RADIUS
const BORDER_HEIGHT_3D := 0.42 # border lines in 3D sit at about the tiles' ground (view_3d.gd's MODEL_GROUND)

# A screen point (from the 3D camera) in this node's coordinates.
func to_canvas(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p

# The screen positions of a hex's six corners in whichever view is showing
# (empty when the 3D camera can't see them).
func screen_corners(c: Vector2i) -> PackedVector2Array:
	if not showing_3d:
		return HexView2D.hex_points(HexView2D.hex_center(c))
	var cam: Camera3D = view_3d.camera
	var centre: Vector3 = view_3d.cell_position(c)
	var top := BORDER_HEIGHT_3D # (one height for every corner, so neighbouring hexes' lines meet)
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		var p := Vector3(centre.x + cos(a) * HEX_RADIUS_3D * 0.97, top, centre.z + sin(a) * HEX_RADIUS_3D * 0.97)
		if cam.is_position_behind(p):
			return PackedVector2Array()
		pts.append(to_canvas(cam.unproject_position(p)))
	return pts

# The hex across edge i (between corners i and i+1), or NO_CELL off the map.
func neighbour_across(c: Vector2i, edge: int) -> Vector2i:
	var a := deg_to_rad(60.0 * edge)
	var spot := HexView2D.hex_center(c) + Vector2(cos(a), sin(a)) * sqrt(3.0) * HexView2D.HEX_SIZE
	for n in HexMap.neighbours(c):
		if HexView2D.hex_center(n).distance_to(spot) < 4.0:
			return n
	return NO_CELL

# A line in the owner's colour along every edge where its land ends, on land you
# have explored (GameState.territory_owner). Drawn a little inside each hex, so two
# peoples' borders side by side both show.
func draw_borders() -> void:
	var s := state
	var owners := {} # hex -> owner, worked out once per frame
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			owners[Vector2i(col, row)] = s.territory_owner(Vector2i(col, row))
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			var f: Faction = owners[c]
			if f == null or not s.player_has_explored(c):
				continue
			var pts := screen_corners(c)
			if pts.is_empty():
				continue
			var centre := (pts[0] + pts[3]) / 2
			var colour := unit_colour(f).lightened(0.2)
			for i in 6:
				var n := neighbour_across(c, i)
				if n != NO_CELL and owners[n] == f:
					continue
				ov.draw_line(pts[i].lerp(centre, 0.07), pts[(i + 1) % 6].lerp(centre, 0.07), colour, 2.5, true)

# Where a city's banner hangs: above its hex (Vector2.INF when the 3D camera can't see it).
func city_anchor(c: Vector2i) -> Vector2:
	if not showing_3d:
		return HexView2D.hex_center(c) - Vector2(0, HexView2D.HEX_SIZE * 0.8)
	var p: Vector3 = view_3d.cell_position(c)
	p.y = view_3d.hex_top(c) + 1.5
	if view_3d.camera.is_position_behind(p):
		return Vector2.INF
	return to_canvas(view_3d.camera.unproject_position(p))

# A banner over every city you have found: its people's flag, its population and
# (not on yours) that people's Trust toward you.
func draw_city_banners(font: Font) -> void:
	for f in state.factions:
		if f.city_pos == NO_CELL or not f.is_alive() or not state.player_has_explored(f.city_pos):
			continue
		var at := city_anchor(f.city_pos)
		if at == Vector2.INF:
			continue
		var pop := str(f.population)
		var trust := ""
		var trust_col := TEXT
		if f != state.player:
			var t: int = state.relation(f).trust
			trust = "TRUST %+d" % t
			trust_col = Color(0.5, 0.9, 0.5) if t > 0 else (Color(1.0, 0.45, 0.35) if t < 0 else TEXT)
		var pop_w := font.get_string_size(pop, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var trust_w := font.get_string_size(trust, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var banner_w := 20.0
		var chip_w := 8.0 + 16.0 + pop_w + 8.0 + (trust_w + 12.0 if trust != "" else 0.0)
		var left := at.x - (banner_w + 2 + chip_w) / 2
		draw_banner(ov, Rect2(left, at.y - 27, banner_w, 28), f)
		var box := Rect2(left + banner_w + 2, at.y - 20, chip_w, 20)
		ov.draw_rect(box, HUD_BG)
		ov.draw_rect(box, GOLD_DIM, false, 1.0)
		var x := box.position.x + 6
		if not draw_game_icon(ov, "pop", Rect2(x, box.position.y + 3, 14, 14), TEXT):
			draw_people(ov, Vector2(x + 7, box.position.y + 10), 5.0, TEXT)
		ov.draw_string(font, Vector2(x + 17, box.position.y + 15), pop, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		if trust != "":
			x += 17 + pop_w + 5
			ov.draw_line(Vector2(x, box.position.y + 4), Vector2(x, box.end.y - 4), GOLD_DIM, 1.0)
			ov.draw_string(font, Vector2(x + 6, box.position.y + 14), trust, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, trust_col)

# --- Top left: your banner and the one goal line -------------------------------------
func draw_goal(font: Font) -> void:
	draw_banner(ov, Rect2(12, 0, 50, 70), state.player)
	var goal := goal_line()
	var text: String = goal[0]
	var colour: Color = goal[1]
	text = fit_text(text, font, 15, 290)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 50
	var rect := Rect2(68, 10, w, 40)
	ov.draw_style_box(frame_style(SMALL_FRAME_SCALE, 0), rect)
	var dot := Vector2(rect.position.x + 20, rect.get_center().y)
	ov.draw_colored_polygon(PackedVector2Array([dot + Vector2(0, -6), dot + Vector2(6, 0), dot + Vector2(0, 6), dot + Vector2(-6, 0)]), colour)
	ov.draw_string(font, Vector2(rect.position.x + 34, rect.position.y + 25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colour)
	top_bar_tips.append([Rect2(12, 0, rect.end.x - 12, 70), "\n".join(status_lines())])

# Cuts a line to fit max_w pixels, ending it with "...".
func fit_text(text: String, font: Font, size: int, max_w: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return text
	while text.length() > 1 and font.get_string_size(text + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		text = text.left(text.length() - 1)
	return text.strip_edges() + "..."

# The ONE thing that matters most right now, by priority: Sköll hunting you, a
# decision waiting, what Sunna still needs, then the next useful action.
func goal_line() -> Array:
	var s := state
	var p := s.player
	var sk := s.skoll
	if s.phase == GameState.Phase.LANDING:
		return ["Choose where to land: click a lit hex", GOLD]
	if s.game_over:
		return [s.end_title, GOLD]
	if sk.active and sk.target == p and not sk.slain:
		var where := " (%d hexes away)" % HexMap.hex_distance(sk.pos, p.city_pos) if s.player_can_see(sk.pos) else ""
		return ["Sköll is hunting you%s" % where, Color(1.0, 0.5, 0.25)]
	if s.is_waiting():
		var what := "an offer from the %s" % s.pending_relation().other.name if not s.has_pending_choice() else String(s.pending_choices[0]["title"]).capitalize()
		return ["A decision waits: %s" % what, Color(1.0, 0.8, 0.4)]
	var need := sunna_need()
	if need != "":
		return [need, Color(1.0, 0.88, 0.55)]
	if Rifts.season_on(s.turn):
		return ["%s is on: %d turn%s left" % [Rifts.season_title(), Rifts.season_left(s.turn), "" if Rifts.season_left(s.turn) == 1 else "s"], SEASON_COLOUR]
	return [next_action(), TEXT]

# What Sunna still needs from you, in a few words ("" = nothing to say).
func sunna_need() -> String:
	var s := state
	var p := s.player
	var d := s.daughter
	if d.is_rogue():
		return "%s is alone in the open: find her (%d%%)" % [SunDaughter.NAME, roundi(d.persuade_chance(p) * 100)]
	if d.holder != p or d.state != SunDaughter.State.SHELTERED:
		return ""
	if p.favour <= SunDaughter.WARN_FAVOUR:
		return "%s is unhappy (Favour %d): at %d she leaves" % [SunDaughter.NAME, p.favour, SunDaughter.LEAVE_FAVOUR]
	if s.turn < Skoll.ARRIVAL_TURN:
		if s.city_defence(p) < SunDaughter.READY_DEFENCE or s.army_power(p) < SunDaughter.READY_ARMY:
			return "%s wants defence %d/%d, army %d/%d by turn %d" % [SunDaughter.NAME, s.city_defence(p), SunDaughter.READY_DEFENCE, s.army_power(p), SunDaughter.READY_ARMY, Skoll.ARRIVAL_TURN]
		return ""
	var missing := s.rise_missing(p)
	if missing.is_empty():
		return "" if s.turn >= GameState.RISE_TURN else "%s is ready to rise on turn %d" % [SunDaughter.NAME, GameState.RISE_TURN]
	return "%s needs: %s" % [SunDaughter.NAME, missing[0] if missing.size() == 1 else "%s (+%d more)" % [missing[0], missing.size() - 1]]

func next_action() -> String:
	var s := state
	var p := s.player
	if placing_outpost:
		return "Click a lit hex to found your outpost"
	var movable := p.units.filter(func(u): return u.moves > 0 and u.busy_until <= s.turn).size()
	if movable > 0:
		return "%d unit%s can still move" % [movable, "" if movable == 1 else "s"]
	if not build_button.disabled or not scout_button.disabled or not outpost_button.disabled or (p.industry >= GameState.WALL_COST and p.walls < GameState.MAX_WALLS) or GameState.Buildings.LIST.keys().any(func(k): return s.can_build_building(p, k)):
		return "%d Industry to spend: open Build" % p.industry
	return "Nothing left to do: end the turn"

# Everything the old status lines said (hover the goal line to read it).
func status_lines() -> Array[String]:
	var s := state
	var player := s.player
	var skoll := s.skoll
	var lines: Array[String] = ["Turn %d of %d." % [s.turn, GameState.END_TURN]]
	if player.overlord != "":
		lines.append("TRIBUTARY of the %s: %d Industry a turn to them (attack them to rise up)." % [player.overlord, s.tribute_amount(player)])
	if skoll.slain:
		lines.append("Sköll is dead.")
	elif skoll.active and player.city_pos != NO_CELL:
		var where := "%d hexes from yours" % HexMap.hex_distance(skoll.pos, player.city_pos) if s.player_can_see(skoll.pos) else "out of sight"
		var hurt := " (wounded: %d of %d)" % [skoll.effective_strength(), skoll.strength] if skoll.wounds > 0 else ""
		lines.append("Sköll%s, Strength %d%s, hunts %s (%s). Your defence: %d." % [" (MORTAL)" if skoll.is_mortal() else "", skoll.effective_strength(), hurt, skoll.target_text(), where, s.city_defence(player)])
	elif skoll.returns > 0:
		lines.append("Sköll is in the void: he returns on turn %d, stronger (Strength %d)." % [skoll.away_until, skoll.strength + Skoll.STRENGTH_PER_RETURN])
	elif s.turn < Skoll.ARRIVAL_TURN:
		lines.append("Sköll arrives on turn %d (his howling starts on turn %d)." % [Skoll.ARRIVAL_TURN, Skoll.WARNING_TURN])
	lines.append(season_line())
	lines.append(sunna_line())
	return lines

# One line on the season (Rifts.season_on): on now, or when it next comes.
func season_line() -> String:
	var t := state.turn
	if Rifts.season_on(t):
		return "%s: the rifts glow. %d turn%s left." % [Rifts.season_title(), Rifts.season_left(t), "" if Rifts.season_left(t) == 1 else "s"]
	return "%s comes on turn %d (%d turns, every %d)." % [Rifts.season_title(), Rifts.next_season(t), Rifts.SEASON_LENGTH, Rifts.SEASON_EVERY]

# One line on where Sunna is and how she feels (status tooltip and the Sunna panel).
func sunna_line() -> String:
	var s := state
	var player := s.player
	var daughter := s.daughter
	var skoll := s.skoll
	if daughter.is_swallowed():
		return "Sköll swallowed %s. He is the sun now (Strength %d), but MORTAL: a combined force can kill him." % [SunDaughter.NAME, skoll.strength]
	if daughter.is_risen():
		return "%s has RISEN with %s. Sköll is mortal but enraged and hunts her city: it must stand until turn %d." % [SunDaughter.NAME, "you" if daughter.holder == player else "the " + daughter.holder.name, GameState.END_TURN]
	if daughter.is_rogue():
		var seen := "" if s.player_can_see(daughter.pos) else " You can't see where she is."
		return "She is ALONE IN THE OPEN! Move a unit onto her to persuade her (your chance %d%%).%s" % [roundi(daughter.persuade_chance(player) * 100), seen]
	if daughter.holder == null:
		return "%s has not chosen a people yet." % SunDaughter.NAME
	var note := "Sköll knows: he hunts her city." if skoll.knows_her else "Sköll doesn't know which city."
	if daughter.holder == player and player.favour <= SunDaughter.WARN_FAVOUR:
		note = "UNHAPPY: at Favour %d she leaves." % SunDaughter.LEAVE_FAVOUR
	return "%s %s. %s Her Favour toward you: %d of %d." % ["You shelter" if daughter.holder == player else "The " + daughter.holder.name + " shelter", SunDaughter.NAME, note, player.favour, SunDaughter.MAX_FAVOUR]

# --- Right edge: the resource column -------------------------------------------------
func draw_resources(font: Font) -> void:
	var s := state
	var p := s.player
	var industry_net: int = s.industry_change(p) - s.tribute_amount(p)
	var rows := [
		["pop", str(p.population), 0, false, "Population %d (your city's size). Every point above 1 gives +1 Food, +1 Industry and +%d city defence a turn.\nThe city grows by 1 when stored Food reaches %d and Food isn't falling." % [p.population, GameState.POP_DEFENCE, s.growth_cost(p)]],
		["food", str(p.food), s.food_change(p), true, "Food: %d stored; at %d your city grows. Food only grows your city (Gold pays your armies).\nThis turn: %s" % [p.food, s.growth_cost(p), parts_text(s.food_parts(p))]],
		["gold", str(p.gold), s.gold_change(p), true, "Gold: %d stored. Each army costs %d a turn, each scout %d; if Gold runs out, a unit deserts. A Market adds +%d.\nThis turn: %s" % [p.gold, GameState.ARMY_GOLD, GameState.SCOUT_GOLD, GameState.Buildings.MARKET_GOLD, parts_text(s.gold_parts(p))]],
		["industry", str(p.industry), industry_net, true, "Industry: %d stored, spent on units, outposts and city buildings (Build).\nThis turn: %s%s" % [p.industry, parts_text(s.industry_parts(p)), ", tribute %+d" % -s.tribute_amount(p) if s.tribute_amount(p) > 0 else ""]],
		["army", str(s.army_power(p)), 0, false, "Army: the total Strength of your units (%d armies, supply %d/%d; %d scouts; %d outposts). The AIs compare armies before demanding or declaring war; %s wants %d+ by turn %d.\nEach army costs %d Gold a turn, each scout %d (now %d a turn)." % [s.army_count(p), s.army_count(p), s.supply_cap(p), p.scout_count(), p.outposts.size(), SunDaughter.NAME, SunDaughter.READY_ARMY, Skoll.ARRIVAL_TURN, GameState.ARMY_GOLD, GameState.SCOUT_GOLD, s.army_upkeep(p)]],
		["land", str(s.land_count(p)), 0, false, "Land: hexes of your territory that aren't ash (%s). On turn %d, Dominion goes to whoever holds the most." % [", ".join(s.ais.filter(func(f): return f.is_alive()).map(func(f): return "%s %d" % [f.name, s.land_count(f)])), GameState.END_TURN]],
	]
	ov.draw_style_box(frame_style(SMALL_FRAME_SCALE, 0), RES_RECT)
	for i in rows.size():
		var row: Array = rows[i]
		var y := RES_RECT.position.y + 10 + i * 35.0
		if not draw_game_icon(ov, row[0], Rect2(RES_RECT.position.x + 10, y + 6, 22, 22)):
			draw_resource_icon(row[0], Vector2(RES_RECT.position.x + 21, y + 17))
		var x := RES_RECT.position.x + 40
		ov.draw_string(title_font, Vector2(x, y + 23), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
		if row[3]:
			var w := title_font.get_string_size(row[1] + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var change: int = row[2]
			ov.draw_string(font, Vector2(x + w, y + 22), "(%+d)" % change, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.9, 0.5) if change >= 0 else Color(1.0, 0.45, 0.35))
		if i > 0:
			ov.draw_line(Vector2(RES_RECT.position.x + 12, y), Vector2(RES_RECT.end.x - 12, y), Color(GOLD_DIM, 0.4), 1.0)
		top_bar_tips.append([Rect2(RES_RECT.position.x, y, RES_RECT.size.x, 35), row[4]])

# --- Toasts (top centre) ------------------------------------------------------------------
func draw_toasts(font: Font) -> void:
	var life := TOAST_TIME_BUSY if toasts.size() > TOAST_SHOWN else TOAST_TIME
	var y := 12.0
	for i in mini(TOAST_SHOWN, toasts.size()):
		var t: Dictionary = toasts[i]
		var alpha := clampf(life - t["age"], 0.0, 1.0) * clampf(t["age"] / 0.15, 0.3, 1.0)
		var source: Array[String] = [t["text"]]
		var lines := wrap_lines(source, font, TOAST_W - 28, 15).slice(0, 3)
		var w := 0.0
		for line in lines:
			w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
		w += 28
		var h := lines.size() * 19.0 + 12
		var rect := Rect2(TOAST_CENTRE_X - w / 2, y, w, h)
		ov.draw_rect(rect, Color(HUD_BG, HUD_BG.a * alpha))
		ov.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(GOLD, alpha), 1.0)
		ov.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color(GOLD, alpha), 1.0)
		for j in lines.size():
			ov.draw_string(font, Vector2(rect.position.x + 14, y + 20 + j * 19), lines[j], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.88, 0.55, alpha))
		y += h + 6

# --- Pictures drawn in code (plain styling until there is art) ------------------------------
# A faction's banner: a swallow-tailed flag in its colour with its emblem.
func draw_banner(ci: CanvasItem, r: Rect2, f: Faction) -> void:
	var key: String = "banner_" + f.name.to_lower()
	if ui_tex.has(key):
		draw_fitted(ci, ui_tex[key], r)
		return
	var notch := r.size.y * 0.16
	var flag := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.get_center().x, r.end.y - notch), Vector2(r.position.x, r.end.y)])
	ci.draw_colored_polygon(flag, unit_colour(f).darkened(0.35))
	var edge := flag.duplicate()
	edge.append(flag[0])
	ci.draw_polyline(edge, GOLD_DIM, 1.0, true)
	draw_emblem(ci, Vector2(r.get_center().x, r.position.y + r.size.y * 0.42), r.size.x * 0.62, f.name, Color(0.95, 0.92, 0.85))

# Each people's sign: Norse rune, Japanese torii, Celtic knot, Greek temple.
func draw_emblem(ci: CanvasItem, c: Vector2, s: float, people: String, col: Color) -> void:
	var w := maxf(1.0, s * 0.1)
	match people:
		"Norse": # the rune raido
			ci.draw_line(c + Vector2(-0.25, -0.5) * s, c + Vector2(-0.25, 0.5) * s, col, w)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.25, -0.5) * s, c + Vector2(0.25, -0.22) * s, c + Vector2(-0.25, 0.02) * s, c + Vector2(0.3, 0.5) * s]), col, w)
		"Japanese":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.56, -0.5) * s, c + Vector2(-0.4, -0.4) * s, c + Vector2(0.4, -0.4) * s, c + Vector2(0.56, -0.5) * s]), col, w * 1.3)
			ci.draw_line(c + Vector2(-0.4, -0.18) * s, c + Vector2(0.4, -0.18) * s, col, w)
			for x in [-0.27, 0.27]:
				ci.draw_line(c + Vector2(x, -0.42) * s, c + Vector2(x, 0.5) * s, col, w)
		"Celtic":
			for i in 3:
				var a := deg_to_rad(-90.0 + i * 120.0)
				ci.draw_arc(c + Vector2(cos(a), sin(a)) * s * 0.17, s * 0.27, 0, TAU, 20, col, w * 0.8, true)
		"Greek":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.52, -0.2) * s, c + Vector2(0, -0.52) * s, c + Vector2(0.52, -0.2) * s]), col)
			for x in [-0.34, 0.0, 0.34]:
				ci.draw_rect(Rect2(c + Vector2(x - 0.07, -0.14) * s, Vector2(0.14, 0.52) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.52, 0.4) * s, Vector2(1.04, 0.12) * s), col)

# Sunna's sun with her Favour toward you as a number and a gold ring filling toward 10.
func draw_favour_sun(ci: CanvasItem, c: Vector2, radius: float, font_size: int) -> void:
	var favour := state.player.favour
	ci.draw_arc(c, radius, 0, TAU, 48, Color(0.22, 0.19, 0.15), 3.0, true)
	if favour > 0:
		ci.draw_arc(c, radius, -PI / 2, -PI / 2 + TAU * clampf(float(favour) / SunDaughter.MAX_FAVOUR, 0.0, 1.0), 48, Color(1.0, 0.82, 0.35), 3.5, true)
	for i in 8:
		var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		ci.draw_line(c + dir * radius * 0.52, c + dir * radius * 0.74, Color(1.0, 0.82, 0.35), maxf(1.5, radius * 0.08))
	ci.draw_circle(c, radius * 0.44, Color(1.0, 0.85, 0.4))
	if font_size <= 0:
		return # (the number is shown elsewhere)
	var font := ThemeDB.fallback_font
	ci.draw_string(font, c + Vector2(-radius, font_size * 0.36), str(favour), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, font_size, Color(0.2, 0.12, 0.05))

func draw_people(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-0.55, -0.45) * s, s * 0.38, col)
	ci.draw_circle(c + Vector2(0.55, -0.45) * s, s * 0.38, col)
	ci.draw_arc(c + Vector2(-0.55, 0.75) * s, s * 0.6, PI, TAU, 10, col, s * 0.35)
	ci.draw_arc(c + Vector2(0.55, 0.75) * s, s * 0.6, PI, TAU, 10, col, s * 0.35)

func draw_swords(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	for side in [-1.0, 1.0]:
		var tip := c + Vector2(side * -0.75, -0.75) * s
		var hilt := c + Vector2(side * 0.75, 0.75) * s
		ci.draw_line(tip, hilt, col, maxf(1.5, s * 0.16))
		var guard := c + Vector2(side * 0.45, 0.45) * s
		ci.draw_line(guard + Vector2(-side * 0.25, 0.25) * s, guard + Vector2(side * 0.25, -0.25) * s, col, maxf(1.5, s * 0.14))

func draw_resource_icon(kind: String, c: Vector2) -> void:
	var col := GOLD
	match kind:
		"pop":
			draw_people(ov, c + Vector2(0, -1), 7.0, col)
		"food": # wheat: a stem with grains
			ov.draw_line(c + Vector2(0, 9), c + Vector2(0, -9), col, 1.5)
			for i in 3:
				var y := -6.0 + i * 5.0
				ov.draw_circle(c + Vector2(-3, y), 2.4, col)
				ov.draw_circle(c + Vector2(3, y), 2.4, col)
			ov.draw_circle(c + Vector2(0, -10), 2.2, col)
		"industry": # an anvil
			ov.draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -5), c + Vector2(9, -5), c + Vector2(7, -1), c + Vector2(3, 0), c + Vector2(3, 4), c + Vector2(7, 8), c + Vector2(-7, 8), c + Vector2(-3, 4), c + Vector2(-3, 0), c + Vector2(-7, -1)]), col)
		"gold": # a coin
			ov.draw_circle(c, 9.0, col)
			ov.draw_arc(c, 6.0, 0, TAU, 24, HUD_BG, 1.5)
		"army":
			draw_swords(ov, c, 9.0, col)
		"land": # a mountain
			ov.draw_colored_polygon(PackedVector2Array([c + Vector2(-11, 8), c + Vector2(-2, -8), c + Vector2(3, 0), c + Vector2(6, -4), c + Vector2(11, 8)]), col)

# The picture on a round HUD button (see round_button).
func draw_icon(b: Button, kind: String) -> void:
	var c := b.size / 2
	var r := b.size.x / 2
	var col := GOLD if not b.disabled else Color(0.42, 0.39, 0.35)
	var font := ThemeDB.fallback_font
	var lit: bool = active_icons.get(b, false) or (b.is_hovered() and not b.disabled)
	if lit:
		col = Color(1.0, 0.86, 0.55)
	var ring: Texture2D = ui_tex.get("end_turn_ring" if kind == "end_turn" else "icon_button_ring")
	if kind == "sunna" and ui_tex.has("sunna_medallion"):
		# her medallion, the gold ring filling toward 10 around it, the Favour on a badge
		var favour := state.player.favour
		b.draw_arc(c, r - 1, 0, TAU, 48, Color(0.12, 0.1, 0.08, 0.85), 4.0, true)
		if favour > 0:
			b.draw_arc(c, r - 1, -PI / 2, -PI / 2 + TAU * clampf(float(favour) / SunDaughter.MAX_FAVOUR, 0.0, 1.0), 48, Color(1.0, 0.82, 0.35), 4.0, true)
		draw_fitted(b, ui_tex["sunna_medallion"], Rect2(Vector2(5, 5), b.size - Vector2(10, 10)), Color(1.15, 1.1, 1.0) if lit else Color.WHITE)
		var tag := Vector2(b.size.x - 5, b.size.y - 5)
		b.draw_circle(tag, 10.0, Color(0.1, 0.08, 0.06))
		b.draw_arc(tag, 10.0, 0, TAU, 20, GOLD, 1.5, true)
		b.draw_string(title_font, tag + Vector2(-10, 5), str(favour), HORIZONTAL_ALIGNMENT_CENTER, 20, 13, TEXT)
		return
	if ring != null:
		if lit:
			b.draw_circle(c, r * 0.95, Color(1.0, 0.75, 0.35, 0.18))
		draw_fitted(b, ring, Rect2(Vector2.ZERO, b.size), Color(0.55, 0.52, 0.48) if b.disabled else (Color(1.2, 1.12, 1.0) if lit else Color.WHITE))
	var icon_rect := Rect2(c - Vector2(r, r) * 0.46, Vector2(r, r) * 0.92)
	match kind:
		"end_turn":
			var waiting := state.is_waiting() and not state.game_over
			var big := 15 if waiting else 18
			b.draw_string(title_font, Vector2(0, c.y - 12), "ANSWER" if waiting else "END", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, big, col)
			b.draw_string(title_font, Vector2(0, c.y + 7), "FIRST" if waiting else "TURN", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, big, col)
			b.draw_line(Vector2(c.x - 24, c.y + 15), Vector2(c.x + 24, c.y + 15), Color(col, 0.6), 1.0)
			b.draw_string(title_font, Vector2(0, c.y + 31), "TURN %d/%d" % [state.turn, GameState.END_TURN], HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 11, TEXT)
			return
		"offer", "request", "popup":
			if not draw_game_icon(b, kind, Rect2(c - Vector2(r, r) * 0.5, Vector2(r, r)), col):
				b.draw_string(font, Vector2(0, c.y + 8), "!", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 22, col)
			var badge := Vector2(b.size.x - 4, 4)
			b.draw_circle(badge, 9.0, BADGE_RED)
			b.draw_string(font, badge + Vector2(-9, 5), str(badge_count(kind)), HORIZONTAL_ALIGNMENT_CENTER, 18, 13, Color.WHITE)
			return
	if draw_game_icon(b, kind, icon_rect, col):
		return
	match kind: # the shapes drawn in code, if an icon is missing
		"diplomacy":
			var s := r * 0.5
			for side in [-1.0, 1.0]:
				b.draw_colored_polygon(PackedVector2Array([c + Vector2(side * 1.2, -0.15) * s, c + Vector2(side * 0.75, -0.45) * s, c + Vector2(side * 0.45, 0.05) * s, c + Vector2(side * 0.9, 0.35) * s]), col)
			b.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.55, -0.25) * s, c + Vector2(0.1, -0.55) * s, c + Vector2(0.6, -0.15) * s, c + Vector2(0.5, 0.25) * s, c + Vector2(-0.05, 0.55) * s, c + Vector2(-0.6, 0.2) * s]), col)
		"build":
			var s := r * 0.5
			b.draw_line(c + Vector2(-0.9, 0.9) * s, c + Vector2(0.3, -0.3) * s, col, s * 0.24)
			b.draw_circle(c + Vector2(0.35, -0.35) * s, s * 0.4, col)
		"sunna":
			draw_favour_sun(b, c, r * 0.72, 14)
		"chronicle":
			var s := r * 0.5
			for side in [-1.0, 1.0]:
				b.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.5) * s, c + Vector2(side * 0.95, -0.7) * s, c + Vector2(side * 0.95, 0.55) * s, c + Vector2(0, 0.75) * s]), col)
		"settings":
			b.draw_circle(c, r * 0.34, col)
			b.draw_circle(c, r * 0.14, HUD_BG)

# How the map shows what is at war or at peace in the Diplomacy panel.
func draw_stance(c: Control, f: Faction) -> void:
	var d: Diplomacy = state.relation(f)
	var centre := c.size / 2
	var r := Rect2(centre - Vector2(12, 12), Vector2(24, 24))
	if d.at_war or state.player.overlord == f.name:
		if not draw_game_icon(c, "army", r, Color(1.0, 0.4, 0.3)):
			draw_swords(c, centre, 9.0, Color(1.0, 0.4, 0.3))
	elif d.pact_active():
		if not draw_game_icon(c, "diplomacy", r, Color(0.55, 0.85, 0.6)):
			c.draw_circle(centre, 8.0, Color(0.55, 0.85, 0.6))
			c.draw_circle(centre, 4.0, HUD_BG)
	elif not draw_game_icon(c, "peace", r, Color(0.75, 0.9, 0.8)):
		var col := Color(0.75, 0.9, 0.8)
		c.draw_arc(centre + Vector2(-6, 2), 6.0, PI * 1.1, PI * 1.9, 8, col, 2.5)
		c.draw_arc(centre + Vector2(6, 2), 6.0, PI * 1.1, PI * 1.9, 8, col, 2.5)
		c.draw_circle(centre + Vector2(0, 0), 2.5, col)

func draw_sun_icon(ci: CanvasItem, centre: Vector2, radius: float) -> void:
	for i in 8:
		var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		ci.draw_line(centre + dir * radius * 1.2, centre + dir * radius * 1.9, Color(1.0, 0.85, 0.3), 2.0)
	ci.draw_circle(centre, radius, Color(1.0, 0.9, 0.4))

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

# Ash: grey flecks.
func draw_ash_mark(c: Vector2) -> void:
	for v in [Vector2(-8, -4), Vector2(5, -8), Vector2(9, 5), Vector2(-3, 7), Vector2(0, -1)]:
		draw_circle(c + v, 1.8, Color(0.62, 0.6, 0.58))

# [["city", 2], ["army upkeep", -2]] -> "city +2, army upkeep -2"
func parts_text(parts: Array) -> String:
	return ", ".join(parts.map(func(p): return "%s %+d" % [p[0], p[1]]))

# What's under the mouse: a part of the top bar, or what's on a hex and its land.
func draw_tooltip() -> void:
	var lines: Array[String] = []
	for tip in top_bar_tips:
		if tip[0].has_point(hover_pos):
			lines.assign(String(tip[1]).split("\n"))
	var at := hover_pos + Vector2(14, 22)
	if lines.is_empty():
		lines = hex_tooltip(hover_cell)
		# above the hovered hex, so the units around it stay visible
		var hex_at := hover_pos if showing_3d else HexView2D.hex_center(hover_cell)
		at = hex_at + Vector2(18, -HexView2D.HEX_SIZE - lines.size() * 17 + 6)
		if at.y - 14 < TOP_BAR_BOTTOM:
			at.y = hex_at.y + HexView2D.HEX_SIZE + 14 # no room above without covering the top bar: below it
	if lines.is_empty():
		return
	var font := ThemeDB.fallback_font
	lines = wrap_lines(lines, font, 520) # long lines wrap
	var w := 0.0
	for line in lines:
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	var screen := get_viewport_rect().size
	at.x = clampf(at.x, 8, screen.x - RES_RECT.size.x - w - 30) # stay left of the resource column
	at.y = clampf(at.y, 18, screen.y - lines.size() * 17 - 4)
	ov.draw_rect(Rect2(at - Vector2(6, 14), Vector2(w + 12, lines.size() * 17 + 6)), Color(0.06, 0.06, 0.06, 0.9))
	for i in lines.size():
		ov.draw_string(font, at + Vector2(0, i * 17), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.95, 0.85) if i == 0 else Color(0.8, 0.8, 0.75))

# Breaks lines wider than max_w at spaces (continuations are indented).
func wrap_lines(lines: Array[String], font: Font, max_w: float, size := 13) -> Array[String]:
	var out: Array[String] = []
	for line in lines:
		var current := ""
		for word in line.split(" "):
			var trial := word if current == "" else current + " " + word
			if current != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
				out.append(current)
				current = "   " + word
			else:
				current = trial
		out.append(current)
	return out

# Everything the player knows about a hex, one line each (empty if unexplored).
func hex_tooltip(c: Vector2i) -> Array[String]:
	var s := state
	var lines: Array[String] = []
	if c == NO_CELL or not (s.phase == GameState.Phase.LANDING or s.player_has_explored(c)):
		return lines
	var seen := s.player_can_see(c)
	if seen and s.skoll.is_at(c):
		var sk := s.skoll
		var hurt := " (%d with his wounds; they heal %d a turn)" % [sk.effective_strength(), Skoll.WOUND_HEAL] if sk.wounds > 0 else ""
		lines.append("Sköll, the wolf who swallowed the sun: Strength %d%s. Hunting %s." % [sk.strength, hurt, sk.target_text()])
		if sk.is_mortal():
			lines.append("   MORTAL: an attack that beats him kills him. Each other army of yours or your allies next to him adds +%d." % GameState.WOLF_SUPPORT)
		else:
			lines.append("   Can't be killed while %s is hidden: an attacker dies but wounds him; wounds of half his Strength drive him back." % SunDaughter.NAME)
	var u := s.unit_at(c)
	if u != null and (seen or u.faction == s.player):
		var who := "Your" if u.faction == s.player else "The %s" % u.faction.name
		var kind := "scout" if u.is_scout() else "army"
		var line := "%s %s: HP %d/%d, Strength %d" % [who, kind, u.hp, Unit.MAX_HP, u.strength]
		if u.fighting_strength() != u.strength:
			line += " (%d while wounded)" % u.fighting_strength()
		if s.defender_strength(u) != u.fighting_strength():
			line += ", defends at %d here" % s.defender_strength(u)
		line += ", moves %d/%d" % [u.moves, u.max_moves()]
		if u.busy_until > s.turn:
			line += ", standing watch until turn %d" % u.busy_until
		if u.faction != s.player:
			line += "  [%s]" % ("AT WAR with you" if s.at_war(s.player, u.faction) else "at peace")
		lines.append(line)
		if u.hp < Unit.MAX_HP and u.faction == s.player:
			lines.append("   Heals %d HP in a turn it doesn't move or fight (%d in your own land)." % [GameState.HEAL_REST, GameState.HEAL_HOME])
		if u.faction != s.player and not u.is_scout() and s.at_war(s.player, u.faction):
			lines.append("   Zone of control: your units stop when they step next to it, and can't walk past it.")
		if selected != null and u.faction != s.player and HexMap.is_neighbour(selected.pos, c) and not s.is_city(c):
			var e: Vector2i = s.expected_combat(selected, u)
			lines.append("   If your selected unit attacks: it deals about %d and takes about %d (of %d HP)." % [e.x, e.y, selected.hp])
	var walker: RiftWalker = s.rifts.walker_at(c)
	if walker != null and seen:
		var line := "A Rift Walker, out of the roots of Yggdrasil: HP %d/%d, Strength %d" % [walker.hp, RiftWalker.MAX_HP, RiftWalker.STRENGTH]
		if s.walker_defence(walker) != RiftWalker.STRENGTH:
			line += ", defends at %d here" % s.walker_defence(walker)
		lines.append(line)
		var land_owner := s.territory_owner(c)
		var eats := ("eating %d of your Food a turn" % Rifts.WALKER_FOOD) if land_owner == s.player else ("eating %d of the %s's Food a turn" % [Rifts.WALKER_FOOD, land_owner.name]) if land_owner != null else "on nobody's land, so it eats nothing"
		lines.append("   It never attacks first and fights back if attacked. Now %s. Attacking it is never an act of war." % eats)
		if selected != null and HexMap.is_neighbour(selected.pos, c):
			var e: Vector2i = s.expected_walker_combat(selected, walker)
			lines.append("   If your selected unit attacks: it deals about %d and takes about %d (of %d HP)." % [e.x, e.y, selected.hp])
	if seen and s.daughter.is_rogue() and s.daughter.pos == c:
		lines.append("%s, alone in the open. Move a unit onto her to persuade her (%d%%)." % [SunDaughter.NAME.capitalize(), roundi(s.daughter.persuade_chance(s.player) * 100)])
	var city := s.city_owner(c)
	if city != null:
		var who := "Your city" if city == s.player else "The %s city" % city.name
		lines.append("%s: HP %d/%d, population %d, %+d Food and %+d Industry a turn, defence %d" % [who, city.city_hp, GameState.CITY_MAX_HP, city.population, s.food_change(city), s.industry_change(city), s.city_defence(city)])
		if selected != null and city != s.player and HexMap.is_neighbour(selected.pos, c):
			var e: Vector2i = s.expected_siege(selected, city)
			lines.append("   If your selected unit attacks: the city loses about %d HP, your unit about %d (of %d). At 0 HP it becomes your tributary." % [e.x, e.y, selected.hp])
		var extra: Array[String] = []
		if city.walls > 0:
			extra.append("walls %d" % city.walls)
		for key in city.buildings:
			extra.append(GameState.Buildings.LIST[key]["name"])
		if s.daughter.shelters_with(city):
			extra.append("shelters %s" % SunDaughter.NAME)
		if city.overlord != "":
			extra.append("pays tribute to the %s" % city.overlord)
		if not extra.is_empty():
			lines.append("   " + ", ".join(extra))
	var post := s.outpost_owner(c)
	if post != null:
		var t: int = s.terrain_at(c)
		lines.append("%s outpost: +%d Food, +%d Industry a turn (from its %s)" % ["Your" if post == s.player else "The %s" % post.name, Terrain.OUTPOST_FOOD[t], Terrain.OUTPOST_INDUSTRY[t], Terrain.NAMES[t].to_lower()])
	if s.player.known_rifts.has(c) or (c == s.rifts.revealed and seen):
		lines.append("A rift in the void: Sköll can come through here.")
		lines.append("   " + ("It glows: %s is on." % Rifts.SEASON_NAME if Rifts.season_on(s.turn) else "It sleeps until %s (turn %d)." % [Rifts.SEASON_NAME, Rifts.next_season(s.turn)]))
	for r in s.ruins:
		if r["cell"] == c and not r["taken"]:
			lines.append("Ruins: move a unit here to search them.")
	if s.phase == GameState.Phase.PLAYING:
		var land_owner := s.territory_owner(c)
		if land_owner != null and land_owner != s.player:
			lines.append("%s land%s" % [land_owner.name, " (borders CLOSED to you: entering declares war)" if s.closed_border(c) else ""])
	if selected != null and HexMap.is_neighbour(selected.pos, c) and s.unit_at(c) == null and walker == null and not (s.is_city(c) and c != s.player.city_pos) and s.passable(c):
		var holder: Unit = s.zoc_holder(s.player, selected.pos)
		if s.zoc_blocks(s.player, selected.pos, c):
			lines.append("Zone of control: your unit is next to a %s army and can't slip past it to here. Attack it, step away, or stay." % holder.faction.name)
		elif s.in_enemy_zoc(s.player, c) and selected.max_moves() > 1:
			lines.append("Zone of control: stepping here, next to an enemy army, ends your unit's move.")
	if s.is_ash(c):
		lines.append("Ash: dead land. No outposts, no income, counts as nobody's land.")
	var land: int = s.terrain_at(c)
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
	lines.append(text)
	return lines

# A small health bar under a unit: green when healthy, through yellow, to red.
func draw_hp_bar(at: Vector2, hp: int) -> void:
	var w := 26.0
	var frac := clampf(float(hp) / Unit.MAX_HP, 0.0, 1.0)
	draw_rect(Rect2(at - Vector2(w / 2 + 1, 1), Vector2(w + 2, 5)), Color(0.08, 0.08, 0.08))
	var col := Color(0.85, 0.2, 0.15).lerp(Color(0.95, 0.85, 0.2), clampf(frac * 2.0, 0.0, 1.0)) if frac < 0.5 else Color(0.95, 0.85, 0.2).lerp(Color(0.3, 0.85, 0.3), (frac - 0.5) * 2.0)
	draw_rect(Rect2(at - Vector2(w / 2, 0), Vector2(w * frac, 3)), col)

# A Rift Walker: a dark knot of roots with a cold blue rim (the season's colour).
func draw_walker(c: Vector2) -> void:
	var r := HexView2D.HEX_SIZE * 0.5
	draw_circle(c, r + 2.0, SEASON_COLOUR)
	draw_circle(c, r, Color(0.08, 0.1, 0.16))
	for i in 3: # three roots twisting out from the middle
		var a := TAU * i / 3.0 + 0.4
		var mid := c + Vector2.from_angle(a) * r * 0.45 + Vector2.from_angle(a + PI / 2) * r * 0.2
		draw_polyline(PackedVector2Array([c, mid, c + Vector2.from_angle(a) * r * 0.85]), Color(SEASON_COLOUR, 0.85), 2.0)
	draw_circle(c, r * 0.18, Color(0.75, 0.9, 1.0))

# A rift in the void: a dark swirl.
func draw_rift(rc: Vector2) -> void:
	var glow := Rifts.season_on(state.turn) # the season: the rifts glow
	if glow:
		draw_circle(rc, HexView2D.HEX_SIZE * 0.8, Color(SEASON_COLOUR, 0.5))
	var ring := SEASON_COLOUR if glow else Color(0.6, 0.3, 0.8)
	draw_circle(rc, HexView2D.HEX_SIZE * 0.5, Color(0.12, 0.05, 0.18))
	draw_arc(rc, HexView2D.HEX_SIZE * 0.5, 0, TAU, 24, ring, 3.0 if glow else 2.0)
	draw_arc(rc, HexView2D.HEX_SIZE * 0.28, 0.5, TAU * 0.8, 16, ring, 2.0)

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
