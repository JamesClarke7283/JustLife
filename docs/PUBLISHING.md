# Publishing JustLife

The [Publish to itch.io workflow](../.github/workflows/publish-itch.yml) builds a clean checkout and uploads these channels to [impulse20/justlife](https://impulse20.itch.io/justlife):

| Channel | Contents | Launch |
| --- | --- | --- |
| `linux-x86_64` | Linux x86_64 executable, notices and build manifest | `JustLife.x86_64` |
| `windows-x86_64` | Windows x86_64 executable, notices and manifest | `JustLife.exe` |
| `macos` | ZIP containing a universal Intel/Apple Silicon `.app` and notices | Extract ZIP, open `JustLife.app` |

The macOS app is ad-hoc signed using Godot's built-in signer. It is not Apple Developer ID signed or notarized. macOS may require approval in Privacy & Security after the first attempted launch. Windows builds are not Authenticode signed. CI checks headless startup on all three operating systems; these checks do not replace a graphical playthrough on each platform.

## Run a release

1. Open [GitHub Actions → Publish to itch.io](https://github.com/JamesClarke7283/JustLife/actions/workflows/publish-itch.yml).
2. Choose **Run workflow** and the branch or tag to build.
3. Optionally enter a display version, such as `0.1.0`. With no version, tags use their tag name and branch runs use `dev-<commit>`.
4. Leave **Publish all three builds to itch.io** checked to upload, or uncheck it to validate and download build artifacts without changing itch.io.

Pushing a tag beginning with `v`, such as `v0.1.0`, also builds and publishes that exact commit. Ordinary pushes to `main` do not publish automatically. Use distinct version labels so players can identify a release. Runs are serialized so simultaneous releases cannot overwrite each other's platform channels.

All three export jobs and native startup checks must pass before publishing starts. Downloads are verified with pinned SHA-256 hashes; GitHub actions are pinned to commit SHAs. The executables are smoke tested in isolated data directories; macOS also verifies the universal binary and app signature. Platform packages travel between jobs in tar archives to retain permissions, with checksums checked again before upload. Build artifacts remain available for 14 days; failure logs remain for 7 days. The macOS ZIP is passed directly to butler, which preserves the application bundle when creating the downloadable build.

Butler uploads the three channels sequentially. itch.io does not provide an atomic release across channels: an interrupted publish can leave some channels updated. Rerun the failed publish job to complete that release. A successful upload may take a few minutes to finish processing on itch.io; the workflow prints the channel status after the uploads.

## Secret and tool maintenance

Set the repository's **Settings → Secrets and variables → Actions → Repository secrets** entry named `BUTLER_API_KEY` to an itch.io API key with permission to publish this project. This secret is available only in the publish step. Never put the value in this repository, workflow inputs, a command-line argument, or build files.

To rotate the key, replace that same repository secret with the new key and revoke the old key at itch.io. For the GitHub CLI, run the following and paste the new key at its prompt:

```sh
gh secret set BUTLER_API_KEY --repo JamesClarke7283/JustLife
```

`tools/ci_install.py` pins Godot **4.7.2** and butler **15.31.0**. When updating Godot, update the version and both archive checksums together, using the official release assets, then run a build-only workflow first. The template version must match the editor. When updating butler, update its version and checksum together. The installer is intended for Ubuntu x86_64 runners and requires Python 3.9 or later.

## Local exports

Install Godot 4.7.2 and its matching export templates, then choose a fresh output directory:

```sh
python3 tools/export_game.py --platform linux --output dist/JustLife-linux
python3 tools/export_game.py --platform windows --output dist/JustLife-windows
python3 tools/export_game.py --platform macos --output dist/JustLife-macos
```

Use `--godot /path/to/godot` and `--templates /path/to/4.7.2.stable` to select explicit tools. `--work-dir /path/to/build-work` controls where the snapshot and diagnostic logs are retained. The original `python3 tools/export_linux.py` command still builds to `dist/JustLife/JustLife.x86_64` by default.

The helper copies runtime assets, scripts, scenes and notices to a private snapshot, removes editor MCP/autoload services, imports from source, and exports the chosen preset. It keeps development artwork, tests, research screenshots and local saves out of the release. Output folders are refreshed after a successful build; unrelated files already in a reused output folder are retained, so use fresh directories for publishing. macOS requires `macos.zip` in the template directory; its snapshot enables ASTC texture imports for Apple Silicon. Standard Windows templates use Windows' system libraries. Custom templates that include optional Agility SDK or PIX DLLs must keep those files beside the executable template so Godot can copy them into the package.

With butler installed and `BUTLER_API_KEY` supplied through your environment, the equivalent uploads are:

```sh
butler push dist/JustLife-linux impulse20/justlife:linux-x86_64 --userversion 0.1.0 --fix-permissions
butler push dist/JustLife-windows impulse20/justlife:windows-x86_64 --userversion 0.1.0
butler push dist/JustLife-macos/JustLife.zip impulse20/justlife:macos --userversion 0.1.0 --fix-permissions
butler status impulse20/justlife
```

See the official [butler installation](https://itch.io/docs/butler/installing.html), [authentication](https://itch.io/docs/butler/login.html) and [upload documentation](https://itch.io/docs/butler/pushing.html).
