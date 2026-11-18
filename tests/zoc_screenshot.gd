extends SceneTree
const H := preload("res://tests/helpers.gd")
# Zone of control on screen: your army selected next to a Japanese army (at
# war). Hovers the enemy army, a hex the rule forbids and a free hex; saves
# zoc_*.png to $S and prints each tooltip.
var m
func hover(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos
	Input.parse_input_event(e)
	for i in 4: await process_frame
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("S"), file])
func _initialize() -> void:
	seed(12)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	H.answer_choices(s)
	var jp = s.ais[0]
	var p = s.player.units[0]; p.pos = Vector2i(7, 7); p.moves = 1
	jp.units[0].pos = Vector2i(8, 7)
	s.relation(jp).rival_declare_war("test")
	s.update_sight(); m.selected = p; m.refresh()
	for i in 3: await process_frame
	var blocked: Vector2i = HexMap.neighbours(p.pos).filter(func(c): return HexMap.is_neighbour(c, jp.units[0].pos))[0]
	var free: Vector2i = HexMap.neighbours(p.pos).filter(func(c): return HexMap.hex_distance(c, jp.units[0].pos) >= 2)[0]
	for pair in [["army", jp.units[0].pos], ["blocked", blocked], ["free", free]]:
		await hover(HexView2D.hex_center(pair[1]))
		print("%s %s: %s" % [pair[0], pair[1], m.hex_tooltip(m.hover_cell)])
		await shot("zoc_" + pair[0])
	quit()
