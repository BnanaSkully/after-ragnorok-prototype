extends Node3D

# The 3D view of the game (first step). Like main.gd, it owns no rules: it only
# READS the GameState and shows it. main.gd creates it, hands it the state, and
# switches between the 2D and 3D views (V, or the 3D button for phones). Clicking on hexes, buttons and
# pop-ups all stay in main.gd.
#
# Placeholders until real models arrive in assets/models/: each hex is a
# six-sided prism coloured by its land, a city is a box, a unit a small cylinder.
# Sköll is the real model (assets/models/units/skoll.glb).

const SKOLL_SCENE := preload("res://assets/models/units/skoll.glb")
const NO_CELL := HexMap.NO_CELL

# --- Sizes (in 3D units; one hex is HEX_RADIUS from its centre to a corner) ---
const HEX_RADIUS := 1.0
const HEX_GAP := 0.04 # a thin dark line between hexes
# How tall each land's prism is (index = Terrain.Type: plains, forest, hills, mountains, water)
const TERRAIN_HEIGHTS := [0.2, 0.26, 0.4, 0.7, 0.1]
const UNSEEN_HEIGHT := 0.2
const SKOLL_LENGTH_IN_HEXES := 1.25 # nose to tail, in hex widths
const SKOLL_STEP_TIME := 0.6 # seconds to walk one hex
# Which way the model faces before we turn it: 0 if its nose points along +Z.
const SKOLL_MODEL_YAW := 0.0

# --- Camera ---
const CAMERA_PITCH := 60.0 # degrees down from the horizon
const ZOOM_MIN := 6.0
const ZOOM_MAX := 40.0
const PAN_SPEED := 0.9 # map units a second, per unit of zoom distance

# Colours copied from the 2D view so both views agree
const ASH_COLOUR := Color(0.36, 0.34, 0.33)
const UNSEEN_COLOUR := Color(0.03, 0.03, 0.04)

var state: GameState # set by main.gd before the view is added
var terrain_colours: Array = [] # set by main.gd (its TERRAIN_COLOURS)
var colour_of: Callable # main.gd's unit_colour(faction)
var territory_colour_of: Callable # main.gd's territory_colour(faction)

@onready var camera: Camera3D = $Camera
var cam_target := Vector3.ZERO # the point on the ground the camera looks at
var cam_distance := 22.0
var dragging := false
var touches := {} # finger index -> where it is on the screen (phones and touch screens)

var hexes := {} # Vector2i -> MeshInstance3D
var prism_meshes: Array[CylinderMesh] = [] # one per height, shared by all hexes
var unseen_mesh: CylinderMesh
var materials := {} # colour -> StandardMaterial3D, shared
var unit_nodes: Array[MeshInstance3D] = [] # reused each frame
var city_nodes: Array[MeshInstance3D] = []
var army_mesh: CylinderMesh
var scout_mesh: CylinderMesh
var city_mesh: BoxMesh

var skoll: Node3D
var skoll_anim: AnimationPlayer
var skoll_feet := 0.0 # how far below the model's origin its feet are (after scaling)
var skoll_cell := NO_CELL # the hex the model is standing on (or walking to)
var skoll_from := Vector3.ZERO
var skoll_to := Vector3.ZERO
var skoll_walk_time := 0.0 # seconds left walking (0 = standing still)
var skoll_walk_total := 0.0

func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-50, -30, 0) # low sun from the upper left, for shadows
	build_meshes()
	build_board()
	build_skoll()
	# start over the middle of the map, nudged right so the side panel doesn't cover it
	var last := cell_position(Vector2i(HexMap.COLS - 1, HexMap.ROWS - 1))
	cam_target = Vector3(last.x * 0.5 + 3.0, 0.0, last.z * 0.5)
	place_camera()

# --- Hex positions: the same layout as hex_view_2d.gd (pointy-top, offset rows) ---
func cell_position(cell: Vector2i) -> Vector3:
	var w := sqrt(3.0) * HEX_RADIUS
	return Vector3(w * (cell.x + 0.5 * (cell.y % 2)), 0.0, 1.5 * HEX_RADIUS * cell.y)

func hex_top(cell: Vector2i) -> float:
	if not hex_is_explored(cell):
		return UNSEEN_HEIGHT
	return TERRAIN_HEIGHTS[state.terrain_at(cell)]

func hex_is_explored(cell: Vector2i) -> bool:
	return state.phase == GameState.Phase.LANDING or state.player_has_explored(cell)

# --- Building the scene once ------------------------------------------------------
func build_meshes() -> void:
	for h in TERRAIN_HEIGHTS:
		prism_meshes.append(make_prism(h))
	unseen_mesh = make_prism(UNSEEN_HEIGHT)
	army_mesh = CylinderMesh.new()
	army_mesh.top_radius = 0.28
	army_mesh.bottom_radius = 0.32
	army_mesh.height = 0.45
	scout_mesh = CylinderMesh.new()
	scout_mesh.top_radius = 0.15
	scout_mesh.bottom_radius = 0.18
	scout_mesh.height = 0.3
	city_mesh = BoxMesh.new()
	city_mesh.size = Vector3(0.9, 0.6, 0.9)

