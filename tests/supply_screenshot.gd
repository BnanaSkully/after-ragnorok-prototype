extends SceneTree
const H := preload("res://tests/helpers.gd")
# Builds armies by clicking until supply is full: the Army button greys out
# and says so; hovering "Units" explains supply and upkeep. Saves supply.png.
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
	seed(4)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	s.player.industry = 40; s.player.food = 30; m.refresh()
	var clicks := 0
	while not m.build_button.disabled and clicks < 10:
		await click_at(m.build_button.get_global_rect().get_center()); clicks += 1
	print("after %d clicks: button '%s' disabled=%s; armies %d, supply %d, upkeep %d; message: %s" % [clicks, m.build_button.text, m.build_button.disabled, s.army_count(s.player), s.supply_cap(s.player), s.army_upkeep(s.player), s.messages])
	for t in m.top_bar_tips:
		if t[1].begins_with("Units"): await hover(t[0].get_center())
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/supply.png" % OS.get_environment("S"))
	quit()
