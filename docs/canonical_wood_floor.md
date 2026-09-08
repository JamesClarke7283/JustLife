# Canonical wood floor finish

Warm oak (`cfa97e`) and Walnut (`896953`) now use an original procedural wood material on canonical floor boxes. Each construction scene owns at most two ShaderMaterials, shared by its matching floor pieces. Other colors retain the existing StandardMaterial3D. Saved finish colors, structural records, floor supports, collision/navigation, stair holes and mesh counts do not change.

The shader works in world metres: boards are 0.30m wide and 1.66m long, with an alternating 0.83m end stagger and restrained 7/8mm seams. Adjacent boxes, finish-overlay subdivisions and the pieces around stair openings share one pattern instead of stretching independent texture coordinates. Small deterministic tone differences and soft wavy fibres distinguish the boards. Pixel-width filtering reduces distant seam aliasing and fades the fine grain. The pattern applies to upward faces; slab sides keep their base color. There are no texture downloads, reference-derived artwork, per-board mesh nodes or vertex displacement.

The separately authored starter timber, its board seams, bathroom tiles and foundation retain their original implementation. Pale stone and custom colors stay plain. This is a finish update, not a furnished upper-room or character-art redesign.

Run the isolated material, starter-finish and existing Live-floor controls:

```sh
TMPDIR=dist/test-work python3 tests/run_wood_floor.py
```

Use an absolute TMPDIR if running outside the project directory. The runner retains its copied project, logs, report and source/copy hashes. It removes only the development MCP configuration from the copy and isolates both XDG and JustLife save paths. The Live wrapper preloads the actual main scene before inherited test execution; it preserves every existing assertion and avoids the already identified test script-loading-order retention issue.

For an actual rendered comparison, supply the retained public two-floor save from `tests/run_public_twofloor.py`:

```sh
TMPDIR=dist/test-work python3 tests/run_wood_floor.py --capture-public-slot /absolute/path/to/the/public-twofloor-save.json
```

This optional mode opens a render window, so coordinate desktop use. It copies the original save unchanged, restores the paused upstairs checkpoint through the real loader, and captures Oak/Walnut at wide/close framing plus a stone control. Walnut/stone are explicit material-only fixture variants; actor roots, the reading instruction, wallet, clock and original slot bytes are checked. This is not another public-build or household-travel playthrough.

The material was rendered with Godot4.7.2 Forward+ on Linux. Other render backends/platforms and frame-time costs are not independently qualified by these captures. The shader uses ordinary spatial uniforms, world-position varyings and fragment derivatives supported by the engine; no renderer-specific coarse/fine derivative variants are used.

API references consulted: [spatial shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html), [shader language/source_color](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html), [ShaderMaterial parameters](https://docs.godotengine.org/en/4.7/classes/class_shadermaterial.html), [shader functions](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shader_functions.html).

## Independent review

The independent critic accepted the bounded material improvement at **8/10 visually and 8.5/10 for functional integration**, after inspecting all ten matched images and verifying the frozen input/evidence manifests. The regular stagger and uniform fine grain remain visible limits; still captures do not establish motion shimmer, platform coverage or frame-time performance. No blocker was found and the whole-game score is unchanged. The frozen review is `dist/test-work/justlife-sanitation-critic-j9mepnxc/evidence/WOOD_FLOOR_CRITIC_REVIEW.md`, SHA-256 `92edf87fdeb5889cf9d3ab37d43ce1fb10c7f8c6395432684599d699dd187421`.
