extends Node2D

const HEX_SIZE := 32.0
const COLS := 12
const ROWS := 10
const OFFSET := Vector2(60, 80)

var unit_pos := Vector2i(3, 3)
var unit_selected := false
var unit_moves := 1

var city_pos := Vector2i(2, 2)
var turn := 1
var food := 0
var industry := 0

func _ready() -> void:
	var button := Button.new()
	button.text = "End Turn"
	button.position = Vector2(700, 20)
	button.pressed.connect(end_turn)
	add_child(button)

func end_turn() -> void:
	turn += 1
	food += 2
	industry += 1
	unit_moves = 1
	unit_selected = false
	queue_redraw()

func hex_center(cell: Vector2i) -> Vector2:
	var w := sqrt(3.0) * HEX_SIZE
	var h := 1.5 * HEX_SIZE
	return Vector2(w * (cell.x + 0.5 * (cell.y % 2)), h * cell.y) + OFFSET

func hex_points(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(a), sin(a)) * HEX_SIZE)
	return pts

func is_neighbour(a: Vector2i, b: Vector2i) -> bool:
	return a != b and hex_center(a).distance_to(hex_center(b)) < HEX_SIZE * 1.9

func cell_at(pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			var d := pos.distance_to(hex_center(c))
			if d < best_d:
				best_d = d
				best = c
	return best if best_d <= HEX_SIZE else Vector2i(-1, -1)

func _draw() -> void:
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			var pts := hex_points(hex_center(c))
			var fill := Color(0.25, 0.45, 0.3)
			if c == city_pos or is_neighbour(city_pos, c):
				fill = Color(0.3, 0.4, 0.6)
			if unit_selected and is_neighbour(unit_pos, c):
				fill = Color(0.9, 0.75, 0.3)
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.1, 0.1, 0.1), 2.0)

	var cc := hex_center(city_pos)
	draw_rect(Rect2(cc - Vector2(14, 14), Vector2(28, 28)), Color(0.95, 0.95, 0.85))

	var ring := Color.WHITE if unit_selected else Color(0.1, 0.1, 0.1)
	draw_circle(hex_center(unit_pos), HEX_SIZE * 0.55, ring)
	draw_circle(hex_center(unit_pos), HEX_SIZE * 0.45, Color(0.8, 0.2, 0.2))

	var font := ThemeDB.fallback_font
	var info := "Turn %d    Food %d    Industry %d    Moves %d" % [turn, food, industry, unit_moves]
	draw_string(font, Vector2(20, 35), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := cell_at(get_local_mouse_position())
		if cell == unit_pos and unit_moves > 0:
			unit_selected = not unit_selected
		elif unit_selected and is_neighbour(unit_pos, cell):
			unit_pos = cell
			unit_moves -= 1
			unit_selected = false
		else:
			unit_selected = false
		queue_redraw()
