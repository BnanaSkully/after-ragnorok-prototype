extends SceneTree
const H := preload("res://tests/helpers.gd")
# The HUD (Nathan's mockup, EL2 style) at 1152x648: turn 1 and turn 16, in 2D
# and 3D, with every panel closed and with each panel open, a toast, and the red
# badges beside End Turn. Real clicks on the round buttons. Saved to $S as hud_*.png.
# Needs a window (not --headless):
#   S=/tmp/shots xvfb-run -a -s "-screen 0 1152x648x24" godot --rendering-driver opengl3 --script tests/hud_screenshot.gd
var m
func click_at(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	for i in 3: await process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; e.position = pos; e.global_position = pos
		Input.parse_input_event(e)
		for i in 3: await process_frame
func click_button(b: Button) -> void:
	await click_at(b.get_global_rect().get_center())
func shot(file: String) -> void:
	Input.warp_mouse(Vector2(40, 620)) # (out of the way: no tooltip)
	for i in 3: await process_frame
	m.hover_cell = HexMap.NO_CELL; m.hover_pos = Vector2(-1, -1); m.queue_redraw()
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("S"), file])
func panels(prefix: String) -> void:
	for key in ["diplomacy", "build", "sunna", "chronicle", "settings"]:
		await click_button(m.icon_buttons[key])
		print("%s: opened %s (open_panel=%s), panel size %s" % [prefix, key, m.open_panel, m.panels[key].size])
		await shot("%s_%s" % [prefix, key])
	await click_button(m.icon_buttons["settings"]) # closes it again
	print("%s: closed, open_panel='%s'" % [prefix, m.open_panel])
func _initialize() -> void:
	seed(11)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	s.start_landing(); m.refresh()
	await shot("hud_landing")
	var spots: Array = H.landing_spots(s)
	spots.sort_custom(func(a, b): return absi(a.x - 7) + absi(a.y - 5) < absi(b.x - 7) + absi(b.y - 5))
	s.try_land(spots[0])
	s.update_sight(); m.refresh()
	for i in 10: await process_frame
	await shot("hud_turn1")
	print("goal turn 1: %s" % [m.goal_line()[0]])
	await panels("hud_turn1")
	while s.turn <= 15 and not s.game_over:
		H.answer_choices(s)
		s.end_turn()
		if s.turn < 15 and s.has_pending_offer(): s.pending_relation().answer(false)
		if s.turn < 15: H.answer_choices(s)
		s.reveal_area(s.player, s.player.city_pos, mini(2 + int(s.turn / 3.0), 7))
		s.update_sight()
	print("turn %d, waiting %s, chronicle %d entries" % [s.turn, s.is_waiting(), m.chronicle.size()])
	m.refresh()
	for i in 4: await process_frame
	await shot("hud_turn16_popup")
	if s.is_waiting():
		var hide: Node = m.choice_panel if m.choice_panel.visible else m.offer_panel
		for b in hide.find_children("*", "Button", true, false):
			if b.text.begins_with("Look at the map"): await click_button(b)
		print("pop-up put aside: popups_hidden=%s, badges %s" % [m.popups_hidden, ["offer", "request", "popup"].map(func(k): return "%s=%d" % [k, m.badge_count(k)])])
	s.messages.assign(["Sköll came through a rift near the Greek city. The ash spreads.", "Your scouts report a new rift to the east."])
	for i in 8: await process_frame
	await shot("hud_turn16")
	print("goal turn 16: %s" % [m.goal_line()[0]])
	await panels("hud_turn16")
	m.toggle_3d()
	for i in 30: await process_frame
	var v = m.view_3d
	var last: Vector3 = v.cell_position(Vector2i(HexMap.COLS - 1, HexMap.ROWS - 1))
	v.cam_target = Vector3(last.x * 0.5, 0.0, last.z * 0.5); v.cam_distance = 18.0; v.place_camera()
	for i in 10: await process_frame
	await shot("hud_turn16_3d")
	await click_button(m.icon_buttons["diplomacy"])
	await shot("hud_turn16_3d_diplomacy")
	v.cam_target = v.cell_position(s.player.city_pos); v.cam_distance = 10.0; v.place_camera()
	await click_button(m.icon_buttons["diplomacy"])
	for i in 10: await process_frame
	await shot("hud_turn16_3d_city")
	quit()
