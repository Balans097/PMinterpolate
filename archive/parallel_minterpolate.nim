## parallel_minterpolate.nim
## Parallelize video frame interpolation with FFmpeg.
## Rewritten from Python to Nim.
##
## Usage:
##   ./parallel_minterpolate <inputVideo> --split <N> [--outputDir <NAME>] [--fps <N>] [--shutdown]
##
## Requirements:
##   - FFmpeg in PATH
##   - opencv_utils or direct ffprobe for video info (uses ffprobe here — no OpenCV dependency)
##   - Windows only (generates .bat file)

import std/[os, osproc, parseopt, strformat, strutils, math]

# ─── Types ────────────────────────────────────────────────────────────────────

type
  Config = object
    inputVideo : string
    split      : int
    outputDir  : string
    fps        : int
    shutdown   : bool

# ─── Helpers ──────────────────────────────────────────────────────────────────

proc zeroPad(n, width: int): string =
  result = $n
  while result.len < width:
    result = "0" & result

proc secondsToHHMMSS(totalSecs: int): string =
  ## Format seconds as HH:MM:SS (suitable for ffmpeg -segment_time)
  let h = totalSecs div 3600
  let m = (totalSecs mod 3600) div 60
  let s = totalSecs mod 60
  result = fmt"{h:02d}:{m:02d}:{s:02d}"

proc getVideoDurationSeconds(videoPath: string): int =
  ## Use ffprobe to obtain the video duration in whole seconds.
  ## Falls back to 0 on error.
  let cmd = fmt"""ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "{videoPath}""""
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    stderr.writeLine "Error: ffprobe failed. Make sure FFmpeg/ffprobe is installed and in PATH."
    quit(1)
  let trimmed = output.strip()
  # duration is a float like "123.456"
  try:
    result = int(parseFloat(trimmed).round())
  except ValueError:
    stderr.writeLine fmt"Error: could not parse duration from ffprobe output: '{trimmed}'"
    quit(1)

# ─── Argument parsing ─────────────────────────────────────────────────────────

proc parseArgs(): Config =
  result = Config(
    split     : 0,
    outputDir : "output",
    fps       : 60,
    shutdown  : false
  )

  var positionalsDone = false

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdArgument:
      if not positionalsDone:
        result.inputVideo = p.key
        positionalsDone = true
      else:
        stderr.writeLine fmt"Unexpected positional argument: {p.key}"
        quit(1)
    of cmdLongOption, cmdShortOption:
      case p.key
      of "split":
        result.split = parseInt(p.val)
      of "o", "outputDir":
        result.outputDir = p.val
      of "fps":
        result.fps = parseInt(p.val)
      of "shutdown":
        result.shutdown = true
      of "h", "help":
        echo """
Usage: parallel_minterpolate <inputVideo> --split N [OPTIONS]

Positional arguments:
  inputVideo            path to an input MP4 video file

Options:
  --split N             number of tasks to generate equally (required)
  -o, --outputDir NAME  output directory name  [default: output]
  --fps N               target FPS             [default: 60]
  --shutdown            shutdown computer after tasks complete
  -h, --help            show this help message
"""
        quit(0)
      else:
        stderr.writeLine fmt"Unknown option: --{p.key}"
        quit(1)

  # Validate required arguments
  if result.inputVideo == "":
    stderr.writeLine "Error: inputVideo is required."
    quit(1)
  if result.split <= 0:
    stderr.writeLine "Error: --split N is required and must be > 0."
    quit(1)
  if not fileExists(result.inputVideo):
    stderr.writeLine fmt"Error: input file not found: {result.inputVideo}"
    quit(1)

# ─── Main ─────────────────────────────────────────────────────────────────────

proc main() =
  let cfg = parseArgs()

  # ── Probe video duration ──────────────────────────────────────────────────
  let videoSeconds  = getVideoDurationSeconds(cfg.inputVideo)
  let partsSeconds  = max(1, videoSeconds div cfg.split)
  let partsTime     = secondsToHHMMSS(partsSeconds)

  echo fmt"Input       : {cfg.inputVideo}"
  echo fmt"Duration    : {secondsToHHMMSS(videoSeconds)} ({videoSeconds}s)"
  echo fmt"Split into  : {cfg.split} parts (~{partsSeconds}s each / {partsTime})"
  echo fmt"Target FPS  : {cfg.fps}"
  echo fmt"Output dir  : {cfg.outputDir}"

  # ── Create output directory ───────────────────────────────────────────────
  if not dirExists(cfg.outputDir):
    createDir(cfg.outputDir)

  # Absolute path to input (used inside the batch file)
  let absInput = absolutePath(cfg.inputVideo)

  # ── Write list.txt for ffmpeg concat ─────────────────────────────────────
  let listPath = cfg.outputDir / "list.txt"
  var listFile = open(listPath, fmWrite)
  for i in 0 ..< cfg.split:
    listFile.writeLine(fmt"file 'output{zeroPad(i,3)}.{cfg.fps}fps.mp4'")
  listFile.close()

  # ── Write run.bat ─────────────────────────────────────────────────────────
  let batPath = cfg.outputDir / "run.bat"
  var bat = open(batPath, fmWrite)

  # Step 1 – split the source video into chunks
  bat.writeLine(
    fmt"""ffmpeg -i "{absInput}" -c copy -map 0 -segment_time {partsTime} """ &
    fmt"""-f segment -reset_timestamps 1 output%03d.mp4"""
  )
  bat.writeLine("")

  # Step 2 – launch all interpolation tasks in parallel, wait for all to finish
  bat.writeLine("(")
  for i in 0 ..< cfg.split:
    let inChunk  = fmt"output{zeroPad(i,3)}.mp4"
    let outChunk = fmt"output{zeroPad(i,3)}.{cfg.fps}fps.mp4"
    bat.writeLine(
      fmt"""  start "TASK {i+1}" ffmpeg -i {inChunk} -crf 10 """ &
      fmt"""-vf "minterpolate=fps={cfg.fps}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1" {outChunk}"""
    )
  bat.writeLine(") | pause")
  bat.writeLine("")

  # Step 3 – wait a moment, then concatenate all chunks
  bat.writeLine("timeout /t 3 /nobreak > nul")
  bat.writeLine(fmt"""ffmpeg -f concat -safe 0 -i list.txt -c copy final.mp4""")

  # Optional – shut down after completion
  if cfg.shutdown:
    bat.writeLine("timeout /t 3 /nobreak > nul")
    bat.writeLine("shutdown /s /f /t 0")

  bat.close()
  echo fmt"Batch file written: {batPath}"

  # ── Execute the batch file ────────────────────────────────────────────────
  let prevDir = getCurrentDir()
  setCurrentDir(cfg.outputDir)
  echo "Launching run.bat ..."
  discard startProcess("run.bat", options = {poUsePath})
  setCurrentDir(prevDir)

when isMainModule:
  main()
