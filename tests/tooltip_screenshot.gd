extends SceneTree
const H := preload("res://tests/helpers.gd")
# Hovering with a real mouse: the top bar's Food and Pop, your city, an AI
# unit, Sköll and a rift. Saves tip_*.png to $S and prints each tooltip.
var m
func hover(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos
	Input.parse_input_event(e)
	for i in 4: await process_frame
func shot(name: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("S"), name])
func tip_text() -> Array:
	for t in m.top_bar_tips:
		if t[0].has_point(m.hover_pos): return [t[1]]
	return m.hex_tooltip(m.hover_cell)
func _initialize() -> void:
	seed(12)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	s.player_build_building("granary"); s.player.population = 3
	var jp = s.ais[0]
	jp.units[0].pos = Vector2i(8, 5); s.terrain[Vector2i(8, 5)] = Terrain.Type.HILLS
	s.skoll.active = true; s.skoll.pos = Vector2i(4, 6); s.skoll.target = s.player
	s.player.known_rifts[Vector2i(3, 7)] = true
	s.update_sight(); m.refresh()
	for i in 3: await process_frame
	for t in m.top_bar_tips:
		if t[1].begins_with("Food"): await hover(t[0].get_center()); print("FOOD: %s" % [tip_text()]); await shot("tip_food")
	for t in m.top_bar_tips:
		if t[1].begins_with("Population"): await hover(t[0].get_center()); print("POP: %s" % [tip_text()])
	for c in [s.player.city_pos, Vector2i(8, 5), Vector2i(4, 6), Vector2i(3, 7)]:
		await hover(HexView2D.hex_center(c))
		print("HEX %s: %s" % [c, tip_text()])
		if c == Vector2i(8, 5): await shot("tip_unit")
		if c == s.player.city_pos: await shot("tip_city")
	quit()
