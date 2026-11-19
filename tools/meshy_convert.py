# Converts a Meshy FBX (from its zip, with its .png textures beside it) into a
# light .glb for Godot: decimated to about <target_tris> triangles, colour and
# normal textures shrunk to <tex_px>. Needs Blender's Python module: pip install bpy
# Example: python3 tools/meshy_convert.py Meshy_X.fbx assets/models/props/x.glb 4000 512
# usage: python3 meshy_convert.py <fbx> <out.glb> <target_tris> <tex_px>
import bpy, sys, os
fbx, out, target, px = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
print('tris before', tris)
def count():
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
for attempt in range(4):
    now = count()
    if now <= target * 1.2: break
    for o in meshes:
        mod = o.modifiers.new('dec', 'DECIMATE'); mod.ratio = max(0.02, target / now)
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier='dec')
print('tris after', sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes))
# Meshy's FBX leaves its textures unlinked: build a simple material from the
# zip's own images (colour + normal), shrunk to px.
d = os.path.dirname(fbx)
stem = os.path.splitext(os.path.basename(fbx))[0]
def load(suffix):
    p = os.path.join(d, stem + suffix + '.png')
    if not os.path.exists(p): return None
    img = bpy.data.images.load(p)
    if max(img.size) > px: img.scale(px, px)
    img.pack()
    return img
col, nor = load(''), load('_normal')
mat = bpy.data.materials.new('meshy'); mat.use_nodes = True
nt = mat.node_tree; bsdf = nt.nodes['Principled BSDF']
bsdf.inputs['Roughness'].default_value = 0.85; bsdf.inputs['Metallic'].default_value = 0.0
if col:
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = col
    nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
if nor:
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = nor; t.image.colorspace_settings.name = 'Non-Color'
    nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(t.outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
for o in meshes:
    o.data.materials.clear(); o.data.materials.append(mat)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o not in meshes]:
    bpy.data.objects.remove(o)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_cameras=False, export_lights=False, export_animations=False)
print('size', os.path.getsize(out))
