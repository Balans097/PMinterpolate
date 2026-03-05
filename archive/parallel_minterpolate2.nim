## parallel_minterpolate.nim
## Parallelize video frame interpolation with FFmpeg.
## Cross-platform: Windows and Linux.
## Bilingual UI: English / Russian  (--lang en|ru)
##
## Usage:
##   ./parallel_minterpolate <inputVideo> --split <N> [OPTIONS]
##
## Requirements:
##   - FFmpeg + ffprobe in PATH
##   - Nim 1.6+  (build only)

import std/[os, osproc, parseopt, strformat, strutils, math, sequtils]

# ─── Platform ─────────────────────────────────────────────────────────────────

const isWindows = defined(windows)
const devNull   = when isWindows: "NUL" else: "/dev/null"

# ─── i18n ─────────────────────────────────────────────────────────────────────

type Lang = enum langEn, langRu

type MsgId = enum
  msgErrFfprobe
  msgErrFfprobeOutput
  msgErrUnknownOpt
  msgErrUnexpectedArg
  msgErrNoInput
  msgErrSplitPositive
  msgErrFileNotFound
  msgErrBadContainer
  msgErrBadPasses
  msgErrTaskFailed
  msgErrAbortFailed
  msgLabelInput
  msgLabelDuration
  msgLabelSplit
  msgLabelFps
  msgLabelContainer
  msgLabelPasses
  msgLabelOutputDir
  msgStep1
  msgStep2Pass1
  msgStep2Pass2
  msgStep2Single
  msgTaskStarted
  msgWaiting
  msgStep3
  msgStep4
  msgDone
  msgHelp

const EN: array[MsgId, string] = [
  "Error: ffprobe failed. Is FFmpeg installed and in PATH?",
  "Error: unexpected ffprobe output: '$1'",
  "Error: unknown option: --$1",
  "Error: unexpected positional argument: $1",
  "Error: inputVideo is required.",
  "Error: --split must be a positive integer.",
  "Error: file not found: $1",
  "Error: --container must be 'mp4' or 'mkv'.",
  "Error: --passes must be 1 or 2.",
  "Error: chunk $1 failed (exit code $2).",
  "Aborting: one or more chunks failed.",
  "Input      ",
  "Duration   ",
  "Split into ",
  "Target FPS ",
  "Container  ",
  "Passes     ",
  "Output dir ",
  "[1/4] Splitting into chunks...",
  "[2/4] Pass 1/2 - motion analysis (parallel)...",
  "[2/4] Pass 2/2 - interpolation (parallel)...",
  "[2/4] Interpolation (parallel)...",
  "  chunk $1 started (PID $2)",
  "  waiting for all chunks to finish...",
  "[3/4] Concatenating chunks...",
  "[4/4] Cleaning up...",
  "Done! Output: $1",
  """
Usage: parallel_minterpolate <inputVideo> --split N [OPTIONS]

Arguments:
  inputVideo              path to input video file

Options:
  --split N               number of parallel chunks (required)
  -o, --outputDir NAME    output directory          [default: output]
  --fps N                 target FPS                [default: 60]
  --container FORMAT      output container: mp4|mkv [default: mkv]
  --passes N              encoding passes: 1|2      [default: 1]
  --lang LANG             interface language: en|ru [default: en]
  --shutdown              shut down when done
  -h, --help              show this help
""",
]

