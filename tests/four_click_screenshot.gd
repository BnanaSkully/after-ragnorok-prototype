extends SceneTree
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
func _initialize() -> void:
	seed(15)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 5:
		await click_button(m.crossing_buttons.get_children().filter(func(b): return not b.is_queued_for_deletion())[0])
	await click_at(HexView2D.hex_center(Vector2i(6, 4)))
	print("landed: %s" % (s.phase == GameState.Phase.PLAYING))
	var greek = s.ais[2]
	var celtic = s.ais[1]
	s.relation(greek).trust = 10
	m.refresh()
	await click_button(m.faction_buttons[greek]["pact"])
	print("clicked Greek treaty button: Greek treaty=%s, others: Japanese %s Celtic %s; Celtic button disabled now (one action a turn)=%s" % [s.relation(greek).pact_active(), s.relation(s.ais[0]).pact_active(), s.relation(celtic).pact_active(), m.faction_buttons[celtic]["pact"].disabled])
	print("   msg: %s" % [s.messages])
	# force an offer from the Celtic and check the pop-up names them
	await click_button(m.end_turn_button)
	if m.offer_panel.visible: await click_button(m.offer_accept_button)
	s.relation(celtic).pending = {"type": "oath"}
	m.refresh()
	for i in 3: await process_frame
	print("pop-up heading: '%s', accept button '%s'" % [m.offer_heading.text, m.offer_accept_button.text])
	await click_button(m.offer_accept_button)
	print("accepted -> Celtic bond=%s, pop-up hidden=%s" % [s.relation(celtic).pact_active(), not m.offer_panel.visible])
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("%s/four_click.png" % OS.get_environment("S"))
	quit()
