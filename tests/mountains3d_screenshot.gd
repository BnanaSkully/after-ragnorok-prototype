extends SceneTree
const H := preload("res://tests/helpers.gd")
# Mountains in the 3D view, built from the peak props: a range of joined mountain
# hexes and one lone mountain (mountains3d.png, mountains3d_close.png,
# mountains3d_low.png), and a real random map (mountains3d_map.png).
# Needs a window (not --headless). Saved to $S.
var m
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OS.get_environment("S"), file])
func _initialize() -> void:
	seed(7)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	s.start_landing()
	var spots: Array = H.landing_spots(s)
	s.try_land(spots[0])
	# the rest of the map (a random one) first, from far away
	s.reveal_area(s.player, Vector2i(7, 5), 12)
	s.update_sight(); m.refresh()
	m.toggle_3d()
	for i in 30: await process_frame
	await shot("mountains3d_map.png")
	# a range bending across five hexes, a pair, and a lone peak, on plains
	var v = m.view_3d
	var at := Vector2i(7, 5)
	for c in s.terrain:
		if HexMap.hex_distance(c, at) <= 3 and s.terrain[c] == Terrain.Type.MOUNTAINS:
			s.terrain[c] = Terrain.Type.PLAINS
	for c in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 3), Vector2i(10, 3), Vector2i(5, 7)]:
		s.terrain[c] = Terrain.Type.MOUNTAINS
	m.refresh()
	for i in 5: await process_frame
	v.cam_target = v.cell_position(at); v.cam_distance = 11.0; v.place_camera()
	for i in 10: await process_frame
	await shot("mountains3d.png")
	v.cam_distance = 6.5; v.place_camera()
	for i in 5: await process_frame
	await shot("mountains3d_close.png")
	v.camera.position = v.cell_position(at) + Vector3(-1.0, 1.4, 5.5)
	v.camera.look_at(v.cell_position(Vector2i(6, 5)) + Vector3(0, 0.7, 0), Vector3.UP)
	for i in 5: await process_frame
	await shot("mountains3d_low.png")
	quit()
