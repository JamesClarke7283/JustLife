Adult eye and lid source

`art/characters.blend` is the editable reviewed production source, with a usable Scene, original rig and live shape keys. The four adult GLBs are its fresh exports. Runtime face controls are unchanged. This folder maintains the original two-stage sculpt rather than rerunning the older v23 generator, which intentionally protected eye geometry.

Reproduce from the repository root into a new private directory:

```sh
python3 -B tools/adult_eyes/generate.py --repository . --output dist/test-work/adult-eye-rebuild
```

The output directory must not exist. The driver extracts only the exact original `art/characters.blend` blob from commit `133d6a97c093a28569e5647eb383f7fb2f2780dd`; it does not check out or modify the repository. If that Git history is unavailable, `--input-blend PATH` accepts a standalone original input with the same pinned SHA-256. The final editable file can also be used directly without either historical input. Blender 5.2.1 LTS was used. Each GLB export runs in a fresh single-thread Blender process; neither the driver nor authoring scripts control an open editor.

The first stage changes ten eye pieces, both upper lids and a local orbital head mask. It makes the globe shallower, fits iris/pupil/catchlight depth to it, opens the neutral lid margin, and authors the corresponding Blink closure. The second stage changes only both upper lids: outer/corner attachment blends into the existing head, and the closed lower edge fits the supporting orbital surface. All ten first-stage eye pieces and the head remain exact in stage two. Mouth, nose and ear geometry outside the declared head mask, hair, clothing, body and rig are preserved by the authoring witnesses.

The authoring guards preserve native topology, UVs, weights, key names/settings, mesh-versus-Basis offsets and recorded non-owned object/material data. First-stage Sclera/Catchlight identity vectors retain exact X/Z; 1,141 depth-only subtraction results change by at most 9.313225746154785e-10 local units after the same explicitly checked float32 Basis translation. This is documented owned arithmetic, not a tolerance for unrelated channels. Stage two preserves every non-Blink relative identity vector exactly. Export triangulation and derived normals may change on the owned meshes; unrelated decoded payloads were checked separately before visual qualification.

`contract.json` uses exact digests of complete recorded object facts and material values, avoiding a large witness dump. `verify_native.py` reopens without saving and checks those values and a usable Scene. A `.blend` re-save is not promised to be byte-identical: the qualified rebuild has exact recorded native facts/material values and all four byte-identical GLBs. The driver retains logs/receipts and stops on a failed phase or mismatched export. Known local Blender addon startup logs included the cattrs import error despite successful CLI completion; they remain in private evidence, not hidden as clean logs.

The current review shows a substantially reduced raised lid border, a more open neutral eye and less profile protrusion. Angular closed corner creases, horizontal lid bands and the inherited lower seam remain visible limitations. Held Creator and controller checks do not establish all motion/contact cases. The final matched LOD and paused Live appearance review accepts this source increment. The [iteration review](../../docs/REVIEWS/iteration_44_adult_eyes.md) records those controls and the limited ordinary-distance evidence. This artwork increment was not numerically rescored and does not qualify a packaged release or the whole game.