const RU: array[MsgId, string] = [
  "Ошибка: ffprobe завершился с ошибкой. Установлен ли FFmpeg и добавлен ли он в PATH?",
  "Ошибка: неожиданный вывод ffprobe: '$1'",
  "Ошибка: неизвестный параметр: --$1",
  "Ошибка: лишний позиционный аргумент: $1",
  "Ошибка: укажите входной видеофайл.",
  "Ошибка: --split должен быть положительным целым числом.",
  "Ошибка: файл не найден: $1",
  "Ошибка: --container должен быть 'mp4' или 'mkv'.",
  "Ошибка: --passes должен быть 1 или 2.",
  "Ошибка: фрагмент $1 завершился с кодом $2.",
  "Прерывание: один или несколько фрагментов завершились с ошибкой.",
  "Файл        ",
  "Длительн.  ",
  "Разбить на  ",
  "Целевой FPS ",
  "Контейнер   ",
  "Проходов    ",
  "Папка вывода",
  "[1/4] Разбивка на фрагменты...",
  "[2/4] Проход 1/2 - анализ движения (параллельно)...",
  "[2/4] Проход 2/2 - интерполяция (параллельно)...",
  "[2/4] Интерполяция (параллельно)...",
  "  фрагмент $1 запущен (PID $2)",
  "  ожидание завершения всех фрагментов...",
  "[3/4] Склейка фрагментов...",
  "[4/4] Удаление временных файлов...",
  "Готово! Результат: $1",
  """
Использование: parallel_minterpolate <видеофайл> --split N [ПАРАМЕТРЫ]

Аргументы:
  видеофайл               путь к входному видеофайлу

Параметры:
  --split N               количество параллельных фрагментов (обязателен)
  -o, --outputDir ИМЯ     папка вывода               [по умолчанию: output]
  --fps N                 целевой FPS                [по умолчанию: 60]
  --container ФОРМАТ      контейнер: mp4|mkv         [по умолчанию: mkv]
  --passes N              количество проходов: 1|2   [по умолчанию: 1]
  --lang ЯЗЫК             язык интерфейса: en|ru     [по умолчанию: en]
  --shutdown              выключить компьютер по завершении
  -h, --help              показать эту справку
""",
]

var gLang = langEn

proc T(id: MsgId): string =
  case gLang
  of langEn: EN[id]
  of langRu: RU[id]

proc T(id: MsgId; a: string): string    = T(id).replace("$1", a)
proc T(id: MsgId; a, b: string): string = T(id).replace("$1", a).replace("$2", b)

# ─── Types ────────────────────────────────────────────────────────────────────

type
  Config = object
    inputVideo : string
    split      : int
    outputDir  : string
    fps        : int
    container  : string
    passes     : int
    shutdown   : bool

# ─── Helpers ──────────────────────────────────────────────────────────────────

proc zeroPad(n, width: int): string =
  result = $n
  while result.len < width: result = "0" & result

proc secondsToHHMMSS(s: int): string =
  fmt"{s div 3600:02d}:{(s mod 3600) div 60:02d}:{s mod 60:02d}"

proc getVideoDurationSeconds(videoPath: string): int =
  let cmd = "ffprobe -v error -show_entries format=duration " &
            "-of default=noprint_wrappers=1:nokey=1 \"" & videoPath & "\""
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    stderr.writeLine T(msgErrFfprobe)
    quit(1)
  let trimmed = output.strip()
  try:
    result = int(parseFloat(trimmed).round())
  except ValueError:
    stderr.writeLine T(msgErrFfprobeOutput, trimmed)
    quit(1)

# ─── FFmpeg argv builders ─────────────────────────────────────────────────────
# Return seq[string] (argv) for startProcess — no shell, no quoting issues.

proc minterpolateFilter(fps: int): string =
  "minterpolate=fps=" & $fps & ":mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"

proc interpArgs(inChunk, outFile, ext: string; fps, passNum: int): seq[string] =
  ## 2-pass: passNum=1 writes stats to devNull, passNum=2 encodes output.
  let vf   = minterpolateFilter(fps)
  let stem = splitFile(inChunk).name

  result = @["ffmpeg", "-y",
             "-i", inChunk,
             "-i", inChunk,
             "-map", "0:v:0"]

  if passNum == 1:
    result &= @["-vf", vf, "-crf", "10",
                "-passlogfile", stem,
                "-pass", "1", "-an", "-f", "null", devNull]
  else:
    result &= @["-vf", vf, "-crf", "10",
                "-passlogfile", stem,
                "-pass", "2",
                "-map", "1:a?", "-map", "1:s?", "-map", "1:t?", "-map", "1:d?",
                "-c:a", "copy", "-c:s", "copy", "-c:t", "copy", "-c:d", "copy",
                outFile]

