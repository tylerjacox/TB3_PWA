(function() {
  'use strict';

  var NAMESPACE = 'urn:x-cast:com.tb3.workout';
  var restInterval = null;
  var clockOffset = 0; // sender time - local time

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
    stopRestTimer();
  }

  function renderWorkout(d) {
    document.getElementById('idle').classList.add('hidden');
    document.getElementById('workout').classList.remove('hidden');

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

    // Rest timer
    if (d.restTimer && d.restTimer.running && d.restTimer.targetEndTime) {
      clockOffset = d.restTimer.serverTimeNow - Date.now();
      startRestTimer(d.restTimer.targetEndTime);
    } else {
      stopRestTimer();
    }
  }

  // --- Barbell / Plate Diagram ---
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

  function plateDiv(weight) {
    var h = Math.round((PLATE_HEIGHT[weight] || 50) / 100 * MAX_PLATE_H);
    var w = PLATE_WIDTH[weight] || 8;
    var color = PLATE_COLORS[weight] || '#888';
    return '<div class="barbell-plate" style="height:' + h + 'px;width:' + w + 'px;background:' + color + '"></div>';
  }

  function startRestTimer(targetEndTime) {
    stopRestTimer();
    var el = document.getElementById('restTimer');
    var timeEl = document.getElementById('restTime');
    el.classList.add('active');

    function tick() {
      var now = Date.now() + clockOffset;
      var remaining = Math.max(0, targetEndTime - now);
      var mins = Math.floor(remaining / 60000);
      var secs = Math.floor((remaining % 60000) / 1000);
      timeEl.textContent = mins + ':' + (secs < 10 ? '0' : '') + secs;
      if (remaining <= 0) {
        stopRestTimer();
      }
    }

    tick();
    restInterval = setInterval(tick, 250);
  }

  function stopRestTimer() {
    if (restInterval) {
      clearInterval(restInterval);
      restInterval = null;
    }
    document.getElementById('restTimer').classList.remove('active');
  }

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
})();
