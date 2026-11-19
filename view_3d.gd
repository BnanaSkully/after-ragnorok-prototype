extends Node3D

# The 3D view of the game (first step). Like main.gd, it owns no rules: it only
# READS the GameState and shows it. main.gd creates it, hands it the state, and
# switches between the 2D and 3D views (V, or the 3D button for phones). Clicking on hexes, buttons and
# pop-ups all stay in main.gd.
#
# Each hex is a low-poly tile made in code (tile_kit_3d.gd: grass, pines, hills,
# snowy peaks, lakes) until real tile models arrive in assets/models/tiles/.
# A city is still a box and a unit a small cylinder (placeholders).
# Sköll is the real model (assets/models/units/skoll.glb).

const SKOLL_SCENE := preload("res://assets/models/units/skoll.glb")
const NO_CELL := HexMap.NO_CELL

# --- Sizes (in 3D units; one hex is HEX_RADIUS from its centre to a corner) ---
const HEX_RADIUS := 1.0
# Real tile models: assets/models/tiles/plains.glb, forest.glb, hills.glb,
# mountains.glb, water.glb (and ash.glb), any that exist. Each is scaled to fit
# one hex, its bottom on the ground. Units stand at TileKit3D.top_height either way.
const TILE_MODEL_PATH := "res://assets/models/tiles/%s.glb"
const TILE_MODEL_YAW := 0.0 # turn (radians) if the models come out flat-top instead of pointy-top
# Nathan's Meshy models (assets/models/props/), made smaller for phones.
const LONGHOUSE := preload("res://assets/models/props/longhouse.glb") # a city
const RUNESTONE := preload("res://assets/models/props/runestone.glb") # ruins not yet searched
const RIFT := preload("res://assets/models/props/rift.glb") # a rift you have found
const PINE := preload("res://assets/models/props/pine.glb")
const GRASS := preload("res://assets/models/props/grass.glb")
# Nathan's Meshy tileable textures, laid over the Blender kit's flat colours
# (like concept_art/tile_set_preview.png). Triplanar: they need no UVs.
const GRASS_TEXTURE := preload("res://assets/textures/grass.png")
const CLIFF_TEXTURE := preload("res://assets/textures/cliff.png")
const TEXTURE_SCALE := 0.9 # repeats per map unit
# How each land shades the grass texture (multiplied), so lands stay easy to tell apart.
const GRASS_SHADE := {
	Terrain.Type.PLAINS: Color(0.95, 1.1, 0.8),
	Terrain.Type.FOREST: Color(0.65, 0.8, 0.6),
	Terrain.Type.HILLS: Color(0.95, 0.9, 0.65),
}
# Lands dressed with props: forest is a grassy tile with pines on it, plains get a
# clump of grass on some hexes. [base tile, prop, how many, height, distance from the middle]
const DRESSING := {
	Terrain.Type.FOREST: ["plains", PINE, 5, 1.0, 0.5],
	Terrain.Type.PLAINS: ["", GRASS, 1, 0.32, 0.5],
}
const LONGHOUSE_LENGTH := 1.1 # its longest side (a hex is 2.0 corner to corner)
const RUNESTONE_HEIGHT := 0.55
const RIFT_RIM := 0.8 # how far up the rift model its rim is (0 bottom, 1 top): the rim is put at grass level
const MOUNTAIN_STRETCH := 1.35 # the mountain tile is drawn this much taller than its model
const CITY_UNIT_OFFSET := Vector3(0.0, 0, 0.5) # a unit in its city stands in front of the longhouse
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
var tiles := {} # the tile models, from TileKit3D.build_all(), shared by all hexes
var tile_scenes := {} # land -> PackedScene, for each land with a real model in assets/models/tiles/
var overlays := {} # tint -> material that multiplies a real model's colours by the tint
var materials := {} # colour -> StandardMaterial3D, shared
var tile_materials := {} # tint -> material that keeps the tile's own colours, shared
var unit_nodes: Array[MeshInstance3D] = [] # reused each frame
var city_nodes: Array[MeshInstance3D] = [] # a banner in the owner's colour beside each longhouse
var pole_nodes: Array[MeshInstance3D] = [] # the banners' poles
var prop_pools := {} # PackedScene -> Array[Node3D], reused each frame (longhouses, runestones, rifts)
var prop_fits := {} # PackedScene -> [scale, lift], measured once
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

func hex_top(cell: Vector2i) -> float:
	if not hex_is_explored(cell):
		return TileKit3D.top_height(Terrain.Type.PLAINS)
	return TileKit3D.top_height(state.terrain_at(cell))

func hex_is_explored(cell: Vector2i) -> bool:
	return state.phase == GameState.Phase.LANDING or state.player_has_explored(cell)