proc singlePassArgs(inChunk, outFile: string; fps: int): seq[string] =
  let vf = minterpolateFilter(fps)
  @["ffmpeg", "-y",
    "-i", inChunk,
    "-i", inChunk,
    "-map", "0:v:0",
    "-map", "1:a?", "-map", "1:s?", "-map", "1:t?", "-map", "1:d?",
    "-vf", vf, "-crf", "10",
    "-c:a", "copy", "-c:s", "copy", "-c:t", "copy", "-c:d", "copy",
    outFile]

# ─── Process helpers ──────────────────────────────────────────────────────────

proc runSeq(args: seq[string]) =
  ## Run one ffmpeg command, inherit terminal output, abort on failure.
  let p = startProcess(args[0], args = args[1..^1],
                       options = {poUsePath, poParentStreams})
  let rc = p.waitForExit()
  p.close()
  if rc != 0:
    stderr.writeLine "ffmpeg exited with code " & $rc
    quit(rc)

proc runParallel(tasks: seq[seq[string]]) =
  ## Launch all tasks at once, all printing to the same terminal.
  ## Wait for every task; collect failures and abort if any.
  var procs: seq[Process]

  for i, args in tasks:
    let p = startProcess(args[0], args = args[1..^1],
                         options = {poUsePath, poParentStreams})
    echo T(msgTaskStarted, zeroPad(i, 3), $p.processID())
    procs.add(p)

  echo T(msgWaiting)

  var anyFailed = false
  for i, p in procs:
    let rc = p.waitForExit()
    p.close()
    if rc != 0:
      stderr.writeLine T(msgErrTaskFailed, zeroPad(i, 3), $rc)
      anyFailed = true

  if anyFailed:
    stderr.writeLine T(msgErrAbortFailed)
    quit(1)

# ─── Argument parsing ─────────────────────────────────────────────────────────

proc parseArgs(): Config =
  result = Config(split: 0, outputDir: "output", fps: 60,
                  container: "mkv", passes: 1, shutdown: false)

  let rawArgs = commandLineParams()

  # Early pass: detect --lang before any error messages are printed
  for i, arg in rawArgs:
    if arg.startsWith("--lang="):
      if arg[7..^1].toLowerAscii() == "ru": gLang = langRu
    elif arg == "--lang" and i + 1 < rawArgs.len:
      if rawArgs[i+1].toLowerAscii() == "ru": gLang = langRu

  var positionalsDone = false
  var p = initOptParser(rawArgs, shortNoVal = {},
                        longNoVal = @["shutdown", "help", "h"],
                        mode = LaxMode)
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdArgument:
      if not positionalsDone:
        result.inputVideo = p.key
        positionalsDone = true
      else:
        stderr.writeLine T(msgErrUnexpectedArg, p.key); quit(1)
    of cmdLongOption, cmdShortOption:
      case p.key
      of "split":          result.split     = parseInt(p.val)
      of "o", "outputDir": result.outputDir = p.val
      of "fps":            result.fps       = parseInt(p.val)
      of "container":
        let v = p.val.toLowerAscii()
        if v notin ["mp4", "mkv"]:
          stderr.writeLine T(msgErrBadContainer); quit(1)
        result.container = v
      of "passes":
        let v = parseInt(p.val)
        if v notin [1, 2]:
          stderr.writeLine T(msgErrBadPasses); quit(1)
        result.passes = v
      of "lang":
        gLang = if p.val.toLowerAscii() == "ru": langRu else: langEn
      of "shutdown": result.shutdown = true
      of "h", "help": echo T(msgHelp); quit(0)
      else: stderr.writeLine T(msgErrUnknownOpt, p.key); quit(1)

  if result.inputVideo == "":
    stderr.writeLine T(msgErrNoInput); quit(1)
  if result.split <= 0:
    stderr.writeLine T(msgErrSplitPositive); quit(1)
  if not fileExists(result.inputVideo):
    stderr.writeLine T(msgErrFileNotFound, result.inputVideo); quit(1)

