# Child Bob LOD rim

This stage changes only the two child lower-detail Bob caps. It reduces the outer cap before generating the 7 mm inward shell; the accepted v36 exporter instead reduces the completed shell. The cap uses the same 0.12 reduction ratio. All native artwork and both full-detail child models remain byte exact. All 338 other decoded meshes, their projected accessor-sharing relationships, materials, nodes, skeletons and morphs stay exact in each LOD. The cap’s evaluated topology, normals, interpolated UVs and indices deliberately change through the export order; unrelated payloads are never rounded or repaired.

The existing v36 source and CLI remain unchanged. This exporter is a separate bounded stage, and the old source-generation pipeline continues to reproduce its historical accepted outputs. The unchanged v36 guarded transfer function imports the 25 Bob primitives from each fresh Blender export, then a stricter final witness requires that only Hair_Bob_Cap actually differs from the accepted LOD. This preserves the unrelated standard-LOD Crop UV payload despite reproducible raw exporter drift. Named consumer values and protected sharing are compared exactly; numeric accessor IDs are storage addresses.

## Reproduction

Use Blender 5.2.1 LTS build `9e2066aef7ef` and ordinary Python. The extractor reads five hash-pinned local Git objects from commit `5ee38d2fd1dde81ee4c1dcb01bd0cf9c01597dc4`. No private archive or network is required; a shallow checkout must already have those objects, or the same pinned inputs may be supplied separately.

```sh
python tools/child_bob_lod_hem/extract_inputs.py --repository . --output /absolute/new/bob-lod-inputs
python tools/child_bob_lod_hem/generate.py --source /absolute/new/bob-lod-inputs/art/characters_child.blend --baseline-models /absolute/new/bob-lod-inputs/assets/models --output /absolute/new/bob-lod-output
```

The output must be new. Native source and full models are copied byte exactly; two fresh, single-thread Blender processes export the LODs. Both raw GLBs and guarded final GLBs must match their qualified hashes. Logs, transfer witnesses and a reproduction receipt are retained. Inputs, old helper files and current scripts are checked before and after. The installed Blender environment has emitted a retained `cattrs` addon traceback; output equality does not imply clean addon logs.

The cap changes from 3,594 to 3,724 triangles (+130, about 3.6%), with 61 additional exported vertices and 2,732 bytes per GLB. These are geometry/storage counts, not a measured FPS result. The correction targets narrow dark hem teeth at Creator rear obliques; smooth heavy rear volume and broad angular cut corners remain. Ordinary Live heads are small at the supported camera, so Creator views carry detailed hem assessment. Shared verbose RGB8 startup warnings keep the historical capture receipts in failed strict status. No overall game score increase is claimed.
