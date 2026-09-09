# Adult lower-face volume

This reproduces the reviewed V4 neutral chin/mouth support, shared Smile and
mouth-anchor adjustment. It starts from the production adult-eye Blend at
`0c108161dffa361c9ebf1d812757d8389b548351`, SHA-256
`2f2dec8e9919482c10aa76975595bd053e379ecea3d4728c1b77603ee14e961c`.
It does not build on the earlier face trials.

From the repository root, with Blender 5.2.1 LTS and Python 3 available:

```sh
python3 tools/adult_face_volume/generate.py --repository . --output /tmp/justlife-adult-face
```

Alternatively, replace `--repository .` with `--input-blend /path/to/characters.blend`.
The standalone input must have the same reviewed hash. `--blender /path/to/blender`
selects the executable. The output directory must not already exist.

The generator reuses `tools/adult_eyes/source_facts.py`, `verify_native.py` and
`export_variant.py`; their reviewed hashes are in `contract.json`. It authors the
neutral source, measures the native seam, applies Smile and the mouth anchor,
reopens the Blend for object/material verification, then exports all four adult
variants in separate processes. Outputs are under `final/art` and
`final/assets/models`. Each stage has its own five data/config/cache/temp roots
and Blender configuration. `HOME` is inherited unchanged. Failed stages and
startup diagnostics stay in the output receipt and logs.

The neutral stage changes only `Skin_Head_continuous`, `Lips_Upper_soft`,
`Lips_Lower_soft` and `Lips_Smile_seam`. Existing topology, materials, rig and key
metadata remain fixed. The same quantized displacement is applied to mesh and
all shape keys; 45 relative-key and 31 mesh/Basis float32 subtraction differences
were recorded, at most 7.45 and 3.73 nanometres in local coordinates respectively.
The author records them explicitly. The finish stage replaces only the four
Smile targets and transports `Character.mouth_anchor` to `[0, .054, .118866]`.

Native seam ring vertices **384–391** define the center. Float32 world coordinates
followed by `fsum` ring means reproduce the measured authored center and end
rises. The Smile parameters are fixed reviewed art values, checked against those
measurements: half-width `.033`, center height `1.5119999788934058`, corner
coefficient `.004864473379434882`. The coefficient averages the two endpoint
`rise / (x / half_width)^2` values. This quadratic guide approximates the actual
intermediate seam inside the ten-millimetre Smile band. Anchor transport uses
the original offset from the same native center, converts through Head-local
Blender coordinates to Godot, then rounds the property to six decimals.

The contract requires exact recorded native object/material values and exact
four GLB hashes. It records native Blend byte equality separately because saved
file metadata can differ. A fresh tool run is required to qualify a relocated
extraction; source comparison alone is insufficient.

The accepted visual scope is a bounded chin/support improvement, approximately
5.5/10 in the reviewed front/profile views. The underside remains slightly
angular; outlined lips, a pointed lip edge and a faint Smile cheek crease remain.
Zero projected sign reversals in the examined lip triangles is not a full
self-intersection proof. Lip/seam Z follows the shared raw field while their
depth fits the smoothed head. Contact, LOD and identity checks are separate
qualification gates; this generator does not replace those tests or establish
finished face quality.
