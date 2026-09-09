# Adult Crop shape and head clearance

The adult Crop hairstyle now follows the ears and nape, with softer crown and side flow joining the cap. The accepted asymmetric front sweep remains. A final clearance correction prevents the scalp intrusion found with the combined-maximum head identity. Both adult frames and their detailed and LOD exports are updated. Face identity, garments, rig, shared materials and all other ages remain unchanged.

The independent critic accepted the replacement after inspecting 26 corrected views: ten default Creator/Live views and sixteen combined-maximum identity, friendly and anchored eating views. The bounded hairstyle score is **7.5/10**; the broader game remains **7.2/10**. Modest rear/temple flare and small lower-edge LOD shading ripples remain. This is an incremental improvement toward the open 10/10 goal.

## Verification

The matched default captures passed 1,015 assertions per run and the endpoint/acting captures passed 1,653 per run, with zero failures and clean Godot diagnostics. Only the four adult model inputs changed; every recorded control and head-motion trace matched exactly. Root verified the 76 capture pins and the critic's frozen report, then inspected corrected rear, acting, front and Live examples. These checks cover the displayed body/identity combinations and fixed animation phases, not every possible combination or continuous animation frame.

The source change affects 14 Crop meshes. Cap and sideburn coordinates change; six crown and five side-flow meshes have deliberately rebuilt topology and UVs. The final clearance step changes 316 cap vertices horizontally while preserving their heights and all other native geometry and metadata. Fresh source verification passes 377 assertions for that step; exact named decoded export comparisons pass 12,636. Detailed cap UVs and indices remain exact. Cap-only LOD re-decimation changes the vertex/UV count from 2,173 to 2,159, retaining 10,782 indices. Non-cap decoded values and sharing remain exact.

The portable three-stage Blender pipeline reproduced all four final GLBs byte-for-byte. Separate fresh native checks passed 1,149 assertions across its stages. Recreated Blender containers differ in bytes while their recorded authoring data matches; this is a same-environment result, not a cross-version guarantee. Known Blender addon-registration tracebacks and exporter notices are retained in the successful process logs and are not described as warning-free.

Root verified all 76 source-package artifacts and every expected current file before copying the 20-file promotion set. The existing 20-file production manifest changes only the adult source and four adult exports. Runtime scripts do not change in this increment. Reproduction instructions and the immutable starting source are in [the source README](../../art/source/crop_v26/README.md).

## Retained evidence

- Source handoff: `dist/test-work/crop-clearance-portable-v27-84z3rcl2/FINAL_HANDOFF.md`; freeze SHA-256 `820976871f7d03e36d310edaa5ac77a9854b517a3c0a3feae7887e0c459a342d`.
- Visual report: `dist/test-work/crop-invite-critic-v26-kwf3f_lr/CROP_CLEARANCE_GATE.md`, SHA-256 `5365707a1cee3ee74869a1713aafed3e2dc52b56e7b4a7732a155cdbeed6e434`.
- Matched captures: `dist/test-work/adult-crop-v25-iuy8uad1/CLEARANCE_CAPTURE_FROZEN.json`, SHA-256 `0b5de80364d3318cdf5bd440d8665a63561943fc24eb1bfb54a2ad5d8eaa4143`.
- Root promotion receipt: `dist/game-work/crop_clearance_promotion_receipt.json`.

Earlier rejected shapes and the pre-clearance endpoint failure remain preserved. The latter passed default views but exposed scalp in the larger head's rear and acting views. A positional accessor comparison also failed when rebuilt meshes shared identical indices; exact comparisons by named consumer replaced numeric table alignment without relaxing protected values or sharing. The native tuple/JSON-array comparison error and an initial diagnostic syntax error remain recorded. None of these attempts is counted as a clean success.

Package integration and actual executable verification are recorded separately in [release verification](../RELEASE_VERIFICATION.md).