# --- Building the scene once ------------------------------------------------------
func build_meshes() -> void:
	tiles = TileKit3D.build_all()
	# Real tile models (exported from Blender) win over the ones made in code.
	for land in Terrain.NAMES.size():
		var path := TILE_MODEL_PATH % Terrain.NAMES[land].to_lower()
		if ResourceLoader.exists(path):
			tile_scenes[land] = load(path)
	tile_scenes["rift"] = RIFT # a found rift is a whole tile of its own
	if ResourceLoader.exists(TILE_MODEL_PATH % "ash"):
		tile_scenes["ash"] = load(TILE_MODEL_PATH % "ash")
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
			# the same land doesn't always look the same: a variant and a turn picked from the hex
			var pick := (col * 7 + row * 13) % 101
			mi.rotation.y = (pick % 6) * TAU / 6.0
			mi.set_meta("variant", pick % TileKit3D.VARIANTS)
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
	var rifts := shown_rifts()
	for c in hexes:
		var mi: MeshInstance3D = hexes[c]
		var tint := Color.WHITE
		var mesh: ArrayMesh
		var key: Variant = s.terrain_at(c) # which tile this hex shows (a land, or "ash")
		if s.is_ash(c):
			key = "ash"
			mesh = tiles["ash"]
		else:
			mesh = tiles[s.terrain_at(c)][mi.get_meta("variant")]
		if rifts.has(c):
			key = "rift" # a rift you have found takes the place of its hex's tile
		if not landing:
			var land_owner := s.territory_owner(c)
			if land_owner != null:
				tint = tint.lerp(territory_colour_of.call(land_owner), 0.45)
		if dark:
			tint = tint.darkened(0.7)
		if not hex_is_explored(c):
			mesh = tiles["unseen"]
			tint = UNSEEN_COLOUR # never seen: a black block
		elif not landing and not s.player_can_see(c):
			tint = tint.darkened(0.45) # seen before, out of sight now
		elif landing and not s.can_land_at(c):
			tint = tint.darkened(0.6)
		if mesh != tiles["unseen"] and tile_scenes.has(key):
			mi.mesh = null
			show_model(mi, key, tint)
		else:
			show_model(mi, null, tint)
			mi.mesh = mesh
			mi.material_override = tile_material(tint)

# Puts a real tile model on a hex (made once, remade only when its land changes),
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
		model = make_tile_model(key, mi.get_meta("variant"))
		model.name = "Model"
		model.set_meta("key", key)
		mi.add_child(model)
	var overlay := tint_overlay(tint)
	for part in model.find_children("*", "GeometryInstance3D", true, false):
		(part as GeometryInstance3D).material_overlay = overlay

# A real tile model, and for dressed lands its props (pines on forest, grass on plains).
func make_tile_model(key, variant: int) -> Node3D:
	var holder := Node3D.new()
	var base_key = key
	var dress: Array = DRESSING.get(key, [])
	if not dress.is_empty() and dress[0] != "" and tile_scenes.has(Terrain.NAMES.find(String(dress[0]).capitalize())):
		base_key = Terrain.NAMES.find(String(dress[0]).capitalize())
	var base: Node3D = tile_scenes[base_key].instantiate()
	holder.add_child(base)
	fit_to_hex(base, MOUNTAIN_STRETCH if key is int and key == Terrain.Type.MOUNTAINS else 1.0)
	restyle(base, key)
	if key is String and key == "rift":
		# sink the rift so its rim is level with the grass on the hexes around it
		var h := model_bounds(base).size.y * base.scale.y
		base.position.y -= h * RIFT_RIM - TileKit3D.top_height(Terrain.Type.PLAINS)
	if dress.is_empty():
		return holder
	var count: int = dress[2]
	if key == Terrain.Type.PLAINS and variant != 0:
		count = 0 # grass on one plains hex in three
	var top := TileKit3D.top_height(Terrain.Type.PLAINS)
	for i in count:
		var angle := TAU * (i + 0.3 * variant) / maxf(count, 1.0) + 0.6
		var spot := Vector3(cos(angle), 0, sin(angle)) * float(dress[4])
		var prop := place_scaled(dress[1], spot + Vector3(0, top, 0), float(dress[3]) * (0.85 + 0.1 * ((i + variant) % 3)), "height")
		prop.rotation.y = angle * 3.0
		holder.add_child(prop)
	return holder

# Swaps the kit's flat colours for textured ones: grass on the tops, rock on the sides, shiny water.
var restyled := {} # [land, kit material name] -> material
func restyle(model: Node3D, land) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var old := m.mesh.surface_get_material(i)
			if old == null:
				continue
			var key := [land, old.resource_name]
			if not restyled.has(key):
				restyled[key] = restyled_material(land, old.resource_name)
			if restyled[key] != null:
				m.set_surface_override_material(i, restyled[key])

