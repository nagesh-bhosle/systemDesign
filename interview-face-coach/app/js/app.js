import { createAnalyzer } from './analyzer.js';

const $ = s => document.querySelector(s);
const els = {
  video: $('#video'), overlay: $('#overlay'),
  modelStatus: $('#modelStatus'), cameraStatus: $('#cameraStatus'),
  btnCamera: $('#btnCamera'), btnCalibrate: $('#btnCalibrate'), btnStart: $('#btnStart'), btnEnd: $('#btnEnd'), btnReset: $('#btnReset'),
  stateBadge: $('#stateBadge'), noFaceHint: $('#noFaceHint'),
  statState: $('#statState'), statScore: $('#statScore'), statEyeContact: $('#statEyeContact'), statFps: $('#statFps'),
  calibProgress: $('#calibProgress'), calibText: $('#calibText'),
  emotionBars: $('#emotionBars'),
  sigBrow: $('#sigBrow'), sigSmile: $('#sigSmile'), sigEar: $('#sigEar'), sigMouth: $('#sigMouth'), sigHead: $('#sigHead'), sigTop: $('#sigTop'),
  barBrow: $('#barBrow'), barSmile: $('#barSmile'), barEar: $('#barEar'), barMouth: $('#barMouth'),
  timelineChart: $('#timelineChart'), sessionTime: $('#sessionTime'), sessionSamples: $('#sessionSamples'), faceStatus: $('#faceStatus'),
  rawLog: $('#rawLog'),
  report: $('#report'), reportScore: $('#reportScore'), reportVerdict: $('#reportVerdict'), reportSummary: $('#reportSummary'),
  barConf: $('#barConf'), barComp: $('#barComp'), barEng: $('#barEng'),
  valConf: $('#valConf'), valComp: $('#valComp'), valEng: $('#valEng'),
  reportTable: $('#reportTable'), reportTips: $('#reportTips'), reportGood: $('#reportGood'), reportChart: $('#reportChart'),
  btnDownloadJson: $('#btnDownloadJson'), btnDownloadHtml: $('#btnDownloadHtml'), btnCloseReport: $('#btnCloseReport'),
  clearStorage: $('#clearStorage'), toast: $('#toast'),
};

const analyzer = createAnalyzer();
let stream = null;
let modelsLoaded = false;
let calibrating = false;
let calibSamples = [];
let session = null; // {startAt, log:[], timer}
let rafId = null;
let lastDetectMs = 0;
let fpsSmooth = 0, lastFpsAt = performance.now(), frames = 0;
let timelineChart = null, reportChart = null;
let lastLogAt = 0;

// ---------- helpers ----------
function toast(msg, ms=2600){
  els.toast.textContent = msg;
  els.toast.classList.remove('hidden');
  setTimeout(()=> els.toast.classList.add('hidden'), ms);
}
function fmtTime(s){ const m=String(Math.floor(s/60)).padStart(2,'0'); const ss=String(Math.floor(s%60)).padStart(2,'0'); return m+':'+ss; }

const EMOTIONS = ['neutral','happy','sad','angry','fearful','disgusted','surprised'];
function ensureEmotionBars(){
  if(els.emotionBars.children.length) return;
  for(const e of EMOTIONS){
    const row = document.createElement('div');
    row.className='ebar';
    row.innerHTML = `<label>${e}</label><div class="track"><div class="fill" id="fill-${e}"></div></div><b id="val-${e}">0%</b>`;
    els.emotionBars.appendChild(row);
  }
}
function setEmotionBars(expressions){
  if(!expressions) return;
  for(const e of EMOTIONS){
    const v = expressions[e] ?? 0;
    const fill = document.getElementById('fill-'+e);
    const val = document.getElementById('val-'+e);
    if(fill) fill.style.width = (v*100).toFixed(0)+'%';
    if(val) val.textContent = (v*100).toFixed(0)+'%';
    if(fill){
      // tint happy green, others accent
      fill.style.background = e==='happy' ? '#2ecc71' : e==='neutral' ? '#64748b' : e==='fearful' ? '#9b59b6' : '#5b8def';
    }
  }
}

