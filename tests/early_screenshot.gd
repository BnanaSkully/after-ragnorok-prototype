extends SceneTree
const H := preload("res://tests/helpers.gd")

# Real clicks in a window through the early game. Saves to $S:
# landing.png, turn1.png, scout.png, outpost.png, popup.png, turn9.png
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
func shot(name: String) -> void:
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("S"), name])
func live_buttons(box: Node) -> Array:
	return box.get_children().filter(func(b): return not b.is_queued_for_deletion() and not b.disabled)

func _initialize() -> void:
	seed(7)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 5:
		await click_button(live_buttons(m.crossing_buttons)[0])
	await shot("landing")
	var spot: Vector2i = Vector2i(6, 4) if s.can_land_at(Vector2i(6, 4)) else H.landing_spots(s)[0]
	await click_at(HexView2D.hex_center(spot))
	print("landed at %s: %s; Industry %d; units %s" % [spot, s.phase == GameState.Phase.PLAYING, s.player.industry, s.player.units.map(func(u): return "scout" if u.is_scout() else "army")])
	print("buttons: army %s, scout %s, outpost %s, walls %s (disabled?)" % [m.build_button.disabled, m.scout_button.disabled, m.outpost_button.disabled, m.walls_button.disabled])
	await shot("turn1")
	# move the scout twice by clicking, toward the unexplored dark
	var scout = s.player.units.filter(func(u): return u.is_scout())[0]
	await click_at(HexView2D.hex_center(scout.pos))
	for i in 2:
		var goal = s.nearest_unexplored(s.player, scout.pos)
		var step: Vector2i = s.step_toward(scout.pos, goal)
		await click_at(HexView2D.hex_center(step))
	print("scout moved 2 by clicks: at %s, moves left %d, explored %d hexes" % [scout.pos, scout.moves, s.player.explored.size()])
	await shot("scout")
	await click_button(m.outpost_button)
	var spots = s.outpost_spots(s.player)
	print("outpost mode: %d hexes light up, button says '%s'" % [spots.size(), m.outpost_button.text])
	await shot("outpost")
	if not spots.is_empty():
		await click_at(HexView2D.hex_center(spots[0]))
	print("outposts now %s, Industry %d" % [s.player.outposts, s.player.industry])
	# play on (clicking End Turn) until a pop-up shows
	var popup_seen := false
	while s.turn < 9:
		if m.choice_panel.visible:
			if not popup_seen:
				popup_seen = true
				print("pop-up on turn %d: %s" % [s.turn, m.choice_heading.text])
				await shot("popup")
			await click_button(live_buttons(m.choice_buttons)[0])
			continue
		if m.offer_panel.visible:
			await click_button(m.offer_accept_button)
			continue
		await click_button(m.end_turn_button)
	await shot("turn9")
	print("turn %d: explored %d, outposts %d, Industry %d" % [s.turn, s.player.explored.size(), s.player.outposts.size(), s.player.industry])
	quit()