func restyled_material(land, kit_name: String) -> Material:
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * TEXTURE_SCALE
	match kit_name:
		"Kit grass", "Kit forest floor":
			m.albedo_texture = GRASS_TEXTURE
			m.albedo_color = GRASS_SHADE.get(land, Color.WHITE)
		"Kit cliff", "Kit stone", "Kit shore":
			m.albedo_texture = CLIFF_TEXTURE
			m.albedo_color = Color(0.9, 0.85, 0.8) if kit_name == "Kit cliff" else Color(1.3, 1.25, 1.15)
		"Kit water":
			m.uv1_triplanar = false
			m.albedo_color = Color(0.08, 0.2, 0.3)
			m.roughness = 0.12
			m.metallic = 0.4
			m.metallic_specular = 0.8
		_:
			return null
	return m

# A new copy of a prop, scaled so its height (or its longest side) is "size", its bottom at "at".
func place_scaled(scene: PackedScene, at: Vector3, size: float, by: String) -> Node3D:
	if not prop_fits.has(scene):
		var probe: Node3D = scene.instantiate()
		var box := model_bounds(probe)
		probe.free()
		prop_fits[scene] = box
	var b: AABB = prop_fits[scene]
	var measure := b.size.y if by == "height" else maxf(b.size.x, b.size.z)
	var k := size / measure if measure > 0.0 else 1.0
	var node: Node3D = scene.instantiate()
	var holder := Node3D.new()
	holder.add_child(node)
	node.scale = Vector3.ONE * k
	var c := b.get_center()
	node.position = Vector3(-c.x * k, -b.position.y * k, -c.z * k)
	holder.position = at
	return holder

# Scales a model so it is as wide as one hex and stands on the ground ("stretch" makes it taller).
func fit_to_hex(model: Node3D, stretch := 1.0) -> void:
	var box := model_bounds(model)
	var widest := maxf(box.size.x, box.size.z)
	var k := 2.0 * TileKit3D.RADIUS / widest if widest > 0.0 else 1.0
	model.scale = Vector3(k, k * stretch, k)
	model.rotation.y = TILE_MODEL_YAW
	var centre := box.get_center()
	model.position = Vector3(-centre.x * k, -box.position.y * k * stretch, -centre.z * k)

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

func update_cities() -> void:
	var used := 0
	var houses := 0
	for f in state.factions:
		if f.city_pos == NO_CELL or not state.player_has_explored(f.city_pos):
			continue
		var top := cell_position(f.city_pos) + Vector3(0, hex_top(f.city_pos), 0)
		# whose city: a banner in their colour at the longhouse's corner
		var flag_at := top + Vector3(0.62, 0, 0.12)
		var pole := pooled(pole_nodes, used, pole_mesh)
		pole.material_override = material(Color(0.3, 0.22, 0.15))
		pole.position = flag_at + Vector3(0, pole_mesh.height / 2.0, 0)
		var cloth := pooled(city_nodes, used, city_mesh)
		used += 1
		cloth.material_override = material(colour_of.call(f))
		cloth.position = flag_at + Vector3(city_mesh.size.x / 2.0, pole_mesh.height - city_mesh.size.y / 2.0, 0)
		var house := pooled_prop(LONGHOUSE, houses, LONGHOUSE_LENGTH, "longest")
		houses += 1
		house.position = top + Vector3(0, 0, -0.2) # toward the back, leaving room for a unit
		house.rotation.y = 0.0
		tint_prop(house, Color.WHITE if state.player_can_see(f.city_pos) else Color.WHITE.darkened(0.45))
	hide_rest(city_nodes, used)
	hide_rest(pole_nodes, used)
	hide_props(LONGHOUSE, houses)
	update_ruins()

# Unsearched ruins you've seen (a runestone). Rifts you've found replace their tile (update_board).
func update_ruins() -> void:
	var s := state
	var stones := 0
	if s.phase != GameState.Phase.LANDING:
		for r in s.ruins:
			if not r["taken"] and s.player_has_explored(r["cell"]):
				var stone := pooled_prop(RUNESTONE, stones, RUNESTONE_HEIGHT, "height")
				stones += 1
				stone.position = cell_position(r["cell"]) + Vector3(0.25, hex_top(r["cell"]), -0.2)
				tint_prop(stone, Color.WHITE if s.player_can_see(r["cell"]) else Color.WHITE.darkened(0.45))
	hide_props(RUNESTONE, stones)

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

func pooled_prop(scene: PackedScene, i: int, size: float, by: String) -> Node3D:
	if not prop_pools.has(scene):
		prop_pools[scene] = []
	var pool: Array = prop_pools[scene]
	if i >= pool.size():
		var node := place_scaled(scene, Vector3.ZERO, size, by)
		add_child(node)
		pool.append(node)
	pool[i].visible = true
	return pool[i]

func hide_props(scene: PackedScene, used: int) -> void:
	var pool: Array = prop_pools.get(scene, [])
	for i in range(used, pool.size()):
		pool[i].visible = false

func tint_prop(node: Node3D, tint: Color) -> void:
	var overlay := tint_overlay(tint)
	for part in node.find_children("*", "GeometryInstance3D", true, false):
		(part as GeometryInstance3D).material_overlay = overlay

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
