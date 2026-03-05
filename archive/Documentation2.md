# parallel_minterpolate

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language: Nim](https://img.shields.io/badge/language-Nim-yellow.svg)](https://nim-lang.org/)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![i18n](https://img.shields.io/badge/i18n-EN%20%7C%20RU-blue.svg)]()

> Параллельная интерполяция кадров видео с использованием FFmpeg.  
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

**parallel_minterpolate** — утилита командной строки, ускоряющая интерполяцию кадров длинных видеофайлов. Фильтр `minterpolate` в FFmpeg однопоточный, поэтому обработка длинного видео занимает много времени. Программа автоматизирует стандартный подход: делит видео на части, обрабатывает их **одновременно** в нескольких процессах FFmpeg, затем склеивает результат.

Всё выполняется **нативно из одного процесса Nim** — никаких вспомогательных скриптов, никаких дополнительных окон. Весь вывод FFmpeg отображается прямо в том терминале, из которого запущена команда.

**Ключевые возможности:**

- Весь пайплайн (разбивка → интерполяция → склейка → очистка) выполняется в одном вызове
- Перекодируется **только видеопоток** — аудио, субтитры, главы и все прочие дорожки копируются без изменений
- Выходной файл именуется `<имя>_<fps>fps.<контейнер>` (например, `Input_60fps.mkv`)
- Выбор выходного контейнера: **MKV** (по умолчанию) или **MP4**
- Однопроходная и **двухпроходная** интерполяция
- Двуязычный интерфейс: **EN** / **RU**

---

## Как это работает

```
Исходное видео
      │
      ▼
┌──────────────┐
│  1. Разбивка │  ffmpeg -f segment  →  tmp/output000.mkv … tmp/outputN.mkv
└──────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Параллельная интерполяция (N процессов одновременно)        │
│                                                                 │
│  Однопроходный режим (--passes 1):                              │
│    chunk 000: output000.mkv → 000.60fps.mkv  ┐                  │
│    chunk 001: output001.mkv → 001.60fps.mkv  ├─ параллельно     │
│    chunk 002: output002.mkv → 002.60fps.mkv  ┘                  │
│                                                                 │
│  Двухпроходный режим (--passes 2):                              │
│    Проход 1 — анализ → /dev/null + .log  (все chunks параллельно)│
│    Проход 2 — интерполяция → .60fps.mkv  (все chunks параллельно)│
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────┐
│  3. Склейка │  ffmpeg -f concat  →  output/Input_60fps.mkv
└─────────────┘
      │
      ▼
┌──────────────┐
│  4. Очистка  │  removeDir(tmp/)
└──────────────┘
```

**Этап 1 — Разбивка.** Исходный файл нарезается на `N` равных фрагментов без перекодирования (`-c copy -map 0`). Все потоки сохраняются в каждом фрагменте. Фрагменты помещаются в `output/tmp/`.

**Этап 2 — Интерполяция.** Для каждого фрагмента запускается отдельный процесс FFmpeg через `startProcess` с флагом `poParentStreams` — вывод всех процессов идёт в один терминал. Видеопоток перекодируется фильтром `minterpolate`; аудио, субтитры и прочее копируются из того же фрагмента без изменений. При двухпроходном режиме сначала все фрагменты параллельно проходят анализ движения, затем — параллельную интерполяцию.

**Этап 3 — Склейка.** Интерполированные фрагменты объединяются в итоговый файл без повторного кодирования. Все потоки копируются через `-map 0 -c copy`.

**Этап 4 — Очистка.** Директория `tmp/` со всеми промежуточными файлами удаляется автоматически. В `output/` остаётся только итоговый файл.

---

## Требования

| Компонент | Версия | Примечание |
|---|---|---|
| **FFmpeg + ffprobe** | любая актуальная | Должны быть доступны в `PATH` |
| **Nim** | 1.6+ | Только для сборки бинарника |
| **Windows** | 7 / 10 / 11 | — |
| **Linux** | любой дистрибутив | — |

### Установка FFmpeg

**Fedora** (стандартные репозитории могут не содержать FFmpeg из-за патентных ограничений — используйте RPM Fusion):
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
git clone https://github.com/your-username/parallel-minterpolate-nim.git
cd parallel-minterpolate-nim
```

```bash
# Linux и Windows — команда одинакова
nim c -d:release parallel_minterpolate.nim
```

Платформа определяется **во время компиляции** через `defined(windows)` — один исходный файл для всех систем.

Дополнительные флаги оптимизации (опционально):

```bash
nim c -d:release --opt:speed -d:strip parallel_minterpolate.nim
```

| Флаг | Описание |
|---|---|
| `-d:release` | Оптимизация, отключение assert |
| `--opt:speed` | Максимальная скорость выполнения |
| `-d:strip` | Удаление отладочных символов |

---

## Использование

```
./parallel_minterpolate <inputVideo> --split <N> [OPTIONS]
parallel_minterpolate.exe <inputVideo> --split <N> [OPTIONS]
```

---

## Аргументы и опции

### Позиционный аргумент

| Аргумент | Описание |
|---|---|
| `inputVideo` | Путь к входному видеофайлу. **Обязателен.** Поддерживаются любые форматы, которые понимает FFmpeg (MKV, MP4, AVI и др.). |

### Опции

| Опция | Тип | По умолчанию | Описание |
|---|---|---|---|
| `--split N` | `int` | — | Количество частей для параллельной обработки. **Обязателен.** Рекомендуется: число логических ядер CPU. |
| `-o`, `--outputDir NAME` | `string` | `output` | Директория для итогового файла. Создаётся автоматически. |
| `--fps N` | `int` | `60` | Целевая частота кадров после интерполяции. |
| `--container FORMAT` | `mp4\|mkv` | `mkv` | Контейнер выходных файлов. MKV рекомендуется — он надёжнее поддерживает произвольные потоки (субтитры, главы, вложения). |
| `--passes N` | `1\|2` | `1` | Количество проходов кодирования. Режим 2 проходов даёт более качественную интерполяцию за счёт предварительного анализа движения, но занимает вдвое больше времени. |
| `--lang LANG` | `en\|ru` | `en` | Язык интерфейса. Влияет на все сообщения программы. |
| `--shutdown` | флаг | выкл. | Выключить компьютер по завершении. Linux: `sudo systemctl poweroff`. Windows: `shutdown /s /f /t 3`. |
| `-h`, `--help` | флаг | — | Показать справку на выбранном языке и выйти. |

Обе формы записи опций равнозначны:
```bash
--split 4
--split=4
```

---

## Примеры

### Базовый запуск

```bash
# Linux
./parallel_minterpolate video.mkv --split 4

# Windows
parallel_minterpolate.exe video.mkv --split 4
```

Результат: `output/video_60fps.mkv` с видео, интерполированным до 60 fps. Аудио и субтитры идентичны оригиналу.

### Русский интерфейс

```bash
parallel_minterpolate.exe Input.mkv --split 4 --lang ru
```

Вывод:
```
Файл         : Input.mkv
Длительн.   : 00:00:42 (42s)
Разбить на   : 4 (10s / 00:00:10)
Целевой FPS  : 60
Контейнер    : mkv
Проходов     : 1
Папка вывода : output
[1/4] Разбивка на фрагменты...
[2/4] Интерполяция (параллельно)...
  фрагмент 000 запущен (PID 11240)
  фрагмент 001 запущен (PID 15320)
  фрагмент 002 запущен (PID 8904)
  фрагмент 003 запущен (PID 12776)
  ожидание завершения всех фрагментов...
[3/4] Склейка фрагментов...
[4/4] Удаление временных файлов...
Готово! Результат: output/Input_60fps.mkv
```

### MP4 с двумя проходами

```bash
./parallel_minterpolate video.mkv --split 4 --container mp4 --passes 2
```

### Максимальное качество, ночная обработка

```bash
./parallel_minterpolate film.mkv --split 8 --fps 60 --passes 2 --lang ru --shutdown
```

### Справка

```bash
./parallel_minterpolate --help
./parallel_minterpolate --lang ru --help
```

---

## Структура выходных файлов

В процессе обработки с `--split 3 --fps 60 --container mkv` структура выглядит так:

```
output/
├── tmp/
│   ├── list.txt                  # Список фрагментов для ffmpeg concat
│   │
│   ├── output000.mkv             # Исходный фрагмент 1 (все потоки)
│   ├── output001.mkv             # Исходный фрагмент 2
│   ├── output002.mkv             # Исходный фрагмент 3
│   │
│   ├── output000-0.log           # Статистика прохода 1 (только --passes 2)
│   ├── output001-0.log
│   ├── output002-0.log
│   │
│   ├── 000.60fps.mkv             # Интерполированный фрагмент 1
│   ├── 001.60fps.mkv             # Интерполированный фрагмент 2
│   └── 002.60fps.mkv             # Интерполированный фрагмент 3
│
└── video_60fps.mkv               # ← Итоговый результат
```

После завершения директория `tmp/` удаляется автоматически. В `output/` остаётся только итоговый файл.

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

Все пользовательские строки хранятся в двух константных массивах `EN` и `RU`, индексированных перечислением `MsgId`.

**`MsgId`** — идентификаторы всех строк:

| Группа | Идентификаторы |
|---|---|
| Ошибки | `msgErrFfprobe`, `msgErrFfprobeOutput`, `msgErrUnknownOpt`, `msgErrUnexpectedArg`, `msgErrNoInput`, `msgErrSplitPositive`, `msgErrFileNotFound`, `msgErrBadContainer`, `msgErrBadPasses`, `msgErrTaskFailed`, `msgErrAbortFailed` |
| Метки вывода | `msgLabelInput`, `msgLabelDuration`, `msgLabelSplit`, `msgLabelFps`, `msgLabelContainer`, `msgLabelPasses`, `msgLabelOutputDir` |
| Шаги | `msgStep1`, `msgStep2Pass1`, `msgStep2Pass2`, `msgStep2Single`, `msgStep3`, `msgStep4` |
| Прогресс | `msgTaskStarted`, `msgWaiting`, `msgDone` |
| Справка | `msgHelp` |

**`T(id)`**, **`T(id, a)`**, **`T(id, a, b)`** — функции доступа к строкам. Перегрузки с параметрами заменяют маркеры `$1` и `$2`:

```nim
T(msgErrFileNotFound, path)            # → "Error: file not found: /path/to/file"
T(msgErrTaskFailed, "002", "1")        # → "Error: chunk 002 failed (exit code 1)."
T(msgDone, "output/video_60fps.mkv")   # → "Done! Output: output/video_60fps.mkv"
```

**Двойной проход `--lang`.** Флаг обрабатывается прямым перебором `commandLineParams()` до запуска основного парсера — это гарантирует, что даже сообщения об ошибках парсера выводятся на нужном языке.

---

### Типы данных

#### `Config`

```nim
type
  Config = object
    inputVideo : string   # Путь к входному файлу
    split      : int      # Количество частей
    outputDir  : string   # Директория вывода  [default: "output"]
    fps        : int      # Целевой FPS         [default: 60]
    container  : string   # "mkv" или "mp4"    [default: "mkv"]
    passes     : int      # 1 или 2            [default: 1]
    shutdown   : bool     # Выключить ПК после завершения
```

---

### Процедуры

#### `zeroPad(n, width: int): string`

Дополняет целое число ведущими нулями до заданной ширины.

```nim
zeroPad(3, 3)   # → "003"
zeroPad(12, 3)  # → "012"
```

#### `secondsToHHMMSS(s: int): string`

Конвертирует секунды в строку `HH:MM:SS` для параметра `-segment_time` FFmpeg.

#### `getVideoDurationSeconds(videoPath: string): int`

Вызывает `ffprobe` и возвращает длительность видео в целых секундах.

#### `minterpolateFilter(fps: int): string`

Возвращает строку параметров фильтра `minterpolate`. Используется как единая точка для всех режимов:

```
minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1
```

#### `interpArgs(inChunk, outFile, ext: string; fps, passNum: int): seq[string]`

Строит argv для одного ffmpeg-процесса в двухпроходном режиме. Возвращает `seq[string]` для передачи в `startProcess` напрямую — без shell, без проблем с экранированием.

При `passNum = 1`: видео уходит в `devNull`, статистика пишется в `<stem>.log`.  
При `passNum = 2`: итоговый файл с полным маппингом потоков.

#### `singlePassArgs(inChunk, outFile: string; fps: int): seq[string]`

Строит argv для однопроходного режима. Видео перекодируется, все остальные потоки копируются.

#### `runSeq(args: seq[string])`

Запускает один ffmpeg-процесс синхронно с `poParentStreams` (вывод в текущий терминал). При ненулевом коде завершения прерывает программу. Используется для разбивки и склейки.

#### `runParallel(tasks: seq[seq[string]])`

Запускает все задачи одновременно через `startProcess`, выводит PID каждой. Затем ждёт завершения каждого процесса через `waitForExit`. Если хотя бы один процесс завершился с ошибкой — выводит диагностику и прерывает программу.

```nim
proc runParallel(tasks: seq[seq[string]]) =
  var procs: seq[Process]
  for i, args in tasks:
    let p = startProcess(args[0], args = args[1..^1],
                         options = {poUsePath, poParentStreams})
    echo T(msgTaskStarted, zeroPad(i, 3), $p.processID())
    procs.add(p)
  # ...ждём все процессы...
```

#### `parseArgs(): Config`

Разбирает аргументы через `std/parseopt` с `mode = LaxMode` (поддержка `--key value` и `--key=value`). Валидирует все поля.

#### `main()`

Точка входа. Последовательность:

1. Парсит аргументы → выводит сводку
2. Создаёт `output/tmp/`
3. Записывает `list.txt` для concat
4. **Шаг 1:** разбивка через `runSeq`
5. **Шаг 2:** интерполяция через `runParallel` (один или два прохода)
6. **Шаг 3:** склейка через `runSeq`
7. **Шаг 4:** удаляет `tmp/` через `removeDir`
8. Выводит итоговый путь; при `--shutdown` инициирует выключение

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

Знак `?` делает каждый `-map` необязательным: если в файле нет субтитров или глав, FFmpeg не выдаст ошибку.

При склейке (этап 3) используется `-map 0 -c copy` — это гарантирует, что **все** потоки из всех фрагментов попадают в итоговый файл без исключений.

---

## Ограничения

- **`--shutdown` на Linux требует sudo.** Команда `sudo systemctl poweroff` запросит пароль, если не настроен `NOPASSWD` в `/etc/sudoers`.
- **Нагрузка на CPU.** `N` параллельных задач создают `N`-кратную нагрузку. Рекомендуется устанавливать `--split` не более числа логических ядер.
- **Дисковое пространство.** Временно требуется ~3× от размера исходного файла (оригинальные фрагменты + интерполированные фрагменты). При `--passes 2` дополнительно создаются небольшие `.log`-файлы.
- **MP4 и сложные потоки.** Контейнер MP4 имеет ограничения на типы субтитров и вложений. Если исходный файл содержит нестандартные потоки, рекомендуется `--container mkv`.
- **Только `en` и `ru`.** Добавление нового языка требует нового значения в `Lang`, нового массива строк по образцу `EN`/`RU` и ветки в `T()`.

---

## Устранение неполадок

### `ffprobe failed` при запуске

**Причина:** FFmpeg не установлен или не в `PATH`.

```bash
# Проверка
which ffprobe && ffprobe -version   # Linux
where ffprobe                       # Windows CMD
```

### Один из фрагментов завершился с ошибкой

Программа выводит номер фрагмента и код ошибки FFmpeg. Чтобы увидеть подробный вывод конкретного фрагмента — запустите его команду вручную. Команды для каждого фрагмента строятся по схеме из раздела [Маппинг потоков](#маппинг-потоков).

### Рывки на стыках фрагментов в итоговом файле

Убедитесь, что в разбивке используется флаг `-reset_timestamps 1`. Также попробуйте уменьшить `--split` для более длинных фрагментов.

### Слишком высокая нагрузка на CPU

```bash
nproc                          # Linux — число логических ядер
echo %NUMBER_OF_PROCESSORS%    # Windows CMD
```

Установите `--split` равным `nproc - 1` или `nproc - 2`.

### Кириллица отображается некорректно в Windows CMD

Откройте CMD и выполните вручную:
```cmd
chcp 65001
```
Либо смените шрифт консоли на Consolas или Lucida Console через свойства окна.

---

## Лицензия

Distributed under the MIT License.

```
MIT License

Copyright (c) 2024

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
