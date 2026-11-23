extends SceneTree
const H := preload("res://tests/helpers.gd")
# The production queue in the Build panel, and the Queue buttons in the city
# buildings panel, at 1152x648 (2D). Saved to $S as queue_*.png.
#   S=/tmp/shots xvfb-run -a -s "-screen 0 1152x648x24" godot --rendering-driver opengl3 --script tests/queue_screenshot.gd
var m
func shot(file: String) -> void:
	Input.warp_mouse(Vector2(40, 620))
	for i in 3: await process_frame
	m.hover_cell = HexMap.NO_CELL; m.hover_pos = Vector2(-1, -1); m.queue_redraw()
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("S"), file])
func _initialize() -> void:
	seed(11)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	s.start_landing()
	var spots: Array = H.landing_spots(s)
	s.try_land(spots[0])
	H.answer_choices(s)
	s.player_queue("army"); s.player_queue("granary"); s.player_queue("walls"); s.player_queue("scout"); s.player_queue("forge")
	s.end_turn()
	if s.has_pending_offer(): s.pending_relation().answer(false)
	H.answer_choices(s)
	m.open_panel = "build"; m.refresh()
	for i in 6: await process_frame
	await shot("queue_build")
	print("build panel size %s; queue %s, production %d" % [m.panels["build"].size, s.player.queue, s.player.production])
	m.on_open_city()
	for i in 6: await process_frame
	await shot("queue_city")
	quit()
