extends SceneTree
const H := preload("res://tests/helpers.gd")
# Real clicks: the war warning (first click on a unit you're at peace with),
# the side panel's war/peace/ally lines, and the call-to-arms pop-up.
# Saves war_warning.png and call_to_arms.png to $S.
var m
func click_at(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	for i in 3: await process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; e.position = pos; e.global_position = pos
		Input.parse_input_event(e)
		for i in 3: await process_frame
func shot(name: String) -> void:
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("S"), name])
func _initialize() -> void:
	seed(3)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	var jp = s.ais[0]; var celtic = s.ais[1]; var greek = s.ais[2]
	s.relation(celtic).pact_turns_left = 10
	s.relation(greek).rival_declare_war("their army is far stronger")
	s.ai_war_since[s.pair_key(jp, greek)] = 1
	s.pending_choices.clear()
	var pu = s.player.units[0]; pu.pos = Vector2i(7, 3)
	jp.units[0].pos = Vector2i(8, 3)
	s.update_sight(); m.refresh()
	await click_at(HexView2D.hex_center(pu.pos))
	await click_at(HexView2D.hex_center(Vector2i(8, 3)))
	print("after one click: at war with Japanese=%s; message: %s" % [s.at_war(s.player, jp), s.messages])
	await shot("war_warning")
	s.ai_declare_war(jp, celtic)
	m.refresh()
	print("pop-up visible=%s: %s" % [m.choice_panel.visible, m.choice_heading.text])
	await shot("call_to_arms")
	quit()
