# PMinterpolate

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language: Nim](https://img.shields.io/badge/language-Nim-yellow.svg)](https://nim-lang.org/)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![Author](https://img.shields.io/badge/author-Balans097-green.svg)](https://github.com/Balans097)

**Parallel Motion Interpolate** — a free, open-source CLI tool that splits a video into chunks, interpolates each chunk in parallel using FFmpeg's `minterpolate` filter, and merges the results into a single output file.

---

## Why PMinterpolate?

**SVP (SmoothVideo Project) went paid — even on Linux.** If you used it to enjoy silky-smooth playback and don't want to pay for a subscription just to watch your own video files, PMinterpolate is the answer. No DRM, no license keys, no cloud — just FFmpeg doing the work, fast.

### What does high frame rate actually feel like?

Most video is shot at 24 or 30 fps. Your eyes and brain are capable of perceiving motion far beyond that. Frame interpolation generates the in-between frames that the camera never captured:

- **60 fps** — the first threshold where motion stops feeling like "cinema" and starts feeling *real*. Sports, action scenes, and fast pans become dramatically clearer.
- **90 fps** — the sweet spot for animation and TV content. Characters move with a fluidity that feels almost physical.
- **120 fps** — detail that was previously smeared by motion blur becomes sharp and readable. Gaming footage, concerts, and nature documentaries come alive.

Once you watch a 120 fps render of something you've seen a hundred times at 24 fps, going back feels like watching through frosted glass.

---

## Features

- **Batch folder processing** — drop a folder of any size and walk away. PMinterpolate scans it automatically and processes every media file one by one, skipping any that already have an output.
- **True parallelism** — the video is split into N chunks and all chunks are interpolated simultaneously, one FFmpeg process per chunk. Processing time scales down linearly with the number of CPU cores.
- **Automatic CPU detection** — `--split` is optional. By default PMinterpolate uses every logical core available.
- **All streams preserved** — only the video is re-encoded. Audio tracks, subtitles, chapters, and attachments are copied from the source without modification.
- **Any target FPS** — 60, 90, 120, or anything else. You decide.
- **MKV and MP4** output containers.
- **Single-pass and two-pass** interpolation modes.
- **18 supported formats**: mkv, mp4, avi, mov, mpeg, mpg, wmv, flv, webm, ts, m2ts, mts, m4v, 3gp, ogv, vob, divx, xvid.
- **Single terminal window** — all output from all parallel processes appears in the same terminal where you launched the command. No popup windows.
- **Cross-platform** — Windows and Linux, compiled from a single source file.
- **Bilingual interface** — English and Russian (`--lang ru`).

---

## Quick Start

```bash
# Process all media files in the current folder, auto-detect CPU cores
PMinterpolate.exe

# Process a specific folder at 60 fps using 8 cores
PMinterpolate.exe "D:\Videos\Films" --fps 60 --split 8

# Two-pass mode for maximum quality
PMinterpolate.exe "D:\Videos" --fps 120 --passes 2 --lang ru
```

Output files land in the `output/` subfolder, named `<original>_60fps.mkv`.  
Already-converted files are skipped automatically on re-run.

---

## Requirements

- [FFmpeg](https://ffmpeg.org/download.html) in `PATH`
- Windows 7+ or Linux

No installation. No runtime. Just a single executable.

---

## Documentation

- 🇬🇧 [Documentation (English)](docs/Documentation.md)
- 🇷🇺 [Документация (Русский)](docs/Documentation-RU.md)

---

## License

Copyright (c) 2026 Balans097 — [MIT License](LICENSE)