# ─── Main ─────────────────────────────────────────────────────────────────────

proc main() =
  let cfg = parseArgs()

  let videoSeconds = getVideoDurationSeconds(cfg.inputVideo)
  let partsSeconds = max(1, videoSeconds div cfg.split)
  let partsTime    = secondsToHHMMSS(partsSeconds)
  let ext          = cfg.container
  let srcBasename  = splitFile(cfg.inputVideo).name
  let outputName   = srcBasename & "_" & $cfg.fps & "fps." & ext

  echo T(msgLabelInput)     & " : " & cfg.inputVideo
  echo T(msgLabelDuration)  & " : " & secondsToHHMMSS(videoSeconds) &
       " (" & $videoSeconds & "s)"
  echo T(msgLabelSplit)     & " : " & $cfg.split &
       " (" & $partsSeconds & "s / " & partsTime & ")"
  echo T(msgLabelFps)       & " : " & $cfg.fps
  echo T(msgLabelContainer) & " : " & ext
  echo T(msgLabelPasses)    & " : " & $cfg.passes
  echo T(msgLabelOutputDir) & " : " & cfg.outputDir

  let tmpDir    = cfg.outputDir / "tmp"
  let finalPath = cfg.outputDir / outputName
  let absInput  = absolutePath(cfg.inputVideo)

  createDir(tmpDir)

  # list.txt for concat — paths are relative to tmpDir, no directory prefix
  block:
    var lf = open(tmpDir / "list.txt", fmWrite)
    for i in 0 ..< cfg.split:
      lf.writeLine("file '" & zeroPad(i,3) & "." & $cfg.fps & "fps." & ext & "'")
    lf.close()

  # ── Step 1: split ────────────────────────────────────────────────────────
  echo T(msgStep1)
  runSeq(@["ffmpeg", "-y",
           "-i", absInput,
           "-c", "copy", "-map", "0",
           "-segment_time", partsTime,
           "-f", "segment", "-reset_timestamps", "1",
           tmpDir / ("output%03d." & ext)])

  # ── Step 2: interpolation ────────────────────────────────────────────────
  if cfg.passes == 2:
    echo T(msgStep2Pass1)
    var pass1: seq[seq[string]]
    for i in 0 ..< cfg.split:
      let inChunk = tmpDir / ("output" & zeroPad(i,3) & "." & ext)
      pass1.add interpArgs(inChunk, "", ext, cfg.fps, 1)
    runParallel(pass1)

    echo T(msgStep2Pass2)
    var pass2: seq[seq[string]]
    for i in 0 ..< cfg.split:
      let inChunk  = tmpDir / ("output" & zeroPad(i,3) & "." & ext)
      let outChunk = tmpDir / (zeroPad(i,3) & "." & $cfg.fps & "fps." & ext)
      pass2.add interpArgs(inChunk, outChunk, ext, cfg.fps, 2)
    runParallel(pass2)

  else:
    echo T(msgStep2Single)
    var tasks: seq[seq[string]]
    for i in 0 ..< cfg.split:
      let inChunk  = tmpDir / ("output" & zeroPad(i,3) & "." & ext)
      let outChunk = tmpDir / (zeroPad(i,3) & "." & $cfg.fps & "fps." & ext)
      tasks.add singlePassArgs(inChunk, outChunk, cfg.fps)
    runParallel(tasks)

  # ── Step 3: concat ───────────────────────────────────────────────────────
  echo T(msgStep3)
  runSeq(@["ffmpeg", "-y",
           "-f", "concat", "-safe", "0",
           "-i", tmpDir / "list.txt",
           "-map", "0", "-c", "copy",
           finalPath])

  # ── Step 4: cleanup ──────────────────────────────────────────────────────
  echo T(msgStep4)
  removeDir(tmpDir)

  echo T(msgDone, finalPath)

  if cfg.shutdown:
    when isWindows:
      discard execCmd("shutdown /s /f /t 3")
    else:
      discard execCmd("sudo systemctl poweroff")

when isMainModule:
  main()
