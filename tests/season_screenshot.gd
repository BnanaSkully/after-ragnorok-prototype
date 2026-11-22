extends SceneTree
# Full rifts step 3: during the season the rifts you know glow (2D: a blue halo;
# 3D: a cold blue light), the goal line names the season, and the rift tooltip
# says it glows. Shots: season_2d.png, season_3d.png.
# Run: S=<dir> xvfb-run -a -s "-screen 0 1152x648x24" godot --rendering-driver opengl3 --script tests/season_screenshot.gd
const H := preload("res://tests/helpers.gd")
var failed := false

func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("S").path_join(file))

func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	failed = failed or not ok

func _initialize() -> void:
	seed(11)
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s)
	s.start_landing()
	s.try_land(H.landing_spots(s)[0])
	H.answer_choices(s)
	var home: Vector2i = s.player.city_pos
	var rifts: Array[Vector2i] = []
	for c in s.terrain:
		if rifts.size() < 2 and HexMap.hex_distance(c, home) == 2 and rifts.all(func(r): return HexMap.hex_distance(r, c) >= 2):
			rifts.append(c)
	for r in rifts: s.player.known_rifts[r] = true
	s.turn = Rifts.SEASON_FIRST
	s.messages.clear()
	s.update_sight(); m.refresh()
	for i in 5: await process_frame
	var goal: String = m.goal_line()[0]
	check(goal.begins_with(Rifts.season_title()), "goal line names the season: %s" % goal)
	var tip: Array = m.hex_tooltip(rifts[0])
	check(tip.any(func(l): return "It glows" in l), "the rift tooltip says it glows")
	await shot("season_2d.png")
	m.toggle_3d()
	var v = m.view_3d
	v.cam_target = v.cell_position(rifts[0]); v.cam_distance = 8.0; v.place_camera()
	for i in 20: await process_frame
	var glow = v.rift_models[rifts[0]].get_node_or_null("SeasonGlow")
	check(glow != null and glow.visible, "3D: the rift's season light is on")
	await shot("season_3d.png")
	s.turn = Rifts.SEASON_FIRST + Rifts.SEASON_LENGTH
	m.refresh()
	for i in 5: await process_frame
	check(not v.rift_models[rifts[0]].get_node("SeasonGlow").visible, "3D: the light is off once the season has passed")
	print("ALL OK" if not failed else "SOME CHECKS FAILED")
	quit()
