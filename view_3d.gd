extends Node3D

# The 3D view of the game (first step). Like main.gd, it owns no rules: it only
# READS the GameState and shows it. main.gd creates it, hands it the state, and
# switches between the 2D and 3D views (V, or the 3D button for phones). Clicking on hexes, buttons and
# pop-ups all stay in main.gd.
#
# Each hex shows Nathan's tile model for its land (assets/models/tiles/: plains,
# forest, mountain), or a low-poly tile made in code (tile_kit_3d.gd) for lands
# with no model yet (hills, water, ash). A city's hex shows settlement.glb,
# unsearched ruins ruins.glb, a rift you have found rift.glb. Armies are
# units/warrior.glb and scouts units/scout.glb (idle when still, walk when moving,
# the blue arm band repainted in the faction's colour). Sköll is units/skoll.glb.

const SKOLL_SCENE := preload("res://assets/models/units/skoll.glb")
const SUNNA_SCENE := preload("res://assets/models/units/sunna.glb") # Nathan's model: walk, run
const SUNNA_HEIGHT := 1.0 # as tall as a unit
const SUNNA_MODEL_HEIGHT := 1.6 # her height in the file (a skinned mesh: its bones undo the armature's 0.01 scale, so model_bounds can't measure her)
const SUNNA_STEP_TIME := 0.6 # seconds to walk one hex
const SUNNA_LIGHT_COLOUR := Color(1.0, 0.78, 0.4) # warm gold, so her grey cloak stands out on ash and hills
const SUNNA_LIGHT_ENERGY := 2.5
const SUNNA_LIGHT_RANGE := 2.2
const NO_CELL := HexMap.NO_CELL

# --- Sizes (in 3D units; one hex is HEX_RADIUS from its centre to a corner) ---
const HEX_RADIUS := 1.0
# Nathan's tile models: pointy-top hexes, TILE_MODEL_RADIUS from centre to corner
# (the rest of a hex is the gap between tiles), base at y = 0, ground at MODEL_GROUND.
const TILE_MODELS := {
	Terrain.Type.PLAINS: "plains", Terrain.Type.FOREST: "forest", Terrain.Type.HILLS: "hills",
	"plains_living": "plains_living", "forest_living": "forest_living",
	"settlement": "settlement", "ruins": "ruins", "rift": "rift",
}
const TILE_MODEL_PATH := "res://assets/models/tiles/%s.glb"
# Mountains are built from peak props on a plain basalt hex base, so neighbouring
# mountain hexes join into ranges (see make_mountain). Peaks: base at y = 0, sized in hex units.
# Nathan's outpost prop (base at y = 0, sized in hex units), at the back of its hex so a
# unit can stand in the middle, with a small banner in the owner's colour.
const RIFT_OVERLAY_SCALE := 0.75 # the rift laid into its land tile: this big
# The rift model is a whole crater (floor at y 0, rim 0.4-0.7 high). It sinks this far
# (in its own height units) below the land's ground so only its rim shows, and the land
# tile gets a round hole cut where it sits (RIFT_HOLE, cut_hole) so the land never covers
# its pit. Standing on the land (Nathan's phone, v15) it read as a blue box.
const RIFT_SINK := 0.45
const RIFT_HOLE := 0.66 # the hole's radius, in hex units (inside the rim's 0.64-0.74)
const OUTPOST := preload("res://assets/models/props/outpost.glb")
const OUTPOST_OFFSET := Vector3(0.0, 0.0, -0.42)
const PEAK_TALL := preload("res://assets/models/props/peak_tall.glb")
const PEAK_MEDIUM := preload("res://assets/models/props/peak_medium.glb")
const PEAK_LOW := preload("res://assets/models/props/peak_low.glb")
const PEAK_CENTRE_SCALE := 0.85 # the middle peak of a hex in a range
const PEAK_EDGE_SCALE := 0.8 # the peaks on the edge shared with another mountain hex
const TILE_MODEL_RADIUS := 0.98 # made for hexes 1.0 apart (centre to corner), so scale = HEX_RADIUS
# Plains and forest come in two looks: living (green) and ashen (grey, the plain
# plains.glb / forest.glb). A hex looks ashen on dead land, next to it, or within
# ASHEN_RIFT_RANGE of a rift the PLAYER has found (Faction.known_rifts only, so the
# ground never gives away a hidden rift).
const ASHEN_RIFT_RANGE := 2
const LIVING_MODELS := {Terrain.Type.PLAINS: "plains_living", Terrain.Type.FOREST: "forest_living"}
const DEAD_LAND_TINT := Color(0.62, 0.6, 0.6) # dead land (under ash) is the ashen look, greyed further
const ASH_TINT := Color(0.6, 0.52, 0.42) # the ashen plains and forest: warm charcoal, not icy (Nathan, v13)
const HILLS_TINT := Color(0.6, 0.8, 0.4) # hills toward the plains' green: grassy hills with rock, not ash
# The grass tufts in the tile files carry no colour (Blender's colour didn't export), so
# they showed pure white ("glints"). Painted here until the files carry their own colour.
const TUFT_VISIBLE_DISTANCE := 15.0 # grass tufts are hidden beyond this camera distance (they shimmered far away)
const TUFT_COLOURS := {"Plains tuft": Color(0.36, 0.4, 0.22), "Ash tuft": Color(0.4, 0.39, 0.37)}
const MODEL_GROUND := 0.39 # how high the ground is on the models (units and banners stand on it)
const CITY_UNIT_OFFSET := Vector3(0.0, 0, 0.92) # a unit in its city stands in front of the longhouse, toward the camera, clear of its wall and ring (0.5 hid it inside, 0.78 overlapped the wall; the hex corner is at 0.98)
const WARRIOR := preload("res://assets/models/units/warrior.glb")
const SCOUT := preload("res://assets/models/units/scout.glb")
const UNIT_BAND_SHADER := preload("res://assets/shaders/unit_band.gdshader")
const SKOLL_GLOW_SHADER := preload("res://assets/shaders/skoll_glow.gdshader") # his orange glow, shifted toward gold
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
# Water hexes get no tile: one water plane lies under the whole map at WATER_LEVEL, below
# the land tiles' ground (MODEL_GROUND) and the never-seen blocks' top, so neighbouring
# water hexes read as one lake or sea and the land tiles' sides are the shore.
const WATER_LEVEL := 0.25
const WATER_REACH := 1.04 # water hexes reach a little under the land tiles' edges
const WATER_STEPS := 4
const UNIT_HEIGHT := 1.0 # half a hex (a hex is 2.0 corner to corner): readable at full-map zoom
const UNIT_RING_RADIUS := 0.34 # the glowing ring in the owner's colour under every unit
const UNIT_RING_GLOW := 1.4
const CITY_RING_RADIUS := 0.92 # the glowing ring round every city hex you've found
const CITY_RING_GLOW := 1.2
const CITY_LIGHT_COLOUR := Color(1.0, 0.68, 0.38) # warm firelight at each settlement
const CITY_LIGHT_ENERGY := 2.0
const CITY_LIGHT_RANGE := 2.6
const PEAK_DULL := 0.56 # mountain snow: albedo x0.56 (0.7, then 20% less, Nathan v13) and a little greyer, so it doesn't sparkle
const PEAK_SPECULAR := 0.15
const UNIT_MODEL_HEIGHT := 1.8 # how tall the warrior and scout are in their own files
const UNIT_STEP_TIME := 0.45 # seconds to walk one hex
const SKOLL_LENGTH_IN_HEXES := 1.0 # nose to tail, in hex widths
const SKOLL_STEP_TIME := 0.6 # seconds to walk one hex
const SKOLL_VANISH_TIME := 1.0 # seconds he takes to sink away when beaten
const SKOLL_MAX_WALK := Skoll.RAGE_SPEED # the most hexes he runs in a turn; farther than that he reappears instead
# Which way the model faces before we turn it: 0 if its nose points along +Z.
const SKOLL_MODEL_YAW := 0.0

