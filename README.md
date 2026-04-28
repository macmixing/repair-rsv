# repair-rsv

Self-contained Sony `.RSV` repair package.

This folder contains:

- `bin/untrunc-rsv`: working patched recovery binary
- `scripts/recover-rsv.sh`: generic runner for donor clip + broken `.RSV`
- `scripts/build-from-source.sh`: rebuilds the binary from the bundled source
- `source/untrunc-rsv`: full patched source tree
- `patches/0001-measure-audio-chunk-from-rsv.patch`: the local code change that made the test recovery decode cleanly

## Why The Patch Exists

The upstream RSV branch was close, but it derives audio chunk size from donor timing math. On some recordings that can be slightly off and produce a rebuilt MP4 that parses but does not decode cleanly.

The local patch changes RSV recovery to:

- inspect the first GOP directly in the `.RSV`
- measure the actual audio payload size from the file itself
- prefer that measured value over the derived estimate

This makes the recovery less dependent on donor timing assumptions.

## Donor Guidance

Use a donor clip from the same camera and recording mode when possible.

## Quick Use

Run the bundled binary directly:

```zsh
./bin/untrunc-rsv -rsv "/path/to/donor.mp4" "/path/to/broken.RSV"
```

Or use the wrapper:

```zsh
./scripts/recover-rsv.sh "/path/to/donor.mp4" "/path/to/broken.RSV"
```

The repaired file will be written next to the broken `.RSV` with the suffix `_fixed-rsv.MP4`.

## Rebuild From Source

This build expects Homebrew `ffmpeg` and `pkgconf`.

If needed:

```zsh
brew install ffmpeg pkgconf
./scripts/build-from-source.sh
```

That rebuild script compiles `source/untrunc-rsv` and refreshes `bin/untrunc-rsv`.

## Source Of Truth

If you want to review or commit the actual code change, the important file is:

- `source/untrunc-rsv/src/mp4.cpp`

The bundled patch file documents the exact diff separately.
