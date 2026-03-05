## PMinterpolate.nim
## Parallel Motion Interpolate — accelerate video frame interpolation with FFmpeg.
## Cross-platform: Windows and Linux.
## Bilingual UI: English / Russian  (--lang en|ru)
##
## Copyright (c) 2026 Balans097
## https://github.com/Balans097/PMinterpolate
##
## Usage:
##   ./PMinterpolate [inputDir] [--split N] [OPTIONS]
##
## If inputDir is omitted, the directory of the executable is used.
## If --split is omitted, the number of logical CPU cores is used.
## All media files in inputDir are processed sequentially (no recursion).
##
## Requirements:
##   - FFmpeg + ffprobe in PATH
##   - Nim 2.0+  (build only)


# nim c -d:release PMinterpolate.nim





import std/[os, osproc, parseopt, strformat, strutils, math, algorithm]





# ─── Platform ─────────────────────────────────────────────────────────────────

const isWindows = defined(windows)
const devNull   = when isWindows: "NUL" else: "/dev/null"



# ─── Media extensions ─────────────────────────────────────────────────────────

const mediaExts = [
  ".mkv", ".mp4", ".avi", ".mov", ".mpeg", ".mpg",
  ".wmv", ".flv", ".webm", ".ts", ".m2ts", ".mts",
  ".m4v", ".3gp", ".ogv", ".vob", ".divx", ".xvid",
]




proc isMediaFile(path: string): bool =
  splitFile(path).ext.toLowerAscii() in mediaExts





# ─── i18n ─────────────────────────────────────────────────────────────────────

type Lang = enum langEn, langRu

type MsgId = enum
  msgErrFfprobe
  msgErrFfprobeOutput
  msgErrUnknownOpt
  msgErrUnexpectedArg
  msgErrBadContainer
  msgErrBadPasses
  msgErrSplitPositive
  msgErrNoMedia
  msgErrDirNotFound
  msgErrTaskFailed
  msgErrAbortFailed
  msgLabelInput
  msgLabelDuration
  msgLabelSplit
  msgLabelCpus
  msgLabelFps
  msgLabelContainer
  msgLabelPasses
  msgLabelOutputDir
  msgLabelScanDir
  msgLabelFound
  msgLabelFileN
  msgStep1
  msgStep2Pass1
  msgStep2Pass2
  msgStep2Single
  msgTaskStarted
  msgWaiting
  msgStep3
  msgStep4
  msgDone
  msgSkipExists
  msgHelp

const EN: array[MsgId, string] = [
  "Error: ffprobe failed. Is FFmpeg installed and in PATH?",
  "Error: unexpected ffprobe output: '$1'",
  "Error: unknown option: --$1",
  "Error: unexpected positional argument: $1",
  "Error: --container must be 'mp4' or 'mkv'.",
  "Error: --passes must be 1 or 2.",
  "Error: --split must be a positive integer.",
  "Error: no media files found in: $1",
  "Error: directory not found: $1",
  "Error: chunk $1 failed (exit code $2).",
  "Aborting: one or more chunks failed.",
  "Input      ",
  "Duration   ",
  "Chunks     ",
  "CPU cores  ",
  "Target FPS ",
  "Container  ",
  "Passes     ",
  "Output dir ",
  "Scan dir   ",
  "Found      ",
  "[$1/$2] File",
  "[1/4] Splitting into chunks...",
  "[2/4] Pass 1/2 - motion analysis (parallel)...",
  "[2/4] Pass 2/2 - interpolation (parallel)...",
  "[2/4] Interpolation (parallel)...",
  "  chunk $1 started (PID $2)",
  "  waiting for all chunks to finish...",
  "[3/4] Concatenating chunks...",
  "[4/4] Cleaning up...",
  "Done! Output: $1",
  "Skipping (output already exists): $1",
  """
Usage: PMinterpolate [inputDir] [OPTIONS]

Arguments:
  inputDir                directory with media files to process
                          [default: directory of the executable]

Options:
  -i, --inputDir DIR      directory with media files to process
                          (alternative to the positional argument)
  --split N               number of parallel chunks
                          [default: number of logical CPU cores]
  -o, --outputDir NAME    output directory          [default: output]
  --fps N                 target FPS                [default: 60]
  --container FORMAT      output container: mp4|mkv [default: mkv]
  --passes N              encoding passes: 1|2      [default: 1]
  --lang LANG             interface language: en|ru [default: en]
  --shutdown              shut down when done
  -h, --help              show this help

Notes:
  All media files in inputDir are processed sequentially.
  Supported formats: mkv, mp4, avi, mov, mpeg, mpg, wmv, flv,
                     webm, ts, m2ts, mts, m4v, 3gp, ogv, vob, divx, xvid.
  Files already present in outputDir are skipped automatically.
  Output files are named: <original_name>_<fps>fps.<container>
""",
]

