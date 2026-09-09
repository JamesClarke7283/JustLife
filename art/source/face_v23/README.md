# Adult local eye/lip revision23

The editable adult source and four production models use the accepted local V3 eye/lip artwork. This original pass quiets the lower orbital rim, softens the lips and corrects a measured upper-socket overlap through a bounded head mask. Existing eye geometry, facial identity, rig, hair, hands, clothing and other ages remain protected. Rig18/surface2 stays unchanged; face revision23 is a separate source/art revision.

Reproduce from this immutable clothing-v22 input in a fresh Blender5.2.1 LTS process, build9e2066aef7ef:

```sh
blender --background --factory-startup -t 6 --python-exit-code 2 \
  --python tools/sculpt_face.py -- \
  --source art/source/face_v23/characters_clothing_v22.blend \
  --output-root /absolute/new/output
```

The driver requires exact input SHA6de0bf9235efd9f9768ec1ca59945066cbec151b0364313fdd7c1c11f1a3d74f and a separate new or empty output. Before scene mutation it checks the input and compact socket-table hash. It reproduces the local V2 fields, then applies289 coordinate-checked upper-socket changes inside the frozen292-ID mask. Original mesh-to-Basis offsets, relative identity/Smile deltas and source key values are retained. Only the upper-lid Blink target changes relative to Basis.

Output is adult `art/characters.blend`, four fixed adult GLBs and local audit sidecars. Each variant exports from that saved Blend in a fresh single-thread process, with neutral export-only pose, evaluated scene updates and the qualified detailed/LOD settings. The editable Blend retains its original source values. Exact decoded guards reject unknown geometry or metadata drift and preserve raw output/logs; the editor never transplants binary meshes or repairs hair.

One isolated reproduction produced all four GLBs byte-identically. Its saved Blend has different container bytes, while all362 recorded objects plus five full owned-surface records match the accepted editable source exactly. The package retains the exact accepted Blend and records both hashes in `face_v23_manifest.json`. This is same-environment source-value reproduction, not a cross-version guarantee or a claim about every Blender RNA field.

The cattrs addon registration traceback and known exporter notices remain disclosed environment limitations. They did not prevent successful generation; qualified Godot validation logs are clean. Existing clothing/v18 source manifests and all15 nonadult production files are retained. Large private captures, reports, witness data and logs are intentionally excluded from the source tree. See `docs/REVIEWS/iteration_23_face.md` for scoped acceptance and remaining visual limitations.
