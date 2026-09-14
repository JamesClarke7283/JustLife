# Recolourable portrait surface candidate

`author.py` adds original low-frequency complexion zones to the joined face,
radial pigment variation to the two irises, and restrained warm outer corners
to the two sclerae. These are native vertex colours, not borrowed images,
photographic skin or baked shadows. The selected skin/eye colour remains the
material multiplier. Body skin and all other materials are unchanged.

Run in Blender with `--source`, `--output` and `--report`; the output must not
already exist. The author compares all object transforms, mesh positions,
topology, UVs, weights, morphs, armature rest/pose and curve coordinates before
and after. Only five named meshes receive new colour attributes/materials.

Use the existing portrait variant exporter after reviewing the source. The
runtime recognises `Skin_Face_Surface` and `Eyes_Iris_Surface` for recolouring;
`Eyes_Sclera_Surface` retains its authored off-white base. Check actual imported
`COLOR_0` arrays and `vertex_color_use_as_albedo`, then view several complexions
and eye colours in Godot. An authoring receipt alone is not visual acceptance.

This material pass is independent of the cheek/chin geometry repair and can be
reapplied to its final source. Geometry/colour interpolation follows each
identity morph without adding a per-frame painting or texture-baking cost.
