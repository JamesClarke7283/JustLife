# Fuller-height adult lips

This reproduces the reviewed lip-height candidate from accepted adult V4 at
`fc58f69af1aea13ab4b501af7b4ee452464e1fcb`, Blend SHA-256
`5b88ef9f415be618ce1586b49ea51a5086ddc660a460430b1752ce6e3ae2c42e`.
It starts from that production source, not the earlier held depth-only trial.

With Python 3 and Blender 5.2.1 LTS, from the repository root:

```sh
python3 tools/adult_lip_volume/generate.py --repository . --output /tmp/justlife-adult-lips --export
```

Alternatively use `--input-blend /path/to/characters.blend` instead of
`--repository .`. The input must match the same hash. `--blender` selects an
executable. Omit `--export` for the native author and fresh reopen only. The
output directory must be new. Run the generator rather than the author directly
so that isolation, shared-helper pins, native materials and output guards apply.

The author changes only `Lips_Upper_soft`, `Lips_Lower_soft` and
`Lips_Smile_seam`. One actual joined-rim curve controls the positive vertical
scale, 1.45 centrally and smoothly 1 at the fixed corners. The head Basis at the
new height supports the depth refit; the old front field is sampled at original
coordinates. Both actual shell sheets receive the same coordinate mapping.
Central upper/lower height becomes 6.319/7.907 mm. The seam is reduced and
recessed while preserving all 97 native-local ring means. The center of ring
vertices 384–391 and Character mouth_anchor `[0, .054, .118866]` remain fixed.

Mesh and every shape key receive independently stored values plus the same
per-vertex displacement. The reviewed result has zero relative-key or
mesh/Basis rounding differences. The existing shared Smile field is explicitly
reevaluated at old/new points and remains exact. Topology, UVs, weights, key
metadata, materials and all 359 other objects—including head/chin—are protected.
Derived float32 world ring means are recorded individually; their maximum
44.7 nm rounding difference is not corrected by moving additional vertices.

The tool reuses `adult_eyes/source_facts.py`, `verify_native.py`, and
`export_variant.py`, plus the accepted `adult_face_volume` Smile/parameter
contract and generator environment definitions. Shared files are hash-pinned.
The three diagnostic reports must reproduce exactly. The actual native hash
and its equality to the reviewed container are recorded separately. A fresh
read-only reopen checks all 362 object facts, material values and usable Scene.
Optional exports run all four variants in separate processes and require their
reviewed hashes. The actual native hash is passed to each exporter and checked
before and after every native/export stage. Every stage has six private
data/config/cache/temp roots;
HOME stays unchanged and imported helper bytecode writes are disabled.

Outputs are under `candidate/art` and, with `--export`,
`candidate/assets/models`. The receipt retains commands, timings and raw log
hashes. A nonzero stage, timeout, changed input/helper/native source, mismatched
report, native fact or GLB output fails the run. Diagnostic log lines are retained separately and need review even when
the process exits zero; the original author/export runs contain known add-on
and exporter warnings.

The eight matched views show a modest front-view gain, while the profile retains
an angular tip and abrupt return. Scoped face assessment remains about 5.5/10.
The 39 seam projected-sign changes are geometric diagnostics, not 39 proven
folds; the lip triangle and sampled shell checks are not a complete
self-intersection proof. Contact, LOD/identity and rendered appearance remain
separate qualification gates. Source extraction alone does not establish a
successful relocated reproduction.

The first relocated run authored successfully but failed the original strict
Blend-container hash gate. Its three reports were byte-exact, and a separate
fresh reopen matched all native object/material facts. Decompressed comparison
identified exactly two mesh LibraryWeakReference.library_filepath fields,
each gaining one `../` segment. All other decompressed bytes were exact.
That original failed receipt is retained. R2 separates container equality from
the unchanged semantic/report/export gates. This is a justified path-storage
boundary, not a successful R2 reproduction claim: a fresh full generator run
is still required.
