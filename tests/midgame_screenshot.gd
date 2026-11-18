extends SceneTree
const H := preload("res://tests/helpers.gd")
# Part 2 on screen: turn 22 with Sköll (returned, wounded) next to your city,
# ash on the map, your city damaged, his tooltip (midgame.png); Sunna's
# request pop-up (request.png); Sunna risen (risen.png). Saved to $S.
var m
func hover(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos
	Input.parse_input_event(e)
	for i in 4: await process_frame
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OS.get_environment("S"), file])
func _initialize() -> void:
	seed(5)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	s.daughter.join(s.player); s.player.favour = 6
	s.turn = 22
	s.reveal_area(s.player, Vector2i(7, 5), 9)
	s.skoll.active = true; s.skoll.returns = 2; s.skoll.strength = 14; s.skoll.wounds = 4
	s.skoll.knows_her = true; s.skoll.target = s.player
	s.skoll.pos = s.player.city_pos + Vector2i(2, 0)
	for i in 2: s.spread_ash(Vector2i(1, 9))
	s.player.city_hp = 11
	s.player.add_unit(s.player.city_pos + Vector2i(1, 0))
	s.update_sight(); m.refresh()
	await hover(HexView2D.hex_center(s.skoll.pos))
	print("Sköll tooltip: %s" % [m.hex_tooltip(s.skoll.pos)])
	await shot("midgame.png")
	s.next_request_turn = s.turn
	s.maybe_sunna_request(); m.refresh()
	await shot("request.png")
	m.on_choice(1) # refuse, as a click on the button would
	s.player.favour = 8
	s.maybe_rise(); s.update_sight(); m.refresh()
	await hover(Vector2(5, 5))
	await shot("risen.png")
	quit()
