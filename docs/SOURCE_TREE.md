# Source tree

The repository contains the game and its authoring inputs. Rendered evidence, downloaded references and packaged executables stay local; they are not required to import or run a fresh checkout.

| Path | Purpose |
| --- | --- |
| `project.godot`, `scenes/`, `scripts/` | Godot project, scenes and game behavior. |
| `assets/` | Production models, fonts, audio, icon and JustLife splash. Import settings are retained. |
| `art/characters*.blend` | The four accepted age-family authoring sources. |
| `art/furniture.blend`, `art/furniture/`, `art/celebration/` | Original furniture, current hollow oven, child desk booster and birthday cake authoring files. |
| `art/meals/`, `art/recipes/` | Original editable supper props, generator provenance and export hashes; studio renders remain local. |
| `art/transport/`, `art/sanitation/` | Original shared car and cleaning mop Blender sources, with their generators in `tools/`. |
| `art/architecture/` | Original stairs, landing rails and roof-kit Blender sources with geometry contracts and generators. |
| `art/vegetation/` | Original field maple Blender source, portable generator instructions and import/export provenance. |
| `art/source/` | Immutable authoring inputs required to reproduce the accepted characters, plus compact provenance. |
| `art/experiments/` | Clearly marked editable studies and their generators; these are not promoted game assets. |
| `tools/` | Asset generation and Linux export scripts. |
| `tests/` | Simulation, model, controller and rendered playthrough checks. |
| `docs/` | Controls, APIs, reference findings and concise independent reviews. |
| `addons/` | Vendored Godot MCP development toolkit, retained with its notices. The release exporter excludes it. |
| `licenses/`, `CREDITS.md` | Font, engine and component notices plus original-art provenance. |

Local-only outputs include `.godot/`, Python caches, `.mcp.json`, Blender backup files, `dist/`, `art/screenshots/`, `art/iterations/`, generated art renders and reports, candidate `*_rig*`/`*_grip*` model exports, and `research/` browser downloads. `.gitignore` prevents these from returning to commits. Cleanup stops tracking existing copies; it does not delete local evidence or downloads.

Historical review documents may name local screenshots and temporary snapshots. Those paths identify the original review evidence, not files promised in a fresh checkout. The maintained tests can produce new evidence. The reference study retains source links and findings while third-party screenshot downloads remain separate from JustLife's original assets.

The `art/README.md` guide describes the production and experimental Blender inputs. Do not substitute an unreviewed candidate for a production model while tidying files. The game-quality goal and current known limitations remain documented in the main README and review reports.