const RU: array[MsgId, string] = [
  "Ошибка: ffprobe завершился с ошибкой. Установлен ли FFmpeg и добавлен ли он в PATH?",
  "Ошибка: неожиданный вывод ffprobe: '$1'",
  "Ошибка: неизвестный параметр: --$1",
  "Ошибка: лишний позиционный аргумент: $1",
  "Ошибка: --container должен быть 'mp4' или 'mkv'.",
  "Ошибка: --passes должен быть 1 или 2.",
  "Ошибка: --split должен быть положительным целым числом.",
  "Ошибка: медиафайлы не найдены в: $1",
  "Ошибка: папка не найдена: $1",
  "Ошибка: фрагмент $1 завершился с кодом $2.",
  "Прерывание: один или несколько фрагментов завершились с ошибкой.",
  "Файл        ",
  "Длительн.  ",
  "Фрагменты  ",
  "Ядер CPU   ",
  "Целевой FPS ",
  "Контейнер   ",
  "Проходов    ",
  "Папка вывода",
  "Папка скана ",
  "Найдено     ",
  "[$1/$2] Файл",
  "[1/4] Разбивка на фрагменты...",
  "[2/4] Проход 1/2 - анализ движения (параллельно)...",
  "[2/4] Проход 2/2 - интерполяция (параллельно)...",
  "[2/4] Интерполяция (параллельно)...",
  "  фрагмент $1 запущен (PID $2)",
  "  ожидание завершения всех фрагментов...",
  "[3/4] Склейка фрагментов...",
  "[4/4] Удаление временных файлов...",
  "Готово! Результат: $1",
  "Пропуск (результат уже существует): $1",
  """
Использование: PMinterpolate [папка] [ПАРАМЕТРЫ]

Аргументы:
  папка                   папка с медиафайлами для обработки
                          [по умолчанию: папка с исполняемым файлом]

Параметры:
  -i, --inputDir ПАПКА    папка с медиафайлами для обработки
                          (альтернатива позиционному аргументу)
  --split N               количество параллельных фрагментов
                          [по умолчанию: число логических ядер CPU]
  -o, --outputDir ИМЯ     папка вывода               [по умолчанию: output]
  --fps N                 целевой FPS                [по умолчанию: 60]
  --container ФОРМАТ      контейнер: mp4|mkv         [по умолчанию: mkv]
  --passes N              количество проходов: 1|2   [по умолчанию: 1]
  --lang ЯЗЫК             язык интерфейса: en|ru     [по умолчанию: en]
  --shutdown              выключить компьютер по завершении
  -h, --help              показать эту справку

Примечания:
  Все медиафайлы в указанной папке обрабатываются последовательно.
  Поддерживаемые форматы: mkv, mp4, avi, mov, mpeg, mpg, wmv, flv,
                           webm, ts, m2ts, mts, m4v, 3gp, ogv, vob, divx, xvid.
  Файлы, результат для которых уже есть в папке вывода, пропускаются.
  Имя выходного файла: <оригинальное_имя>_<fps>fps.<контейнер>
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
    inputDir   : string
    split      : int      # 0 = auto-detect from CPU count
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

proc detectCpuCount(): int =
  ## Returns the number of logical processors available to the process.
  ## Falls back to 1 if detection fails.
  result = countProcessors()
  if result <= 0: result = 1

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

proc collectMediaFiles(dir: string): seq[string] =
  ## Return sorted list of media files in dir (no recursion).
  for kind, path in walkDir(dir):
    if kind == pcFile and isMediaFile(path):
      result.add(path)
  result.sort()

# ─── FFmpeg argv builders ─────────────────────────────────────────────────────

proc minterpolateFilter(fps: int): string =
  "minterpolate=fps=" & $fps & ":mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"

proc interpArgs(inChunk, outFile, ext: string; fps, passNum: int): seq[string] =
  let vf   = minterpolateFilter(fps)
  let stem = splitFile(inChunk).name
  result = @["ffmpeg", "-y", "-i", inChunk, "-i", inChunk, "-map", "0:v:0"]
  if passNum == 1:
    result &= @["-vf", vf, "-c:v", "libx264", "-preset", "slow", "-crf", "14",
                "-passlogfile", stem,
                "-pass", "1", "-an", "-f", "null", devNull]
  else:
    result &= @["-vf", vf, "-c:v", "libx264", "-preset", "slow", "-crf", "14",
                "-passlogfile", stem,
                "-pass", "2",
                "-map", "1:a?", "-map", "1:s?", "-map", "1:t?", "-map", "1:d?",
                "-c:a", "copy", "-c:s", "copy", "-c:t", "copy", "-c:d", "copy",
                outFile]

proc singlePassArgs(inChunk, outFile: string; fps: int): seq[string] =
  let vf = minterpolateFilter(fps)
  @["ffmpeg", "-y",
    "-i", inChunk, "-i", inChunk,
    "-map", "0:v:0",
    "-map", "1:a?", "-map", "1:s?", "-map", "1:t?", "-map", "1:d?",
    "-vf", vf, "-c:v", "libx264", "-preset", "slow", "-crf", "14",
    "-c:a", "copy", "-c:s", "copy", "-c:t", "copy", "-c:d", "copy",
    outFile]

# ─── Process helpers ──────────────────────────────────────────────────────────

proc runSeq(args: seq[string]) =
  let p = startProcess(args[0], args = args[1..^1],
                       options = {poUsePath, poParentStreams})
  let rc = p.waitForExit()
  p.close()
  if rc != 0:
    stderr.writeLine "ffmpeg exited with code " & $rc
    quit(rc)

proc runParallel(tasks: seq[seq[string]]) =
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

# ─── Single file processor ────────────────────────────────────────────────────

proc processFile(inputVideo: string; cfg: Config) =
  let videoSeconds = getVideoDurationSeconds(inputVideo)
  let partsSeconds = max(1, videoSeconds div cfg.split)
  let partsTime    = secondsToHHMMSS(partsSeconds)
  let ext          = cfg.container
  let srcBasename  = splitFile(inputVideo).name
  let outputName   = srcBasename & "_" & $cfg.fps & "fps." & ext
  let finalPath    = cfg.outputDir / outputName
  let absInput     = absolutePath(inputVideo)

  echo T(msgLabelInput)    & " : " & inputVideo
  echo T(msgLabelDuration) & " : " & secondsToHHMMSS(videoSeconds) &
       " (" & $videoSeconds & "s)"
  echo T(msgLabelSplit)    & " : " & $cfg.split &
       " (" & $partsSeconds & "s / " & partsTime & ")"

  let tmpDir = cfg.outputDir / "tmp"
  createDir(tmpDir)

  block:
    var lf = open(tmpDir / "list.txt", fmWrite)
    for i in 0 ..< cfg.split:
      lf.writeLine("file '" & zeroPad(i,3) & "." & $cfg.fps & "fps." & ext & "'")
    lf.close()

  echo T(msgStep1)
  runSeq(@["ffmpeg", "-y",
           "-fflags", "+genpts",
           "-i", absInput,
           "-c", "copy", "-map", "0",
           "-segment_time", partsTime,
           "-f", "segment", "-reset_timestamps", "1",
           tmpDir / ("output%03d." & ext)])

  if cfg.passes == 2:
    echo T(msgStep2Pass1)
    var pass1: seq[seq[string]]
    for i in 0 ..< cfg.split:
      pass1.add interpArgs(tmpDir / ("output" & zeroPad(i,3) & "." & ext),
                           "", ext, cfg.fps, 1)
    runParallel(pass1)

    echo T(msgStep2Pass2)
    var pass2: seq[seq[string]]
    for i in 0 ..< cfg.split:
      pass2.add interpArgs(tmpDir / ("output" & zeroPad(i,3) & "." & ext),
                           tmpDir / (zeroPad(i,3) & "." & $cfg.fps & "fps." & ext),
                           ext, cfg.fps, 2)
    runParallel(pass2)
  else:
    echo T(msgStep2Single)
    var tasks: seq[seq[string]]
    for i in 0 ..< cfg.split:
      tasks.add singlePassArgs(tmpDir / ("output" & zeroPad(i,3) & "." & ext),
                               tmpDir / (zeroPad(i,3) & "." & $cfg.fps & "fps." & ext),
                               cfg.fps)
    runParallel(tasks)

  echo T(msgStep3)
  runSeq(@["ffmpeg", "-y",
           "-f", "concat", "-safe", "0",
           "-i", tmpDir / "list.txt",
           "-map", "0", "-c", "copy",
           finalPath])

  echo T(msgStep4)
  removeDir(tmpDir)

  echo T(msgDone, finalPath)

# ─── Argument parsing ─────────────────────────────────────────────────────────

proc parseArgs(): Config =
  result = Config(inputDir: "", split: 0, outputDir: "output",
                  fps: 60, container: "mkv", passes: 1, shutdown: false)

  let rawArgs = commandLineParams()

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
        result.inputDir = p.key
        positionalsDone = true
      else:
        stderr.writeLine T(msgErrUnexpectedArg, p.key); quit(1)
    of cmdLongOption, cmdShortOption:
      case p.key
      of "split":
        let v = parseInt(p.val)
        if v <= 0: stderr.writeLine T(msgErrSplitPositive); quit(1)
        result.split = v
      of "i", "inputDir":
        if positionalsDone:
          stderr.writeLine "Error: inputDir specified both as positional argument and --inputDir flag."
          quit(1)
        result.inputDir  = p.val
        positionalsDone  = true
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

  if result.inputDir == "":
    result.inputDir = getAppDir()

  if not dirExists(result.inputDir):
    stderr.writeLine T(msgErrDirNotFound, result.inputDir); quit(1)

  # Auto-detect CPU count if --split was not provided
  if result.split == 0:
    result.split = detectCpuCount()

# ─── Main ─────────────────────────────────────────────────────────────────────

proc main() =
  let cfg        = parseArgs()
  let cpuCount   = detectCpuCount()
  let mediaFiles = collectMediaFiles(cfg.inputDir)

  echo T(msgLabelScanDir)   & " : " & cfg.inputDir
  echo T(msgLabelFound)     & " : " & $mediaFiles.len & " " &
       (if gLang == langRu: "файл(ов)" else: "file(s)")
  echo T(msgLabelCpus)      & " : " & $cpuCount
  echo T(msgLabelSplit)     & " : " & $cfg.split &
       (if cfg.split == cpuCount: " (auto)" else: "")
  echo T(msgLabelFps)       & " : " & $cfg.fps
  echo T(msgLabelContainer) & " : " & cfg.container
  echo T(msgLabelPasses)    & " : " & $cfg.passes
  echo T(msgLabelOutputDir) & " : " & cfg.outputDir
  echo ""

  if mediaFiles.len == 0:
    stderr.writeLine T(msgErrNoMedia, cfg.inputDir)
    quit(1)

  createDir(cfg.outputDir)

  var processed = 0
  var skipped   = 0

  for idx, filePath in mediaFiles:
    let srcBasename = splitFile(filePath).name
    let outputName  = srcBasename & "_" & $cfg.fps & "fps." & cfg.container
    let finalPath   = cfg.outputDir / outputName

    if fileExists(finalPath):
      echo T(msgSkipExists, outputName)
      inc skipped
      continue

    echo "─".repeat(60)
    echo T(msgLabelFileN, $(idx + 1), $mediaFiles.len) & " : " & lastPathPart(filePath)
    echo "─".repeat(60)

    processFile(filePath, cfg)
    inc processed
    echo ""

  echo "═".repeat(60)
  if gLang == langRu:
    echo "Обработано: " & $processed & "  Пропущено: " & $skipped
  else:
    echo "Processed: " & $processed & "  Skipped: " & $skipped
  echo "═".repeat(60)

  if cfg.shutdown:
    when isWindows:
      discard execCmd("shutdown /s /f /t 3")
    else:
      discard execCmd("sudo systemctl poweroff")







when isMainModule:
  main()











# nim c -d:release PMinterpolate.nim

