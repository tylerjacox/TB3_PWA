(function() {
  'use strict';

  var NAMESPACE = 'urn:x-cast:com.tb3.workout';
  var timerInterval = null;
  var clockOffset = 0; // sender time - local time
  var sessionStartedAt = null; // ISO string from sender
  var currentTimerPhase = null; // track phase for sync diffing
  var currentTimerStartedAt = null; // local startedAt for drift detection

  // --- Audio Feedback (matches feedback.ts) ---
  var audioCtx = null;

  function getAudioCtx() {
    if (!audioCtx) audioCtx = new AudioContext();
    return audioCtx;
  }

  function playTones(tones) {
    try {
      var ctx = getAudioCtx();
      if (ctx.state === 'suspended') ctx.resume();
      var now = ctx.currentTime;
      for (var i = 0; i < tones.length; i++) {
        var t = tones[i];
        var osc = ctx.createOscillator();
        var gain = ctx.createGain();
        var start = now + t.delay / 1000;
        var dur = t.dur / 1000;
        osc.type = 'sine';
        osc.frequency.value = t.freq;
        gain.gain.setValueAtTime(0.5, start);
        gain.gain.exponentialRampToValueAtTime(0.001, start + dur);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(start);
        osc.stop(start + dur);
      }
    } catch (e) { /* Audio may not be available */ }
  }

  function soundSetComplete() {
    playTones([{freq:660, dur:120, delay:0}, {freq:880, dur:160, delay:120}]);
  }
  function soundExerciseComplete() {
    playTones([{freq:784, dur:200, delay:0}, {freq:1047, dur:250, delay:200}, {freq:1319, dur:300, delay:450}]);
  }
  function soundRestComplete() {
    // Bold ascending "Go" signal — no speech synthesis on Chromecast
    playTones([
      {freq:523, dur:200, delay:0}, {freq:659, dur:200, delay:200},
      {freq:784, dur:200, delay:400}, {freq:1047, dur:300, delay:600}
    ]);
  }
  function soundSessionComplete() {
    playTones([{freq:523, dur:250, delay:0}, {freq:659, dur:250, delay:250}, {freq:784, dur:300, delay:500}]);
  }

  // --- Countdown Milestone Tones (replaces speechSynthesis — not available on Chromecast) ---
  // Each milestone has a distinct tone pattern so the user can recognize the countdown
  var MILESTONE_TONES = {
    60: [{freq:440, dur:300, delay:0}],                                       // A4 — single attention tone
    30: [{freq:440, dur:200, delay:0}, {freq:440, dur:200, delay:300}],       // A4 x2 — double beep
    15: [{freq:440, dur:150, delay:0}, {freq:440, dur:150, delay:200}, {freq:440, dur:150, delay:400}], // A4 x3 — triple beep
    5:  [{freq:880, dur:150, delay:0}],                                       // A5 — high beep
    4:  [{freq:932, dur:150, delay:0}],                                       // Bb5
    3:  [{freq:988, dur:150, delay:0}],                                       // B5
    2:  [{freq:1047, dur:150, delay:0}],                                      // C6
    1:  [{freq:1175, dur:200, delay:0}]                                       // D6 — highest, longest
  };

  function playMilestone(sec) {
    var tones = MILESTONE_TONES[sec];
    if (tones) playTones(tones);
  }

  // --- State Tracking (for event detection) ---
  var prevCompletedSets = -1;
  var prevExerciseIndex = -1;
  var prevTotalSets = 0;
  var lastAnnouncedSecond = null;
  var restCompleteFired = false;

  // Competition plate colors (matches PlateDisplay.tsx)
  var PLATE_COLORS = {
    45: '#C62828', 35: '#F9A825', 25: '#7B1FA2',
    10: '#E65100', 5: '#42A5F5', 2.5: '#66BB6A', 1.25: '#EEEEEE'
  };

  // Plate height as % of max (45 = 100%), scaled to TV size
  var PLATE_HEIGHT = { 45: 100, 35: 88, 25: 76, 10: 58, 5: 46, 2.5: 38, 1.25: 32 };

  // Plate thickness in px for barbell view (scaled up for TV)
  var PLATE_WIDTH = { 45: 16, 35: 14, 25: 12, 10: 10, 5: 8, 2.5: 6, 1.25: 5 };

  var MAX_PLATE_H = 72; // max plate height in px for TV

  // Belt plate dimensions (scaled up for TV)
  var BELT_PLATE_W = { 45: 60, 35: 54, 25: 48, 10: 40, 5: 34, 2.5: 28, 1.25: 24 };
  var BELT_PLATE_H = { 45: 14, 35: 13, 25: 12, 10: 10, 5: 8, 2.5: 6, 1.25: 5 };

  // --- Clock ---
  function formatTime(date) {
    var h = date.getHours();
    var m = date.getMinutes();
    var ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12 || 12;
    var s = date.getSeconds();
    return h + ':' + (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s + ' ' + ampm;
  }

  function formatElapsed(ms) {
    var totalSecs = Math.floor(ms / 1000);
    var h = Math.floor(totalSecs / 3600);
    var m = Math.floor((totalSecs % 3600) / 60);
    var s = totalSecs % 60;
    return h + ':' + (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
  }

  function updateClock() {
    var now = new Date();
    var text = formatTime(now);
    var headerClock = document.getElementById('clock');
    var idleClock = document.getElementById('idleClock');
    if (headerClock) headerClock.textContent = text;
    if (idleClock) idleClock.textContent = text;

    // Session elapsed timer
    var elapsedEl = document.getElementById('sessionElapsed');
    if (elapsedEl && sessionStartedAt) {
      var elapsed = Date.now() - new Date(sessionStartedAt).getTime();
      elapsedEl.textContent = formatElapsed(Math.max(0, elapsed));
    }
  }

  updateClock();
  setInterval(updateClock, 1000);

  // --- Start Receiver ---
  var context = cast.framework.CastReceiverContext.getInstance();

  context.addCustomMessageListener(NAMESPACE, function(event) {
    try {
      var data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
      if (data.idle) {
        showIdle();
      } else {
        renderWorkout(data);
      }
    } catch (e) {
      console.error('Cast message parse error:', e);
    }
  });

  var options = new cast.framework.CastReceiverOptions();
  options.disableIdleTimeout = true;
  context.start(options);

  // --- Render ---
  function showIdle() {
    document.getElementById('idle').classList.remove('hidden');
    document.getElementById('workout').classList.add('hidden');
    sessionStartedAt = null;
    prevCompletedSets = -1;
    prevExerciseIndex = -1;
    prevTotalSets = 0;
    currentTimerPhase = null;
    currentTimerStartedAt = null;
    stopTimer();
  }

  function renderWorkout(d) {
    document.getElementById('idle').classList.add('hidden');
    document.getElementById('workout').classList.remove('hidden');

    // Session start time
    if (d.startedAt) sessionStartedAt = d.startedAt;

    // Header
    document.getElementById('weekSession').textContent =
      'Week ' + d.week + ' \u2014 Session ' + d.session;
    document.getElementById('templateName').textContent =
      d.templateId.replace(/-/g, ' ').replace(/\b\w/g, function(c) { return c.toUpperCase(); });

    // Exercise
    document.getElementById('exerciseName').textContent = d.exerciseName;
    document.getElementById('weightValue').textContent = d.weight;
    document.getElementById('weightUnit').textContent = d.unit;

    // Plate diagram
    renderPlates(d.plates || [], d.isBodyweight);

    // Reps
    var allDone = d.completedSets >= d.totalSets;
    document.getElementById('reps').textContent = allDone
      ? 'All sets complete'
      : '\u00D7 ' + d.targetReps + ' reps';

    // Set dots
    var dotsHtml = '';
    for (var i = 0; i < d.totalSets; i++) {
      var cls = 'set-dot';
      if (i < d.completedSets) cls += ' completed';
      else if (i === d.completedSets) cls += ' current';
      dotsHtml += '<div class="' + cls + '"></div>';
    }
    document.getElementById('setDots').innerHTML = dotsHtml;

    // Exercise progress
    var progHtml = '';
    for (var j = 0; j < d.exercises.length; j++) {
      var ex = d.exercises[j];
      var pct = ex.totalSets > 0 ? Math.round((ex.completedSets / ex.totalSets) * 100) : 0;
      var pipCls = 'ex-pip';
      if (j === d.currentExerciseIndex) pipCls += ' current';
      if (pct === 100) pipCls += ' done';
      progHtml += '<div class="' + pipCls + '">' +
        '<div class="ex-pip-name">' + escapeHtml(ex.name) + '</div>' +
        '<div class="ex-pip-bar"><div class="ex-pip-fill" style="width:' + pct + '%"></div></div>' +
        '</div>';
    }
    document.getElementById('exerciseProgress').innerHTML = progHtml;

    // Now Playing (Spotify)
    renderNowPlaying(d.nowPlaying);

    // --- Audio event detection (compare to previous state) ---
    if (prevCompletedSets >= 0) {
      // Check if exercise index changed (reset tracking for new exercise)
      if (d.currentExerciseIndex !== prevExerciseIndex) {
        // Exercise changed — reset set tracking, no sound
        prevCompletedSets = d.completedSets;
      } else if (d.completedSets > prevCompletedSets) {
        // Sets increased — determine which event
        var allExercisesDone = d.exercises.every(function(ex) {
          return ex.completedSets >= ex.totalSets;
        });

        if (allExercisesDone) {
          soundSessionComplete();
        } else if (d.completedSets >= d.totalSets) {
          soundExerciseComplete();
        } else {
          soundSetComplete();
        }
      }
    }
    prevCompletedSets = d.completedSets;
    prevExerciseIndex = d.currentExerciseIndex;
    prevTotalSets = d.totalSets;

    // Two-phase timer (with periodic sync drift correction)
    if (d.timer && d.timer.phase) {
      if (d.timer.elapsedMs !== undefined) {
        var newStartedAt = Date.now() - d.timer.elapsedMs;

        // Only reset timer if phase changed or drift exceeds 1 second
        // This prevents visual jumps on periodic sync when already in sync
        if (d.timer.phase !== currentTimerPhase ||
            currentTimerStartedAt === null ||
            Math.abs(newStartedAt - currentTimerStartedAt) > 1000) {
          d.timer.startedAt = newStartedAt;
          currentTimerPhase = d.timer.phase;
          currentTimerStartedAt = newStartedAt;
          clockOffset = 0;
          updateTimer(d.timer);
        }
      } else {
        clockOffset = d.timer.serverTimeNow - Date.now();
        currentTimerPhase = d.timer.phase;
        currentTimerStartedAt = d.timer.startedAt;
        updateTimer(d.timer);
      }
    } else {
      currentTimerPhase = null;
      currentTimerStartedAt = null;
      stopTimer();
    }
  }

  // --- Barbell / Belt / Plate Diagram ---
  function renderPlates(plates, isBodyweight) {
    var el = document.getElementById('plateDiagram');
    if (!plates || plates.length === 0) {
      el.innerHTML = '';
      return;
    }

    // Expand grouped plates into individual entries
    var expanded = [];
    for (var i = 0; i < plates.length; i++) {
      for (var j = 0; j < plates[i].count; j++) {
        expanded.push(plates[i].weight);
      }
    }

    var label = isBodyweight ? 'on belt' : 'per side';
    var html = '<div class="barbell-diagram">';

    if (isBodyweight) {
      // Belt visual: chain → plates stacked vertically → pin
      html += '<div class="belt-visual">';
      html += '<div class="belt-chain"></div>';
      html += '<div class="belt-plates">';
      for (var b = 0; b < expanded.length; b++) {
        html += beltPlateDiv(expanded[b]);
      }
      html += '</div>';
      html += '<div class="belt-pin"></div>';
      html += '</div>';
    } else {
      // Barbell visual
      html += '<div class="barbell-visual">';

      // Left plates (reversed — heaviest near collar)
      html += '<div class="barbell-plates">';
      for (var k = expanded.length - 1; k >= 0; k--) {
        html += plateDiv(expanded[k]);
      }
      html += '</div>';

      // Collar + bar + collar
      html += '<div class="barbell-collar"></div>';
      html += '<div class="barbell-bar"></div>';
      html += '<div class="barbell-collar"></div>';

      // Right plates
      html += '<div class="barbell-plates">';
      for (var m = 0; m < expanded.length; m++) {
        html += plateDiv(expanded[m]);
      }
      html += '</div>';
      html += '</div>';
    }

    // Summary legend
    html += '<div class="plate-summary">';
    for (var n = 0; n < plates.length; n++) {
      var p = plates[n];
      var color = PLATE_COLORS[p.weight] || '#888';
      var text = p.count > 1 ? p.weight + ' x' + p.count : '' + p.weight;
      html += '<span class="plate-label">' +
        '<span class="plate-dot" style="background:' + color + '"></span>' +
        text + '</span>';
    }
    html += '<span class="plate-per-side">' + label + '</span>';
    html += '</div>';

    html += '</div>';
    el.innerHTML = html;
  }

  function beltPlateDiv(weight) {
    var w = BELT_PLATE_W[weight] || 36;
    var h = BELT_PLATE_H[weight] || 8;
    var color = PLATE_COLORS[weight] || '#888';
    return '<div class="belt-plate" style="width:' + w + 'px;height:' + h + 'px;background:' + color + '"></div>';
  }

  function plateDiv(weight) {
    var h = Math.round((PLATE_HEIGHT[weight] || 50) / 100 * MAX_PLATE_H);
    var w = PLATE_WIDTH[weight] || 8;
    var color = PLATE_COLORS[weight] || '#888';
    return '<div class="barbell-plate" style="height:' + h + 'px;width:' + w + 'px;background:' + color + '"></div>';
  }

  function formatTimerMs(ms) {
    var totalSecs = Math.floor(ms / 1000);
    var mins = Math.floor(totalSecs / 60);
    var secs = totalSecs % 60;
    return mins + ':' + (secs < 10 ? '0' : '') + secs;
  }

  function updateTimer(timer) {
    stopTimer();

    // Reset voice/sound tracking for new timer
    lastAnnouncedSecond = null;
    restCompleteFired = false;

    var el = document.getElementById('restTimer');
    var timeEl = document.getElementById('restTime');
    var labelEl = document.getElementById('timerLabel');

    el.classList.add('active');
    el.classList.remove('overtime', 'exercise-phase');

    if (timer.phase === 'rest') {
      labelEl.textContent = 'Rest';
      var restMs = (timer.restDurationSeconds || 0) * 1000;

      function tickRest() {
        var now = Date.now() + clockOffset;
        var elapsed = Math.max(0, now - timer.startedAt);
        var isOvertime = restMs > 0 && elapsed >= restMs;

        timeEl.textContent = formatTimerMs(elapsed);

        if (isOvertime) {
          el.classList.add('overtime');
          // "Go" feedback at overtime threshold (once)
          if (!restCompleteFired) {
            restCompleteFired = true;
            soundRestComplete();
          }
        } else {
          el.classList.remove('overtime');
          // Tone milestones (countdown to overtime)
          if (restMs > 0) {
            var remainingMs = restMs - elapsed;
            if (remainingMs > 0) {
              var sec = Math.ceil(remainingMs / 1000);
              if (sec !== lastAnnouncedSecond && MILESTONE_TONES[sec]) {
                lastAnnouncedSecond = sec;
                playMilestone(sec);
              }
            }
          }
        }
      }

      tickRest();
      timerInterval = setInterval(tickRest, 250);

    } else if (timer.phase === 'exercise') {
      labelEl.textContent = 'Exercise Time';
      el.classList.add('exercise-phase');

      function tickExercise() {
        var now = Date.now() + clockOffset;
        var elapsed = Math.max(0, now - timer.startedAt);
        timeEl.textContent = formatTimerMs(elapsed);
      }

      tickExercise();
      timerInterval = setInterval(tickExercise, 250);
    }
  }

  function stopTimer() {
    if (timerInterval) {
      clearInterval(timerInterval);
      timerInterval = null;
    }
    var el = document.getElementById('restTimer');
    el.classList.remove('active', 'overtime', 'exercise-phase');
  }

  function renderNowPlaying(np) {
    var el = document.getElementById('nowPlaying');
    if (!np || !np.trackName) {
      el.classList.remove('active');
      return;
    }
    el.classList.add('active');
    document.getElementById('nowPlayingTrack').textContent = np.trackName;
    document.getElementById('nowPlayingArtist').textContent = np.artistName || '';
  }

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
})();
