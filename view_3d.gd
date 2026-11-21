extends Node3D

# The 3D view of the game (first step). Like main.gd, it owns no rules: it only
# READS the GameState and shows it. main.gd creates it, hands it the state, and
# switches between the 2D and 3D views (V, or the 3D button for phones). Clicking on hexes, buttons and
# pop-ups all stay in main.gd.
#
# Each hex shows Nathan's tile model for its land (assets/models/tiles/: plains,
# forest, mountain), or a low-poly tile made in code (tile_kit_3d.gd) for lands
# with no model yet (hills, water, ash). A city's hex shows settlement.glb,
# unsearched ruins ruins.glb, a rift you have found rift.glb. Units are small
# cylinders (placeholders). Sköll is the real model (assets/models/units/skoll.glb).

const SKOLL_SCENE := preload("res://assets/models/units/skoll.glb")
const NO_CELL := HexMap.NO_CELL

# --- Sizes (in 3D units; one hex is HEX_RADIUS from its centre to a corner) ---
const HEX_RADIUS := 1.0
# Nathan's tile models: pointy-top hexes, TILE_MODEL_RADIUS from centre to corner
# (the rest of a hex is the gap between tiles), base at y = 0, ground at MODEL_GROUND.
const TILE_MODELS := {
	Terrain.Type.PLAINS: "plains", Terrain.Type.FOREST: "forest", Terrain.Type.MOUNTAINS: "mountain",
	"settlement": "settlement", "ruins": "ruins", "rift": "rift",
}
const TILE_MODEL_PATH := "res://assets/models/tiles/%s.glb"
const TILE_MODEL_RADIUS := 0.98 # made for hexes 1.0 apart (centre to corner), so scale = HEX_RADIUS
const MODEL_GROUND := 0.39 # how high the ground is on the models (units and banners stand on it)
const CITY_UNIT_OFFSET := Vector3(0.0, 0, 0.5) # a unit in its city stands at the front of the settlement
const SKOLL_LENGTH_IN_HEXES := 1.25 # nose to tail, in hex widths
const SKOLL_STEP_TIME := 0.6 # seconds to walk one hex
# Which way the model faces before we turn it: 0 if its nose points along +Z.
const SKOLL_MODEL_YAW := 0.0

# --- Camera ---
const CAMERA_PITCH := 60.0 # degrees down from the horizon
const ZOOM_MIN := 6.0
const ZOOM_MAX := 40.0
const PAN_SPEED := 0.9 # map units a second, per unit of zoom distance

# Never-seen hexes, as in the 2D view
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
var rifts_now: Array = [] # shown_rifts(), worked out once a frame
var tiles := {} # the tile models, from TileKit3D.build_all(), shared by all hexes
var tile_scenes := {} # tile key (a land, "settlement", "ruins", "rift") -> PackedScene
var overlays := {} # tint -> material that multiplies a real model's colours by the tint
var materials := {} # colour -> StandardMaterial3D, shared
var tile_materials := {} # tint -> material that keeps the tile's own colours, shared
var unit_nodes: Array[MeshInstance3D] = [] # reused each frame
var city_nodes: Array[MeshInstance3D] = [] # a banner in the owner's colour on each city
var pole_nodes: Array[MeshInstance3D] = [] # the banners' poles
var army_mesh: CylinderMesh
var scout_mesh: CylinderMesh
var city_mesh: BoxMesh # the banner's cloth
var pole_mesh: CylinderMesh

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

# How high the ground is on a hex: the tile models are thicker than the code-made tiles.
func hex_top(cell: Vector2i) -> float:
	if tile_scenes.has(tile_key(cell)):
		return MODEL_GROUND * HEX_RADIUS
	if not hex_is_explored(cell) or state.is_ash(cell):
		return TileKit3D.top_height(Terrain.Type.PLAINS)
	return TileKit3D.top_height(state.terrain_at(cell))

# Which tile a hex shows: "unseen", a city ("settlement"), unsearched ruins, a rift you
# have found, "ash", or its land (a Terrain.Type).
func tile_key(c: Vector2i) -> Variant:
	var s := state
	if not hex_is_explored(c):
		return "unseen"
	if s.phase != GameState.Phase.LANDING:
		for f in s.factions:
			if f.city_pos == c:
				return "settlement"
		for r in s.ruins:
			if r["cell"] == c and not r["taken"]:
				return "ruins"
		if rifts_now.has(c):
			return "rift"
	if s.is_ash(c):
		return "ash"
	return s.terrain_at(c)

func hex_is_explored(cell: Vector2i) -> bool:
	return state.phase == GameState.Phase.LANDING or state.player_has_explored(cell)

# --- Building the scene once ------------------------------------------------------
func build_meshes() -> void:
	tiles = TileKit3D.build_all()
	# Real tile models win over the ones made in code.
	for key in TILE_MODELS:
		var path: String = TILE_MODEL_PATH % TILE_MODELS[key]
		if ResourceLoader.exists(path):
			tile_scenes[key] = load(path)
	army_mesh = CylinderMesh.new()
	army_mesh.top_radius = 0.15
	army_mesh.bottom_radius = 0.18
	army_mesh.height = 0.3
	scout_mesh = CylinderMesh.new()
	scout_mesh.top_radius = 0.09
	scout_mesh.bottom_radius = 0.11
	scout_mesh.height = 0.2
	city_mesh = BoxMesh.new()
	city_mesh.size = Vector3(0.2, 0.26, 0.02)
	pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.015
	pole_mesh.bottom_radius = 0.015
	pole_mesh.height = 0.75
	pole_mesh.radial_segments = 5

