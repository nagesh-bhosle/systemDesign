# Interview Face Coach — Real-time Facial Coaching for Interviews

> **Webcam → Face Mesh + Emotion AI → "STUCK / CONFIDENT / THINKING" → Session Report & Score (0–100)**

A privacy-first, 100% on-device browser app that watches your face during mock interviews and tells you — in real time — whether you look **confident**, **stuck**, **thinking**, or **anxious**, then generates a **post-interview report** with timeline, score, and coaching tips.

No camera stream ever leaves your device. No API keys. No install.

Based on the pattern of other `systemDesign/*-demo` projects (Docker, `start.sh`, design doc).

---

## Demo

```
Browser (getUserMedia) ──► face-api.js (TinyFaceDetector + 68 landmarks + Expression Net)
                               │
                               ├─► Geometry signals (brow, eyes, mouth, head pose)
                               ├─► Emotion probs (happy/sad/angry/fear/surprise/disgust/neutral)
                               └─► Rule engine ──► CONFIDENT / STUCK / THINKING / ANXIOUS / NEUTRAL
                                                        │
                              ┌─────────────────────────┼──────────────────────────┐
                              │                         │                          │
                         Live badge              Timeline (Chart.js)         Final Report
                      (green/red/yellow)       + localStorage log          + score 0-100
```

**Screenshots:** see `docs/` after first run (report is `report-<timestamp>.html`).

---

## Quick Start (30s)

### Option A — One command (no install)

```bash
cd systemDesign/interview-face-coach
./start.sh
# → opens http://localhost:5173
```

`start.sh` just runs `python3 -m http.server 5173 --directory app`. No pip, no npm.

### Option B — Manual

```bash
cd systemDesign/interview-face-coach/app
python3 -m http.server 5173
# open http://localhost:5173
```

Then:
1. Click **Enable Camera** → allow webcam.
2. Click **Calibrate (3s)** → keep a neutral face (sets your personal baseline).
3. Click **Start Session** → mock-answer a question out loud for 1–3 min.
4. Click **End & Report** → see score, timeline, coaching tips, and **Download JSON / Download Report**.

### Stop

```bash
./stop.sh
```

---

## How It Works (signals → states)

### Raw signals (per frame, ~15 FPS)

| Signal | How computed | Why it matters |
|---|---|---|
| `browFurrow` | eyebrow-to-eye distance vs calibrated baseline (landmarks 17–26 vs 36–47) | Stuck / confusion |
| `eyeOpenness` | Eye Aspect Ratio (EAR) | Stress (wide eyes) / drowsiness |
| `smile` | `expressions.happy` + mouth corner lift (landmarks 48,54) | Confidence |
| `mouthTension` | lip compression (upper/lower lip distance) | Thinking / holding back |
| `headYaw/Pitch` | nose tip (30) vs eye center | Eye contact / looking away |
| `emotions` | face-api `withFaceExpressions()` → 7 probs | Primary driver for state |

### State machine (hysteresis to avoid flicker)

```
CONFIDENT ← happy ≥ 0.35 + brow relaxed + eye contact
STUCK     ← (fear/sad/surprise high OR brow furrow > 1.25× baseline)
             + (lip press OR gaze-away OR long neutral > 4s)
THINKING  ← neutral dominant + lip press + slight head tilt + eyes on camera
ANXIOUS   ← fear/angry elevated + EAR high (wide eyes) + blink rate ↑
NEUTRAL   ← otherwise
```

A state must persist **≥ 600ms** before the badge flips (debounce). Samples are logged at **2 Hz** to `localStorage` + in-memory log for the report.

### Scoring (0–100)

```
confidenceScore = 40 * (confidentFrames / total)
composureScore  = 30 * (1 - stuckFrames / total)
engagementScore = 30 * (eyeContactFrames / total)
total = confidence + composure + engagement

90+ Excellent · 70–89 Good · 50–69 Average · <50 Needs practice
```

Report adds **personalized tips**:
- >25% stuck → "Practice structured pauses: 'Let me think through this aloud...'"
- Eye contact <60% → "Pick a point just above the lens"
- Brow furrow frequent → "Consciously relax forehead between answers"

---

## Project Structure

```
interview-face-coach/
├── README.md
├── InterviewFaceCoach.md      # System design doc (requirements, architecture, scale, privacy)
├── docker-compose.yml         # optional static nginx
├── start.sh / stop.sh
├── app/
│   ├── index.html             # Single-page app
│   ├── css/style.css          # Dark, modern UI
│   ├── js/app.js              # Camera, session, report wiring
│   ├── js/analyzer.js         # Geometry + rule engine (the brain)
│   └── assets/                # icons (none required)
└── docs/
    └── report-example.html    # generated after first session
```

---

## Tech Stack (chosen)

| Layer | Choice | Reason |
|---|---|---|
| Face AI | **face-api.js** (TinyFaceDetector + 68-point landmarks + Expression Net) via CDN | Single `<script>` tag, runs in WebGL/WASM, no build, works offline after first load; 7-emotion model is well-tuned |
| Charts | **Chart.js** via CDN | Timeline visualization without build |
| Hosting | **Python http.server** (or `nginx:alpine` in Docker) | Zero deps, matches "just open it" DX |
| Storage | `localStorage` + JSON/HTML export | No backend → privacy by default |
| Alt considered | MediaPipe Tasks Vision (FaceLandmarker + Blendshapes) | More precise AUs but heavier; face-api is enough for interview coaching. Easy swap: replace `analyzer.js` |

> **Why not a Python/OpenCV/MediaPipe backend?** Requires `pip install`, camera permissions via server, and heavier setup. Browser-only hits the requirement ("check my facial expressions") with 30s setup and **never uploads video** — better for an interview-prep tool.

---

## Privacy

- Video never leaves the browser (`getUserMedia` → `<video>` → canvas → face-api tensors locally).
- No cookies, no analytics. Session log stays in `localStorage` until you clear it.
- Works offline after first model download (models cached by browser).

---

## Extending

- **Backend history:** add `server/` (FastAPI + SQLite) to `POST /sessions` the JSON log and serve leaderboards.
- **Smarter model:** swap `face-api` for `mediapipe/tasks-vision` and map blendshapes → Action Units (AU4 brow lowerer, AU12 lip corner puller) in `analyzer.js`.
- **Voice fusion:** combine with Web Speech API transcript to correlate "um/uh" rate with stuck segments.

---

## System Design Doc

See [`InterviewFaceCoach.md`](./InterviewFaceCoach.md) for full requirements, non-functional tradeoffs, data flow, scaling, and failure modes.

---

## License

MIT — do what you want.
