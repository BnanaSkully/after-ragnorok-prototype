extends SceneTree
const H := preload("res://tests/helpers.gd")
# HP bars on units at different health, and the tooltip of an enemy next to
# your selected unit (predicted damage). Saves health.png to $S.
var m
func click_at(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	for i in 3: await process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; e.position = pos; e.global_position = pos
		Input.parse_input_event(e)
		for i in 3: await process_frame
func hover(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos
	Input.parse_input_event(e)
	for i in 4: await process_frame
func _initialize() -> void:
	seed(3)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	var jp = s.ais[0]
	s.relation(jp).rival_declare_war("test")
	var a = s.player.add_unit(Vector2i(7, 6)); a.hp = 7
	var b = s.player.add_unit(Vector2i(5, 6)); b.hp = 3
	var e = jp.units[0]; e.pos = Vector2i(8, 6); e.hp = 5
	s.update_sight(); m.refresh()
	await click_at(HexView2D.hex_center(a.pos))
	await hover(HexView2D.hex_center(e.pos))
	print("tooltip: %s" % [m.hex_tooltip(e.pos)])
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/health.png" % OS.get_environment("S"))
	quit()
