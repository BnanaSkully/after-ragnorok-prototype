extends SceneTree
const H := preload("res://tests/helpers.gd")
# Real clicks: open "Build...", build a Granary by clicking, open it again.
# Saves city_panel.png to $S.
var m
func click_at(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	for i in 3: await process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; e.position = pos; e.global_position = pos
		Input.parse_input_event(e)
		for i in 3: await process_frame
func _initialize() -> void:
	seed(2)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	s.player.industry = 20; m.refresh()
	await click_at(m.walls_button.get_global_rect().get_center())
	var granary = m.city_buttons.get_children().filter(func(b): return b.text.begins_with("Granary"))[0]
	await click_at(granary.get_global_rect().get_center())
	print("clicked Granary: built=%s, Industry %d, Food a turn %+d" % [s.player.buildings.has("granary"), s.player.industry, s.food_change(s.player)])
	await click_at(m.walls_button.get_global_rect().get_center())
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("%s/city_panel.png" % OS.get_environment("S"))
	quit()
