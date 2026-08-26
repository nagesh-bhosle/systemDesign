// analyzer.js — geometry + rule engine (the brain)
// Face-api gives: detection.box, landmarks (68 pts), expressions (7 probs)
// This module turns those into interview states: CONFIDENT / STUCK / THINKING / ANXIOUS / NEUTRAL

export function createAnalyzer(){
  let baseline = null; // {browEyeDist, ear, mouthOpen, mouthWidth}
  let lastState = 'NEUTRAL';
  let pendingState = null;
  let pendingSince = 0;
  const HYSTERESIS_MS = 600;

  function dist(a,b){ return Math.hypot(a.x-b.x, a.y-b.y); }

  function earForEye(pts){
    // pts: 6 points of one eye in order [p0..p5]
    const vert1 = dist(pts[1], pts[5]);
    const vert2 = dist(pts[2], pts[4]);
    const horiz = dist(pts[0], pts[3]);
    if(horiz < 1) return 0;
    return (vert1+vert2)/(2*horiz);
  }

  function computeSignals(landmarks, expressions){
    const pos = landmarks.positions; // 68 Points
    // eye centers
    const leftEye = pos.slice(36,42);
    const rightEye = pos.slice(42,48);
    const earL = earForEye(leftEye);
    const earR = earForEye(rightEye);
    const ear = (earL+earR)/2;

    // brow-eye distance (vertical): average brow y vs eye center y
    const browY = (pos[19].y + pos[24].y)/2; // midpoints of left/right brow
    const eyeY = (leftEye[1].y + leftEye[2].y + leftEye[4].y + leftEye[5].y + rightEye[1].y + rightEye[2].y + rightEye[4].y + rightEye[5].y)/8;
    // use vertical gap (positive when brow above eye)
    const browEyeDist = Math.max(4, eyeY - browY);

    // mouth geometry
    const mouthOuter = pos.slice(48,60);
    const mouthInnerTop = pos[62], mouthInnerBot = pos[66];
    const mouthOpen = dist(mouthInnerTop, mouthInnerBot);
    const mouthWidth = dist(pos[48], pos[54]);
    const mouthTension = mouthWidth > 1 ? mouthOpen / mouthWidth : 0; // small => pressed lips

    // head pose proxy: nose tip vs eye midpoint
    const eyeMid = { x:(leftEye[0].x+rightEye[3].x)/2, y:(leftEye[0].y+rightEye[0].y)/2 };
    const nose = pos[30];
    const yaw = (nose.x - eyeMid.x) / Math.max(1, mouthWidth);   // - => left, + => right
    const pitch = (nose.y - eyeMid.y) / Math.max(1, mouthWidth);
    const lookingAway = Math.abs(yaw) > 0.35 || pitch < -0.15 || pitch > 0.85;

    // smile cue: happy prob + corner lift vs mouth center
    const smileProb = expressions.happy || 0;
    const mouthCenterY = (pos[48].y + pos[54].y)/2;
    const cornerLift = mouthCenterY - (pos[51].y); // rough; positive when corners up (but use happy as primary)

    return {
      ear, earL, earR, browEyeDist, mouthOpen, mouthWidth, mouthTension,
      yaw, pitch, lookingAway, smileProb, cornerLift
    };
  }

  function classify(signals, expressions){
    const { ear, browEyeDist, mouthTension, lookingAway, smileProb } = signals;
    const { happy=0, sad=0, angry=0, fearful=0, disgusted=0, surprised=0, neutral=0 } = expressions;

    // baseline-relative ratios (neutral => 1.0)
    let browRatio = 1, earRatio = 1, tensionRatio = 1;
    if(baseline){
      browRatio = baseline.browEyeDist / Math.max(1, browEyeDist); // >1 => furrowed (brows lower)
      earRatio = ear / Math.max(0.05, baseline.ear);               // >1 => wider eyes
      // mouthTension is small when pressed; compare to baseline
      tensionRatio = mouthTension / Math.max(0.02, baseline.mouthOpen/baseline.mouthWidth);
    }

    const eyeContact = !lookingAway;
    const browFurrowed = browRatio > 1.22;
    const browRelaxed = browRatio < 1.12;
    const mouthPressed = mouthTension < 0.18 || tensionRatio < 0.65;
    const wideEyes = earRatio > 1.18;

    // priority order — most distinctive first
    // ANXIOUS: fear + wide eyes
    if((fearful > 0.22 || angry > 0.25) && wideEyes){
      return { state:'ANXIOUS', why:`fear/angry + wide eyes` };
    }
    // CONFIDENT: happy + relaxed brow + eye contact (strict to avoid false positive)
    if(happy > 0.35 && browRelaxed && eyeContact && neutral < 0.6){
      return { state:'CONFIDENT', why:`happy ${(happy*100)|0}% + relaxed` };
    }
    // STUCK: brow furrow OR fear/sad/surprise + mouth press/gaze away/long neutral
    const stuckEmotion = fearful > 0.24 || sad > 0.30 || surprised > 0.38;
    if((stuckEmotion || browFurrowed) && (mouthPressed || lookingAway || neutral > 0.45)){
      return { state:'STUCK', why: browFurrowed ? `brow furrow ×${browRatio.toFixed(2)}` : `emotion stuck` };
    }
    // THINKING: neutral dominant + pressed lips + not furrowed + generally looking at camera
    if(neutral > 0.42 && mouthPressed && !browFurrowed){
      return { state:'THINKING', why:`neutral + lip press` };
    }
    // ANXIOUS fallback: disgust/surprise with tension
    if((disgusted > 0.28 || surprised > 0.3) && mouthPressed){
      return { state:'ANXIOUS', why:`tense` };
    }
    return { state:'NEUTRAL', why:`baseline` };
  }

  function debounce(raw){
    const now = performance.now();
    if(raw === lastState) { pendingState=null; return lastState; }
    if(pendingState !== raw){ pendingState = raw; pendingSince = now; return lastState; }
    if(now - pendingSince >= HYSTERESIS_MS){
      lastState = raw;
      pendingState = null;
      return lastState;
    }
    return lastState;
  }

  return {
    get baseline(){ return baseline; },
    isCalibrated(){ return !!baseline; },
    reset(){ baseline=null; lastState='NEUTRAL'; pendingState=null; },

    // Call over ~3s of neutral face frames to set personal baseline
    calibrate(samples){
      if(!samples.length) return null;
      const avg = (arr, k) => arr.reduce((s,x)=>s+x[k],0)/arr.length;
      baseline = {
        browEyeDist: avg(samples,'browEyeDist'),
        ear: avg(samples,'ear'),
        mouthOpen: avg(samples,'mouthOpen'),
        mouthWidth: avg(samples,'mouthWidth'),
      };
      lastState='NEUTRAL';
      return baseline;
    },

    analyze(detection){
      if(!detection){
        const s='NO_FACE';
        const out = debounce(s);
        return { state: out, raw:s, signals:null, expressions:null, why:'no face' };
      }
      const expressions = detection.expressions;
      const signals = computeSignals(detection.landmarks, expressions);
      const { state:raw, why } = classify(signals, expressions);
      const state = debounce(raw);
      // confidence for badge (happy when confident, otherwise top emotion)
      const top = Object.entries(expressions).sort((a,b)=>b[1]-a[1])[0];
      return { state, raw, signals, expressions, top, why };
    },

    // for tests / tuning
    _computeSignals: computeSignals,
    _classify: classify,
  };
}
