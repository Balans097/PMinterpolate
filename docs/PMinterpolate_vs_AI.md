# PMinterpolate vs. AI Interpolation: Comparison

> **PMinterpolate** — an open-source CLI tool using the classic `minterpolate` filter from FFmpeg with parallel processing across CPU cores.  
> **AI interpolation** — neural network models (RIFE, DAIN, FILM, TopazVideo AI, etc.) that predict intermediate frames using trained networks.

---

## Comparison Table

| Criterion | PMinterpolate (FFmpeg) | AI Interpolation |
|---|---|---|
| **Cost** | Free, MIT license | Quality interpolators are always paid (TopazVideo, SVP); free options require setup and deliver inferior results |
| **Privacy** | Fully local, no cloud | Never private regardless of the tool |
| **Quality on simple scenes** | Excellent | Good |
| **Quality on complex scenes** | Artifacts, "ghosting" | Somewhat better |
| **Occlusion handling** | Weak | Good |
| **Hardware requirements** | CPU only | GPU recommended |
| **Speed** | Linear scaling with CPU core count | Fast on GPU, slow on CPU |
| **Batch processing** | Built-in out of the box | Depends on the tool |
| **Format support** | 18 formats | Limited set |
| **Audio/subtitle preservation** | Automatic, no re-encoding | Depends on the tool; often re-encodes |
| **Ease of launch** | Single .exe + FFmpeg | Requires environment setup |
| **Cross-platform** | Windows + Linux | Varies; more often online via browser |

---

## Advantages

### ✅ PMinterpolate

- **Zero cost** — open source, MIT license, no subscriptions
- **Simple deployment** — single executable + FFmpeg in PATH, no dependencies
- **True parallelism** — video is processed in parallel across CPU cores; processing time scales linearly
- **Batch processing** — scans an entire folder, skips already completed files
- **All streams preserved** — audio, subtitles, chapters, and attachments are copied without re-encoding
- **18 supported formats** — mkv, mp4, avi, mov, webm, ts, vob and others
- **Privacy** — no cloud, no telemetry
- **Bilingual interface** — English and Russian (`--lang ru`)

### ✅ AI Interpolation

- **Higher quality on complex scenes** — explosions, smoke, water, and fast motion are handled somewhat better
- **Semantic understanding** — the model "sees" objects, reducing doubling at occlusions
- **Fewer artifacts** — neural networks less often produce artifacts and smearing, but **may introduce non-existent objects**
- **GPU acceleration** — on modern graphics cards, significantly faster than CPU-based algorithms
- **Fine detail preservation** — textures during motion are reproduced more accurately

---

## Disadvantages

### ❌ PMinterpolate

- **Algorithm quality ceiling** — `minterpolate` is based on block search; on dynamic scenes artifacts and doubling of small objects can occasionally appear
- **No GPU acceleration** — CPU only; fast with many cores, but GPU solutions typically win on long video files
- **No semantic understanding** — the algorithm does not distinguish objects, so quality may drop at occlusions
- **Two-pass mode is slower**, but provides a better quality/file size ratio

### ❌ AI Interpolation

- **Cost** — the best tools (TopazVideo AI, SVP) are always paid
- **Requires GPU** — without a discrete graphics card, CPU-mode speed is extremely low
- **Complex setup** — no comparably convenient CLI with out-of-the-box batch processing
- **Fewer formats** — many tools only work with a limited set of containers
- **No codec control** — tools work only with a limited set of codecs; presets are not always optimal
- **"Hallucinations"** — the neural network sometimes generates details that were not in the original

---

## Conclusion

**PMinterpolate** is the optimal choice for most tasks: zero cost, instant start, batch processing, and full privacy. For video with moderate motion, results will be excellent.

**AI interpolation** wins on image quality for dynamic scenes, but requires a GPU, budget, or technical expertise.

Both approaches **complement each other**: PMinterpolate handles 95% of everyday tasks without extra effort; AI tools are brought in where it is necessary to "see" objects and "infer" video content.

---

*Project link: [PMinterpolate on GitHub](https://github.com/Balans097/PMinterpolate)*
