# Juniper floor mop

Original JustLife artwork, authored in Blender by `tools/create_mop.py`. The editable source is `juniper_mop.blend`; the game loads `assets/models/juniper_mop.glb`. The mesh uses a warm ash handle, sage enamel head and woven cotton pad. It has no external assets or textures.

The mesh is in metres, with the cotton underside at ground level. Godot Y-up shaft endpoints are `(0, .06, 0)` and `(0, 1.25, -.38)`. The actor solves both hands to points on this handle while sweeping the head on the floor. Clothing remains on during emergency plant use; no explicit anatomy or liquid stream is rendered.