# --- Camera ---
const CAMERA_PITCH := 60.0 # degrees down from the horizon
const ZOOM_MIN := 6.0
# Map pins: a faction-coloured pin above every unit (gold for Sköll and Sunna), always
# facing the camera and drawn over trees, so armies can be found when zoomed out.
# Hidden when the camera is close (the models read on their own there).
const MARKER_SHOW_DISTANCE := 13.0 # camera distance from which pins show (it starts at 22)
const MARKER_SIZE := 0.032 # pin height per unit of camera distance: they grow as you zoom out
const SKOLL_MARKER := Color(1.0, 0.72, 0.2)
const SUNNA_MARKER := Color.WHITE # white with a small gold sun in its head (SUN_DISC_COLOUR)
const SUN_DISC_COLOUR := Color(1.0, 0.7, 0.1)
const ZOOM_MAX := 40.0
const PAN_SPEED := 0.9 # map units a second, per unit of zoom distance

# Never-seen hexes, as in the 2D view
const UNSEEN_COLOUR := Color(0.03, 0.03, 0.04)
const FOG_MEMORY_DARKEN := 0.6 # seen-before hexes out of sight: about 40% as bright

var state: GameState # set by main.gd before the view is added
var terrain_colours: Array = [] # set by main.gd (its TERRAIN_COLOURS)
var colour_of: Callable # main.gd's unit_colour(faction)
var territory_colour_of: Callable # main.gd's territory_colour(faction)
var marks_of: Callable # main.gd's marked_hexes(): hex -> colour (where the selected unit can go, outpost spots...)
var selected_of: Callable # main.gd's selected unit (or null)
var mark_nodes: Array[MeshInstance3D] = [] # a see-through hex laid on each marked hex
var mark_mesh: ArrayMesh

@onready var camera: Camera3D = $Camera
var cam_target := Vector3.ZERO # the point on the ground the camera looks at
var cam_distance := 22.0
var dragging := false
var touches := {} # finger index -> where it is on the screen (phones and touch screens)

var hexes := {} # Vector2i -> MeshInstance3D
var rifts_now: Array = [] # shown_rifts(), worked out once a frame
var rift_models := {} # hex -> the rift drawn over its land (update_rifts)
var tiles := {} # the tile models, from TileKit3D.build_all(), shared by all hexes
var tile_scenes := {} # tile key (a land, "settlement", "ruins", "rift") -> PackedScene
var overlays := {} # tint -> material that multiplies a real model's colours by the tint
var materials := {} # colour -> StandardMaterial3D, shared
var tile_materials := {} # tint -> material that keeps the tile's own colours, shared
var figures := {} # Unit -> its model on the map (see update_units)
var band_materials := {} # [scene, colour] -> ShaderMaterial, shared
var glow_materials := {} # colour -> glowing unshaded material for the rings
var peak_materials := {} # a peak's own material -> its duller copy
var unit_ring_mesh: TorusMesh
var city_ring_mesh: TorusMesh
var city_ring_nodes: Array[MeshInstance3D] = []
var city_lights: Array[OmniLight3D] = []
var city_nodes: Array[MeshInstance3D] = [] # a banner in the owner's colour on each city
var pole_nodes: Array[MeshInstance3D] = [] # the banners' poles
var city_mesh: BoxMesh # the banner's cloth
var pole_mesh: CylinderMesh
var stand_heights := {} # tile key -> how high the ground is in the middle of that model (a hill's top)
var outpost_models := {} # hex -> its outpost model (made when it appears, freed when it's gone)
var basalt_base: ArrayMesh # a plain hex base in the tiles' basalt cliff texture (under mountains)
var water_shade_mesh: ArrayMesh # a flat hex laid on the water to darken it (fog, territory)

var skoll: Node3D
var markers := {} # a unit's (or Sköll's, Sunna's) model -> its pin
var marker_materials := {} # [colour, sun] -> pin material
var holed_meshes := {} # a tile mesh -> the same mesh with a hole for a rift (cut_hole)
var split_meshes := {} # a tile mesh -> [its ground, its tufts] (see paint_tufts)
var marker_mesh: QuadMesh
var marker_texture: ImageTexture
var sun_marker_texture: ImageTexture # Sunna's pin: a sun disc with rays in the head
var sunna: Node3D # rogue Sunna, out in the open (hidden while she shelters in a city)
var sunna_anim: AnimationPlayer
var sunna_cell := NO_CELL
var sunna_from := Vector3.ZERO
var sunna_walk := 0.0 # seconds left walking to her hex
var skoll_anim: AnimationPlayer
var skoll_feet := 0.0 # how far below the model's origin its feet are (after scaling)
var skoll_cell := NO_CELL # the hex the model is standing on (or walking to)
var skoll_from := Vector3.ZERO
var skoll_to := Vector3.ZERO
var skoll_walk_time := 0.0 # seconds left walking (0 = standing still)
var skoll_walk_total := 0.0
var skoll_height := 0.6 # how tall he stands (set in build_skoll)
var skoll_scale := 1.0 # his size on the map (set in build_skoll)
var skoll_vanish := 0.0 # seconds he has been sinking away after being beaten

