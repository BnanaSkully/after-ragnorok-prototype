extends SceneTree
const H := preload("res://tests/helpers.gd")
# Contested Sunna on screen: the line under the top bar saying what she still
# needs to rise (contested_line.png), and an AI claiming her as its lost sun
# (claim.png). Saved to $S.
var m
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
	s.daughter.join(s.player); s.player.favour = 7
	s.turn = 21
	s.update_sight(); m.refresh()
	print("missing: %s" % [s.rise_missing(s.player)])
	await shot("contested_line.png")
	var r = s.relation(s.ais[0])
	r.pending = {"type": "claim"}
	print("claim: %s" % r.pending_text())
	m.refresh()
	await shot("claim.png")
	quit()
