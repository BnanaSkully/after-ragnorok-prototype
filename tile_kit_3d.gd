class_name TileKit3D

# The 3D view's hex tiles, made in code (view only: no rules here). Each land
# type is one small low-poly model, like the tile kit render in concept_art/
# (tile_kit_v1.png): a block of earth with a grassy top, and on it
#   plains: tufts of grass and a few stones
#   forest: a ring of pine trees (the middle is kept clear for units and cities)
#   hills: three soft green mounds
#   mountains: three grey peaks with snow on top
#   water: a lake sunk in a stone rim
# Each tile is ONE mesh with its colours painted on its corners (vertex
# colours), so the whole map is about 165 meshes: light enough for a phone.
# The view tints a tile (fog of war, territory) by multiplying these colours.
#
# When real tile models are exported from Blender into assets/models/tiles/,
# they can replace these one land type at a time.

const RADIUS := 0.96 # centre to corner (a hex is 1.0, the rest is the gap between tiles)
const BASE_HEIGHT := 0.22 # the block of earth
const TOP_HEIGHT := 0.05 # the grassy slab on top
const VARIANTS := 3 # different random layouts per land type, so the map doesn't repeat

const EARTH := Color(0.32, 0.24, 0.17)
const STONE := Color(0.42, 0.41, 0.4)
const GRASS := [Color(0.42, 0.58, 0.3), Color(0.24, 0.4, 0.21), Color(0.5, 0.52, 0.3), Color(0.3, 0.29, 0.29), Color(0.45, 0.45, 0.44)]
const TUFT := Color(0.6, 0.6, 0.25)
const PINE := Color(0.12, 0.28, 0.17)
const TRUNK := Color(0.3, 0.2, 0.12)
const MOUND := Color(0.45, 0.55, 0.3)
const ROCK := Color(0.4, 0.38, 0.38)
const SNOW := Color(0.92, 0.94, 0.97)
const WATER := Color(0.13, 0.3, 0.55)
const ASH_TOP := Color(0.36, 0.34, 0.33)
const STUMP := Color(0.15, 0.13, 0.12)

# How high a unit or city stands on each land (index = Terrain.Type).
static func top_height(land: int) -> float:
	if land == Terrain.Type.WATER:
		return BASE_HEIGHT # (nothing stands on water: this is the lake's rim)
	return BASE_HEIGHT + TOP_HEIGHT

# Makes every tile: result[land][variant] is an ArrayMesh. Plus "ash" (dead land)
# and "unseen" (a plain dark block for hexes never seen).
static func build_all() -> Dictionary:
	var kit := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 # the same tiles every game
	for land in Terrain.NAMES.size():
		var variants: Array[ArrayMesh] = []
		for v in VARIANTS:
			variants.append(build_tile(land, rng))
		kit[land] = variants
	kit["ash"] = build_ash(rng)
	kit["unseen"] = build_plain(Color(1, 1, 1), Color(1, 1, 1))
	return kit

