extends SceneTree
const H := preload("res://tests/helpers.gd")
# Real clicks: open the Deal panel for a faction at peace and one at war,
# make a trade by clicking. Saves deal_peace.png and deal_war.png to $S.
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
func _initialize() -> void:
	seed(5)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	var celtic = s.ais[1]; var greek = s.ais[2]
	celtic.food = 2; s.player.food = 12
	s.relation(greek).rival_declare_war("test")
	m.refresh()
	await click_button(m.faction_buttons[celtic]["deal"])
	print("deal panel open=%s: %d options" % [m.deal_panel.visible, m.deal_buttons.get_child_count()])
	await shot("deal_peace")
	var trade_btn = m.deal_buttons.get_children().filter(func(b): return b.text.begins_with("Trade 5 Food"))[0]
	var food = s.player.food
	await click_button(trade_btn)
	print("clicked '%s': Food %d -> %d, panel closed=%s, Deal buttons now disabled=%s" % [trade_btn.text, food, s.player.food, not m.deal_panel.visible, m.faction_buttons[greek]["deal"].disabled])
	s.diplomacy_action_used = false
	m.refresh()
	await click_button(m.faction_buttons[greek]["deal"])
	await shot("deal_war")
	quit()
