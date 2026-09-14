# Adult shape candidate evidence

Use **characters_shape_c.blend**, not the earlier exploratory a/b files.

- Frozen source SHA-256: `b5895903f64331e840304f8f106398024cefeebe55b64bb9f2314cd6250213e7`.
- Candidate c SHA-256: `1dc265b82df6a6124c9c7d7450d3536225731fcf18ced9a9e3272362ab34f0f4`.
- Authoring data: `author_c.json`.
- Full native verification: `verify_c.json`, **46 cases, zero failures**.
- Adult preview: `art/experiments/identity_shape_v62/models_c/character.glb`
  (project-relative), SHA-256
  `24d7e052187b22be0a14044486c39686ac20f8289868a58958727b0d83367959`.
- GLB contract check: `export_c.json`, passed. All eleven measured mouth
  offsets and the neutral anchor survive exactly, morph weights are zero,
  and a skin is present. All three new controls survive on the head; the
  frozen eye/lid/brow meshes have none of the new deformations.

The neutral vertices, topology, UVs, material assignments, skin weights, rig,
hair and old shape keys of all 460 objects were preserved exactly. All new
endpoint/corner combinations were checked against neutral, existing unsigned
controls at maximum, all prior controls positive, prior signed controls
negative, and Smile+Blink expression contexts. Across affected meshes there
were no triangle orientation reversals; the smallest area ratio was 0.315.
There were no new brow burial regressions. Each case checked 28 measured
upper/lower lip contact pairs and at least 89 near-head lip rim samples; the
maximum lip-to-head rim distance increase was 0.036 mm.

The neutral reference image was rendered from b, whose neutral geometry is
identical to c and the frozen source. The comparison images are rendered from
c, with all three new controls at -1 or +1 respectively, all prior controls
neutral, and the exact same lighting/materials/camera. Hairstyles are hidden
to expose actual shape differences. These are diagnostic views, not an
in-game quality score or a claim of finished portrait art.

Candidate c eliminates the exploratory bridge field's tiny eyelid effect:
none of the new controls has any target on the original Eyes_*, lids or brows.
When composed later with the new orbital collar, the collar's outer skin rim
should share facial fields while its actual inner aperture must remain safe.
The final eleven-control composition requires its own closed-eye verification
and in-game visual review; the frozen-source pass does not substitute for it.

The shared author is parameterized for all five age families, with reduced
teen/child/infant amplitudes. Only this adult candidate has been authored and
verified in this bounded task. No shipped asset or Godot script was changed.

The standard exporter exited zero. It logged the optional MeshOptimizer
library as unavailable and armature-parent selection warnings; the exported
GLB retains its skin, targets and metadata. Actual Godot import/animation
acceptance is still required in the final composed model. An additional
three-quarter native render was deferred so the age-family hair fitting
could use the shared machine; no render/export processes remain paused.

## Welded-eye composition, pending Blink visual refinement

`characters_welded_shape_a.blend` composes the same three controls onto the
eight-control welded source
`05d23f9f4c35b82fca50fc671e76602f7767dc2a7a34d1a05c7db2cfe85f1524`.
The composed native SHA-256 is
`db218cc33bd940113271dd5194841fecb96932f5c11872daa2c769ee8df02239`.
See `author_welded_a.json` and `verify_welded_a.json`.

This composition passed **70 cases with zero failures**, preserving all 460
source objects and the welded orbital indices exactly. The minimum affected
triangle area ratio was 0.314. Both 64-vertex inner apertures remain exactly
unchanged by the new controls. The full-Blink cases sampled **51,264 globe
rays with zero exposed sclera**; the largest paired closure gap was
0.000954 mm. Outer orbital skin is deformed continuously with adjacent facial
skin; the entire head was not frozen.

This is not a final export or a visual acceptance. Root's Godot macro review
identified small closed-canthus peaks in the input welded Blink, despite zero
globe leakage. The eye artist is trialing a separate Blink-only refinement.
Export of the composed face is held until that result is accepted or rejected;
an accepted revised source must receive its own composition check. No heavy
job remains active or paused from this verification run.