func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-50, -30, 0) # low sun from the upper left, for shadows
	build_meshes()
	build_board()
	build_water()
	build_skoll()
	build_sunna()
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
	var key: Variant = tile_key(cell)
	if stand_heights.has(key):
		return stand_heights[key] * HEX_RADIUS
	if tile_scenes.has(key) or is_mountain_key(key):
		return MODEL_GROUND * HEX_RADIUS
	if not hex_is_explored(cell):
		return TileKit3D.top_height(Terrain.Type.PLAINS)
	return TileKit3D.top_height(state.terrain_at(cell))

# Which tile a hex shows: "unseen", a city ("settlement"), unsearched ruins, a rift you
# have found, or its land (a Terrain.Type; plains and forest away from ash and known
# rifts show their living look instead, see is_ashen). Dead land shows the ashen look.
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
	var land := s.terrain_at(c)
	if land == Terrain.Type.MOUNTAINS and basalt_base != null:
		return mountain_key(c)
	if LIVING_MODELS.has(land) and not is_ashen(c):
		return LIVING_MODELS[land]
	return land

# A mountain hex's look depends on its mountain neighbours (only ones the player has
# seen, so the shape of a range never gives away unexplored land): "mountain" alone,
# "mountain+" in a range, then each shared edge whose peak this hex draws (the hex that
# comes first in reading order draws it, so it is drawn once).
func mountain_key(c: Vector2i) -> String:
	var key := "mountain"
	var edges := ""
	for n in HexMap.neighbours(c):
		if state.terrain_at(n) == Terrain.Type.MOUNTAINS and hex_is_explored(n):
			key = "mountain+"
			if n.y > c.y or (n.y == c.y and n.x > c.x):
				edges += "|%d,%d" % [n.x, n.y]
	return key + edges

func is_mountain_key(key: Variant) -> bool:
	return key is String and key.begins_with("mountain")

# Grey, dying ground: dead land, the hexes next to it, and around the rifts the player
# has found. Only Faction.known_rifts counts, so ash never gives away a hidden rift.
func is_ashen(c: Vector2i) -> bool:
	var s := state
	if s.phase == GameState.Phase.LANDING:
		return false
	if s.is_ash(c) or HexMap.neighbours(c).any(func(n): return s.is_ash(n)):
		return true
	for rift in s.player.known_rifts:
		if HexMap.hex_distance(c, rift) <= ASHEN_RIFT_RANGE:
			return true
	return false

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
	basalt_base = make_basalt_base()
	for key in tile_scenes:
		if not key is String or not key in ["settlement", "rift"]:
			stand_heights[key] = centre_height(tile_scenes[key])
	city_mesh = BoxMesh.new()
	city_mesh.size = Vector3(0.2, 0.26, 0.02)
	pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.015
	pole_mesh.bottom_radius = 0.015
	pole_mesh.height = 0.75
	pole_mesh.radial_segments = 5
	unit_ring_mesh = TorusMesh.new()
	unit_ring_mesh.inner_radius = UNIT_RING_RADIUS - 0.08
	unit_ring_mesh.outer_radius = UNIT_RING_RADIUS
	unit_ring_mesh.rings = 24
	unit_ring_mesh.ring_segments = 6
	city_ring_mesh = TorusMesh.new()
	city_ring_mesh.inner_radius = CITY_RING_RADIUS - 0.05
	city_ring_mesh.outer_radius = CITY_RING_RADIUS
	city_ring_mesh.rings = 6 # six sides: it follows the hex's edge
	city_ring_mesh.ring_segments = 6

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

# The water: one mesh made of every water hex (a little wider than a hex, so it reaches
# under the land tiles' edges and neighbouring water hexes join into one lake or sea).
# Only water hexes: a plane under the whole map showed up inside the rift's hollow.
func build_water() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := HEX_RADIUS * WATER_REACH
	for c in hexes:
		if state.terrain_at(c) != Terrain.Type.WATER:
			continue
		var centre := cell_position(c) + Vector3(0, WATER_LEVEL, 0)
		for i in 6:
			var a0 := TAU * i / 6.0
			var a1 := TAU * (i + 1) / 6.0
			add_water_triangle(st, centre, centre + Vector3(sin(a0), 0, cos(a0)) * r, centre + Vector3(sin(a1), 0, cos(a1)) * r)
	st.generate_normals()
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = st.commit()
	water.material_override = m
	add_child(water)
	# a full-size hex (no gap) so neighbouring darkened water hexes join up
	var b := TileKit3D.Builder.new()
	b.prism(HEX_RADIUS, 0.002, WATER_LEVEL + 0.03, Color.WHITE)
	water_shade_mesh = b.commit()

