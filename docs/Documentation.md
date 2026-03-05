# PMinterpolate

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language: Nim](https://img.shields.io/badge/language-Nim-yellow.svg)](https://nim-lang.org/)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![i18n](https://img.shields.io/badge/i18n-EN%20%7C%20RU-blue.svg)]()
[![Author](https://img.shields.io/badge/author-Balans097-green.svg)](https://github.com/Balans097)

> **Parallel Motion Interpolate** — a command-line tool for accelerating video frame interpolation using FFmpeg.  
> Cross-platform: **Windows** and **Linux** (Fedora, Ubuntu, Arch…).  
> Bilingual interface: **English** and **Russian** (`--lang en|ru`).

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Building](#building)
- [Usage](#usage)
- [Arguments and Options](#arguments-and-options)
- [Examples](#examples)
- [Output File Structure](#output-file-structure)
- [Code Architecture](#code-architecture)
  - [Platform Constants](#platform-constants)
  - [i18n Localization](#i18n-localization)
  - [Data Types](#data-types)
  - [Procedures](#procedures)
- [FFmpeg Parameters](#ffmpeg-parameters)
  - [minterpolate Filter](#minterpolate-filter)
  - [Stream Mapping](#stream-mapping)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

**PMinterpolate** (Parallel Motion Interpolate) is a command-line tool that speeds up frame interpolation for long video files. FFmpeg's `minterpolate` filter is single-threaded, making processing of long videos very slow. PMinterpolate automatically splits the video into segments, processes them **simultaneously** in multiple FFmpeg processes, and then concatenates the result.

Everything runs **natively from a single Nim process** — no helper scripts, no extra windows. All FFmpeg output is displayed directly in the terminal where the command was launched.

**Key features:**

- Automatic CPU core detection — `--split` is optional
- Batch processing: all media files in the specified folder are processed sequentially
- 18 supported formats: mkv, mp4, avi, mov, mpeg, mpg, wmv, flv, webm, ts, m2ts, mts, m4v, 3gp, ogv, vob, divx, xvid
- Only the **video stream is re-encoded** — audio, subtitles, chapters and all other tracks are copied without modification
- Already-processed files are automatically skipped on re-run
- Output files are named `<original_name>_<fps>fps.<container>` (e.g. `film_60fps.mkv`)
- Output container: **MKV** (default) or **MP4**
- Single-pass and **two-pass** interpolation

---

## How It Works

```
Folder with media files
        │
        ▼
┌───────────────────────────────┐
│  Scan (no recursion)          │  collectMediaFiles() → [file1, file2, …]
└───────────────────────────────┘
        │
        ▼  (for each file, sequentially)
┌──────────────┐
│  1. Split    │  ffmpeg -f segment  →  tmp/output000.mkv … tmp/outputN.mkv
└──────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│  2. Parallel interpolation (N processes at once)                    │
│                                                                     │
│  Single-pass mode (--passes 1):                                     │
│    chunk 000: output000.mkv → 000.60fps.mkv  ┐                      │
│    chunk 001: output001.mkv → 001.60fps.mkv  ├─ in parallel         │
│    chunk 00N: output00N.mkv → 00N.60fps.mkv  ┘                      │
│                                                                     │
│  Two-pass mode (--passes 2):                                        │
│    Pass 1 — motion analysis → /dev/null + .log  (all chunks parallel)│
│    Pass 2 — interpolation   → .60fps.mkv        (all chunks parallel)│
└─────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────┐
│  3. Concat   │  ffmpeg -f concat  →  output/film_60fps.mkv
└──────────────┘
        │
        ▼
┌──────────────┐
│  4. Cleanup  │  removeDir(tmp/)
└──────────────┘
        │
        └─── next file…
```

**Step 1 — Split.** The source file is cut into `N` equal segments without re-encoding (`-c copy -map 0`). All streams are preserved in each segment. Segments are placed in `output/tmp/`.

**Step 2 — Interpolation.** A separate FFmpeg process is launched for each segment via `startProcess` with the `poParentStreams` flag — output from all processes goes to the same terminal. The video stream is re-encoded with the `minterpolate` filter; audio, subtitles and other streams are copied from the same segment without modification.

**Step 3 — Concatenation.** Interpolated segments are merged into the final file without re-encoding. All streams are copied via `-map 0 -c copy`.

**Step 4 — Cleanup.** The `tmp/` directory with all intermediate files is deleted automatically. Only the final output file remains in `output/`.

---

## Requirements

| Component | Version | Notes |
|---|---|---|
| **FFmpeg + ffprobe** | any recent | Must be available in `PATH` |
| **Nim** | 2.0+ | Only needed to build the binary |
| **Windows** | 7 / 10 / 11 | — |
| **Linux** | any distribution | — |

### Installing FFmpeg

**Fedora** (use RPM Fusion due to patent restrictions):
```bash
sudo dnf install \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfull/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install ffmpeg
```

**Ubuntu / Debian:**
```bash
sudo apt install ffmpeg
```

**Windows:** download from [ffmpeg.org](https://ffmpeg.org/download.html) and add the `bin` folder to your `PATH`.

Verify:
```bash
ffmpeg -version
ffprobe -version
```

---

## Building

```bash
git clone https://github.com/Balans097/PMinterpolate.git
cd PMinterpolate
```

```bash
# Linux and Windows — same command
nim c -d:release PMinterpolate.nim
```

The target platform is determined **at compile time** via `defined(windows)` — a single source file for all platforms.

Optional optimization flags:

```bash
nim c -d:release --opt:speed -d:strip PMinterpolate.nim
```

| Flag | Description |
|---|---|
| `-d:release` | Enable optimizations, disable asserts |
| `--opt:speed` | Maximum execution speed |
| `-d:strip` | Strip debug symbols |

---

## Usage

```
./PMinterpolate [inputDir] [OPTIONS]
PMinterpolate.exe [inputDir] [OPTIONS]
```

If `inputDir` is omitted, the executable's directory is used.  
If `--split` is omitted, the number of logical CPU cores is detected automatically.

---

## Arguments and Options

### Positional Argument

| Argument | Description |
|---|---|
| `inputDir` | Path to the folder containing media files. **Optional.** Defaults to the directory containing `PMinterpolate.exe`. No recursive search. |

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--split N` | `int` | CPU core count | Number of parallel chunks. If omitted, detected automatically via `countProcessors()`. |
| `-o`, `--outputDir NAME` | `string` | `output` | Output directory. Created automatically if it doesn't exist. |
| `--fps N` | `int` | `60` | Target frame rate after interpolation. |
| `--container FORMAT` | `mp4\|mkv` | `mkv` | Output container. MKV is recommended — it supports arbitrary stream types more reliably. |
| `--passes N` | `1\|2` | `1` | Number of encoding passes. Two-pass mode produces better interpolation quality through motion pre-analysis, but takes twice as long. |
| `--lang LANG` | `en\|ru` | `en` | Interface language. |
| `--shutdown` | flag | off | Shut down the computer when done. Linux: `sudo systemctl poweroff`. Windows: `shutdown /s /f /t 3`. |
| `-h`, `--help` | flag | — | Show help in the selected language and exit. |

Both option forms are equivalent:
```bash
--split 4
--split=4
```

---

## Examples

### Fully automatic run

Run from the folder containing video files — no arguments needed:

```bash
# Linux: process all media files next to the exe, split = CPU core count
./PMinterpolate

# Windows
PMinterpolate.exe
```

### Specify a folder explicitly

```bash
# Linux
./PMinterpolate /mnt/videos/films

# Windows
PMinterpolate.exe "D:\Videos\Films"
```

### English interface (default)

```
PMinterpolate.exe "D:\Videos"
```

Output:
```
Scan dir    : D:\Videos
Found       : 3 file(s)
CPU cores   : 16
Chunks      : 16 (auto)
Target FPS  : 60
Container   : mkv
Passes      : 1
Output dir  : output

────────────────────────────────────────────────────────────
[1/3] File : film_A.mkv
────────────────────────────────────────────────────────────
Input       : D:\Videos\film_A.mkv
Duration    : 01:32:14 (5534s)
Chunks      : 16 (345s / 00:05:45)
[1/4] Splitting into chunks...
[2/4] Interpolation (parallel)...
  chunk 000 started (PID 4412)
  chunk 001 started (PID 7820)
  ...
  waiting for all chunks to finish...
[3/4] Concatenating chunks...
[4/4] Cleaning up...
Done! Output: output\film_A_60fps.mkv

────────────────────────────────────────────────────────────
[2/3] File : film_B.mp4
────────────────────────────────────────────────────────────
...

════════════════════════════════════════════════════════════
Processed: 3  Skipped: 0
════════════════════════════════════════════════════════════
```

### Limit the number of cores

```bash
# Use only 4 cores instead of all available
PMinterpolate.exe --split 4
```

### Maximum quality, overnight processing

```bash
PMinterpolate.exe "D:\Videos" --fps 60 --passes 2 --shutdown
```

### Help

```bash
./PMinterpolate --help
./PMinterpolate --lang ru --help
```

---

## Output File Structure

During processing of a single file with `--split 4 --fps 60 --container mkv`:

```
output/
├── tmp/
│   ├── list.txt                  # Segment list for ffmpeg concat
│   │
│   ├── output000.mkv             # Source segment 1 (all streams)
│   ├── output001.mkv             # Source segment 2
│   ├── output002.mkv             # Source segment 3
│   ├── output003.mkv             # Source segment 4
│   │
│   ├── output000-0.log           # Pass 1 stats (only with --passes 2)
│   ├── ...
│   │
│   ├── 000.60fps.mkv             # Interpolated segment 1
│   ├── 001.60fps.mkv             # Interpolated segment 2
│   ├── 002.60fps.mkv             # Interpolated segment 3
│   └── 003.60fps.mkv             # Interpolated segment 4
│
└── film_60fps.mkv                # ← Final output
```

After completion `tmp/` is deleted automatically. Only the final file remains in `output/`. When processing multiple files in batch mode, `tmp/` is recreated for each file.

---

## Code Architecture

### Platform Constants

```nim
const isWindows = defined(windows)
const devNull   = when isWindows: "NUL" else: "/dev/null"
```

The platform is determined **at compile time**. `devNull` is used in pass 1 of two-pass mode as the target for `-f null`.

---

### i18n Localization

All user-facing strings are stored in two constant arrays `EN` and `RU`, indexed by the `MsgId` enum.

**`MsgId`** — identifiers for all strings:

| Group | Identifiers |
|---|---|
| Errors | `msgErrFfprobe`, `msgErrFfprobeOutput`, `msgErrUnknownOpt`, `msgErrUnexpectedArg`, `msgErrBadContainer`, `msgErrBadPasses`, `msgErrSplitPositive`, `msgErrNoMedia`, `msgErrDirNotFound`, `msgErrTaskFailed`, `msgErrAbortFailed` |
| Output labels | `msgLabelInput`, `msgLabelDuration`, `msgLabelSplit`, `msgLabelCpus`, `msgLabelFps`, `msgLabelContainer`, `msgLabelPasses`, `msgLabelOutputDir`, `msgLabelScanDir`, `msgLabelFound`, `msgLabelFileN` |
| Steps | `msgStep1`, `msgStep2Pass1`, `msgStep2Pass2`, `msgStep2Single`, `msgStep3`, `msgStep4` |
| Progress | `msgTaskStarted`, `msgWaiting`, `msgDone`, `msgSkipExists` |
| Help | `msgHelp` |

**`T(id)`**, **`T(id, a)`**, **`T(id, a, b)`** — string accessor functions. Overloads with parameters replace `$1` and `$2` markers:

```nim
T(msgErrDirNotFound, path)             # → "Error: directory not found: /path"
T(msgErrTaskFailed, "002", "1")        # → "Error: chunk 002 failed (exit code 1)."
T(msgLabelFileN, "2", "5")             # → "[2/5] File"
```

**Early `--lang` detection.** The flag is processed by a direct scan of `commandLineParams()` before the main parser runs — this ensures even parser error messages are printed in the correct language.

---

### Data Types

#### `Config`

```nim
type
  Config = object
    inputDir   : string   # Media folder          [default: getAppDir()]
    split      : int      # Chunk count           [default: 0 → auto]
    outputDir  : string   # Output directory      [default: "output"]
    fps        : int      # Target FPS            [default: 60]
    container  : string   # "mkv" or "mp4"       [default: "mkv"]
    passes     : int      # 1 or 2               [default: 1]
    shutdown   : bool     # Shut down after completion
```

`split = 0` in `Config` means "not set by user" and is replaced by `detectCpuCount()` after argument parsing completes.

---

### Procedures

#### `detectCpuCount(): int`

Returns the number of logical processors via the standard `countProcessors()` from `std/osproc`. Falls back to `1` on failure.

```nim
proc detectCpuCount(): int =
  result = countProcessors()
  if result <= 0: result = 1
```

`countProcessors()` uses OS-level calls:
- **Windows:** `GetSystemInfo` → `dwNumberOfProcessors`
- **Linux:** parses `/proc/cpuinfo`

#### `collectMediaFiles(dir: string): seq[string]`

Iterates over files in `dir` via `walkDir` (no recursion), filters by extension from the `mediaExts` constant, and returns a sorted list of paths as returned by `walkDir`. The path is resolved to an absolute path later in `processFile` via `absolutePath()`.

#### `zeroPad(n, width: int): string`

```nim
zeroPad(3, 3)   # → "003"
zeroPad(12, 3)  # → "012"
```

#### `secondsToHHMMSS(s: int): string`

Converts seconds to `HH:MM:SS` format for the `-segment_time` FFmpeg parameter.

#### `getVideoDurationSeconds(videoPath: string): int`

Calls `ffprobe` and returns the video duration in whole seconds.

#### `minterpolateFilter(fps: int): string`

Returns the `minterpolate` filter parameter string:

```
minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1
```

#### `interpArgs(inChunk, outFile, ext: string; fps, passNum: int): seq[string]`

Builds the argv for one FFmpeg process in two-pass mode. Returns `seq[string]` for direct use with `startProcess` — no shell, no quoting issues.

Pass 1: video goes to `devNull`, stats written to `<stem>.log`.  
Pass 2: final file with full stream mapping.

#### `singlePassArgs(inChunk, outFile: string; fps: int): seq[string]`

Builds argv for single-pass mode. Video is re-encoded; all other streams are copied.

#### `runSeq(args: seq[string])`

Runs a single FFmpeg process synchronously with `poParentStreams` (output goes to the current terminal). Aborts the program on non-zero exit code. Used for splitting and concatenation.

#### `runParallel(tasks: seq[seq[string]])`

Launches all tasks simultaneously via `startProcess`, prints the PID of each. Waits for every process via `waitForExit`. If any process exits with an error — prints diagnostics and aborts.

#### `processFile(inputVideo: string; cfg: Config)`

Full pipeline for a single file: split → interpolation → concat → cleanup.

#### `parseArgs(): Config`

Parses arguments via `std/parseopt` with `mode = LaxMode`. If `--split` is not provided, `result.split` remains `0` and is replaced by `detectCpuCount()` after parsing.

#### `main()`

1. Parses arguments
2. Scans `inputDir` for media files
3. Prints a summary (including CPU core count and effective `--split` value)
4. Processes each file sequentially via `processFile`; files with an existing output are skipped
5. Prints final statistics
6. Initiates shutdown if `--shutdown` was specified

---

## FFmpeg Parameters

### minterpolate Filter

| Parameter | Value | Description |
|---|---|---|
| `fps` | `N` (from `--fps`) | Target frame rate |
| `mi_mode` | `mci` | Motion Compensated Interpolation |
| `mc_mode` | `aobmc` | Adaptive Overlapped Block Motion Compensation |
| `me_mode` | `bidir` | Bidirectional motion estimation |
| `vsbmc` | `1` | Variable-size block motion compensation |

### Stream Mapping

Each interpolation process opens the same segment **twice** as two separate FFmpeg inputs:

```
ffmpeg -i output/tmp/output000.mkv   ← input [0]: source of video stream
       -i output/tmp/output000.mkv   ← input [1]: source of all other streams
       -map 0:v:0                     ← re-encode only the first video stream
       -map 1:a?                      ← all audio tracks — unchanged
       -map 1:s?                      ← subtitles — unchanged
       -map 1:t?                      ← chapters and attachments — unchanged
       -map 1:d?                      ← data streams — unchanged
       -c:a copy -c:s copy -c:t copy -c:d copy
```

The `?` modifier makes each `-map` optional — if the file has no subtitles or chapters, FFmpeg will not raise an error. During concatenation (step 3), `-map 0 -c copy` is used to ensure **all** streams from all segments are included in the final file.

---

## Limitations

- **`--shutdown` on Linux requires sudo.** The command `sudo systemctl poweroff` will prompt for a password unless `NOPASSWD` is configured in `/etc/sudoers`.
- **CPU load.** By default all logical cores are used. Limit if needed via `--split N`.
- **Disk space.** Temporarily requires ~3× the size of the source file. With `--passes 2`, small `.log` statistics files are also created.
- **MP4 and complex streams.** The MP4 container has limitations on subtitle and attachment types. If the source file contains non-standard streams, use `--container mkv`.
- **Only `en` and `ru` languages.** Adding a new language requires a new `Lang` enum value, a new string array modelled after `EN`/`RU`, and a new branch in `T()`.

---

## Troubleshooting

### `ffprobe failed` on startup

```bash
which ffprobe && ffprobe -version   # Linux
where ffprobe                       # Windows CMD
```

### A chunk failed

The program prints the chunk number and FFmpeg exit code. To diagnose, run the failing command manually — commands follow the pattern described in [Stream Mapping](#stream-mapping).

### Stuttering at segment boundaries in the output

Try reducing `--split` to produce longer segments.

### CPU load too high

```bash
# Use only half the cores
PMinterpolate.exe --split 8
```

### Garbled characters in Windows CMD

```cmd
chcp 65001
```

Or change the console font to Consolas or Lucida Console via the window properties.

---

## License

Distributed under the MIT License.

```
MIT License

Copyright (c) 2026 Balans097

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
```
