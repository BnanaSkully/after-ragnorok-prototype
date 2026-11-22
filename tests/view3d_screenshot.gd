extends SceneTree
const H := preload("res://tests/helpers.gd")
# The 3D view (press V in the game): turn 16 with Sköll loose two hexes from
# your city, standing still and looking at the camera (view3d.png), then walking
# one hex (view3d_walk.png). Also the 2D view again after V (view3d_back.png).
# Needs a window (not --headless). Saved to $S.
var m
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OS.get_environment("S"), file])
func press_v() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_V; e.pressed = true
	Input.parse_input_event(e)
	for i in 3: await process_frame
func _initialize() -> void:
	seed(5)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	s.turn = 16
	s.reveal_area(s.player, Vector2i(7, 5), 6)
	s.skoll.active = true
	s.skoll.target = s.player
	s.skoll.pos = s.player.city_pos + Vector2i(2, 1)
	s.player.add_unit(s.player.city_pos + Vector2i(1, 0))
	s.update_sight(); m.refresh()
	await press_v()
	print("3D view shown: %s" % m.showing_3d)
	for i in 30: await process_frame
	await shot("view3d.png")
	var v = m.view_3d
	v.cam_target = v.cell_position(s.skoll.pos); v.cam_distance = 5.0; v.place_camera()
	for i in 5: await process_frame
	await shot("view3d_skoll.png") # close up: his colour texture should show (not grey)
	v.cam_distance = 22.0; v.place_camera()
	s.skoll.pos = s.skoll.pos + Vector2i(-1, 0) # one hex toward the city
	for i in 15: await process_frame # partway through his walk
	await shot("view3d_walk.png")
	await press_v()
	print("back to 2D: %s" % (not m.showing_3d))
	await shot("view3d_back.png")
	quit()