# One triangle of a water hex, cut into WATER_STEPS x WATER_STEPS small ones so the
# waves (moved corner by corner in the shader) have corners to move.
func add_water_triangle(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	var n := WATER_STEPS
	var at := func(i: int, j: int) -> Vector3: # i steps toward p1, j toward p2
		return p0 + (p1 - p0) * (float(i) / n) + (p2 - p0) * (float(j) / n)
	for i in n:
		for j in n - i:
			for v in [at.call(i, j), at.call(i, j + 1), at.call(i + 1, j)]:
				st.add_vertex(v)
			if i + j < n - 1:
				for v in [at.call(i + 1, j), at.call(i, j + 1), at.call(i + 1, j + 1)]:
					st.add_vertex(v)

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
	skoll_scale = k
	skoll.scale = Vector3.ONE * k
	skoll_feet = -box.position.y * k
	skoll_height = box.size.y * k
	skoll.visible = false
	gild_skoll()

# Swaps Sköll's materials for skoll_glow.gdshader: the same textures, with his orange
# glow turned toward gold and shining a little.
func gild_skoll() -> void:
	for mi in skoll.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var own := m.mesh.surface_get_material(i) as StandardMaterial3D
			if own == null:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = SKOLL_GLOW_SHADER
			sm.set_shader_parameter("albedo_tex", own.albedo_texture)
			if own.normal_texture:
				sm.set_shader_parameter("normal_tex", own.normal_texture)
				sm.set_shader_parameter("has_normal", true)
			if own.roughness_texture:
				sm.set_shader_parameter("orm_tex", own.roughness_texture)
			m.set_surface_override_material(i, sm)

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
	update_rifts()
	update_marks()
	update_units(delta)
	update_skoll(delta)
	update_sunna(delta)
	update_markers()

# A glowing, unshaded colour (the rings under units and round cities), shared per colour.
func glow_material(colour: Color, glow: float) -> StandardMaterial3D:
	var key := [colour, glow]
	if not glow_materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = colour
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
		glow_materials[key] = m
	return glow_materials[key]

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
		if key is int and LIVING_MODELS.has(key):
			tint = tint * ASH_TINT # the ashen look
		elif key is int and key == Terrain.Type.HILLS:
			tint = tint * HILLS_TINT
		if not landing and s.is_ash(c):
			tint = tint * DEAD_LAND_TINT
		if dark:
			tint = tint.darkened(0.7)
		if key is String and key == "unseen":
			tint = UNSEEN_COLOUR # never seen: a black block
		elif not landing and not s.player_can_see(c):
			tint = tint.darkened(FOG_MEMORY_DARKEN) # seen before, out of sight now: the model, darkened
		elif landing and not s.can_land_at(c):
			tint = tint.darkened(0.6)
		if tile_scenes.has(key) or is_mountain_key(key):
			mi.mesh = null
			show_model(mi, key, tint, c, rifts_now.has(c) and not is_mountain_key(key))
		elif key is int and key == Terrain.Type.WATER:
			show_model(mi, null, tint) # no tile: the water plane shows through
			mi.mesh = null if tint == Color.WHITE else water_shade_mesh
			mi.material_override = tint_overlay(tint) # darkens the water under it
		else:
			show_model(mi, null, tint)
			if key is String:
				mi.mesh = tiles[key] # "unseen"
			else:
				mi.mesh = tiles[key][mi.get_meta("variant")]
			mi.material_override = tile_material(tint)

# Puts a tile model on a hex (made once, remade only when what the hex shows changes),
# or takes it away (key null). The tint is laid over it like the made-in-code tiles.
func show_model(mi: MeshInstance3D, key, tint: Color, cell := NO_CELL, holed := false) -> void:
	var model: Node3D = mi.get_node_or_null("Model")
	if model != null and (key == null or var_to_str(model.get_meta("key")) != var_to_str(key) or model.get_meta("holed", false) != holed):
		mi.remove_child(model)
		model.queue_free()
		model = null
	if key == null:
		return
	if model == null:
		if is_mountain_key(key):
			model = make_mountain(cell, key)
			model.rotation.y = -mi.rotation.y # its peaks are placed by map direction
		else:
			model = tile_scenes[key].instantiate()
		model.scale = Vector3.ONE * HEX_RADIUS # the models are already sized for hexes 1.0 apart
		model.name = "Model"
		model.set_meta("key", key)
		model.set_meta("holed", holed)
		paint_tufts(model)
		if holed:
			cut_hole(model)
		mi.add_child(model)
	var overlay := tint_overlay(tint)
	for part in model.find_children("*", "GeometryInstance3D", true, false):
		(part as GeometryInstance3D).material_overlay = overlay

# A mountain hex: the basalt base, and on it one tall peak alone, or in a range a
# medium peak in the middle plus a medium or low one on each shared edge it draws.
# Every peak's turn and choice are seeded by where it stands, so the map looks the
# same every time it is drawn.
func make_mountain(c: Vector2i, key: String) -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	base.mesh = basalt_base
	root.add_child(base)
	var ground := MODEL_GROUND
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c, "peak"])
	var centre: Node3D = (PEAK_MEDIUM if key.begins_with("mountain+") else PEAK_TALL).instantiate()
	centre.position = Vector3(0, ground, 0)
	centre.rotation.y = rng.randf() * TAU
	if key.begins_with("mountain+"):
		centre.scale = Vector3.ONE * PEAK_CENTRE_SCALE
	root.add_child(centre)
	var parts := key.split("|")
	for i in range(1, parts.size()):
		var xy := parts[i].split(",")
		var n := Vector2i(int(xy[0]), int(xy[1]))
		var edge_rng := RandomNumberGenerator.new()
		edge_rng.seed = hash([c, n])
		var peak: Node3D = (PEAK_MEDIUM if edge_rng.randf() < 0.5 else PEAK_LOW).instantiate()
		var mid := (cell_position(n) - cell_position(c)) / 2.0 / HEX_RADIUS
		peak.position = Vector3(mid.x, ground, mid.z)
		peak.rotation.y = edge_rng.randf() * TAU
		peak.scale = Vector3.ONE * PEAK_EDGE_SCALE
		root.add_child(peak)
	dull_peaks(root)
	return root