function setBadge(state){
  const map = {
    CONFIDENT:'confident', STUCK:'stuck', THINKING:'thinking', ANXIOUS:'anxious', NEUTRAL:'neutral', NO_FACE:'noface'
  };
  els.stateBadge.textContent = state;
  els.stateBadge.className = 'badge ' + (map[state]||'neutral');
  els.statState.textContent = state;
  els.statState.style.color = state==='CONFIDENT' ? 'var(--conf)' : state==='STUCK' ? 'var(--stuck)' : state==='THINKING' ? 'var(--think)' : state==='ANXIOUS' ? 'var(--anx)' : 'var(--text)';
}

function resizeOverlay(){
  const rect = els.video.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  els.overlay.width = rect.width * dpr;
  els.overlay.height = rect.height * dpr;
  els.overlay.style.width = rect.width+'px';
  els.overlay.style.height = rect.height+'px';
}

// ---------- models ----------
async function loadModels(){
  els.modelStatus.textContent = 'Models: loading…';
  // Try multiple CDNs — face-api weights are ~6MB total
  const bases = [
    'https://cdn.jsdelivr.net/npm/face-api.js@0.22.2/weights',
    'https://justadudewhohacks.github.io/face-api.js/models',
    'https://cdn.jsdelivr.net/gh/justadudewhohacks/face-api.js@master/weights',
  ];
  let lastErr;
  for(const base of bases){
    try{
      await Promise.all([
        faceapi.nets.tinyFaceDetector.loadFromUri(base),
        faceapi.nets.faceLandmark68Net.loadFromUri(base),
        faceapi.nets.faceExpressionNet.loadFromUri(base),
      ]);
      modelsLoaded = true;
      els.modelStatus.textContent = 'Models: ready ✓';
      els.modelStatus.style.color = '#a7f3d0';
      els.modelStatus.style.borderColor = '#2ecc71';
      toast('Models loaded');
      return;
    }catch(e){ lastErr=e; }
  }
  els.modelStatus.textContent = 'Models: failed — reload when online';
  els.modelStatus.style.color = '#fecaca';
  console.error('Model load failed', lastErr);
  toast('Model load failed — check network and reload');
}

// ---------- camera ----------
async function enableCamera(){
  try{
    stream = await navigator.mediaDevices.getUserMedia({ video:{ width: {ideal: 640}, height:{ideal:480}, facingMode:'user'}, audio:false });
    els.video.srcObject = stream;
    await els.video.play();
    els.cameraStatus.textContent = 'Camera: on ✓';
    els.cameraStatus.style.color = '#a7f3d0';
    els.btnCalibrate.disabled = !modelsLoaded;
    els.btnStart.disabled = false;
    resizeOverlay();
    window.addEventListener('resize', resizeOverlay);
    // start loop even before session, for live preview/badge
    if(!rafId) loop();
    toast('Camera on — calibrate with a neutral face');
  }catch(e){
    console.error(e);
    toast('Camera blocked — allow webcam permission');
    els.cameraStatus.textContent = 'Camera: blocked';
  }
}

// ---------- calibration ----------
async function calibrate(){
  if(!modelsLoaded || !stream) return;
  calibrating = true;
  calibSamples = [];
  els.btnCalibrate.disabled = true;
  els.calibText.textContent = 'Calibrating… keep neutral';
  els.calibProgress.style.width = '0%';
  const started = performance.now();
  const DUR = 3000;
  const tick = setInterval(()=> {
    const p = Math.min(1, (performance.now()-started)/DUR);
    els.calibProgress.style.width = (p*100)+'%';
    if(p>=1) clearInterval(tick);
  }, 60);
  // collect samples for DUR
  await new Promise(r=> setTimeout(r, DUR));
  const baseline = analyzer.calibrate(calibSamples);
  calibrating = false;
  els.btnCalibrate.disabled = false;
  if(baseline){
    els.calibText.textContent = `Calibrated ✓ (brow ${baseline.browEyeDist.toFixed(1)} · EAR ${baseline.ear.toFixed(2)})`;
    toast('Calibrated — baseline saved');
  } else {
    els.calibText.textContent = 'Calibration failed — try again with face centered';
    toast('No face during calibration');
  }
}

