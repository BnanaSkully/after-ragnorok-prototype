extends SceneTree
const H := preload("res://tests/helpers.gd")
# Rogue Sunna in the 3D view (her model walking, lit gold) and the map pins that
# show units, Sköll and Sunna when zoomed out (hidden close up).
# Needs a window (not --headless). Saved to $S.
var m
var ok := true
func check(cond: bool, what: String) -> void:
	print(("OK   " if cond else "FAIL ") + what)
	ok = ok and cond
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OS.get_environment("S"), file])
func _initialize() -> void:
	seed(11)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	s.start_landing()
	var spots: Array = H.landing_spots(s)
	spots.sort_custom(func(a, b): return absi(a.x - 7) + absi(a.y - 5) < absi(b.x - 7) + absi(b.y - 5))
	s.try_land(spots[0])
	var home: Vector2i = s.player.city_pos
	s.reveal_area(s.player, home, 6)
	# Sunna walks out onto a free land hex next to the city
	var out := HexMap.NO_CELL
	for n in HexMap.neighbours(home):
		if s.passable(n) and s.unit_at(n) == null:
			out = n
			break
	s.daughter.go_rogue(out)
	# Sköll loose two hexes beyond her
	s.skoll.active = true
	s.skoll.pos = home + Vector2i(3, 0)
	s.skoll.target = s.player
	s.update_sight(); m.refresh()
	m.toggle_3d()
	var v = m.view_3d
	for i in 30: await process_frame
	check(v.sunna.visible, "rogue Sunna is shown")
	check(v.sunna.position.distance_to(v.cell_position(out) + Vector3(0, v.hex_top(out), 0)) < 0.01, "she stands on her hex")
	v.cam_target = v.cell_position(out); v.cam_distance = 7.0; v.place_camera()
	for i in 10: await process_frame
	check(not v.markers[v.sunna].visible, "close up, no pins")
	await shot("sunna3d_close.png")
	# she walks one hex away
	var next := HexMap.NO_CELL
	for n in HexMap.neighbours(out):
		if s.passable(n) and n != home and s.unit_at(n) == null:
			next = n
			break
	s.daughter.pos = next
	for i in 2: await process_frame
	check(v.sunna_walk > 0.0 and v.sunna_anim.current_animation == "walk", "she walks to her new hex (walk %.2f s left, playing %s)" % [v.sunna_walk, v.sunna_anim.current_animation])
	await shot("sunna3d_walking.png")
	v.cam_target = v.cell_position(home); v.cam_distance = 24.0; v.place_camera()
	for i in 40: await process_frame
	check(v.markers[v.sunna].visible and v.markers[v.skoll].visible, "zoomed out, Sunna and Sköll have pins")
	var unit_pins := 0
	for fig in v.figures.values():
		if v.markers.has(fig) and v.markers[fig].visible: unit_pins += 1
	check(unit_pins == v.figures.size() and unit_pins > 0, "zoomed out, every unit you see has a pin (%d)" % unit_pins)
	await shot("sunna3d_far.png")
	print("ALL OK" if ok else "FAILED")
	quit()