# The peaks' snow is bright white in the files and sparkles at night: a shared duller,
# less shiny copy of each of their materials.
func dull_peaks(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == basalt_base:
			continue
		for i in m.mesh.get_surface_count():
			var own := m.mesh.surface_get_material(i) as StandardMaterial3D
			if own == null:
				continue
			if not peak_materials.has(own):
				var dull := own.duplicate() as StandardMaterial3D
				var c := own.albedo_color * PEAK_DULL
				var grey := (c.r + c.g + c.b) / 3.0
				dull.albedo_color = Color(lerpf(c.r, grey, 0.3), lerpf(c.g, grey, 0.3), lerpf(c.b, grey, 0.3), own.albedo_color.a)
				dull.metallic_specular = PEAK_SPECULAR
				dull.roughness = maxf(own.roughness, 0.85)
				peak_materials[own] = dull
			m.set_surface_override_material(i, peak_materials[own])

# The basalt base under mountains: the plains tile's shape with its grass top and
# tufts swapped for the cliff texture its sides already use.
func make_basalt_base() -> ArrayMesh:
	var path := TILE_MODEL_PATH % "plains"
	if not ResourceLoader.exists(path):
		return null
	var tile: Node3D = load(path).instantiate()
	var result: ArrayMesh = null
	for part in tile.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (part as MeshInstance3D).mesh
		var basalt: Material = null
		for i in mesh.get_surface_count():
			if mesh.surface_get_material(i) != null and mesh.surface_get_material(i).resource_name == "Tile bedrock":
				basalt = mesh.surface_get_material(i)
		if basalt == null:
			continue
		result = ArrayMesh.new()
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat != null and TUFT_COLOURS.has(mat.resource_name):
				continue # no grass on a mountain
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
			result.surface_set_material(result.get_surface_count() - 1, basalt)
		break
	tile.free()
	return result

# How high a tile model's ground is at its middle, where a unit stands: the highest
# surface straight above the centre, leaving out the grass tufts (and the tree trunks,
# which have no surface right at the middle). Worked out once per model from its triangles.
# Cities and rifts keep MODEL_GROUND: a unit stands in front of the longhouse, and
# beside the rift's hollow rather than down in it.
func centre_height(scene: PackedScene) -> float:
	var root: Node3D = scene.instantiate()
	var best := -1.0
	for part in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var node: Node = part
		while node != root:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		var mesh: Mesh = (part as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si)
			if mat != null and TUFT_COLOURS.has(mat.resource_name):
				continue
			var arrays := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in range(0, index.size(), 3):
				var h := height_at_centre(xf * verts[index[t]], xf * verts[index[t + 1]], xf * verts[index[t + 2]])
				best = maxf(best, h)
	root.free()
	return best if best > 0.0 else MODEL_GROUND

# The height of a triangle straight above (0, 0), or -1 if it isn't above it.
func height_at_centre(a: Vector3, b: Vector3, c: Vector3) -> float:
	var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(d) < 1e-9:
		return -1.0
	var wa := ((b.z - c.z) * (0.0 - c.x) + (c.x - b.x) * (0.0 - c.z)) / d
	var wb := ((c.z - a.z) * (0.0 - c.x) + (a.x - c.x) * (0.0 - c.z)) / d
	var wc := 1.0 - wa - wb
	if wa < 0.0 or wb < 0.0 or wc < 0.0:
		return -1.0
	return wa * a.y + wb * b.y + wc * c.y

# A known rift's hex: a round hole (RIFT_HOLE) cut in the middle of its land tile for the
# rift's crater to sit in. Every triangle of the ground (and the soil under it) inside
# the hole goes; trees standing in it are hidden. Each mesh is cut once (holed_meshes).
func cut_hole(model: Node3D) -> void:
	for part in model.find_children("*", "MeshInstance3D", true, false):
		var mi := part as MeshInstance3D
		var xf := Transform3D.IDENTITY # where this part sits in the tile
		var node: Node = mi
		while node != model:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		if Vector2(xf.origin.x, xf.origin.z).length() < RIFT_HOLE + 0.04 and xf.origin.y > 0.2:
			mi.visible = false # a tree in the hole
			continue
		if not holed_meshes.has(mi.mesh):
			holed_meshes[mi.mesh] = holed_mesh(mi.mesh, xf)
		mi.mesh = holed_meshes[mi.mesh]

func holed_mesh(mesh: Mesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		var kept := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var inside := true
			var y := 0.0
			for k in 3:
				var p := xf * v[idx[t + k]]
				y += p.y / 3.0
				if Vector2(p.x, p.z).length() >= RIFT_HOLE:
					inside = false
			if inside and y > 0.1:
				continue
			kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays)
		out.surface_set_material(i, mesh.surface_get_material(i))
	return out

# The tufts share a mesh with their tile's ground, so each such mesh is split once into
# the ground (and bedrock) and the tufts (split_meshes), and the tufts get their own node:
# painted (TUFT_COLOURS) and hidden beyond TUFT_VISIBLE_DISTANCE, where they shimmered.
func paint_tufts(model: Node3D) -> void:
	for part in model.find_children("*", "MeshInstance3D", true, false):
		var mi := part as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if not split_meshes.has(mesh):
			split_meshes[mesh] = split_tufts(mesh)
		var split: Array = split_meshes[mesh]
		if split.is_empty():
			continue
		mi.mesh = split[0]
		var tufts := MeshInstance3D.new()
		tufts.mesh = split[1]
		tufts.visibility_range_end = TUFT_VISIBLE_DISTANCE
		tufts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(tufts)

# [ground mesh, tuft mesh] made from a tile mesh, or [] if it has no tufts.
func split_tufts(mesh: Mesh) -> Array:
	var ground := ArrayMesh.new()
	var tufts := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		var is_tuft := mat != null and TUFT_COLOURS.has(mat.resource_name)
		var into := tufts if is_tuft else ground
		into.add_surface_from_arrays(mesh.surface_get_primitive_type(i), mesh.surface_get_arrays(i))
		if is_tuft:
			var paint := material(TUFT_COLOURS[mat.resource_name])
			paint.cull_mode = BaseMaterial3D.CULL_DISABLED # thin blades: seen from both sides
			into.surface_set_material(into.get_surface_count() - 1, paint)
		else:
			into.surface_set_material(into.get_surface_count() - 1, mat)
	if tufts.get_surface_count() == 0:
		return []
	return [ground, tufts]

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

# Marked hexes (the same colours as the 2D view) and a white hex under the selected unit.
func update_marks() -> void:
	if mark_mesh == null:
		var b := TileKit3D.Builder.new()
		b.prism(HEX_RADIUS * 0.9, 0.01, 0.0, Color.WHITE)
		mark_mesh = b.commit()
	var marks: Dictionary = marks_of.call() if marks_of.is_valid() else {}
	var chosen = selected_of.call() if selected_of.is_valid() else null
	if chosen != null:
		marks[chosen.pos] = Color.WHITE
	var used := 0
	for c in marks:
		var node := pooled(mark_nodes, used, mark_mesh)
		used += 1
		node.material_override = mark_material(marks[c])
		node.position = cell_position(c) + Vector3(0, hex_top(c) + 0.04, 0)
	hide_rest(mark_nodes, used)

func mark_material(colour: Color) -> StandardMaterial3D:
	var key := Color(colour, 0.45)
	if not materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = key
		m.no_depth_test = false
		materials[key] = m
	return materials[key]

# The hex whose middle is nearest a point on the map (NO_CELL off the map).
func cell_at_point(p: Vector3) -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for c in hexes:
		var d := Vector2(p.x, p.z).distance_to(Vector2(cell_position(c).x, cell_position(c).z))
		if d < best_d:
			best_d = d
			best = c
	return best if best_d <= HEX_RADIUS else NO_CELL

# The hex under a point on the screen (where the mouse points, through the camera
# onto the ground), or NO_CELL off the map. main.gd uses it for clicks in 3D.
func cell_at_screen(screen_pos: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return NO_CELL
	var t := (MODEL_GROUND * HEX_RADIUS - from.y) / dir.y
	if t < 0.0:
		return NO_CELL
	return cell_at_point(from + dir * t)

# Whose city: a banner in the owner's colour on each settlement you've found.
# Rifts you know of: the rift model laid over the hex's own land tile (Nathan: "draw the
# rift as an overlay on the hex's own land tile instead of replacing it"), smaller
# (RIFT_OVERLAY_SCALE), sunk into a hole cut in the land (RIFT_SINK, cut_hole).
func update_rifts() -> void:
	for c in rifts_now:
		var model: Node3D = rift_models.get(c)
		if model == null:
			model = tile_scenes["rift"].instantiate()
			model.scale = Vector3.ONE * HEX_RADIUS * RIFT_OVERLAY_SCALE
			model.rotation.y = hexes[c].rotation.y if hexes.has(c) else 0.0
			add_child(model)
			rift_models[c] = model
		# its rim at the land's ground (not a hill's top: the hole takes the hill's middle)
		model.position = cell_position(c) + Vector3(0, (MODEL_GROUND - RIFT_SINK * RIFT_OVERLAY_SCALE) * HEX_RADIUS, 0)
		var dim := Color.WHITE if state.player_can_see(c) else Color.WHITE.darkened(FOG_MEMORY_DARKEN)
		var overlay := tint_overlay(dim)
		for part in model.find_children("*", "GeometryInstance3D", true, false):
			(part as GeometryInstance3D).material_overlay = overlay
	for c in rift_models.keys():
		if not rifts_now.has(c):
			rift_models[c].queue_free()
			rift_models.erase(c)

func update_cities() -> void:
	var used := 0
	for f in state.factions:
		if f.city_pos == NO_CELL or not state.player_has_explored(f.city_pos):
			continue
		var flag_at := cell_position(f.city_pos) + Vector3(0.55, hex_top(f.city_pos), 0.3)
		var pole := pooled(pole_nodes, used, pole_mesh)
		pole.material_override = material(Color(0.3, 0.22, 0.15))
		pole.scale = Vector3.ONE
		pole.position = flag_at + Vector3(0, pole_mesh.height / 2.0, 0)
		var cloth := pooled(city_nodes, used, city_mesh)
		used += 1
		cloth.material_override = material(colour_of.call(f))
		cloth.scale = Vector3.ONE
		cloth.position = flag_at + Vector3(city_mesh.size.x / 2.0, pole_mesh.height - city_mesh.size.y / 2.0, 0)
		var ring := pooled(city_ring_nodes, used - 1, city_ring_mesh)
		ring.material_override = glow_material(colour_of.call(f), CITY_RING_GLOW)
		ring.scale = Vector3.ONE * HEX_RADIUS
		ring.rotation.y = 0.0 # the torus already puts its corners at 30° + 60°k: on the pointy-top hex's corners (PI / 6 turned it flat-top)
		ring.position = cell_position(f.city_pos) + Vector3(0, MODEL_GROUND * HEX_RADIUS + 0.02, 0)
		if used > city_lights.size():
			var lamp := OmniLight3D.new()
			lamp.light_color = CITY_LIGHT_COLOUR
			lamp.light_energy = CITY_LIGHT_ENERGY
			lamp.omni_range = CITY_LIGHT_RANGE
			add_child(lamp)
			city_lights.append(lamp)
		var light := city_lights[used - 1]
		light.visible = true
		light.position = cell_position(f.city_pos) + Vector3(0, hex_top(f.city_pos) + 0.9, 0.3)
	var cities := used
	hide_rest(city_ring_nodes, cities)
	for i in range(cities, city_lights.size()):
		city_lights[i].visible = false
	# outposts you know of: Nathan's model, and a smaller banner in the owner's colour
	var known := {}
	for f in state.factions:
		for c in f.outposts:
			if not state.player_has_explored(c):
				continue
			known[c] = true
			var model: Node3D = outpost_models.get(c)
			if model == null:
				model = OUTPOST.instantiate()
				model.scale = Vector3.ONE * HEX_RADIUS
				model.rotation.y = PI # its door toward the middle of the hex
				add_child(model)
				outpost_models[c] = model
			var base := cell_position(c) + OUTPOST_OFFSET * HEX_RADIUS
			model.position = base + Vector3(0, hex_top(c), 0)
			var dim := Color.WHITE if state.player_can_see(c) else Color.WHITE.darkened(FOG_MEMORY_DARKEN)
			var overlay := tint_overlay(dim)
			for part in model.find_children("*", "GeometryInstance3D", true, false):
				(part as GeometryInstance3D).material_overlay = overlay
			var flag_at := base + Vector3(0.3, hex_top(c), 0)
			var pole := pooled(pole_nodes, used, pole_mesh)
			pole.material_override = material(Color(0.3, 0.22, 0.15))
			pole.scale = Vector3.ONE * 0.7
			pole.position = flag_at + Vector3(0, pole_mesh.height * 0.35, 0)
			var cloth := pooled(city_nodes, used, city_mesh)
			used += 1
			cloth.material_override = material(colour_of.call(f))
			cloth.scale = Vector3.ONE * 0.7
			cloth.position = flag_at + Vector3(city_mesh.size.x * 0.35, pole_mesh.height * 0.7 - city_mesh.size.y * 0.35, 0)
	for c in outpost_models.keys():
		if not known.has(c):
			outpost_models[c].queue_free()
			outpost_models.erase(c)
	hide_rest(city_nodes, used)
	hide_rest(pole_nodes, used)

# Rifts the player knows about (drawn as their hex's tile by update_board).
func shown_rifts() -> Array:
	var s := state
	if s.phase == GameState.Phase.LANDING:
		return []
	var rifts: Array = s.player.known_rifts.keys()
	var w := s.rifts.revealed
	if w != NO_CELL and s.player_can_see(w) and not rifts.has(w):
		rifts.append(w)
	return rifts

# Armies and scouts: one animated model per unit you can see. When a unit's hex
# changes it walks there (walk animation), then stands (idle).
func update_units(delta: float) -> void:
	var seen := {}
	for f in state.factions:
		for u in f.units:
			if f != state.player and not state.player_can_see(u.pos):
				continue # hidden by fog of war
			seen[u] = true
			var fig: Node3D = figures.get(u)
			if fig == null or fig.get_meta("scout") != u.is_scout():
				if fig != null:
					fig.queue_free()
				fig = make_figure(u.is_scout())
				figures[u] = fig
			var col: Color = colour_of.call(f)
			if f == state.player and u.moves <= 0:
				col = col.darkened(0.4) # dim = already moved, like the 2D view
			paint_band(fig, col)
			var target := cell_position(u.pos) + Vector3(0, hex_top(u.pos), 0)
			if state.is_city(u.pos):
				target += CITY_UNIT_OFFSET # standing in its city: at the front of the settlement
			walk_figure(fig, u.pos, target, delta)
	for u in figures.keys():
		if not seen.has(u):
			figures[u].queue_free()
			figures.erase(u)

func make_figure(is_scout: bool) -> Node3D:
	var fig: Node3D = (SCOUT if is_scout else WARRIOR).instantiate()
	fig.scale = Vector3.ONE * UNIT_HEIGHT / UNIT_MODEL_HEIGHT
	fig.set_meta("scout", is_scout)
	fig.set_meta("cell", NO_CELL)
	fig.set_meta("walk", 0.0)
	var anim: AnimationPlayer = fig.find_child("AnimationPlayer", true, false)
	for anim_name in ["idle", "walk"]:
		if anim and anim.has_animation(anim_name):
			anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	add_child(fig)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = unit_ring_mesh
	ring.scale = Vector3.ONE / fig.scale.x # the ring keeps its own size, whatever the model's scale
	ring.position = Vector3(0, 0.02 / fig.scale.x, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fig.add_child(ring)
	fig.rotation.y = randf() * TAU # (until it first walks somewhere)
	if anim and anim.has_animation("idle"):
		# each unit breathes at its own pace and from its own point in the loop
		anim.speed_scale = randf_range(0.85, 1.15)
		anim.play("idle")
		anim.seek(randf() * anim.get_animation("idle").length, true)
	return fig

# Repaints the blue arm band in the faction's colour (a shared material per colour).
func paint_band(fig: Node3D, col: Color) -> void:
	if fig.get_meta("band", Color.TRANSPARENT) == col:
		return
	fig.set_meta("band", col)
	fig.set_meta("marker", col)
	var ring := fig.get_node_or_null("Ring") as MeshInstance3D
	if ring:
		ring.material_override = glow_material(col, UNIT_RING_GLOW)
	for mi in fig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == ring:
			continue
		for i in m.mesh.get_surface_count():
			var own := m.mesh.surface_get_material(i) as StandardMaterial3D
			if own == null:
				continue
			var key := [own, col]
			if not band_materials.has(key):
				var sm := ShaderMaterial.new()
				sm.shader = UNIT_BAND_SHADER
				sm.set_shader_parameter("albedo_tex", own.albedo_texture)
				sm.set_shader_parameter("band_colour", col)
				band_materials[key] = sm
			m.set_surface_override_material(i, band_materials[key])

# Stands a unit's model on its hex, or walks it there if the unit has just moved.
func walk_figure(fig: Node3D, cell: Vector2i, target: Vector3, delta: float) -> void:
	var anim: AnimationPlayer = fig.find_child("AnimationPlayer", true, false)
	var from_cell: Vector2i = fig.get_meta("cell")
	if from_cell == NO_CELL:
		fig.position = target # just came into view
	elif from_cell != cell:
		fig.set_meta("from", fig.position)
		var total := UNIT_STEP_TIME * maxi(1, HexMap.hex_distance(from_cell, cell))
		fig.set_meta("walk", total)
		fig.set_meta("walk_total", total)
	fig.set_meta("cell", cell)
	var left: float = fig.get_meta("walk")
	var next_anim := "idle"
	if left > 0.0:
		left = maxf(0.0, left - delta)
		fig.set_meta("walk", left)
		var from: Vector3 = fig.get_meta("from")
		fig.position = from.lerp(target, 1.0 - left / float(fig.get_meta("walk_total")))
		var dir := target - from
		if Vector2(dir.x, dir.z).length() > 0.001:
			fig.rotation.y = atan2(dir.x, dir.z)
		next_anim = "walk"
	else:
		fig.position = target
	if anim and anim.current_animation != next_anim and anim.has_animation(next_anim):
		anim.play(next_anim, 0.2)

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

# A pin's picture, made once: a round head on a point, white with a dark edge (the
# material colours it). With sun, the head holds a gold disc with eight short rays
# (Sunna's pin, drawn white so it never looks like Sköll's gold one).
func make_marker_texture(sun := false) -> ImageTexture:
	var w := 48
	var h := 72
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var head := Vector2(w / 2.0, w / 2.0)
	var r := w / 2.0 - 2.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# inside the round head, or the triangle from the head down to the tip
			var half := r * clampf(1.0 - (p.y - head.y) / (h - 2.0 - head.y), 0.0, 1.0) * 0.75
			var d_head := p.distance_to(head)
			var in_tip := p.y >= head.y and absf(p.x - head.x) <= half
			if d_head <= r or in_tip:
				var edge := d_head > r - 4.0 and not (in_tip and absf(p.x - head.x) <= half - 4.0 and p.y < h - 6.0)
				if in_tip and d_head > r - 4.0 and absf(p.x - head.x) <= half - 4.0:
					edge = false
				var c := Color(0.08, 0.06, 0.05) if edge else Color.WHITE
				if sun and not edge and is_sun(p - head):
					c = SUN_DISC_COLOUR
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# Inside the sun drawn in Sunna's pin head: a disc, and eight rays around it.
func is_sun(v: Vector2) -> bool:
	var d := v.length()
	if d <= 7.5:
		return true
	if d < 10.0 or d > 15.0:
		return false
	var a := fposmod(v.angle(), PI / 4.0)
	return minf(a, PI / 4.0 - a) * d <= 1.6

func marker_material(colour: Color, sun := false) -> StandardMaterial3D:
	var key := [colour, sun]
	if not marker_materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.no_depth_test = true # seen through trees and peaks
		m.render_priority = 10
		m.albedo_texture = sun_marker_texture if sun else marker_texture
		m.albedo_color = colour
		marker_materials[key] = m
	return marker_materials[key]

# Places a pin above every model that has one (units, Sköll, Sunna), sized by how far
# away the camera is; none when the camera is close.
func update_markers() -> void:
	if marker_mesh == null:
		marker_texture = make_marker_texture()
		sun_marker_texture = make_marker_texture(true)
		marker_mesh = QuadMesh.new()
		marker_mesh.size = Vector2(2.0 / 3.0, 1.0)
	var pins_on := cam_distance >= MARKER_SHOW_DISTANCE
	var size := MARKER_SIZE * cam_distance
	var wanted := {}
	for fig in figures.values():
		wanted[fig] = [fig.get_meta("marker", Color.WHITE), UNIT_HEIGHT]
	wanted[skoll] = [SKOLL_MARKER, skoll_height]
	wanted[sunna] = [SUNNA_MARKER, SUNNA_HEIGHT]
	for node in wanted:
		var pin: MeshInstance3D = markers.get(node)
		if pin == null or not is_instance_valid(pin):
			pin = MeshInstance3D.new()
			pin.mesh = marker_mesh
			pin.top_level = true
			pin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(node as Node3D).add_child(pin)
			markers[node] = pin
		var colour: Color = wanted[node][0]
		var height: float = wanted[node][1]
		pin.visible = pins_on and (node as Node3D).visible
		if pin.visible:
			pin.material_override = marker_material(colour, node == sunna)
			pin.scale = Vector3.ONE * size
			pin.global_position = (node as Node3D).global_position + Vector3(0, height + size * 0.55, 0)
	for node in markers.keys():
		if not is_instance_valid(node):
			markers.erase(node)

# --- Sunna, when she has gone rogue: she walks over the land, lit warm gold --------
func build_sunna() -> void:
	sunna = SUNNA_SCENE.instantiate()
	add_child(sunna)
	sunna.scale = Vector3.ONE * SUNNA_HEIGHT / SUNNA_MODEL_HEIGHT
	sunna_anim = sunna.find_child("AnimationPlayer", true, false)
	if sunna_anim and sunna_anim.has_animation("walk"):
		sunna_anim.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
		sunna_anim.play("walk")
	var lamp := OmniLight3D.new()
	lamp.light_color = SUNNA_LIGHT_COLOUR
	lamp.light_energy = SUNNA_LIGHT_ENERGY
	lamp.omni_range = SUNNA_LIGHT_RANGE
	lamp.top_level = true # placed by update_sunna, not scaled with her
	lamp.name = "Light"
	sunna.add_child(lamp)
	sunna.visible = false

# She is shown only while rogue and in your sight. She always walks (Nathan: "show
# rogue Sunna with the walk animation"), toward her new hex when she moves.
func update_sunna(delta: float) -> void:
	var d := state.daughter
	if not d.is_rogue() or not state.player_can_see(d.pos):
		sunna.visible = false
		sunna_cell = NO_CELL
		return
	var target := cell_position(d.pos) + Vector3(0, hex_top(d.pos), 0)
	if not sunna.visible or sunna_cell == NO_CELL:
		sunna.visible = true
		sunna.position = target
		sunna_walk = 0.0
	elif d.pos != sunna_cell:
		sunna_from = sunna.position
		sunna_walk = SUNNA_STEP_TIME * maxi(1, HexMap.hex_distance(sunna_cell, d.pos))
		sunna.set_meta("walk_total", sunna_walk)
		var dir := target - sunna_from
		sunna.rotation.y = atan2(dir.x, dir.z)
	sunna_cell = d.pos
	if sunna_walk > 0.0:
		sunna_walk = maxf(0.0, sunna_walk - delta)
		sunna.position = sunna_from.lerp(target, 1.0 - sunna_walk / float(sunna.get_meta("walk_total")))
	else:
		sunna.position = target
	(sunna.get_node("Light") as Node3D).global_position = sunna.global_position + Vector3(0, SUNNA_HEIGHT * 0.9, 0.2)

# --- Sköll: idle while standing, walks from hex to hex when he moves ---------------
func update_skoll(delta: float) -> void:
	var w := state.skoll
	var shown := w.active and state.player_can_see(w.pos)
	if not shown:
		if not w.active and skoll.visible and skoll_cell != NO_CELL and skoll_vanish < SKOLL_VANISH_TIME:
			# beaten (or sated): he sinks into the ground where he stood and is gone; he
			# never walks or drifts back to a rift
			skoll_vanish += delta
			var t := minf(1.0, skoll_vanish / SKOLL_VANISH_TIME)
			skoll.scale = Vector3.ONE * skoll_scale * (1.0 - 0.6 * t)
			skoll.position.y -= delta * 0.8
			return
		skoll.visible = false
		skoll.scale = Vector3.ONE * skoll_scale
		skoll_cell = NO_CELL
		skoll_walk_time = 0.0
		return
	skoll_vanish = 0.0
	var target := cell_position(w.pos) + Vector3(0, hex_top(w.pos) + skoll_feet, 0)
	if not skoll.visible or skoll_cell == NO_CELL:
		# he just came into view: stand him on his hex
		skoll.visible = true
		skoll.position = target
		skoll_cell = w.pos
		skoll_walk_time = 0.0
	elif w.pos != skoll_cell and HexMap.hex_distance(skoll_cell, w.pos) > SKOLL_MAX_WALK:
		# farther than he can run in a turn: he came out of a rift somewhere else, so
		# he appears there instead of drifting across the map
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
		# feet on the ground of whichever hex he is crossing (not a straight line through the air)
		var under := cell_at_point(skoll.position)
		if under != NO_CELL:
			skoll.position.y = hex_top(under) + skoll_feet
		face(skoll_to - skoll_from)
		play("walk")
	else:
		skoll.position = target # (the hex can change height when it turns to ash or comes into view)
		# standing still: he faces the city he is hunting (he used to turn to the camera,
		# which looked like he followed it around)
		var prey: Faction = w.target
		if prey != null and prey.city_pos != NO_CELL and prey.city_pos != w.pos:
			face(cell_position(prey.city_pos) - cell_position(w.pos))
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