// ---------- session ----------
function startSession(){
  if(!stream){ toast('Enable camera first'); return; }
  session = { startAt: Date.now(), log: [] };
  els.btnStart.disabled = true;
  els.btnEnd.disabled = false;
  els.btnCalibrate.disabled = true;
  els.report.classList.add('hidden');
  lastLogAt = 0;
  // session timer
  session.timer = setInterval(()=> {
    const s = (Date.now()-session.startAt)/1000;
    els.sessionTime.textContent = fmtTime(s);
  }, 250);
  toast('Session started — answer a question out loud');
}

function endSession(){
  if(!session) return;
  clearInterval(session.timer);
  els.btnStart.disabled = false;
  els.btnEnd.disabled = true;
  els.btnCalibrate.disabled = false;
  const duration = (Date.now()-session.startAt)/1000;
  const report = buildReport(session.log, duration);
  showReport(report, session.log);
  // persist
  try{
    const key='ifc_sessions';
    const all = JSON.parse(localStorage.getItem(key)||'[]');
    all.push({ at: new Date().toISOString(), duration, log: session.log, report });
    localStorage.setItem(key, JSON.stringify(all.slice(-20)));
  }catch{}
  toast('Session ended — report ready');
}

function resetAll(){
  if(session) clearInterval(session.timer);
  session = null;
  analyzer.reset();
  els.calibText.textContent = 'Not calibrated';
  els.calibProgress.style.width='0%';
  els.sessionTime.textContent='00:00';
  els.sessionSamples.textContent='0 samples';
  els.rawLog.textContent='—';
  setBadge('NEUTRAL');
  els.report.classList.add('hidden');
  if(timelineChart){ timelineChart.data.labels=[]; timelineChart.data.datasets[0].data=[]; timelineChart.update(); }
}

// ---------- scoring & report ----------
function buildReport(log, duration){
  const n = log.length || 1;
  const counts = { CONFIDENT:0, STUCK:0, THINKING:0, ANXIOUS:0, NEUTRAL:0, NO_FACE:0 };
  let eyeContact = 0, tops = {};
  for(const p of log){ counts[p.state]=(counts[p.state]||0)+1; if(p.eyeContact) eyeContact++; tops[p.topEmotion]=(tops[p.topEmotion]||0)+1; }
  const pct = k => (counts[k]/n*100);
  const confidence = pct('CONFIDENT');
  const composure = 100 - pct('STUCK') - pct('ANXIOUS')*0.5;
  const engagement = n ? (eyeContact/n*100) : 0;
  const total = Math.max(0, Math.min(100, Math.round(confidence*0.4 + Math.max(0,composure)*0.3 + engagement*0.3)));
  let verdict='', level='';
  if(total>=90){ verdict='Excellent — you look confident and composed'; level='Excellent'; }
  else if(total>=70){ verdict='Good — solid presence, minor stuck moments'; level='Good'; }
  else if(total>=50){ verdict='Average — reviewers would notice hesitation'; level='Average'; }
  else { verdict='Needs practice — visible stuck/anxious segments'; level='Needs practice'; }

  const tips=[], good=[];
  if(pct('STUCK')>25) tips.push('You looked stuck >25% of the time. Practice structured pauses: say “Let me think through this aloud…” instead of freezing. Rehearse 2–3 cold-start sentences.');
  else if(pct('STUCK')>12) tips.push('A few stuck moments — try box-breathing (4-4-4) before answering and keep your forehead relaxed.');
  if(engagement<60) tips.push('Eye contact was low. Pick a point just above the lens and return to it after glancing away. Avoid looking down when thinking.');
  if(pct('ANXIOUS')>12) tips.push('Anxious signals detected (wide eyes / tension). Slow your pace 15% and take one deliberate pause per answer.');
  if(pct('THINKING')>40) tips.push('Long thinking segments — narrate your thought process so silence doesn’t read as stuck.');
  if(!tips.length) tips.push('Nice balance — keep doing timed mock rounds to lock this in.');

  if(confidence>30) good.push(`Confident segments ${confidence.toFixed(0)}% — strong smile + relaxed brow moments.`);
  if(engagement>70) good.push(`Good eye contact ${engagement.toFixed(0)}% — keeps interviewer engaged.`);
  if(pct('NEUTRAL')>30 && pct('STUCK')<10) good.push('Composed neutral baseline — you don’t over-express, which reads as steady.');

  const topEmotion = Object.entries(tops).sort((a,b)=>b[1]-a[1])[0]?.[0] || 'neutral';
  return { total, level, verdict, confidence, composure: Math.max(0,composure), engagement, pct, counts, n, duration, topEmotion, tips, good };
}

