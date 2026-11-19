extends SceneTree
const H := preload("res://tests/helpers.gd")
# The 3D view button and touch controls: taps the "3D" button (touch_2d.png
# before, touch_3d.png after), drags one finger to pan (touch_pan.png), pinches
# two fingers apart to zoom in (touch_zoom.png), then taps "2D" to go back.
# Prints the camera before and after each gesture. Needs a window. Saved to $S.
var m
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OS.get_environment("S"), file])
func touch(index: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index; e.position = pos; e.pressed = down
	Input.parse_input_event(e)
	await process_frame
func drag(index: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index; e.position = to; e.relative = to - from
	Input.parse_input_event(e)
	await process_frame
func tap_button(b: Button) -> void:
	var c := b.get_global_rect().get_center()
	await touch(0, c, true)
	await touch(0, c, false)
	for i in 3: await process_frame
func cam() -> String:
	return "target %s distance %.1f" % [m.view_3d.cam_target, m.view_3d.cam_distance]
func _initialize() -> void:
	seed(5)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	s.reveal_area(s.player, Vector2i(7, 5), 6)
	s.update_sight(); m.refresh()
	await shot("touch_2d.png")
	await tap_button(m.view_button)
	print("after tapping '3D': showing_3d=%s, button now says '%s'" % [m.showing_3d, m.view_button.text])
	for i in 10: await process_frame
	await shot("touch_3d.png")
	print("start: " + cam())
	await touch(0, Vector2(400, 300), true)
	for k in 10: await drag(0, Vector2(400 + k * 20, 300), Vector2(420 + k * 20, 300))
	await touch(0, Vector2(600, 300), false)
	print("after a one-finger drag 200 px right: " + cam())
	await shot("touch_pan.png")
	await touch(0, Vector2(350, 300), true)
	await touch(1, Vector2(450, 300), true)
	for k in 10:
		await drag(0, Vector2(350 - k * 10, 300), Vector2(340 - k * 10, 300))
		await drag(1, Vector2(450 + k * 10, 300), Vector2(460 + k * 10, 300))
	await touch(0, Vector2(250, 300), false)
	await touch(1, Vector2(550, 300), false)
	print("after pinching apart (100 px to 300 px): " + cam())
	await shot("touch_zoom.png")
	await tap_button(m.view_button)
	print("after tapping '2D': showing_3d=%s, button now says '%s'" % [m.showing_3d, m.view_button.text])
	quit()