func build_board() -> void:
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			var mi := MeshInstance3D.new()
			add_child(mi)
			mi.position = cell_position(c)
			# so repeats look less obvious: each hex turned by a random multiple of 60°
			# (seeded by its position, so it's the same every game) and a variant of the code tiles
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(c)
			mi.rotation.y = rng.randi_range(0, 5) * TAU / 6.0
			mi.set_meta("variant", rng.randi_range(0, TileKit3D.VARIANTS - 1))
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
		var b: AABB = transform_to(root, mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

# Where a node sits relative to one of its ancestors (works before they're in the scene).
func transform_to(ancestor: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

# --- Every frame: read the state and update what's shown -------------------------
func _process(delta: float) -> void:
	if state == null:
		return
	pan_with_keys(delta)
	rifts_now = shown_rifts()
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

# A tile keeps its own painted colours; the tint multiplies them (white = as made).
func tile_material(tint: Color) -> StandardMaterial3D:
	if not tile_materials.has(tint):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = tint
		m.roughness = 0.9
		tile_materials[tint] = m
	return tile_materials[tint]

func update_board() -> void:
	var s := state
	var landing := s.phase == GameState.Phase.LANDING
	var dark := s.daughter.is_swallowed()
	for c in hexes:
		var mi: MeshInstance3D = hexes[c]
		var key: Variant = tile_key(c)
		var tint := Color.WHITE
		if not landing:
			var land_owner := s.territory_owner(c)
			if land_owner != null:
				tint = tint.lerp(territory_colour_of.call(land_owner), 0.45)
		if dark:
			tint = tint.darkened(0.7)
		if key is String and key == "unseen":
			tint = UNSEEN_COLOUR # never seen: a black block
		elif not landing and not s.player_can_see(c):
			tint = tint.darkened(0.45) # seen before, out of sight now: the model, darkened
		elif landing and not s.can_land_at(c):
			tint = tint.darkened(0.6)
		if tile_scenes.has(key):
			mi.mesh = null
			show_model(mi, key, tint)
		else:
			show_model(mi, null, tint)
			if key is String:
				mi.mesh = tiles[key] # "unseen" or "ash"
			else:
				mi.mesh = tiles[key][mi.get_meta("variant")]
			mi.material_override = tile_material(tint)

# Puts a tile model on a hex (made once, remade only when what the hex shows changes),
# or takes it away (key null). The tint is laid over it like the made-in-code tiles.
func show_model(mi: MeshInstance3D, key, tint: Color) -> void:
	var model: Node3D = mi.get_node_or_null("Model")
	if model != null and (key == null or model.get_meta("key") != key):
		mi.remove_child(model)
		model.queue_free()
		model = null
	if key == null:
		return
	if model == null:
		model = tile_scenes[key].instantiate()
		model.scale = Vector3.ONE * HEX_RADIUS # the models are already sized for hexes 1.0 apart
		model.name = "Model"
		model.set_meta("key", key)
		mi.add_child(model)
	var overlay := tint_overlay(tint)
	for part in model.find_children("*", "GeometryInstance3D", true, false):
		(part as GeometryInstance3D).material_overlay = overlay

func tint_overlay(tint: Color) -> StandardMaterial3D:
	if tint == Color.WHITE:
		return null
	if not overlays.has(tint):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL # darkens the model's own colours, like the tint on the code tiles
		m.albedo_color = tint
		overlays[tint] = m
	return overlays[tint]

# Whose city: a banner in the owner's colour on each settlement you've found.
func update_cities() -> void:
	var used := 0
	for f in state.factions:
		if f.city_pos == NO_CELL or not state.player_has_explored(f.city_pos):
			continue
		var flag_at := cell_position(f.city_pos) + Vector3(0.55, hex_top(f.city_pos), 0.3)
		var pole := pooled(pole_nodes, used, pole_mesh)
		pole.material_override = material(Color(0.3, 0.22, 0.15))
		pole.position = flag_at + Vector3(0, pole_mesh.height / 2.0, 0)
		var cloth := pooled(city_nodes, used, city_mesh)
		used += 1
		cloth.material_override = material(colour_of.call(f))
		cloth.position = flag_at + Vector3(city_mesh.size.x / 2.0, pole_mesh.height - city_mesh.size.y / 2.0, 0)
	hide_rest(city_nodes, used)
	hide_rest(pole_nodes, used)

# Rifts the player knows about (drawn as their hex's tile by update_board).
func shown_rifts() -> Array:
	var s := state
	if s.phase == GameState.Phase.LANDING:
		return []
	var rifts: Array = s.player.known_rifts.keys()
	var w := s.skoll.revealed_rift
	if w != NO_CELL and s.player_can_see(w) and not rifts.has(w):
		rifts.append(w)
	return rifts

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
			var beside := Vector3.ZERO
			if state.is_city(u.pos):
				beside = CITY_UNIT_OFFSET # standing in its city: next to the longhouse
			mi.position = cell_position(u.pos) + beside + Vector3(0, lift + mesh.height / 2.0, 0)
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