function showReport(report, log){
  els.report.classList.remove('hidden');
  els.reportScore.textContent = report.total;
  els.reportVerdict.textContent = `${report.level} · ${report.total}/100`;
  els.reportSummary.textContent = report.verdict + ` · ${report.n} samples over ${report.duration.toFixed(0)}s · dominant emotion: ${report.topEmotion}`;
  // ring
  const ring = document.querySelector('.score-ring');
  const deg = report.total/100*360;
  ring.style.background = `conic-gradient(var(--accent) ${deg}deg, #20304a ${deg}deg)`;
  // breakdown bars
  els.barConf.style.width = report.confidence.toFixed(0)+'%';
  els.barComp.style.width = Math.max(0,report.composure).toFixed(0)+'%';
  els.barEng.style.width = report.engagement.toFixed(0)+'%';
  els.valConf.textContent = report.confidence.toFixed(0)+'%';
  els.valComp.textContent = Math.max(0,report.composure).toFixed(0)+'%';
  els.valEng.textContent = report.engagement.toFixed(0)+'%';
  // table
  const rows = ['CONFIDENT','STUCK','THINKING','ANXIOUS','NEUTRAL','NO_FACE'].map(k=> `<tr><td>${k}</td><td>${report.counts[k]||0}</td><td>${(report.pct(k)).toFixed(1)}%</td></tr>`).join('');
  els.reportTable.innerHTML = `<tr><th>State</th><th>Count</th><th>%</th></tr>`+rows;
  els.reportTips.innerHTML = report.tips.map(t=>`<li>${t}</li>`).join('');
  els.reportGood.innerHTML = report.good.map(t=>`<li>${t}</li>`).join('');
  // chart
  const labels = log.map((_,i)=> String(i));
  const stateToNum = { CONFIDENT:4, NEUTRAL:3, THINKING:2, ANXIOUS:1, STUCK:0, NO_FACE:0 };
  const data = log.map(p=> stateToNum[p.state] ?? 3);
  const color = log.map(p=> p.state==='CONFIDENT' ? '#2ecc71' : p.state==='STUCK' ? '#e74c3c' : p.state==='THINKING' ? '#f39c12' : p.state==='ANXIOUS' ? '#9b59b6' : '#64748b');
  if(reportChart) reportChart.destroy();
  reportChart = new Chart(els.reportChart, {
    type:'line',
    data:{ labels, datasets:[{ data, borderColor:'#5b8def', backgroundColor:'rgba(91,141,239,.18)', fill:true, tension:.25, pointRadius:0, borderWidth:1.5 }]},
    options:{ responsive:true, plugins:{legend:{display:false}}, scales:{ y:{ min:0,max:4, ticks:{ callback:v=>['STUCK','ANXIOUS','THINKING','NEUTRAL','CONFIDENT'][v]||v }}, x:{ display:false } } }
  });
  els.report.scrollIntoView({ behavior:'smooth' });

  // wire downloads
  els.btnDownloadJson.onclick = ()=> {
    const blob = new Blob([JSON.stringify({ report, log }, null, 2)], {type:'application/json'});
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href=url; a.download=`interview-face-coach-${Date.now()}.json`; a.click(); URL.revokeObjectURL(url);
  };
  els.btnDownloadHtml.onclick = ()=> {
    const html = `<!doctype html><meta charset="utf-8"><title>Interview Face Coach Report</title>
    <body style="font-family:system-ui;padding:24px;max-width:900px;margin:auto">
    <h1>Interview Face Coach — Report (${new Date().toLocaleString()})</h1>
    <h2>${report.level} · ${report.total}/100</h2>
    <p>${report.verdict}</p>
    <p>Samples: ${report.n} · Duration: ${report.duration.toFixed(1)}s · Confidence ${report.confidence.toFixed(0)}% · Composure ${report.composure.toFixed(0)}% · Engagement ${report.engagement.toFixed(0)}%</p>
    <h3>Breakdown</h3><pre>${JSON.stringify(report.counts,null,2)}</pre>
    <h3>Tips</h3><ul>${report.tips.map(t=>`<li>${t}</li>`).join('')}</ul>
    <h3>Good</h3><ul>${report.good.map(t=>`<li>${t}</li>`).join('')}</ul>
    <h3>Log</h3><pre style="max-height:400px;overflow:auto;background:#f6f8fa;padding:12px;border-radius:8px">${JSON.stringify(log,null,2)}</pre>
    </body>`;
    const blob = new Blob([html], {type:'text/html'});
    const url = URL.createObjectURL(blob);
    const a=document.createElement('a'); a.href=url; a.download=`report-${Date.now()}.html`; a.click(); URL.revokeObjectURL(url);
  };
}

