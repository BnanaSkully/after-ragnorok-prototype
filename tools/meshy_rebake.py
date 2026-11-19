# Re-converts a Meshy FBX for the game: voxel remesh + decimate (keeps the shape), new UVs,
# and bakes the colour from the original. Optional last arg: clip the footprint to a pointy-top hex
# (fraction of its narrowest half-width); the cut sides get the "Kit cliff" material.
# Run: python3 -I -c "import sys,runpy; sys.argv=['x','--',<fbx>,<out.glb>,<tris>,<px>,<voxel_frac>,[clip]]; runpy.run_path('tools/meshy_rebake.py')"
# usage: -- <fbx> <out.glb> <target_tris> <tex_px> <voxel_frac>
import bpy, sys, os, mathutils
a = sys.argv[sys.argv.index('--')+1:]
fbx, out, target, px, vfrac = a[0], a[1], int(a[2]), int(a[3]), float(a[4])
clip = float(a[5]) if len(a) > 5 else 0.0
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.fbx(filepath=fbx)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in meshes: print('obj', o.name, len(o.data.polygons))
src = max(meshes, key=lambda o: len(o.data.polygons))
for o in meshes:
    if o is not src: bpy.data.objects.remove(o)
d = os.path.dirname(fbx); stem = os.path.splitext(os.path.basename(fbx))[0]
col_img = bpy.data.images.load(os.path.join(d, stem + '.png'))
smat = bpy.data.materials.new('src'); smat.use_nodes = True
t = smat.node_tree.nodes.new('ShaderNodeTexImage'); t.image = col_img
bs = smat.node_tree.nodes['Principled BSDF']
smat.node_tree.links.new(t.outputs['Color'], bs.inputs['Base Color'])
src.data.materials.clear(); src.data.materials.append(smat)
# apply transforms so both meshes share space
bpy.context.view_layer.objects.active = src
src.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
size = max(src.dimensions)
# low-poly copy: voxel remesh (closes the strands into one skin), then decimate
low = src.copy(); low.data = src.data.copy(); sc.collection.objects.link(low)
low.name = 'low'
low.data.materials.clear()
m = low.modifiers.new('r', 'REMESH'); m.mode = 'VOXEL'; m.voxel_size = size * vfrac
bpy.context.view_layer.objects.active = low
bpy.ops.object.select_all(action='DESELECT'); low.select_set(True)
bpy.ops.object.modifier_apply(modifier='r')
if clip > 0:
    import math
    bb = [low.matrix_world @ mathutils.Vector(c) for c in low.bound_box]
    cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2; cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
    half = min(low.dimensions.x, low.dimensions.y) / 2
    apo = half * clip * math.cos(math.radians(30))
    bpy.ops.object.mode_set(mode='EDIT')
    for i in range(6):
        ang = math.radians(60 * i + 30) # game corner on +Z (Blender -Y); sides between corners
        nrm = mathutils.Vector((math.sin(ang), -math.cos(ang), 0))
        co = mathutils.Vector((cx, cy, 0)) + nrm * apo
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.bisect(plane_co=co, plane_no=nrm, use_fill=True, clear_outer=True)
    bpy.ops.object.mode_set(mode='OBJECT')
n = len(low.data.polygons) * 2
print('remeshed tris', n)
if n > target:
    m = low.modifiers.new('d', 'DECIMATE'); m.ratio = target / n; m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='d')
print('low tris', sum(len(p.vertices) - 2 for p in low.data.polygons))
bpy.ops.object.shade_smooth()
# new UVs
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')
# bake target material
img = bpy.data.images.new('baked', px, px)
lmat = bpy.data.materials.new('meshy'); lmat.use_nodes = True
lt = lmat.node_tree; tn = lt.nodes.new('ShaderNodeTexImage'); tn.image = img
lt.nodes.active = tn
lb = lt.nodes['Principled BSDF']; lb.inputs['Roughness'].default_value = 0.9; lb.inputs['Metallic'].default_value = 0.0
low.data.materials.append(lmat)
if clip > 0:
    # the cut sides: the game textures them like the other tiles' cliffs
    cmat = bpy.data.materials.new('Kit cliff'); cmat.use_nodes = True
    cmat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.25, 0.23, 0.22, 1)
    dummy = cmat.node_tree.nodes.new('ShaderNodeTexImage'); dummy.image = bpy.data.images.new('dummy', 8, 8)
    cmat.node_tree.nodes.active = dummy
    low.data.materials.append(cmat)
    for poly in low.data.polygons:
        c = poly.center
        for i in range(6):
            ang = math.radians(60 * i + 30)
            nrm = mathutils.Vector((math.sin(ang), -math.cos(ang), 0))
            if abs((c - mathutils.Vector((cx, cy, c.z))).dot(nrm) - apo) < 1e-4 and abs(poly.normal.dot(nrm)) > 0.9:
                poly.material_index = 1
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 4
sc.render.bake.use_selected_to_active = True
sc.render.bake.cage_extrusion = size * vfrac * 2
sc.render.bake.max_ray_distance = size * vfrac * 4
sc.render.bake.margin = 4
bpy.ops.object.select_all(action='DESELECT'); src.select_set(True); low.select_set(True)
bpy.context.view_layer.objects.active = low
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})
img.filepath_raw = out.replace('.glb', '_baked.png'); img.file_format = 'PNG'; img.save()
img.pack()
lt.links.new(tn.outputs['Color'], lb.inputs['Base Color'])
if clip > 0: cmat.node_tree.nodes.remove(dummy)
bpy.data.objects.remove(src)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_cameras=False, export_lights=False, export_animations=False)
print('size', os.path.getsize(out))
