extends SceneTree
# Full rifts step 4: Rift Walkers on the map. 2D: a dark knot of roots with a
# blue rim and an HP bar; 3D: Nathan's brood model with a blue pin when zoomed
# out. The second one is a skeleton horde (2D a pale skull; 3D a placeholder,
# the warrior painted bone-white). The tooltip says what it
# is and what it costs; the hex is marked for attack next to a selected unit.
# Shots: walker_2d.png, walker_3d.png, walker_3d_far.png.
# Run: S=<dir> xvfb-run -a -s "-screen 0 1152x648x24" godot --rendering-driver opengl3 --script tests/walker_screenshot.gd
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
	var army = s.player.units.filter(func(u): return not u.is_scout())[0]
	# a Walker on your land, next to your army, and another one a little farther out
	var near := HexMap.NO_CELL
	var far := HexMap.NO_CELL
	for c in HexMap.neighbours(home):
		if near == HexMap.NO_CELL and not s.is_blocked(c):
			near = c
	for c in s.terrain:
		if far == HexMap.NO_CELL and HexMap.hex_distance(c, home) == 3 and not s.is_blocked(c):
			far = c
	s.rifts.walkers.append(RiftWalker.new(near, far))
	s.rifts.walkers.append(RiftWalker.new(far, far, RiftWalker.Kind.HORDE)) # a skeleton horde
	s.rifts.walkers[1].hp = 4
	s.turn = Rifts.SEASON_FIRST
	s.messages.clear()
	s.update_sight()
	m.selected = army
	m.refresh()
	for i in 5: await process_frame
	var tip: Array = m.hex_tooltip(near)
	check(tip.any(func(l): return "brood" in l), "tooltip names the brood: %s" % [tip.slice(0, 3)])
	check(tip.any(func(l): return "eating 1 of your Food" in l), "tooltip says it eats your Food")
	check(tip.any(func(l): return "If your selected unit attacks" in l), "tooltip predicts the fight")
	var no_spots: Array[Vector2i] = []
	check(m.highlight_of(near, no_spots) == Color(0.95, 0.45, 0.2), "its hex is marked for attack next to your army")
	check(m.hex_tooltip(far).any(func(l): return "skeleton horde" in l and "4/6" in l), "tooltip names the skeleton horde: %s" % [m.hex_tooltip(far).slice(0, 2)])
	check(s.food_parts(s.player).any(func(p): return "Brood" in p[0]), "Food breakdown lists it")
	m.hover_cell = near
	await shot("walker_2d.png")
	m.toggle_3d()
	var v = m.view_3d
	v.cam_target = v.cell_position(near); v.cam_distance = 7.0; v.place_camera()
	for i in 20: await process_frame
	check(v.walker_figures.size() == 2, "3D: both Walkers have a figure (%d)" % v.walker_figures.size())
	await shot("walker_3d.png")
	v.cam_target = v.cell_position(far); v.place_camera()
	for i in 10: await process_frame
	await shot("horde_3d.png")
	v.cam_target = v.cell_position(near)
	v.cam_distance = 22.0; v.place_camera()
	for i in 10: await process_frame
	var pins := 0
	for fig in v.walker_figures.values():
		if v.markers.has(fig) and v.markers[fig].visible: pins += 1
	check(pins == 2, "3D: zoomed out, both have a pin (%d)" % pins)
	await shot("walker_3d_far.png")
	print("ALL OK" if not failed else "SOME CHECKS FAILED")
	quit()