// ---------- timeline chart (live) ----------
function ensureTimeline(){
  if(timelineChart) return;
  timelineChart = new Chart(els.timelineChart, {
    type:'line',
    data:{ labels:[], datasets:[{ data:[], borderColor:'#5b8def', backgroundColor:'rgba(91,141,239,.15)', fill:true, tension:.3, pointRadius:0, borderWidth:1.5 }]},
    options:{ responsive:true, animation:false, plugins:{legend:{display:false}}, scales:{ y:{ min:0,max:4, ticks:{ callback:v=>['STUCK','ANXIOUS','THINKING','NEUTRAL','CONFIDENT'][v]||v }}, x:{ display:false } } }
  });
}

// ---------- main loop ----------
async function loop(){
  rafId = requestAnimationFrame(loop);
  if(!modelsLoaded || !stream) return;
  if(document.hidden) return;
  const now = performance.now();
  // throttle to ~15 fps
  if(now - lastDetectMs < 66) return;
  lastDetectMs = now;

  const video = els.video;
  if(video.readyState < 2) return;
  // keep overlay size in sync
  if(els.overlay.width===0) resizeOverlay();

  let detection = null;
  try{
    detection = await faceapi
      .detectSingleFace(video, new faceapi.TinyFaceDetectorOptions({ inputSize: 416, scoreThreshold: 0.5 }))
      .withFaceLandmarks()
      .withFaceExpressions();
  }catch(e){ /* ignore frame */ }

  // draw overlay
  const ctx = els.overlay.getContext('2d');
  const dpr = window.devicePixelRatio||1;
  ctx.clearRect(0,0, els.overlay.width, els.overlay.height);
  ctx.save();
  // face-api coords are in video pixel space; map to overlay
  if(detection){
    const vw = video.videoWidth, vh = video.videoHeight;
    const ow = els.overlay.width, oh = els.overlay.height;
    const sx = ow / vw, sy = oh / vh;
    const box = detection.detection.box;
    ctx.strokeStyle = '#5b8def';
    ctx.lineWidth = 2 * dpr;
    ctx.strokeRect(box.x*sx, box.y*sy, box.width*sx, box.height*sy);
    // landmarks (small dots)
    ctx.fillStyle = 'rgba(91,141,239,.9)';
    for(const p of detection.landmarks.positions){
      ctx.beginPath(); ctx.arc(p.x*sx, p.y*sy, 1.2*dpr, 0, Math.PI*2); ctx.fill();
    }
  }
  ctx.restore();

  const result = analyzer.analyze(detection || null);
  // calibration sampling
  if(calibrating && result.signals){
    calibSamples.push(result.signals);
  }

  // UI: badge, emotions, signals
  setBadge(result.state);
  els.faceStatus.textContent = detection ? `${result.state} · ${(detection.detection.score*100)|0}% face` : 'No face';
  els.noFaceHint.classList.toggle('hidden', !!detection);
  if(result.expressions) setEmotionBars(result.expressions);
  if(result.signals){
    const s=result.signals;
    const browRatio = analyzer.baseline ? (analyzer.baseline.browEyeDist / Math.max(1,s.browEyeDist)) : 1;
    els.sigBrow.textContent = browRatio.toFixed(2)+'×';
    els.sigSmile.textContent = (s.smileProb*100).toFixed(0)+'%';
    els.sigEar.textContent = s.ear.toFixed(2);
    els.sigMouth.textContent = s.mouthTension.toFixed(2);
    els.sigHead.textContent = `${s.yaw.toFixed(2)}, ${s.pitch.toFixed(2)}` + (s.lookingAway ? ' · away' : ' · centered');
    els.sigTop.textContent = result.top ? `${result.top[0]} ${(result.top[1]*100).toFixed(0)}%` : '—';
    // mini bars (clamped 0-1-ish)
    els.barBrow.style.width = Math.min(100, Math.max(0, (browRatio-0.9)/0.6*100))+'%';
    els.barSmile.style.width = (s.smileProb*100)+'%';
    els.barEar.style.width = Math.min(100, s.ear/0.35*100)+'%';
    els.barMouth.style.width = Math.min(100, s.mouthTension/0.35*100)+'%';
    els.statEyeContact.textContent = s.lookingAway ? 'low' : 'good';
    els.statEyeContact.style.color = s.lookingAway ? '#e74c3c' : '#2ecc71';
  }

  // fps
  frames++;
  if(now - lastFpsAt > 1000){
    fpsSmooth = Math.round(frames*1000/(now-lastFpsAt));
    els.statFps.textContent = fpsSmooth;
    lastFpsAt = now; frames=0;
  }

  // session logging at 2 Hz
  if(session && now - lastLogAt > 500){
    lastLogAt = now;
    const t = (Date.now()-session.startAt)/1000;
    const entry = {
      t: Number(t.toFixed(1)),
      state: result.state,
      raw: result.raw,
      topEmotion: result.top?.[0] || 'unknown',
      topScore: result.top ? Number(result.top[1].toFixed(3)) : 0,
      browFurrow: result.signals ? Number((analyzer.baseline ? analyzer.baseline.browEyeDist/Math.max(1,result.signals.browEyeDist) : 1).toFixed(2)) : null,
      smile: result.signals ? Number(result.signals.smileProb.toFixed(3)) : null,
      eyeContact: result.signals ? !result.signals.lookingAway : false,
      why: result.why,
    };
    session.log.push(entry);
    els.sessionSamples.textContent = `${session.log.length} samples`;
    // keep last 20 for pre
    const tail = session.log.slice(-20).map(e=> `${String(e.t).padStart(5)}s  ${e.state.padEnd(9)}  ${e.topEmotion} ${(e.topScore*100).toFixed(0)}%  ${e.why}`).join('\n');
    els.rawLog.textContent = tail;
    // live chart (keep last 120 points = 60s at 2Hz)
    ensureTimeline();
    const stateToNum = { CONFIDENT:4, NEUTRAL:3, THINKING:2, ANXIOUS:1, STUCK:0, NO_FACE:0 };
    timelineChart.data.labels.push(String(entry.t));
    timelineChart.data.datasets[0].data.push(stateToNum[entry.state] ?? 3);
    if(timelineChart.data.labels.length>120){ timelineChart.data.labels.shift(); timelineChart.data.datasets[0].data.shift(); }
    timelineChart.update('none');
    // score live (rough)
    const conf = session.log.filter(x=>x.state==='CONFIDENT').length / session.log.length *100;
    const stuck = session.log.filter(x=>x.state==='STUCK').length / session.log.length *100;
    const liveScore = Math.round(conf*0.4 + (100-stuck)*0.3 + (session.log.filter(x=>x.eyeContact).length/session.log.length*100)*0.3);
    els.statScore.textContent = isFinite(liveScore) ? String(liveScore) : '—';
  }
}

// ---------- events ----------
ensureEmotionBars();
els.btnCamera.addEventListener('click', enableCamera);
els.btnCalibrate.addEventListener('click', calibrate);
els.btnStart.addEventListener('click', startSession);
els.btnEnd.addEventListener('click', endSession);
els.btnReset.addEventListener('click', resetAll);
els.btnCloseReport.addEventListener('click', ()=> els.report.classList.add('hidden'));
els.clearStorage.addEventListener('click', (e)=>{ e.preventDefault(); localStorage.removeItem('ifc_sessions'); toast('Stored sessions cleared'); });

// keyboard: space = start/end
window.addEventListener('keydown', (e)=>{
  if(e.code==='Space' && (e.target===document.body || e.target.tagName==='BUTTON')){
    e.preventDefault();
    if(!session) startSession(); else endSession();
  }
});

// init
loadModels();
resizeOverlay();
setBadge('NEUTRAL');