# A six-sided cylinder is a hex prism. Godot puts its first corner on +Z, which
# is "up" on the screen here, so the hexes come out pointy-top like the 2D map.
func make_prism(height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.radial_segments = 6
	m.rings = 1
	m.top_radius = HEX_RADIUS - HEX_GAP
	m.bottom_radius = HEX_RADIUS - HEX_GAP
	m.height = height
	return m

func build_board() -> void:
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			var mi := MeshInstance3D.new()
			add_child(mi)
			hexes[c] = mi

func build_skoll() -> void:
	skoll = SKOLL_SCENE.instantiate()
	add_child(skoll)
	skoll_anim = skoll.find_child("AnimationPlayer", true, false)
	for anim_name in ["idle", "walk"]:
		if skoll_anim and skoll_anim.has_animation(anim_name):
			skoll_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR # (the file has them play once)
	# Scale him so he is SKOLL_LENGTH_IN_HEXES hexes long, nose to tail.
	var box := model_bounds(skoll)
	var longest := maxf(box.size.x, box.size.z)
	var hex_width := sqrt(3.0) * HEX_RADIUS
	var k := SKOLL_LENGTH_IN_HEXES * hex_width / longest if longest > 0.0 else 1.0
	skoll.scale = Vector3.ONE * k
	skoll_feet = -box.position.y * k
	skoll.visible = false

# The model's size: every mesh's box joined together (in the model's own units).
func model_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (root.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

# --- Every frame: read the state and update what's shown -------------------------
func _process(delta: float) -> void:
	if state == null:
		return
	pan_with_keys(delta)
	update_board()
	update_cities()
	update_units()
	update_skoll(delta)

func material(colour: Color) -> StandardMaterial3D:
	if not materials.has(colour):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.9
		materials[colour] = m
	return materials[colour]

func update_board() -> void:
	var s := state
	var landing := s.phase == GameState.Phase.LANDING
	var dark := s.daughter.is_swallowed()
	for c in hexes:
		var mi: MeshInstance3D = hexes[c]
		var land: int = s.terrain_at(c)
		var fill: Color = ASH_COLOUR if s.is_ash(c) else terrain_colours[land]
		var mesh: CylinderMesh = prism_meshes[land]
		if not landing:
			var land_owner := s.territory_owner(c)
			if land_owner != null:
				fill = fill.lerp(territory_colour_of.call(land_owner), 0.45)
		if dark:
			fill = fill.darkened(0.7)
		if not hex_is_explored(c):
			fill = UNSEEN_COLOUR # never seen: black
			mesh = unseen_mesh
		elif not landing and not s.player_can_see(c):
			fill = fill.darkened(0.45) # seen before, out of sight now
		elif landing and not s.can_land_at(c):
			fill = fill.darkened(0.6)
		mi.mesh = mesh
		mi.material_override = material(fill)
		mi.position = cell_position(c) + Vector3(0, mesh.height / 2.0, 0)

func update_cities() -> void:
	var used := 0
	for f in state.factions:
		if f.city_pos == NO_CELL or not state.player_has_explored(f.city_pos):
			continue
		var mi := pooled(city_nodes, used, city_mesh)
		used += 1
		mi.material_override = material(colour_of.call(f).lerp(Color(0.95, 0.95, 0.85), 0.5))
		mi.position = cell_position(f.city_pos) + Vector3(0, hex_top(f.city_pos) + city_mesh.size.y / 2.0, 0)
	hide_rest(city_nodes, used)

func update_units() -> void:
	var used := 0
	for f in state.factions:
		for u in f.units:
			if f != state.player and not state.player_can_see(u.pos):
				continue # hidden by fog of war
			var mesh: CylinderMesh = scout_mesh if u.is_scout() else army_mesh
			var mi := pooled(unit_nodes, used, mesh)
			used += 1
			var col: Color = colour_of.call(f)
			if f == state.player and u.moves <= 0:
				col = col.darkened(0.4) # dim = already moved, like the 2D view
			mi.material_override = material(col)
			var lift := hex_top(u.pos)
			if state.is_city(u.pos):
				lift += city_mesh.size.y # standing in its city: on the roof
			mi.position = cell_position(u.pos) + Vector3(0, lift + mesh.height / 2.0, 0)
	hide_rest(unit_nodes, used)

# Reuses the i-th node of a pool (making it if needed) instead of making new ones every frame.
func pooled(pool: Array[MeshInstance3D], i: int, mesh: Mesh) -> MeshInstance3D:
	if i >= pool.size():
		var mi := MeshInstance3D.new()
		add_child(mi)
		pool.append(mi)
	pool[i].mesh = mesh
	pool[i].visible = true
	return pool[i]

func hide_rest(pool: Array[MeshInstance3D], used: int) -> void:
	for i in range(used, pool.size()):
		pool[i].visible = false

# --- Sköll: idle while standing, walks from hex to hex when he moves ---------------
func update_skoll(delta: float) -> void:
	var w := state.skoll
	var shown := w.active and state.player_can_see(w.pos)
	if not shown:
		skoll.visible = false
		skoll_cell = NO_CELL
		skoll_walk_time = 0.0
		return
	var target := cell_position(w.pos) + Vector3(0, hex_top(w.pos) + skoll_feet, 0)
	if not skoll.visible or skoll_cell == NO_CELL:
		# he just came into view: stand him on his hex
		skoll.visible = true
		skoll.position = target
		skoll_cell = w.pos
		skoll_walk_time = 0.0
	elif w.pos != skoll_cell:
		# he moved since last frame: walk from where he is to the new hex
		skoll_from = skoll.position
		skoll_to = target
		skoll_walk_total = SKOLL_STEP_TIME * maxi(1, HexMap.hex_distance(skoll_cell, w.pos))
		skoll_walk_time = skoll_walk_total
		skoll_cell = w.pos
	if skoll_walk_time > 0.0:
		skoll_walk_time = maxf(0.0, skoll_walk_time - delta)
		var t := 1.0 - skoll_walk_time / skoll_walk_total
		skoll.position = skoll_from.lerp(skoll_to, t)
		face(skoll_to - skoll_from)
		play("walk")
	else:
		skoll.position = target # (the hex can change height when it turns to ash or comes into view)
		face(camera.global_position - skoll.position) # standing still: he looks at you
		play("idle")

# Turns him (only around the vertical axis) to look along a direction.
func face(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() < 0.001:
		return
	skoll.rotation.y = atan2(direction.x, direction.z) + SKOLL_MODEL_YAW

func play(anim_name: String) -> void:
	if skoll_anim and skoll_anim.current_animation != anim_name and skoll_anim.has_animation(anim_name):
		skoll_anim.play(anim_name, 0.2)

# --- Camera: WASD, middle-drag or one finger to pan; the wheel or a pinch to zoom --
func place_camera() -> void:
	var pitch := deg_to_rad(CAMERA_PITCH)
	camera.position = cam_target + Vector3(0, sin(pitch), cos(pitch)) * cam_distance
	camera.look_at(cam_target, Vector3.UP)

func pan_with_keys(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1
	if Input.is_key_pressed(KEY_S):
		move.z += 1
	if Input.is_key_pressed(KEY_A):
		move.x -= 1
	if Input.is_key_pressed(KEY_D):
		move.x += 1
	if move != Vector3.ZERO:
		cam_target += move.normalized() * PAN_SPEED * cam_distance * delta
		clamp_target()
		place_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 0.9)
	elif event is InputEventMouseMotion and dragging:
		pan_by_pixels(event.relative)
	elif event is InputEventScreenTouch:
		# a finger touched or left the screen
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			touches[event.index] = event.position # (it touched down on a button, then slid onto the map)
		var span_before := finger_span()
		touches[event.index] = event.position
		if touches.size() == 1:
			pan_by_pixels(event.relative) # one finger: drag the map
		elif touches.size() == 2 and span_before > 0.0:
			zoom_by(span_before / maxf(finger_span(), 1.0)) # two fingers: pinch apart to zoom in, together to zoom out
	elif event is InputEventMagnifyGesture:
		zoom_by(1.0 / event.factor) # a laptop trackpad's pinch

# How far apart the first two fingers are on the screen (0 with fewer than two).
func finger_span() -> float:
	if touches.size() < 2:
		return 0.0
	var points: Array = touches.values()
	return (points[0] as Vector2).distance_to(points[1])

# Moves the camera's distance by a factor (below 1 = closer), within the limits.
func zoom_by(factor: float) -> void:
	cam_distance = clampf(cam_distance * factor, ZOOM_MIN, ZOOM_MAX)
	place_camera()

# Drags the map with the mouse or a finger: the further out you are, the more ground a pixel covers.
func pan_by_pixels(relative: Vector2) -> void:
	var per_pixel := cam_distance / get_viewport().get_visible_rect().size.y * 1.2
	cam_target -= Vector3(relative.x, 0, relative.y) * per_pixel
	clamp_target()
	place_camera()

# Taken off screen (back to 2D): forget any fingers or drag, their "let go" may never arrive.
func _exit_tree() -> void:
	touches.clear()
	dragging = false

func clamp_target() -> void:
	var last := cell_position(Vector2i(HexMap.COLS - 1, HexMap.ROWS - 1))
	cam_target.x = clampf(cam_target.x, -2.0, last.x + 6.0)
	cam_target.z = clampf(cam_target.z, -2.0, last.z + 2.0)
