# Iteration 40 — splash texture startup warning

The JustLife splash keeps the same artwork and all colour pixels, but is stored as RGBA8 PNG so the tested Forward+ renderer can upload it directly. The former RGB8 asset produced `Image format RGB8 not supported by hardware, converting to RGBA8` at startup on the NVIDIA GeForce RTX 5090. This is an asset encoding fix, with no change to the splash setting, display duration, game scripts or model assets.

## Evidence

Three isolated minimal startups establish the source of the warning. The original image with the splash enabled reproduces it; disabling the splash is clean; the re-encoded image with the splash enabled is clean. The first and third use byte-identical project settings and scripts. Disabling the splash was a diagnostic control only.

Godot's `Image.convert(Image.FORMAT_RGBA8)` and `save_png` preserve all 1,573,352 RGB pixels and the 1672×941 dimensions. Every new alpha byte is 255. The conversion script verifies the complete decoded data and PNG reload; an independent Pillow decode confirms the same result. The asset grows from 1,815,424 to 2,007,483 bytes. [Godot documents PNG as the supported splash format](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-application-boot-splash-image).

The unchanged six-view Creator/Live capture on the previously integrated household-traffic and Bob-hem runtime now completes a clean import and a clean verbose Forward+ run: **59 assertions, zero failures, six images and four successful observed audio drains**. All six PNGs and the entire control report are byte-identical to the reviewed previous run. The two 1,135-file source maps differ only in the splash PNG; every runtime script matches commit `03f4c3e`. Source and executed-copy hashes remain unchanged during the run. Timings are receipts, not performance measurements.

The original warning-bearing capture remains failed and retained. This new result follows an actual asset correction; diagnostics were neither suppressed nor filtered out. It covers the same bounded Creator/Live views, not the pending stair/walk changes, the three-day household test or a new packaged release. No new overall quality rating follows.

## Asset provenance

Original PNG SHA-256: `debb7ddfe5e8364fd6fd6e8e11130ea3e22761283a31c982726455ff06d08b65`, retained in Git `03f4c3e858ad757c4ae0c7da1a0df544361f8f86`. Derived PNG: `d1e84a944319a6431b6368c98d15613ece23c826c1269aa8f4ecf81de4d9b25e`. Existing artwork-generation attribution is unchanged.

Encoded-file and metadata identity are not claimed: Godot's PNG writer omits the original `caBX` chunk and adds sRGB intent 0. The original file with its signed metadata remains retained; the derived file does not copy a stale signature. The private 45-pin evidence freeze has SHA-256 `ddd92324db0544faf38a4e676d8bc0c1c2a65e492db6206aa73ccfe76dd5da8c`, including the exact original, conversion script, new file, raw startup/render logs and read-only verification.
