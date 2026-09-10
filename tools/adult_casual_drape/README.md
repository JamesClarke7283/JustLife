# Adult casual drape and skin weights

Reproduce the original casual-shirt hem/shoulder and shared-trouser contour, followed by the reviewed shoulder-weight correction. The first stage moves seven garment meshes while preserving independent Mesh/Basis coordinates and relative shape vectors with explicit float rounding records. The second changes only six casual-shirt/trim weight arrays, keeping the resulting coordinates, trousers, body and rig exact. The head, lips, mouth anchor, limb lengths, materials and unrelated outfits remain protected.

Use Blender 5.2.1 LTS and the existing shared `tools/adult_eyes` helpers plus `tools/adult_face_volume/generate.py`. From the repository root:

```sh
python tools/adult_casual_drape/generate.py --repository . --output dist/casual-reproduction --export
```

The output directory must be new. The tool reads the pinned original Blend directly from commit `94bcbf363c4a8834b73cb06298b5c805d84414f8`, without changing the working tree. Alternatively, pass `--input-blend /absolute/path/characters.blend` with that exact 2a181222… input; do not feed the final authored Blend back through the chain. `--blender /path/to/blender` selects the executable. Omit `--export` for the two native stages and fresh reopen alone.

Each Blender stage runs serially in a separate bounded background process with six private environment roots; HOME is unchanged. Reports, native intermediate/final files, four optional GLBs and retained logs go only into the requested output. The final editable file is `candidate/art/characters.blend`. The small manifest pins the input, shared tools, reports and four exports; complete measurement arrays and object facts are generated locally rather than duplicated in the source tree.

The drape report and both object-fact files must reproduce exactly. The weight report records its actual intermediate Blend hash; only that named `source_sha256` field is compared separately before requiring all remaining report values to match after deterministic JSON serialization. Blender may rewrite relative weak-library paths when saving in another directory, so actual container hashes are recorded and must stay unchanged throughout subsequent stages. Fresh native inspection checks all 362 object digests, materials and the usable Scene, derived from the exact generated final facts. All four GLB hashes remain strict. No arbitrary geometry or report differences are accepted.

This preserves the reviewed author parameters and evaluation order. Relocated execution of this extracted chain is a release gate, separate from source review. Stage logs retain Blender startup/add-on/export diagnostics even when exits are zero. The garment increment improves hem/leg flow and repairs the demonstrated arm-weight deformation; it does not claim perfect shoulder styling, cloth simulation or collision-free motion in every pose. Review production poses and both model detail levels when intentionally changing these parameters.
