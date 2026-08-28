# Interview Face Coach — System Design

## 1. Problem

During mock interviews, candidates can't see themselves. They don't know when they *look* stuck (furrowed brow, frozen mouth, gaze-away), when they look confident (smile, open eyes, eye contact), or how they came across overall. **Goal:** a real-time facial coach that classifies state live and produces a post-session report with a score and tips.

Target user: a solo interviewee practicing DSA/behavioral answers on their laptop (1 face, 1 camera, 2–15 min sessions).

## 2. Requirements

### Functional
1. Webcam capture + live face detection (≥10 FPS).
2. Per-frame expression analysis → one of: `CONFIDENT | STUCK | THINKING | ANXIOUS | NEUTRAL | NO_FACE`.
3. Live badge + confidence % + raw emotion bars.
4. Timeline chart of states over the session.
5. End-of-session report: overall score 0–100, breakdown, coaching tips, JSON + HTML export.
6. Calibration (3s neutral baseline) for brow/eye personalization.
7. Works offline after first load; no video upload.

### Non-Functional
- **Privacy:** video never leaves device (hard constraint).
- **Latency:** < 80ms per frame on a 2020 laptop (via TinyFaceDetector, 416px input).
- **Accuracy:** good-enough for coaching (precision > recall for STUCK; avoid false "confident").
- **Setup:** < 30s, zero installs (browser only).
- **Cost:** $0 infra (static hosting).

## 3. Architecture

```
                ┌──────────────────────────────────────────────────┐
  Camera ──────►│  Browser App (Single Page)                       │
 getUserMedia   │  ┌────────────┐  ┌──────────┐  ┌──────────────┐  │
                │  │face-api.js │─►│analyzer.js│─►│  app.js      │  │
                │  │ TinyFace   │  │• geometry │  │• calibration │  │
                │  │ + Landmarks│  │• emotions │  │• state FSM   │  │
                │  │ + Expr Net │  │• rules    │  │• log 2 Hz    │  │
                │  └────────────┘  └──────────┘  │• timeline    │  │
                │                                 │• score+report│  │
                │  localStorage ◄─────────────────└──────────────┘  │
                └──────────────────────────────────────────────────┘
                         │
                         │ CDN on first load only (face-api + Chart.js + models)
                         ▼
                    jsdelivr / unpkg (cached thereafter)
```

No backend. Optional `nginx:alpine` static container for `docker compose up`.

## 4. Key Decisions

| Decision | Choice | Alternative | Tradeoff |
|---|---|---|---|
| Face AI | face-api.js (3 nets, ~6 MB weights) | MediaPipe Tasks Vision (WASM, blendshapes/AUs) | face-api: simpler, 1 script tag, 7 emotions out-of-box. MediaPipe: more precise AUs but heavier swap later. |
| Detector | TinyFaceDetector (416px, scoreThreshold 0.5) | SSD Mobilenet | Tiny is 5× faster, enough for 1 frontal face |
| State logic | Rule engine + hysteresis (≥600ms) | LSTM/ML classifier | Rules are explainable, tunable, no training data needed; ML would overfit small dataset |
| Sampling | 15 FPS analysis, 2 Hz logging | Log every frame | 2 Hz keeps report small (~240 points for 2 min) and chart readable |
| Baseline | 3s neutral calibration (brow distance, EAR, mouth) | Fixed thresholds | Personalization handles glasses, face shape, camera distance |

## 5. Data Flow (per frame)

```
video frame → canvas (416px) → face-api detectSingleFace()
                                   ├─ box, 68 landmarks, 7 expressions
                                   └─► analyzer.analyze(detection, baseline)
                                         ├─ browFurrow = browEyeDist / baselineBrowEyeDist
                                         ├─ eyeOpenness = EAR / baselineEAR
                                         ├─ smileLift = (mouth corners y) + happy prob
                                         ├─ headYaw/Pitch from nose vs eye center
                                         └─ classify() → state + score + reasons
                                              └─ debounce (hysteresis) → badge + log
```

## 6. Scoring & Tips (deterministic, auditable)

See README § Scoring. Tips are rule-matched to segment stats, not LLM-generated.

## 7. Failure Modes

| Failure | Handling |
|---|---|
| No face | Show `NO_FACE` badge, don't log, prompt "Center your face" |
| Multiple faces | Use largest box (interviewee is closest) |
| Low light | TinyFace score < 0.5 → "Improve lighting" banner |
| Model load fails | Retry 2×, then show "Offline — reload when online" |
| Tab hidden | Pause analysis (`visibilitychange`) to save CPU |

## 8. Privacy

- `getUserMedia` stream → `<video>` element only; never `fetch`/`WebSocket`.
- `localStorage` key `ifc_sessions` holds only `{t, state, topEmotion, browFurrow, smile}` — no images.
- `Report` HTML is generated client-side via Blob URL.

## 9. Scale & Cost

- Static files → CDN/CloudFront $0–$1/mo at interview-prep scale.
- No auth, no DB, no GPU. CPU is client's.
- To scale to teams: add `server/` (FastAPI + Postgres) behind `POST /sessions` with opt-in upload.

## 10. Future

1. Micro-expression (AU) model via MediaPipe blendshapes.
2. Voice prosody fusion (Web Speech API → filler-word rate correlated with STUCK).
3. LLM coach: feed timeline + transcript to GPT for narrative feedback (opt-in, server-side).
4. Mobile PWA + front-camera.
