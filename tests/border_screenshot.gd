extends SceneTree
const H := preload("res://tests/helpers.gd")
# Your army next to Celtic land at peace: the closed-border hexes show in a
# warning colour; one click warns that entering declares war; then the Deal
# panel with "Ask for open borders". Saves borders.png and borders_deal.png.
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
	seed(6)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	var celtic = s.ais[1]
	var a = s.player.units[0]; a.moves = 1
	for row in HexMap.ROWS: # a free hex 2 from the Celtic city: right outside their land
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if HexMap.hex_distance(c, celtic.city_pos) == 2 and s.unit_at(c) == null and c.x > celtic.city_pos.x:
				a.pos = c
	s.reveal_area(s.player, celtic.city_pos, 3)
	s.update_sight(); m.refresh()
	await click_at(HexView2D.hex_center(a.pos))
	var target = HexMap.neighbours(a.pos).filter(func(c): return s.territory_owner(c) == celtic and s.unit_at(c) == null and not s.is_city(c))
	print("closed-border neighbours: %d" % target.size())
	if not target.is_empty():
		await click_at(HexView2D.hex_center(target[0]))
		print("after one click: at war=%s; message: %s" % [s.at_war(s.player, celtic), s.messages])
	await shot("borders")
	s.messages.clear(); m.selected = null; m.break_warning_cell = HexMap.NO_CELL; m.refresh()
	await click_at(m.faction_buttons[celtic]["deal"].get_global_rect().get_center())
	print("deal options: %s" % [m.deal_buttons.get_children().map(func(b): return b.text).slice(0, 2)])
	await shot("borders_deal")
	quit()