static func build_tile(land: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var b := Builder.new()
	var top := BASE_HEIGHT + TOP_HEIGHT
	if land == Terrain.Type.WATER:
		b.prism(RADIUS, BASE_HEIGHT, 0.0, STONE)
		b.prism(RADIUS * 0.8, 0.012, BASE_HEIGHT, WATER) # the lake, inside the stone rim
		for i in 3:
			b.part(sphere(0.06, 0.05), rng.randf() * TAU, ring_spot(rng, 0.86, 0.9, BASE_HEIGHT), ROCK)
		return b.commit()
	b.prism(RADIUS, BASE_HEIGHT, 0.0, EARTH)
	b.prism(RADIUS, TOP_HEIGHT, BASE_HEIGHT, GRASS[land])
	match land:
		Terrain.Type.PLAINS:
			for i in 7:
				var at := ring_spot(rng, 0.3, 0.8, top)
				b.part(cone(0.045, 0.14, 4), rng.randf() * TAU, at + Vector3(0, 0.07, 0), TUFT)
			for i in 2:
				b.part(sphere(0.06, 0.045), rng.randf() * TAU, ring_spot(rng, 0.35, 0.75, top), ROCK)
		Terrain.Type.FOREST:
			var count := 8
			for i in count:
				var angle := TAU * i / count + rng.randf_range(-0.25, 0.25)
				var dist := rng.randf_range(0.5, 0.72)
				var h := rng.randf_range(0.45, 0.65)
				pine(b, Vector3(cos(angle) * dist, top, sin(angle) * dist), h)
		Terrain.Type.HILLS:
			for i in 3:
				var angle := TAU * i / 3.0 + rng.randf_range(-0.3, 0.3)
				var dist := rng.randf_range(0.45, 0.55)
				var r := rng.randf_range(0.26, 0.32)
				b.part(sphere(r, r * 0.55), 0.0, Vector3(cos(angle) * dist, top, sin(angle) * dist), MOUND)
			b.part(sphere(0.06, 0.04), 0.0, ring_spot(rng, 0.2, 0.3, top), ROCK)
		Terrain.Type.MOUNTAINS:
			peak(b, Vector3(0, top, 0.05), 0.62, 1.5)
			var a := rng.randf() * TAU
			peak(b, Vector3(cos(a) * 0.42, top, sin(a) * 0.42), 0.38, 0.95)
			a += rng.randf_range(2.0, 3.6)
			peak(b, Vector3(cos(a) * 0.42, top, sin(a) * 0.42), 0.34, 0.8)
	return b.commit()

# Dead land under the ash: grey top, a few burnt stumps.
static func build_ash(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := Builder.new()
	var top := BASE_HEIGHT + TOP_HEIGHT
	b.prism(RADIUS, BASE_HEIGHT, 0.0, EARTH.darkened(0.3))
	b.prism(RADIUS, TOP_HEIGHT, BASE_HEIGHT, ASH_TOP)
	for i in 3:
		b.part(cylinder(0.035, 0.12), 0.0, ring_spot(rng, 0.4, 0.7, top) + Vector3(0, 0.06, 0), STUMP)
	return b.commit()

# A plain block (used for never-seen hexes, which the view paints black).
static func build_plain(side: Color, top_colour: Color) -> ArrayMesh:
	var b := Builder.new()
	b.prism(RADIUS, BASE_HEIGHT, 0.0, side)
	b.prism(RADIUS, TOP_HEIGHT, BASE_HEIGHT, top_colour)
	return b.commit()

static func pine(b: Builder, at: Vector3, h: float) -> void:
	b.part(cylinder(0.03, h * 0.25), 0.0, at + Vector3(0, h * 0.125, 0), TRUNK)
	b.part(cone(h * 0.32, h * 0.6, 6), 0.0, at + Vector3(0, h * 0.2 + h * 0.3, 0), PINE)
	b.part(cone(h * 0.22, h * 0.45, 6), 0.0, at + Vector3(0, h * 0.5 + h * 0.225, 0), PINE.lightened(0.08))

static func peak(b: Builder, at: Vector3, r: float, h: float) -> void:
	b.part(cone(r, h, 5), 0.0, at + Vector3(0, h / 2.0, 0), ROCK)
	# the snow cap: the top quarter of the same cone, a hair wider so it covers the rock
	var cap_h := h * 0.28
	b.part(cone(r * 0.28 * 1.06, cap_h, 5), 0.0, at + Vector3(0, h - cap_h / 2.0 + 0.005, 0), SNOW)

# A random spot on the tile's top, between two distances from the middle.
static func ring_spot(rng: RandomNumberGenerator, near: float, far: float, y: float) -> Vector3:
	var angle := rng.randf() * TAU
	var dist := rng.randf_range(near, far) * RADIUS * 0.866 # stay inside the hex's flat sides
	return Vector3(cos(angle) * dist, y, sin(angle) * dist)

static func cone(r: float, h: float, sides: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	m.cap_bottom = false
	return m

static func cylinder(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 5
	m.rings = 1
	return m

# A low-poly dome (half a squashed sphere), its flat side on the ground.
static func sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h * 2.0
	m.radial_segments = 8
	m.rings = 4
	m.is_hemisphere = true
	return m

# Collects the pieces of one tile into a single mesh, each piece painted one colour.
class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()

	# A hex block: pointy-top (Godot's 6-sided cylinder puts a corner on +Z, "up" on screen).
	# Built by hand so its sides are flat-shaded, like the low-poly render.
	func prism(r: float, h: float, bottom: float, colour: Color) -> void:
		var top := bottom + h
		var corners: Array[Vector3] = []
		for i in 6:
			var a := TAU * i / 6.0
			corners.append(Vector3(sin(a) * r, 0, cos(a) * r))
		# top face: a fan around the centre
		var centre := verts.size()
		add_vertex(Vector3(0, top, 0), Vector3.UP, colour)
		for i in 6:
			add_vertex(corners[i] + Vector3(0, top, 0), Vector3.UP, colour)
		for i in 6:
			indices.append_array([centre, centre + 1 + (i + 1) % 6, centre + 1 + i])
		# sides: one flat quad each
		for i in 6:
			var a := corners[i]
			var c := corners[(i + 1) % 6]
			var n := ((a + c) / 2.0).normalized()
			var s := verts.size()
			add_vertex(a + Vector3(0, top, 0), n, colour)
			add_vertex(c + Vector3(0, top, 0), n, colour)
			add_vertex(c + Vector3(0, bottom, 0), n, colour)
			add_vertex(a + Vector3(0, bottom, 0), n, colour)
			indices.append_array([s, s + 1, s + 2, s, s + 2, s + 3])

	# Adds a ready-made Godot shape, turned around the vertical axis and moved into place.
	func part(mesh: PrimitiveMesh, yaw: float, at: Vector3, colour: Color) -> void:
		var arrays := mesh.get_mesh_arrays()
		var xform := Transform3D(Basis(Vector3.UP, yaw), at)
		var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var src_i: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var start := verts.size()
		for k in src_v.size():
			add_vertex(xform * src_v[k], xform.basis * src_n[k], colour)
		for k in src_i:
			indices.append(start + k)

	func add_vertex(v: Vector3, n: Vector3, colour: Color) -> void:
		verts.append(v)
		normals.append(n)
		colours.append(colour)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m
