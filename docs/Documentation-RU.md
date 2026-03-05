# PMinterpolate

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language: Nim](https://img.shields.io/badge/language-Nim-yellow.svg)](https://nim-lang.org/)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![i18n](https://img.shields.io/badge/i18n-EN%20%7C%20RU-blue.svg)]()
[![Author](https://img.shields.io/badge/author-Balans097-green.svg)](https://github.com/Balans097)

> **Parallel Motion Interpolate** — утилита командной строки для ускорения интерполяции кадров видео с использованием FFmpeg.  
> Кросс-платформенное приложение: **Windows** и **Linux** (Fedora, Ubuntu, Arch…).  
> Двуязычный интерфейс: **English** и **Русский** (`--lang en|ru`).

---

## Содержание

- [Обзор](#обзор)
- [Как это работает](#как-это-работает)
- [Требования](#требования)
- [Сборка](#сборка)
- [Использование](#использование)
- [Аргументы и опции](#аргументы-и-опции)
- [Примеры](#примеры)
- [Структура выходных файлов](#структура-выходных-файлов)
- [Архитектура кода](#архитектура-кода)
  - [Константы платформы](#константы-платформы)
  - [Система локализации i18n](#система-локализации-i18n)
  - [Типы данных](#типы-данных)
  - [Процедуры](#процедуры)
- [Параметры FFmpeg](#параметры-ffmpeg)
  - [Фильтр minterpolate](#фильтр-minterpolate)
  - [Маппинг потоков](#маппинг-потоков)
- [Ограничения](#ограничения)
- [Устранение неполадок](#устранение-неполадок)
- [Лицензия](#лицензия)

---

## Обзор

**PMinterpolate** (Parallel Motion Interpolate) — утилита командной строки, ускоряющая интерполяцию кадров длинных видеофайлов. Фильтр `minterpolate` в FFmpeg однопоточный, поэтому обработка длинного видео занимает много времени. Программа автоматически делит видео на части, обрабатывает их **одновременно** в нескольких процессах FFmpeg, затем склеивает результат.

Всё выполняется **нативно из одного процесса Nim** — никаких вспомогательных скриптов, никаких дополнительных окон. Весь вывод FFmpeg отображается прямо в том терминале, из которого запущена команда.

**Ключевые возможности:**

- Автоматическое определение числа логических ядер CPU — `--split` указывать не обязательно
- Пакетная обработка: все медиафайлы в указанной папке обрабатываются последовательно
- Поддержка 18 форматов: mkv, mp4, avi, mov, mpeg, mpg, wmv, flv, webm, ts, m2ts, mts, m4v, 3gp, ogv, vob, divx, xvid
- Перекодируется **только видеопоток** — аудио, субтитры, главы и все прочие дорожки копируются без изменений
- Готовые файлы автоматически пропускаются при повторном запуске
- Выходной файл именуется `<имя>_<fps>fps.<контейнер>` (например, `film_60fps.mkv`)
- Выбор контейнера: **MKV** (по умолчанию) или **MP4**
- Однопроходная и **двухпроходная** интерполяция

---

## Как это работает

```
Папка с медиафайлами
      │
      ▼
┌──────────────────────────────┐
│  Сканирование (без рекурсии) │  collectMediaFiles() → [file1, file2, …]
└──────────────────────────────┘
      │
      ▼  (для каждого файла последовательно)
┌──────────────┐
│  1. Разбивка │  ffmpeg -f segment  →  tmp/output000.mkv … tmp/outputN.mkv
└──────────────┘
      │
      ▼
┌──────────────────────────────────────────────────────────────────┐
│  2. Параллельная интерполяция (N процессов одновременно)         │
│                                                                  │
│  Однопроходный режим (--passes 1):                               │
│    chunk 000: output000.mkv → 000.60fps.mkv  ┐                   │
│    chunk 001: output001.mkv → 001.60fps.mkv  ├─ параллельно      │
│    chunk 00N: output00N.mkv → 00N.60fps.mkv  ┘                   │
│                                                                  │
│  Двухпроходный режим (--passes 2):                               │
│    Проход 1 — анализ → /dev/null + .log  (все chunks параллельно)│
│    Проход 2 — интерполяция → .60fps.mkv  (все chunks параллельно)│
└──────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────┐
│  3. Склейка │  ffmpeg -f concat  →  output/film_60fps.mkv
└─────────────┘
      │
      ▼
┌──────────────┐
│  4. Очистка  │  removeDir(tmp/)
└──────────────┘
      │
      └─── следующий файл…
```

**Этап 1 — Разбивка.** Исходный файл нарезается на `N` равных фрагментов без перекодирования (`-c copy -map 0`). Все потоки сохраняются в каждом фрагменте. Фрагменты помещаются в `output/tmp/`.

**Этап 2 — Интерполяция.** Для каждого фрагмента запускается отдельный процесс FFmpeg через `startProcess` с флагом `poParentStreams` — вывод всех процессов идёт в один терминал. Видеопоток перекодируется фильтром `minterpolate`; аудио, субтитры и прочее копируются из того же фрагмента без изменений.

**Этап 3 — Склейка.** Интерполированные фрагменты объединяются в итоговый файл без повторного кодирования. Все потоки копируются через `-map 0 -c copy`.

**Этап 4 — Очистка.** Директория `tmp/` со всеми промежуточными файлами удаляется автоматически. В `output/` остаётся только итоговый файл.

---

## Требования

| Компонент | Версия | Примечание |
|---|---|---|
| **FFmpeg + ffprobe** | любая актуальная | Должны быть доступны в `PATH` |
| **Nim** | 2.0+ | Только для сборки бинарника |
| **Windows** | 7 / 10 / 11 | — |
| **Linux** | любой дистрибутив | — |

### Установка FFmpeg

**Fedora** (используйте RPM Fusion из-за патентных ограничений):
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

**Windows:** скачать с [ffmpeg.org](https://ffmpeg.org/download.html), добавить папку `bin` в переменную `PATH`.

Проверка:
```bash
ffmpeg -version
ffprobe -version
```

---

## Сборка

```bash
git clone https://github.com/Balans097/PMinterpolate.git
cd PMinterpolate
```

```bash
# Linux и Windows — команда одинакова
nim c -d:release PMinterpolate.nim
```

Платформа определяется **во время компиляции** через `defined(windows)` — один исходный файл для всех систем.

Дополнительные флаги оптимизации (опционально):

```bash
nim c -d:release --opt:speed -d:strip PMinterpolate.nim
```

| Флаг | Описание |
|---|---|
| `-d:release` | Оптимизация, отключение assert |
| `--opt:speed` | Максимальная скорость выполнения |
| `-d:strip` | Удаление отладочных символов |

---

## Использование

```
./PMinterpolate [inputDir] [OPTIONS]
PMinterpolate.exe [inputDir] [OPTIONS]
```

Если `inputDir` не указан — используется папка с исполняемым файлом.  
Если `--split` не указан — используется число логических ядер CPU (определяется автоматически).

---

## Аргументы и опции

### Позиционный аргумент

| Аргумент | Описание |
|---|---|
| `inputDir` | Путь к папке с медиафайлами. **Необязателен.** Если не указан — используется папка рядом с `PMinterpolate.exe`. Поиск файлов без рекурсии. |

### Опции

| Опция | Тип | По умолчанию | Описание |
|---|---|---|---|
| `--split N` | `int` | число ядер CPU | Количество частей для параллельной обработки. Если не указан, определяется автоматически через `countProcessors()`. |
| `-o`, `--outputDir NAME` | `string` | `output` | Директория для итоговых файлов. Создаётся автоматически. |
| `--fps N` | `int` | `60` | Целевая частота кадров после интерполяции. |
| `--container FORMAT` | `mp4\|mkv` | `mkv` | Контейнер выходных файлов. MKV рекомендуется — он надёжнее поддерживает произвольные потоки. |
| `--passes N` | `1\|2` | `1` | Количество проходов. Режим 2 проходов даёт более качественную интерполяцию за счёт предварительного анализа движения, но занимает вдвое больше времени. |
| `--lang LANG` | `en\|ru` | `en` | Язык интерфейса. |
| `--shutdown` | флаг | выкл. | Выключить компьютер по завершении. Linux: `sudo systemctl poweroff`. Windows: `shutdown /s /f /t 3`. |
| `-h`, `--help` | флаг | — | Показать справку на выбранном языке и выйти. |

Обе формы записи опций равнозначны:
```bash
--split 4
--split=4
```

---

## Примеры

### Полностью автоматический запуск

Запустите из папки с видеофайлами — аргументы не нужны:

```bash
# Linux: обработать все медиафайлы рядом с exe, split = число ядер CPU
./PMinterpolate

# Windows
PMinterpolate.exe
```

### Указать папку явно

```bash
# Linux
./PMinterpolate /mnt/videos/films

# Windows
PMinterpolate.exe "D:\Videos\Films"
```

### Английский интерфейс (по умолчанию)

```
PMinterpolate.exe "D:\Videos"
```

Вывод:
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

### Ограничить число ядер

```bash
# Использовать только 4 ядра вместо всех доступных
PMinterpolate.exe --split 4
```

### Максимальное качество

```bash
PMinterpolate.exe "D:\Videos" --fps 60 --passes 2
```

### Справка

```bash
./PMinterpolate --help
./PMinterpolate --lang ru --help
```

---

## Структура выходных файлов

При обработке одного файла с параметрами `--split 4 --fps 60 --container mkv`:

```
output/
├── tmp/
│   ├── list.txt                  # Список фрагментов для ffmpeg concat
│   │
│   ├── output000.mkv             # Исходный фрагмент 1 (все потоки)
│   ├── output001.mkv             # Исходный фрагмент 2
│   ├── output002.mkv             # Исходный фрагмент 3
│   ├── output003.mkv             # Исходный фрагмент 4
│   │
│   ├── output000-0.log           # Статистика прохода 1 (только при --passes 2)
│   ├── ...
│   │
│   ├── 000.60fps.mkv             # Интерполированный фрагмент 1
│   ├── 001.60fps.mkv             # Интерполированный фрагмент 2
│   ├── 002.60fps.mkv             # Интерполированный фрагмент 3
│   └── 003.60fps.mkv             # Интерполированный фрагмент 4
│
└── film_60fps.mkv                # ← Итоговый результат
```

После завершения `tmp/` удаляется автоматически. В `output/` остаётся только итоговый файл. При пакетной обработке нескольких файлов `tmp/` пересоздаётся для каждого файла.

---

## Архитектура кода

### Константы платформы

```nim
const isWindows = defined(windows)
const devNull   = when isWindows: "NUL" else: "/dev/null"
```

Платформа определяется **во время компиляции**. `devNull` используется в первом проходе двухпроходного режима как цель для `-f null`.

---

### Система локализации i18n

Все строки пользовательского интерфейса хранятся в двух константных массивах `EN` и `RU`, индексируемых перечислением `MsgId`.

**`MsgId`** — идентификаторы всех строк:

| Группа | Идентификаторы |
|---|---|
| Ошибки | `msgErrFfprobe`, `msgErrFfprobeOutput`, `msgErrUnknownOpt`, `msgErrUnexpectedArg`, `msgErrBadContainer`, `msgErrBadPasses`, `msgErrSplitPositive`, `msgErrNoMedia`, `msgErrDirNotFound`, `msgErrTaskFailed`, `msgErrAbortFailed` |
| Метки вывода | `msgLabelInput`, `msgLabelDuration`, `msgLabelSplit`, `msgLabelCpus`, `msgLabelFps`, `msgLabelContainer`, `msgLabelPasses`, `msgLabelOutputDir`, `msgLabelScanDir`, `msgLabelFound`, `msgLabelFileN` |
| Шаги | `msgStep1`, `msgStep2Pass1`, `msgStep2Pass2`, `msgStep2Single`, `msgStep3`, `msgStep4` |
| Прогресс | `msgTaskStarted`, `msgWaiting`, `msgDone`, `msgSkipExists` |
| Справка | `msgHelp` |

**`T(id)`**, **`T(id, a)`**, **`T(id, a, b)`** — функции доступа к строкам. Перегрузки с параметрами заменяют маркеры `$1` и `$2`:

```nim
T(msgErrDirNotFound, path)             # → "Error: directory not found: /path"
T(msgErrTaskFailed, "002", "1")        # → "Error: chunk 002 failed (exit code 1)."
T(msgLabelFileN, "2", "5")             # → "[2/5] File"
```

**Двойной проход `--lang`.** Флаг обрабатывается прямым перебором `commandLineParams()` до запуска основного парсера — это гарантирует, что даже сообщения об ошибках парсера выводятся на нужном языке.

---

### Типы данных

#### `Config`

```nim
type
  Config = object
    inputDir   : string   # Папка с медиафайлами  [default: getAppDir()]
    split      : int      # Количество фрагментов [default: 0 → auto]
    outputDir  : string   # Директория вывода     [default: "output"]
    fps        : int      # Целевой FPS            [default: 60]
    container  : string   # "mkv" или "mp4"       [default: "mkv"]
    passes     : int      # 1 или 2               [default: 1]
    shutdown   : bool     # Выключить ПК после завершения
```

`split = 0` в `Config` означает «не задано пользователем» и заменяется результатом `detectCpuCount()` после завершения парсинга аргументов.

---

### Процедуры

#### `detectCpuCount(): int`

Определяет число логических процессоров через стандартную процедуру `countProcessors()` из `std/osproc`. При ошибке возвращает `1`.

```nim
proc detectCpuCount(): int =
  result = countProcessors()
  if result <= 0: result = 1
```

`countProcessors()` использует системные вызовы:
- **Windows:** `GetSystemInfo` → `dwNumberOfProcessors`
- **Linux:** разбор `/proc/cpuinfo`

#### `collectMediaFiles(dir: string): seq[string]`

Перебирает файлы в `dir` через `walkDir` (без рекурсии), фильтрует по расширению из константы `mediaExts`, возвращает отсортированный список путей в том виде, в котором их возвращает `walkDir`. Преобразование в абсолютный путь выполняется позже в `processFile` через `absolutePath()`.

#### `zeroPad(n, width: int): string`

```nim
zeroPad(3, 3)   # → "003"
zeroPad(12, 3)  # → "012"
```

#### `secondsToHHMMSS(s: int): string`

Конвертирует секунды в `HH:MM:SS` для параметра `-segment_time` FFmpeg.

#### `getVideoDurationSeconds(videoPath: string): int`

Вызывает `ffprobe` и возвращает длительность видео в целых секундах.

#### `minterpolateFilter(fps: int): string`

Возвращает строку параметров фильтра `minterpolate`:

```
minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1
```

#### `interpArgs(inChunk, outFile, ext: string; fps, passNum: int): seq[string]`

Строит argv для одного ffmpeg-процесса в двухпроходном режиме. Возвращает `seq[string]` для передачи в `startProcess` напрямую — без shell, без проблем с экранированием.

Проход 1: видео направляется в `devNull`, статистика записывается в `<stem>.log`.  
Проход 2: итоговый файл с полным маппингом потоков.

#### `singlePassArgs(inChunk, outFile: string; fps: int): seq[string]`

Строит argv для однопроходного режима. Видео перекодируется; все остальные потоки копируются.

#### `runSeq(args: seq[string])`

Запускает один ffmpeg-процесс синхронно с `poParentStreams`. При ненулевом коде завершения прерывает программу. Используется для разбивки и склейки.

#### `runParallel(tasks: seq[seq[string]])`

Запускает все задачи одновременно через `startProcess`, выводит PID каждой. Ждёт завершения всех через `waitForExit`. Если хотя бы один процесс завершился с ошибкой — выводит диагностику и прерывает программу.

#### `processFile(inputVideo: string; cfg: Config)`

Полный пайплайн обработки одного файла: разбивка → интерполяция → склейка → очистка.

#### `parseArgs(): Config`

Разбирает аргументы через `std/parseopt` с `mode = LaxMode`. Если `--split` не передан, `result.split` остаётся равным `0` и заменяется на `detectCpuCount()` после завершения парсинга.

#### `main()`

1. Парсит аргументы
2. Сканирует `inputDir`
3. Выводит сводку (включая число ядер CPU и значение `--split`)
4. Последовательно обрабатывает каждый файл через `processFile`; файлы с уже готовым результатом пропускаются
5. Выводит итоговую статистику
6. При `--shutdown` инициирует выключение

---

## Параметры FFmpeg

### Фильтр minterpolate

| Параметр | Значение | Описание |
|---|---|---|
| `fps` | `N` (из `--fps`) | Целевая частота кадров |
| `mi_mode` | `mci` | Motion Compensated Interpolation |
| `mc_mode` | `aobmc` | Адаптивная компенсация перекрытия блоков |
| `me_mode` | `bidir` | Двунаправленный поиск движения |
| `vsbmc` | `1` | Компенсация блоков переменного размера |

### Маппинг потоков

Каждый процесс интерполяции открывает один и тот же фрагмент **дважды** как два отдельных входа FFmpeg:

```
ffmpeg -i output/tmp/output000.mkv   ← вход [0]: источник видеопотока
       -i output/tmp/output000.mkv   ← вход [1]: источник остальных потоков
       -map 0:v:0                     ← перекодировать только первый видеопоток
       -map 1:a?                      ← все аудиодорожки — без изменений
       -map 1:s?                      ← субтитры — без изменений
       -map 1:t?                      ← главы и вложения — без изменений
       -map 1:d?                      ← потоки данных — без изменений
       -c:a copy -c:s copy -c:t copy -c:d copy
```

Знак `?` делает каждый `-map` необязательным. При склейке (этап 3) используется `-map 0 -c copy` — все потоки из всех фрагментов попадают в итоговый файл.

---

## Ограничения

- **`--shutdown` на Linux требует sudo.** Команда `sudo systemctl poweroff` запросит пароль, если не настроен `NOPASSWD` в `/etc/sudoers`.
- **Нагрузка на CPU.** По умолчанию используются все логические ядра. При необходимости ограничьте через `--split N`.
- **Дисковое пространство.** Временно требуется ~3× от размера обрабатываемого файла. При `--passes 2` дополнительно создаются небольшие `.log`-файлы.
- **MP4 и сложные потоки.** Контейнер MP4 имеет ограничения на типы субтитров и вложений. При наличии нестандартных потоков рекомендуется `--container mkv`.
- **Только `en` и `ru`.** Добавление нового языка требует нового значения в `Lang`, нового массива строк по образцу `EN`/`RU` и ветки в `T()`.

---

## Устранение неполадок

### `ffprobe failed` при запуске

```bash
which ffprobe && ffprobe -version   # Linux
where ffprobe                       # Windows CMD
```

### Один из фрагментов завершился с ошибкой

Программа выводит номер фрагмента и код выхода FFmpeg. Команды для каждого фрагмента строятся по схеме из раздела [Маппинг потоков](#маппинг-потоков) — запустите нужную команду вручную для диагностики.

### Рывки на стыках фрагментов

Попробуйте уменьшить `--split` для более длинных фрагментов.

### Слишком высокая нагрузка на CPU

```bash
# Использовать только половину ядер
PMinterpolate.exe --split 8
```

### Кириллица отображается некорректно в Windows CMD

```cmd
chcp 65001
```

Либо смените шрифт консоли на Consolas или Lucida Console через свойства окна.

---

## Лицензия

Распространяется под лицензией MIT.

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
