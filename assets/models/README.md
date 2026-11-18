# Game-ready 3D models

Put game-ready models here, in these folders:

- `tiles/`: hex tiles (plains, forest, hills, mountains, water, rifts...)
- `props/`: things that sit on a tile (trees, ruins, runestones, buildings)
- `units/`: armies, scouts, Sköll, the Sun's Daughter

Rules:

- **.glb only.** Never put a .blend file here (Godot would ask for Blender's executable to import it). Export from Blender as glTF Binary (.glb).
- **Textures at most 1024 px** on their longest side.
- Source files (.blend) and reference art stay in `concept_art/`, which Godot ignores.
