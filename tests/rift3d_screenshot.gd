extends SceneTree
# A known rift in 3D shows Nathan's rift tile, whole, in place of its land tile (he
# modelled it as a tile; overlaying it on the land looked wrong). One rift on each land
# a rift can be on: plains, forest, hills. Shots: rift3d_close.png, rift3d_far.png.
# Run: S=<dir> xvfb-run -a -s "-screen 0 1152x648x24" godot --rendering-driver opengl3 --script tests/rift3d_screenshot.gd
const H := preload("res://tests/helpers.gd")
var m
var v
var failed := false

func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("S").path_join(file))

func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	failed = failed or not ok

func _initialize() -> void:
	seed(11)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s)
	s.start_landing()
	s.try_land(H.landing_spots(s)[0])
	H.answer_choices(s)
	var home: Vector2i = s.player.city_pos
	var lands := [Terrain.Type.PLAINS, Terrain.Type.FOREST, Terrain.Type.HILLS]
	var rifts: Array[Vector2i] = []
	for c in s.terrain: # three hexes 3 away from your city, apart from each other
		if rifts.size() < 3 and HexMap.hex_distance(c, home) == 3 and rifts.all(func(r): return HexMap.hex_distance(r, c) >= 2):
			rifts.append(c)
	for i in 3:
		s.terrain[rifts[i]] = lands[i]
		s.player.known_rifts[rifts[i]] = true
	s.reveal_area(s.player, home, 5)
	s.update_sight(); m.refresh()
	m.toggle_3d()
	v = m.view_3d
	v.cam_target = v.cell_position(rifts[1]); v.cam_distance = 7.0; v.place_camera()
	for i in 20: await process_frame
	for c in rifts:
		var tile: Node3D = v.hexes[c].get_node_or_null("Model")
		check(tile != null and str(tile.get_meta("key")) == "rift", "the rift at %s shows the rift tile" % c)
	var plain: Node3D = v.hexes[home].get_node_or_null("Model")
	check(plain != null and str(plain.get_meta("key")) != "rift", "a hex with no rift shows its own tile")
	await shot("rift3d_close.png")
	v.cam_target = v.cell_position(home); v.cam_distance = 16.0; v.place_camera()
	for i in 10: await process_frame
	await shot("rift3d_far.png")
	print("ALL OK" if not failed else "SOME CHECKS FAILED")
	quit()
