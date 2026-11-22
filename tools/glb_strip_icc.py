# Godot 4.7 can't read a JPEG texture that carries a colour profile (an "ICC" block,
# which Meshy and some Blender exports add): the texture silently goes missing and
# the model shows up grey. This rewrites a .glb in place with those blocks removed
# (the pictures themselves are not touched or recompressed).
# Usage: python3 tools/glb_strip_icc.py file.glb [more.glb ...]
import json, struct, sys

def strip_icc(jpeg):
    if jpeg[:2] != b"\xff\xd8":
        return jpeg
    out, k = bytearray(jpeg[:2]), 2
    while k < len(jpeg) - 4 and jpeg[k] == 0xFF:
        marker = jpeg[k + 1]
        if marker == 0xDA: # start of the picture data: copy the rest as is
            break
        length = struct.unpack(">H", jpeg[k + 2:k + 4])[0]
        if marker != 0xE2: # APP2 holds the ICC profile
            out += jpeg[k:k + 2 + length]
        k += 2 + length
    out += jpeg[k:]
    return bytes(out)

def fix(path):
    data = open(path, "rb").read()
    json_len = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8
    blob = data[bin_start:bin_start + struct.unpack("<I", data[20 + json_len:24 + json_len])[0]]
    images = {im["bufferView"] for im in doc.get("images", []) if im.get("mimeType") == "image/jpeg" and "bufferView" in im}
    new_bin, changed = bytearray(), 0
    for i, view in enumerate(doc["bufferViews"]):
        start = view.get("byteOffset", 0)
        chunk = blob[start:start + view["byteLength"]]
        if i in images:
            fixed = strip_icc(chunk)
            changed += fixed != chunk
            chunk = fixed
        while len(new_bin) % 4:
            new_bin += b"\x00"
        view["byteOffset"] = len(new_bin)
        view["byteLength"] = len(chunk)
        new_bin += chunk
    while len(new_bin) % 4:
        new_bin += b"\x00"
    doc["buffers"][0]["byteLength"] = len(new_bin)
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(new_bin)
    out = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<I", len(js)) + b"JSON" + js
    out += struct.pack("<I", len(new_bin)) + b"BIN\x00" + new_bin
    open(path, "wb").write(out)
    print(path, ":", changed, "texture(s) fixed")

for p in sys.argv[1:]:
    fix(p)
