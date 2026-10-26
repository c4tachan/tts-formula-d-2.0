// The track editor page. Everything it shows comes from the server's event
// stream, and every edit goes back to the server as an op: the page never
// changes the track itself, so it and Claude always see the same thing.
'use strict';

const $ = (id) => document.getElementById(id);
const svg = $('board');
const client = 'page-' + Math.random().toString(36).slice(2, 8);
const SEATS = {
  White: '#f2f2f2', Brown: '#8d5a3b', Yellow: '#ffd60a', Orange: '#ff8c1a', Green: '#2fbf4a', Teal: '#1fb5ad',
  Red: '#ff3b30', Pink: '#ff6ec7', Blue: '#2b7de9', Purple: '#9b59f6',
};
const ID_RE = /\b([imopb]\.[cs]\d+\.\d+(?:\+\d+)?)\b/g;

const S = {
  open: null, track: null, byId: {}, problems: [], flagged: new Set(), summary: null, rev: -1,
  image: null, stages: [], sel: [], hover: null, pointer: [0, 0], presence: { clients: {}, claude_listening: false },
  notes: [], messages: [], jobs: {}, tracks: [], boards: [], unsaved: [],
  view: { x: 0, y: 0, w: 1000, h: 700 }, underlay: null, mode: null, busy: false,
  watchJob: null, watchKey: null, preview: null, unread: 0, carEls: new Map(), lastClaudeSel: '',
};

// Server -----------------------------------------------------------------------

async function api(method, path, body) {
  const r = await fetch(path, {
    method, headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
}

async function act(path, body) {
  try {
    return await api('POST', path, { author: 'user', ...(body || {}) });
  } catch (e) {
    toast(e.message, true);
    return null;
  }
}

const ops = (list) => (list.length ? act('/api/op', { ops: list }) : null);
const idOf = (key) => (S.byId[key] ? S.byId[key].id : key);
const cell = () => (S.summary && S.summary.cell) || 40;

function connect() {
  const es = new EventSource('/api/events');
  es.onmessage = (e) => handle(JSON.parse(e.data));
  es.onerror = () => setClaude(false, 'editor server unreachable, retrying');
}

function handle(ev) {
  switch (ev.type) {
    case 'state':
      applyState(ev);
      if (ev.messages) { S.messages = ev.messages; renderChat(); }
      if (ev.jobs) {
        ev.jobs.forEach((j) => { S.jobs[j.id] = j; });
        // A page opened mid-run follows the run.
        const running = ev.jobs.find((j) => j.status === 'running');
        if (running && !S.watchJob) {
          watch(running);
          $('jobLog').textContent = running.lines.join('\n') + '\n';
        }
        renderJob();
      }
      break;
    case 'tracks':
      S.tracks = ev.tracks; S.boards = ev.boards; S.unsaved = ev.unsaved || [];
      fillPickers();
      break;
    case 'presence':
      S.presence = ev;
      renderPresence();
      break;
    case 'message':
      S.messages.push(ev.message);
      renderChat();
      if (ev.message.from === 'claude' && !tabOn('chat')) {
        S.unread += 1;
        $('chatBadge').hidden = false;
        $('chatBadge').textContent = S.unread;
        toast('Claude: ' + ev.message.text.slice(0, 140));
      }
      break;
    case 'notes':
      S.notes = ev.notes;
      renderNotes();
      break;
    case 'job':
      S.jobs[ev.job.id] = ev.job;
      if (ev.job.status === 'running' && ev.job.id !== S.watchJob
          && !(S.jobs[S.watchJob] && S.jobs[S.watchJob].status === 'running')) watch(ev.job);
      renderJob();
      break;
    case 'job-line': {
      const j = S.jobs[ev.job];
      if (j) { j.lines.push(ev.line); j.step = ev.step; }
      if (ev.job === S.watchJob) {
        const log = $('jobLog');
        log.textContent += ev.line + '\n';
        log.scrollTop = log.scrollHeight;
        $('jobState').textContent = ev.step ? '— ' + ev.step : '';
      }
      break;
    }
    case 'stage':
      onStage(ev);
      break;
    case 'focus':
      S.messages.push({ id: 0, from: 'system', kind: 'system', t: Date.now() / 1000,
        text: 'Claude points at ' + (ev.ids || []).join(', ') + (ev.text ? ' — ' + ev.text : '') });
      renderChat();
      if ($('followClaude').checked && ev.ids && ev.ids.length) fitTo(ev.ids);
      break;
  }
}

function applyState(st) {
  if (st.rev < S.rev && st.open === S.open) return;
  if (S.preview && st.open !== S.preview.key) {
    // Still following a detection: what else changes waits.
    S.open = st.open;
    S.rev = st.rev;
    return;
  }
  const changedTrack = st.open !== S.open || (st.track && !S.track);
  S.open = st.open;
  S.rev = st.rev;
  if (st.track) {
    S.track = st.track;
    S.byId = {};
    for (const s of S.track.spaces) S.byId[String(s.id)] = s;
    S.image = st.image;
    S.stages = st.stages || [];
  } else if (!st.open) {
    S.track = null;
    S.byId = {};
  }
  S.problems = st.problems || [];
  S.checks = st.checks || [];
  S.flagged = new Set(S.problems.map((p) => String(p.id)));
  for (const c of S.checks) if (c.id) S.flagged.add(String(c.id));
  S.summary = st.summary || null;
  S.busy = !!st.busy;
  if (st.notes) S.notes = st.notes;
  if (st.presence) S.presence = st.presence;
  S.sel = S.sel.filter((id) => S.byId[id]);
  if (changedTrack) {
    S.sel = [];
    S.underlay = null;
    if (S.preview && S.preview.key === S.open) {
      // The detection being watched has its first track: keep its step image.
      S.underlay = S.preview.underlay;
    }
    S.preview = null;
    $('bg').setAttribute('href', S.image || '');
    if (S.startBox && S.startBox.length === 4) { fitBox(S.startBox); S.startBox = null; } else fit();
  }
  renderAll();
  renderSide();
  renderPresence();
  if (st.track) renderStages();
  const last = st.last;
  if (last && last.author === 'claude' && !changedTrack && last.notes && last.notes.length) {
    toast('Claude: ' + last.notes.slice(0, 3).join('; ') + (last.notes.length > 3 ? ' …' : ''));
    if (last.ids) flash(last.ids.map(String));
  }
}

// Drawing -----------------------------------------------------------------------

const esc = (v) => String(v).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function laneOf(s) { return s.pit ? 0 : (s.lane || 1); }

function renderAll() {
  const t = S.track;
  $('empty').hidden = !!(t || S.preview);
  const w = t ? t.image.width : S.preview ? S.preview.w : 1000;
  const h = t ? t.image.height : S.preview ? S.preview.h : 700;
  for (const id of ['bg', 'under']) {
    $(id).setAttribute('width', w);
    $(id).setAttribute('height', h);
  }
  $('bg').classList.toggle('hidden-layer', !$('lyBoard').checked || !t);
  const under = S.underlay && $('lyUnder').checked;
  $('under').setAttribute('href', under ? S.underlay.url : '');
  $('under').style.opacity = $('underOpacity').value / 100;
  $('under').classList.toggle('hidden-layer', !under);
  renderLinks();
  renderCars();
  renderMarks();
  renderIds();
  renderNotes();
  renderLayout();
  applyView();
}

function renderLinks() {
  const g = $('gLinks');
  const t = S.track;
  if (!t || !$('lyLinks').checked) { g.innerHTML = ''; return; }
  const c = cell();
  g.style.strokeWidth = (c * 0.035).toFixed(2);
  const out = [];
  for (const s of t.spaces) {
    for (const n of s.next || []) {
      const o = S.byId[String(n)];
      if (!o) continue;
      const dx = o.pos[0] - s.pos[0], dy = o.pos[1] - s.pos[1];
      const d = Math.hypot(dx, dy) || 1;
      const ux = dx / d, uy = dy / d;
      const a = Math.min(0.2 * c, d * 0.3), b = Math.min(0.38 * c, d * 0.45);
      const cls = 'link' + (s.fixed ? ' fixed' : '') + (laneOf(o) !== laneOf(s) ? ' cross' : '');
      out.push(`<line class="${cls}" x1="${(s.pos[0] + ux * a).toFixed(1)}" y1="${(s.pos[1] + uy * a).toFixed(1)}" `
        + `x2="${(o.pos[0] - ux * b).toFixed(1)}" y2="${(o.pos[1] - uy * b).toFixed(1)}" `
        + `marker-end="url(#${s.fixed ? 'arrowFixed' : 'arrow'})"/>`);
    }
  }
  g.innerHTML = out.join('');
}

// Spaces drawn as solid cars hide the arrows printed in them, so they can
// be outlines or dots instead; each keeps a full-size invisible hit area.
function carMarkup(s) {
  const c = cell(), L = 0.36 * c, W = 0.17 * c;
  const colour = s.box ? ` style="color:${SEATS[s.box] || '#ccc'}"` : '';
  const cls = 'car l' + laneOf(s) + (s.fixed ? ' fixed' : '') + (String(s.id) === S.hover ? ' hover' : '');
  const style = $('carStyle').value;
  let body;
  if (style === 'solid') {
    body = `<rect class="body" x="${-L}" y="${-W}" width="${2 * L}" height="${2 * W}" rx="${W * 0.45}"/>`
      + `<path class="nose" d="M${L * 0.95} 0 L${L * 0.45} ${-W * 0.6} L${L * 0.45} ${W * 0.6}z"/>`;
  } else if (style === 'dot') {
    body = `<line class="tick" x1="0" y1="0" x2="${L * 0.9}" y2="0" stroke-width="${(c * 0.04).toFixed(2)}"/>`
      + `<circle class="dot" r="${(c * 0.09).toFixed(1)}" stroke-width="${(c * 0.02).toFixed(2)}"/>`;
  } else {
    // An outline, and a small nose at the front: the cell's middle, where
    // its arrow is printed, stays clear.
    body = `<rect class="ol" x="${-L}" y="${-W}" width="${2 * L}" height="${2 * W}" rx="${W * 0.45}" stroke-width="${(c * 0.045).toFixed(2)}"/>`
      + `<path class="olnose" d="M${L} 0 L${L * 0.72} ${-W * 0.45} L${L * 0.72} ${W * 0.45}z"/>`;
  }
  return `<g class="${cls}" data-id="${esc(s.id)}"${colour} transform="translate(${s.pos[0]} ${s.pos[1]}) rotate(${s.rot || 0})">`
    + `<rect class="hit" x="${-L}" y="${-W}" width="${2 * L}" height="${2 * W}"/>${body}</g>`;
}

function renderCars() {
  const g = $('gCars');
  S.carEls.clear();
  g.style.opacity = $('carOpacity').value / 100;
  if (!S.track || !$('lyCars').checked) { g.innerHTML = ''; return; }
  g.style.strokeWidth = (cell() * 0.03).toFixed(2);
  g.innerHTML = S.track.spaces.map(carMarkup).join('');
  for (const el of g.children) S.carEls.set(el.dataset.id, el);
}

function ring(s, r, cls) {
  return `<circle class="ring ${cls}" data-id="${esc(s.id)}" cx="${s.pos[0]}" cy="${s.pos[1]}" r="${r.toFixed(1)}"/>`;
}

function claudeSel() {
  const c = S.presence.clients && S.presence.clients.claude;
  return (c && c.selection) || [];
}

function renderMarks() {
  const g = $('gMarks');
  const t = S.track;
  if (!t) { g.innerHTML = ''; return; }
  const c = cell();
  g.style.strokeWidth = (c * 0.08).toFixed(2);
  const out = [];
  for (const id of S.flagged) {
    const s = S.byId[id];
    if (s) out.push(ring(s, 0.55 * c, 'prob'));
  }
  // The grid, pole first, joined in order.
  const start = (t.start || []).map((id) => S.byId[String(id)]).filter(Boolean);
  if (start.length) {
    out.push(`<polyline class="gridline" style="stroke-width:${(c * 0.05).toFixed(1)};stroke-dasharray:${(c * 0.15).toFixed(1)} ${(c * 0.1).toFixed(1)}" points="${start.map((s) => s.pos.join(',')).join(' ')}"/>`);
    start.forEach((s, i) => {
      out.push(`<text class="gridnum" x="${s.pos[0] + 0.45 * c}" y="${s.pos[1] - 0.35 * c}" font-size="${(0.45 * c).toFixed(1)}">${i + 1}</text>`);
      if (i === 0) out.push(ring(s, 0.7 * c, 'you" style="stroke:#fff'));
    });
  }
  for (const id of claudeSel()) {
    const s = S.byId[String(id)];
    if (s) out.push(ring(s, 0.78 * c, 'claude'));
  }
  for (const id of S.sel) {
    const s = S.byId[id];
    if (s) out.push(ring(s, 0.64 * c, 'you'));
  }
  g.innerHTML = out.join('');
}

function flash(ids) {
  const g = $('gMarks');
  const c = cell();
  const add = ids.map((id) => S.byId[id]).filter(Boolean).map((s) => ring(s, 0.9 * c, 'flash')).join('');
  g.insertAdjacentHTML('beforeend', add);
}

function scale() { return svg.clientWidth / S.view.w; }

function renderIds() {
  const g = $('gIds');
  const c = cell();
  if (!S.track || !$('lyIds').checked || c * scale() < 38) { g.innerHTML = ''; return; }
  const v = S.view, m = c;
  const fs = (0.12 * c).toFixed(1);
  const out = [];
  for (const s of S.track.spaces) {
    const [x, y] = s.pos;
    if (x < v.x - m || x > v.x + v.w + m || y < v.y - m || y > v.y + v.h + m) continue;
    // At the back of the car: the arrow is printed in the middle and ahead.
    const r = (s.rot || 0) * Math.PI / 180;
    const bx = x - Math.cos(r) * 0.2 * c, by = y - Math.sin(r) * 0.2 * c;
    out.push(`<text class="sid" x="${bx.toFixed(1)}" y="${(by + 0.04 * c).toFixed(1)}" font-size="${fs}">${esc(s.id)}</text>`);
  }
  g.style.strokeWidth = (c * 0.025).toFixed(2);
  g.innerHTML = out.join('');
}

function renderNotes() {
  const g = $('gNotes');
  if (!S.track) { g.innerHTML = ''; return; }
  const c = cell();
  const out = [];
  for (const n of S.notes) {
    const pts = (n.spaces || []).map((id) => S.byId[String(id)]).filter(Boolean).map((s) => s.pos);
    if (n.pos) pts.push(n.pos);
    if (!pts.length) continue;
    out.push(`<g class="note" style="stroke-width:${(c * 0.06).toFixed(1)}">`);
    for (const p of pts) out.push(`<circle cx="${p[0]}" cy="${p[1]}" r="${(0.9 * c).toFixed(1)}"/>`);
    out.push(`<text x="${pts[0][0] + c}" y="${pts[0][1] - c}" font-size="${(0.42 * c).toFixed(1)}">${esc(n.text)}</text></g>`);
  }
  g.innerHTML = out.join('');
}

function renderLayout() {
  const g = $('gLayout');
  const t = S.track;
  if (!t) { g.innerHTML = ''; return; }
  const out = [];
  const c = cell();
  if (t.panel) {
    const w = t.panel.width, h = w * 0.28;
    out.push(`<g class="layout"><rect x="${t.panel.pos[0] - w / 2}" y="${t.panel.pos[1] - h / 2}" width="${w}" height="${h}" rx="6"/>`
      + `<text x="${t.panel.pos[0] - w / 2 + 8}" y="${t.panel.pos[1] - h / 2 + 0.5 * c}" font-size="${0.45 * c}">race panel</text></g>`);
  }
  if (t.dice) {
    const d = 2.2 * c;
    const side = t.dice_side || 'up';
    const dir = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }[side] || [0, -1];
    const [x, y] = t.dice;
    out.push(`<g class="layout"><rect x="${x - d / 2}" y="${y - d / 2}" width="${d}" height="${d}" rx="8"/>`
      + `<line x1="${x}" y1="${y}" x2="${x + dir[0] * d * 0.7}" y2="${y + dir[1] * d * 0.7}" stroke="#fff" stroke-width="${0.08 * c}"/>`
      + `<text x="${x - d / 2 + 6}" y="${y + d / 2 - 6}" font-size="${0.4 * c}">dice</text></g>`);
  }
  g.innerHTML = out.join('');
}

// View ---------------------------------------------------------------------------

function applyView() {
  const cw = svg.clientWidth || 1, ch = svg.clientHeight || 1;
  S.view.h = S.view.w * ch / cw;
  const v = S.view;
  svg.setAttribute('viewBox', `${v.x} ${v.y} ${v.w} ${v.h}`);
  const c = cell();
  $('coords').textContent = `${S.pointer[0].toFixed(0)}, ${S.pointer[1].toFixed(0)} px · zoom ${(scale() * 100).toFixed(0)}% · cell ${c.toFixed(0)} px`;
}

let idsPending = false;
function viewChanged() {
  applyView();
  if (!idsPending) {
    idsPending = true;
    requestAnimationFrame(() => { idsPending = false; renderIds(); });
  }
  sendPresence();
}

function fitBox(box) {
  const [x0, y0, x1, y1] = box;
  const cw = svg.clientWidth || 1, ch = svg.clientHeight || 1;
  const bw = Math.max(1, x1 - x0), bh = Math.max(1, y1 - y0);
  const w = Math.max(bw, bh * cw / ch);
  S.view = { x: (x0 + x1) / 2 - w / 2, y: (y0 + y1) / 2 - (w * ch / cw) / 2, w, h: w * ch / cw };
  viewChanged();
}

function fit() {
  const t = S.track;
  const w = t ? t.image.width : S.preview ? S.preview.w : 1000;
  const h = t ? t.image.height : S.preview ? S.preview.h : 700;
  fitBox([-w * 0.02, -h * 0.02, w * 1.02, h * 1.02]);
}

function fitTo(ids) {
  const pts = ids.map((id) => S.byId[String(id)]).filter(Boolean).map((s) => s.pos);
  if (!pts.length) return;
  const c = cell() * 4;
  const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
  fitBox([Math.min(...xs) - c, Math.min(...ys) - c, Math.max(...xs) + c, Math.max(...ys) + c]);
}

function toImg(e) {
  const pt = svg.createSVGPoint();
  pt.x = e.clientX; pt.y = e.clientY;
  const p = pt.matrixTransform(svg.getScreenCTM().inverse());
  return [p.x, p.y];
}

svg.addEventListener('wheel', (e) => {
  e.preventDefault();
  // With spaces picked up, the wheel turns them, as in TTS: 15° a notch,
  // 2° with Shift (which some browsers report as a sideways scroll).
  if (drag && drag.kind === 'move') {
    const notches = (e.deltaY || e.deltaX) * (e.deltaMode === 1 ? 33 : 1) / 100;
    drag.turn += notches * (e.shiftKey ? 2 : 15);
    drawDrag(drag);
    return;
  }
  const [px, py] = toImg(e);
  const k = Math.pow(1.0015, e.deltaY);
  const v = S.view;
  const w = Math.min(Math.max(v.w * k, 40), 20000);
  const f = w / v.w;
  S.view = { x: px - (px - v.x) * f, y: py - (py - v.y) * f, w, h: v.h * f };
  viewChanged();
}, { passive: false });

window.addEventListener('resize', () => viewChanged());

// Pointer --------------------------------------------------------------------------

let drag = null;

svg.addEventListener('pointerdown', (e) => {
  const p = toImg(e);
  const car = e.target.closest && e.target.closest('.car');
  if (S.mode && e.button === 0) { doMode(p); return; }
  svg.setPointerCapture(e.pointerId);
  if (e.button === 1 || (e.button === 0 && !car && !e.shiftKey)) {
    drag = { kind: 'pan', sx: e.clientX, sy: e.clientY, view: { ...S.view }, moved: false };
    svg.classList.add('panning');
  } else if (e.button === 0 && !car && e.shiftKey) {
    drag = { kind: 'box', p0: p, p1: p };
  } else if (e.button === 0 && car) {
    const id = car.dataset.id;
    if (e.ctrlKey || e.metaKey) { linkTo(id); drag = null; return; }
    if (e.shiftKey) {
      S.sel = S.sel.includes(id) ? S.sel.filter((x) => x !== id) : [...S.sel, id];
      selectionChanged();
      return;
    }
    if (!S.sel.includes(id)) { S.sel = [id]; selectionChanged(); }
    drag = { kind: 'move', p0: p, moved: false, d: [0, 0], turn: 0,
      orig: S.sel.map((sid) => [sid, [...S.byId[sid].pos]]) };
  }
});

svg.addEventListener('pointermove', (e) => {
  const p = toImg(e);
  S.pointer = p;
  if (!drag) {
    const car = e.target.closest && e.target.closest('.car');
    setHover(car ? car.dataset.id : null);
    applyView();
    return;
  }
  if (drag.kind === 'pan') {
    const k = S.view.w / svg.clientWidth;
    const dx = (e.clientX - drag.sx) * k, dy = (e.clientY - drag.sy) * k;
    if (Math.abs(e.clientX - drag.sx) + Math.abs(e.clientY - drag.sy) > 3) drag.moved = true;
    S.view = { ...drag.view, x: drag.view.x - dx, y: drag.view.y - dy };
    viewChanged();
  } else if (drag.kind === 'box') {
    drag.p1 = p;
    const r = $('boxSel');
    r.hidden = false;
    r.setAttribute('x', Math.min(drag.p0[0], p[0]));
    r.setAttribute('y', Math.min(drag.p0[1], p[1]));
    r.setAttribute('width', Math.abs(p[0] - drag.p0[0]));
    r.setAttribute('height', Math.abs(p[1] - drag.p0[1]));
  } else if (drag.kind === 'move') {
    const dx = p[0] - drag.p0[0], dy = p[1] - drag.p0[1];
    if (Math.hypot(dx, dy) * scale() > 2) drag.moved = true;
    if (!drag.moved) return;
    drag.d = [dx, dy];
    drawDrag(drag);
  }
});

// The spaces being carried, where they would go if dropped now.
function drawDrag(d) {
  const [dx, dy] = d.d;
  for (const [sid, o] of d.orig) {
    const el = S.carEls.get(sid);
    const s = S.byId[sid];
    if (el) el.setAttribute('transform', `translate(${o[0] + dx} ${o[1] + dy}) rotate(${(s.rot || 0) + d.turn})`);
  }
  for (const el of $('gMarks').querySelectorAll('.ring.you')) {
    const o = d.orig.find((x) => x[0] === el.dataset.id);
    if (o) { el.setAttribute('cx', o[1][0] + dx); el.setAttribute('cy', o[1][1] + dy); }
  }
  $('modeInfo').textContent = d.turn ? `turned ${d.turn > 0 ? '+' : ''}${d.turn.toFixed(0)}°` : '';
}

svg.addEventListener('pointerup', (e) => {
  const d = drag;
  drag = null;
  svg.classList.remove('panning');
  if (!d) return;
  if (d.kind === 'pan' && !d.moved && e.button === 0 && S.sel.length) {
    S.sel = [];
    selectionChanged();
  } else if (d.kind === 'box') {
    $('boxSel').hidden = true;
    const x0 = Math.min(d.p0[0], d.p1[0]), x1 = Math.max(d.p0[0], d.p1[0]);
    const y0 = Math.min(d.p0[1], d.p1[1]), y1 = Math.max(d.p0[1], d.p1[1]);
    const inside = S.track ? S.track.spaces.filter((s) => s.pos[0] >= x0 && s.pos[0] <= x1
      && s.pos[1] >= y0 && s.pos[1] <= y1).map((s) => String(s.id)) : [];
    S.sel = [...new Set([...S.sel, ...inside])];
    selectionChanged();
  } else if (d.kind === 'move' && (d.moved || d.turn)) {
    const [dx, dy] = d.moved ? d.d : [0, 0];
    $('modeInfo').textContent = '';
    ops(d.orig.map(([sid, o]) => {
      const op = { op: 'move', id: idOf(sid), pos: [+(o[0] + dx).toFixed(1), +(o[1] + dy).toFixed(1)] };
      if (d.turn) op.rot = +((((S.byId[sid].rot || 0) + d.turn) % 360 + 360) % 360).toFixed(1);
      return op;
    })).then((r) => { if (!r) renderAll(); });
  }
});

svg.addEventListener('dblclick', (e) => {
  if (e.target.closest && e.target.closest('.car')) return;
  if (S.track) ops([{ op: 'add', pos: toImg(e).map((v) => +v.toFixed(1)) }]);
});

svg.addEventListener('pointerleave', () => setHover(null));

function setHover(id) {
  if (id === S.hover) return;
  if (S.hover && S.carEls.get(S.hover)) S.carEls.get(S.hover).classList.remove('hover');
  S.hover = id;
  if (id && S.carEls.get(id)) S.carEls.get(id).classList.add('hover');
  const s = id && S.byId[id];
  $('hoverInfo').innerHTML = s ? `<b>${esc(s.id)}</b> lane ${laneOf(s)} · ${s.pos[0].toFixed(0)},${s.pos[1].toFixed(0)} · ${(s.rot || 0).toFixed(0)}°`
    + ` → ${(s.next || []).map(esc).join(', ') || 'nothing'}${s.fixed ? ' (fixed)' : ''}`
    + (S.flagged.has(id) ? ` · <span class="prob">${esc(S.problems.filter((p) => String(p.id) === id).map((p) => p.text).join('; '))}</span>` : '')
    : '';
  sendPresence();
}

function selectionChanged() {
  renderMarks();
  renderSide();
  sendPresence();
}

function linkTo(id) {
  const from = S.sel[S.sel.length - 1];
  if (!from) { toast('Select the space a car moves from, then Ctrl-click the one it moves to.'); return; }
  if (from === id) return;
  ops([{ op: 'link', from: idOf(from), to: idOf(id) }]);
}

// Modes: the next click on the board places something.
function setMode(mode, text) {
  S.mode = mode;
  svg.classList.toggle('mode', !!mode);
  $('modeInfo').textContent = mode ? text + ' (Esc to cancel)' : '';
  $('diceBtn').classList.toggle('armed', mode === 'dice');
  $('panelBtn').classList.toggle('armed', mode === 'panel');
}

function doMode(p) {
  const pos = p.map((v) => Math.round(v));
  if (S.mode === 'dice') ops([{ op: 'dice', pos }]);
  if (S.mode === 'panel') ops([{ op: 'panel', pos }]);
  setMode(null);
}

// Keys ------------------------------------------------------------------------------

document.addEventListener('keydown', (e) => {
  if (e.target.matches && e.target.matches('input, textarea, select')) return;
  const k = e.key.toLowerCase();
  const mod = e.ctrlKey || e.metaKey;
  if (mod && k === 'z') { e.preventDefault(); e.shiftKey ? redo() : undo(); return; }
  if (mod && k === 'y') { e.preventDefault(); redo(); return; }
  if (mod && k === 's') { e.preventDefault(); save(); return; }
  if (mod || e.altKey || !S.track) return;
  // A held key repeats: fine for turning and nudging, not for adding a
  // space, deleting or toggling (two spaces on one spot, say).
  if (e.repeat && !/^(q|e|arrow)/.test(k)) return;
  const sel = S.sel.map(idOf);
  const digit = /^Digit([0-3])$/.exec(e.code);
  if (digit && sel.length) {
    ops(sel.map((id) => ({ op: 'lane', id, lane: +digit[1] })));
    return;
  }
  switch (k) {
    case 'q': case 'e':
      ops(sel.map((id) => ({ op: 'turn', id, by: (k === 'q' ? -1 : 1) * (e.shiftKey ? 2 : 15) })));
      break;
    case 'arrowleft': case 'arrowright': case 'arrowup': case 'arrowdown': {
      e.preventDefault();
      const n = e.shiftKey ? 5 : 1;
      const [dx, dy] = { arrowleft: [-n, 0], arrowright: [n, 0], arrowup: [0, -n], arrowdown: [0, n] }[k];
      ops(S.sel.map((sid) => { const s = S.byId[sid]; return { op: 'move', id: s.id, pos: [s.pos[0] + dx, s.pos[1] + dy] }; }));
      break;
    }
    case 'a':
      ops([{ op: 'add', pos: S.pointer.map((v) => +v.toFixed(1)) }]);
      break;
    case 'delete': case 'backspace':
      ops(sel.map((id) => ({ op: 'delete', id })));
      break;
    case 'u':
      ops(sel.map((id) => ({ op: 'unfix', id })));
      break;
    case 'g': {
      const target = S.hover || S.sel[S.sel.length - 1];
      if (target) ops([{ op: 'grid', id: idOf(target) }]);
      break;
    }
    case 'f':
      S.sel.length ? fitTo(S.sel) : fit();
      break;
    case 'c':
      e.preventDefault();
      showTab('chat');
      $('chatText').focus();
      break;
    case 'escape':
      setMode(null);
      S.sel = [];
      selectionChanged();
      break;
    default:
      return;
  }
});

const undo = () => act('/api/undo');
const redo = () => act('/api/redo');

async function save() {
  if (!S.open) return;
  const r = await act('/api/save');
  if (r) toast('Saved ' + r.path + (r.adjacency ? ' — rerunning adjacency' : ''));
}

// Presence ------------------------------------------------------------------------

let presenceTimer = null;
let presenceDue = false;
function sendPresence(now) {
  const body = () => {
    const v = S.view;
    return {
      client, who: 'user', key: S.open, selection: S.sel.map(idOf), hover: S.hover ? idOf(S.hover) : null,
      viewport: [v.x, v.y, v.x + v.w, v.y + v.h].map((x) => Math.round(x)),
    };
  };
  if (now) return api('POST', '/api/presence', body()).catch(() => {});
  if (presenceTimer) { presenceDue = true; return; }
  api('POST', '/api/presence', body()).catch(() => {});
  presenceTimer = setTimeout(() => {
    presenceTimer = null;
    if (presenceDue) { presenceDue = false; sendPresence(); }
  }, 300);
}
setInterval(() => sendPresence(), 30000);

function setClaude(on, text) {
  $('claudeDot').classList.toggle('on', on);
  $('claudeState').textContent = text;
}

function renderPresence() {
  const listening = S.presence.claude_listening;
  setClaude(listening, listening ? 'Claude: listening' : 'Claude: not listening');
  $('claudeState').title = listening ? 'Messages you send in the Claude tab reach Claude now.'
    : 'Ask Claude in the terminal to join: it runs tools/editor/fdedit.py listen.';
  const key = claudeSel().join(',');
  if (key !== S.lastClaudeSel) {
    S.lastClaudeSel = key;
    renderMarks();
  }
}

// Side panel ----------------------------------------------------------------------

function tabOn(name) { return $('tab-' + name).classList.contains('on'); }

function showTab(name) {
  document.querySelectorAll('#tabs button').forEach((b) => b.classList.toggle('on', b.dataset.tab === name));
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('on', t.id === 'tab-' + name));
  if (name === 'chat') {
    S.unread = 0;
    $('chatBadge').hidden = true;
    const log = $('chatLog');
    log.scrollTop = log.scrollHeight;
  }
}
document.querySelectorAll('#tabs button').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));

function idLinks(list) {
  return list.length ? list.map((n) => `<span class="idlink" data-go="${esc(n)}">${esc(n)}</span>`).join(', ') : '<span class="muted">none</span>';
}

function renderSide() {
  const t = S.track;
  $('dirty').hidden = !(S.summary && S.summary.dirty);
  $('undoBtn').disabled = !(S.summary && S.summary.undo);
  $('redoBtn').disabled = !(S.summary && S.summary.redo);
  for (const id of ['saveBtn', 'revertBtn']) $(id).disabled = !t || S.busy;
  $('probCount').textContent = S.problems.length + (S.checks || []).length;
  $('promoteBtn').hidden = !(S.open && S.open.startsWith('draft:'));
  if (t) {
    $('layoutInfo').textContent = `dice ${t.dice ? t.dice.join(', ') + ' (' + (t.dice_side || 'facing the middle') + ')' : 'not set'}`
      + ` · panel ${t.panel ? t.panel.pos.join(', ') + ', ' + t.panel.width + ' wide' : 'not set'}`
      + ` · grid ${(t.start || []).length} places`;
  }
  // Problems
  $('probList').innerHTML = S.problems.map((p) => `<li data-go="${esc(p.id)}"><b>${esc(p.id)}</b> ${esc(p.text)}</li>`).join('');
  $('checkList').innerHTML = (S.checks || []).map((c) => `<li ${c.id ? `data-go="${esc(c.id)}"` : ''}><b>${esc(c.test)}</b>: ${linkIds(c.text)}</li>`).join('')
    || '<li class="muted">all pass</li>';
  // The selection
  const box = $('spaceInfo');
  if (!t || !S.sel.length) {
    box.className = 'muted';
    box.innerHTML = t ? 'Click a space to see it. Shift-click or shift-drag to select several.' : '';
    return;
  }
  box.className = '';
  if (S.sel.length > 1) {
    box.innerHTML = `<p><b>${S.sel.length} spaces selected</b></p>
      <div class="row wrap"><button data-lane="1">Lane 1</button><button data-lane="2">Lane 2</button><button data-lane="3">Lane 3</button>
      <button data-do="unfix">Auto links</button><button data-do="delete">Delete</button><button data-do="ask">Ask Claude</button></div>
      <p class="small muted">${idLinks(S.sel.slice(0, 40))}${S.sel.length > 40 ? ' …' : ''}</p>`;
    return;
  }
  const s = S.byId[S.sel[0]];
  const into = t.spaces.filter((o) => (o.next || []).some((n) => String(n) === String(s.id))).map((o) => o.id);
  const place = (t.start || []).findIndex((g) => String(g) === String(s.id));
  const probs = S.problems.filter((p) => String(p.id) === String(s.id));
  box.innerHTML = `<div class="kv">
    <span class="k">space</span><b>${esc(s.id)}</b>
    <span class="k">lane</span><select id="fLane">${[0, 1, 2, 3].map((l) => `<option ${l === (s.lane ?? 1) ? 'selected' : ''}>${l}</option>`).join('')}</select>
    <span class="k">facing</span><span><input type="number" id="fRot" step="1" value="${(s.rot || 0).toFixed(1)}"> °</span>
    <span class="k">position</span><span><input type="number" id="fX" step="0.5" value="${s.pos[0]}"> <input type="number" id="fY" step="0.5" value="${s.pos[1]}"></span>
    <span class="k">sector</span><span>${esc(s.sector ?? '—')}${s.corner ? ' · corner ' + esc(s.corner) : ''}${s.box ? ' · pit box ' + esc(s.box) : ''}</span>
    <span class="k">pit lane</span><label><input type="checkbox" id="fPit" ${s.pit ? 'checked' : ''} ${s.box ? 'disabled' : ''}> in the pit lane</label>
    <span class="k">leads to</span><span>${(s.next || []).map((n) => `<span class="idlink" data-go="${esc(n)}">${esc(n)}</span> <a class="idlink" data-unlink="${esc(n)}" title="Remove this link">✕</a>`).join(', ') || '<span class="muted">nothing</span>'}</span>
    <span class="k">links</span><span>${s.fixed ? 'set by hand <button data-do="unfix">Auto</button>' : 'automatic'}</span>
    <span class="k">from</span><span>${idLinks(into)}</span>
    <span class="k">grid</span><span>${place >= 0 ? 'place ' + (place + 1) : '—'} <button data-do="grid">${place >= 0 ? 'Off the grid' : 'Next grid place'}</button></span>
  </div>
  ${probs.map((p) => `<p class="prob">${esc(p.text)}</p>`).join('')}
  <div class="row wrap"><button data-do="delete">Delete</button><button data-do="ask">Ask Claude</button></div>
  <p class="small muted">Ctrl-click another space to link this one to it.</p>`;
  $('fLane').onchange = (e) => ops([{ op: 'lane', id: s.id, lane: +e.target.value }]);
  $('fRot').onchange = (e) => ops([{ op: 'rotate', id: s.id, rot: +e.target.value }]);
  $('fPit').onchange = (e) => ops([{ op: 'set', id: s.id, fields: { pit: e.target.checked, lane: e.target.checked ? 0 : Math.max(1, s.lane || 1) } }]);
  $('fX').onchange = $('fY').onchange = () => ops([{ op: 'move', id: s.id, pos: [+$('fX').value, +$('fY').value] }]);
}

document.addEventListener('click', (e) => {
  const go = e.target.closest('[data-go]');
  if (go) {
    const id = go.dataset.go;
    if (S.byId[id]) { S.sel = [id]; selectionChanged(); fitTo([id]); }
    return;
  }
  const un = e.target.closest('[data-unlink]');
  if (un && S.sel.length === 1) {
    ops([{ op: 'link', from: idOf(S.sel[0]), to: idOf(un.dataset.unlink) }]);
    return;
  }
  const lane = e.target.closest('[data-lane]');
  if (lane) { ops(S.sel.map((id) => ({ op: 'lane', id: idOf(id), lane: +lane.dataset.lane }))); return; }
  const d = e.target.closest('[data-do]');
  if (!d) return;
  const sel = S.sel.map(idOf);
  if (d.dataset.do === 'unfix') ops(sel.map((id) => ({ op: 'unfix', id })));
  if (d.dataset.do === 'delete') ops(sel.map((id) => ({ op: 'delete', id })));
  if (d.dataset.do === 'grid') ops([{ op: 'grid', id: sel[0] }]);
  if (d.dataset.do === 'ask') { showTab('chat'); $('chatText').focus(); }
});

// Chat --------------------------------------------------------------------------

function linkIds(text) {
  return esc(text).replace(ID_RE, (m) => (S.byId[m] ? `<span class="idlink" data-go="${m}">${m}</span>` : m));
}

function renderChat() {
  const log = $('chatLog');
  const atEnd = log.scrollTop + log.clientHeight >= log.scrollHeight - 30;
  log.innerHTML = S.messages.slice(-300).map((m) => {
    const when = new Date(m.t * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    if (m.from === 'system') return `<div class="msg system">${linkIds(m.text)}</div>`;
    const c = m.context || {};
    const ctx = m.from === 'user' && c.selection && c.selection.length
      ? `<div class="ctx">with ${c.selection.length} selected: ${c.selection.slice(0, 8).map((id) => linkIds(String(id))).join(', ')}${c.selection.length > 8 ? ' …' : ''}</div>` : '';
    return `<div class="msg ${m.from}"><div class="who">${m.from === 'user' ? 'You' : 'Claude'} · ${when}</div>${linkIds(m.text)}${ctx}</div>`;
  }).join('');
  if (atEnd) log.scrollTop = log.scrollHeight;
}

$('chatForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const text = $('chatText').value.trim();
  if (!text) return;
  $('chatText').value = '';
  await sendPresence(true);
  await act('/api/message', { from: 'user', text });
  if (!S.presence.claude_listening) toast('Claude is not listening yet: in the terminal, ask Claude to join the editor.');
});
$('chatText').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('chatForm').requestSubmit(); }
});

// Detection -----------------------------------------------------------------------

function fillPickers() {
  const pick = $('trackPick');
  const real = S.tracks.filter((t) => t.kind === 'real');
  const drafts = S.tracks.filter((t) => t.kind === 'draft');
  const opt = (t) => `<option value="${esc(t.key)}" ${t.key === S.open ? 'selected' : ''}>${esc(t.name)}${t.kind === 'draft' ? ' (draft)' : ''}${S.unsaved.includes(t.key) ? ' •' : ''}</option>`;
  pick.innerHTML = `<option value="" ${S.open ? '' : 'selected'} disabled>Open a track…</option>`
    + `<optgroup label="Tracks">${real.map(opt).join('')}</optgroup>`
    + (drafts.length ? `<optgroup label="Detection drafts">${drafts.map(opt).join('')}</optgroup>` : '');
  const src = $('detSource');
  const was = src.value;
  const boards = S.boards.filter((b) => b.image);
  const group = (cat, label) => {
    const list = boards.filter((b) => b.category === cat);
    return list.length ? `<optgroup label="${label}">${list.map((b) => `<option value="${esc(b.id)}">${esc(b.name)}</option>`).join('')}</optgroup>` : '';
  };
  const uploads = drafts.filter((t) => t.source === 'upload');
  src.innerHTML = '<option value="">—</option>' + group('formula_d', 'Formula D') + group('formula_de', 'Formula Dé')
    + (uploads.length ? `<optgroup label="Uploaded">${uploads.map((t) => `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('')}</optgroup>` : '');
  if (was) src.value = was;
  else if (S.open) src.value = S.open.replace(/^draft:/, '');
}

$('trackPick').addEventListener('change', (e) => { if (e.target.value) act('/api/open', { key: e.target.value }); });

function detectOptions() {
  return {
    read: $('detRead').value, reverse: $('detReverse').checked, category: $('detCategory').value,
    steps: [...document.querySelectorAll('.detStep')].filter((c) => c.checked).map((c) => c.value),
    follow: $('detFollow').checked,
  };
}

async function runDetect(id) {
  const r = await act('/api/detect', { id, options: detectOptions() });
  if (!r) return;
  watch(r.job);
  showTab('detect');
}

function watch(job) {
  S.watchJob = job.id;
  S.watchKey = job.key;
  $('jobLog').textContent = '';
  if (job.kind === 'detect' && job.key !== S.open && $('detFollow').checked) {
    // Following a detection on another board: show only its step images
    // until the server opens its draft.
    S.preview = { key: job.key, w: 1000, h: 700, underlay: null };
    S.previewStages = [];
    S.track = null;
    S.byId = {};
    S.underlay = null;
    S.sel = [];
    renderAll();
    renderStages();
  }
  renderJob();
}

async function endPreview() {
  S.preview = null;
  S.rev = -1;
  try { applyState(await api('GET', '/api/state')); } catch (e) { toast(e.message, true); }
}

async function uploadAndDetect(file) {
  try {
    const q = new URLSearchParams({ name: file.name, category: $('detCategory').value });
    const r = await fetch('/api/upload?' + q, { method: 'POST', body: file });
    const j = await r.json();
    if (!r.ok) throw new Error(j.error);
    toast('Uploaded ' + file.name + ' as ' + j.id);
    await runDetect(j.id);
  } catch (e) {
    toast(e.message, true);
  }
}

$('detRun').addEventListener('click', () => {
  const file = $('detFile').files[0];
  if (file) { uploadAndDetect(file); $('detFile').value = ''; return; }
  const id = $('detSource').value;
  if (!id) { toast('Pick a board or an image first.', true); return; }
  if (S.tracks.some((t) => t.key === 'draft:' + id) && !confirm('Run the detector on ' + id + ' again? It replaces the draft, edits and all.')) return;
  runDetect(id);
});

function onStage(ev) {
  const live = ev.key === S.watchKey;
  if (ev.key === S.open || live) {
    const i = S.stages.findIndex((s) => s.file === ev.file);
    const st = { name: ev.name, file: ev.file, url: ev.url, fresh: true };
    if (ev.key !== S.open) {
      // Before the track exists, the stage list is the watched job's own.
      S.previewStages = S.previewStages || [];
      const j = S.previewStages.findIndex((s) => s.file === ev.file);
      if (j >= 0) S.previewStages[j] = st; else S.previewStages.push(st);
    } else if (i >= 0) S.stages[i] = st; else S.stages.push(st);
    renderStages();
  }
  if (live && $('detFollow').checked) setUnderlay({ name: ev.name, url: ev.url }, ev.key);
}

function setUnderlay(st, key) {
  if (key && key !== S.open && S.preview) {
    // No track yet: show the picture on its own, at its own size.
    const img = new Image();
    img.onload = () => {
      const first = S.preview.w === 1000 && S.preview.h === 700;
      S.preview.w = img.naturalWidth;
      S.preview.h = img.naturalHeight;
      S.preview.underlay = st;
      S.underlay = st;
      renderAll();
      if (first) fit();
    };
    img.src = st.url;
    return;
  }
  S.underlay = st;
  $('lyUnder').checked = true;
  renderAll();
  renderStages();
}

function renderStages() {
  const list = (S.preview && S.watchKey !== S.open) ? (S.previewStages || []) : S.stages;
  const order = (n) => (/^\d/.test(n) ? n : '9' + n);
  const sorted = [...list].sort((a, b) => order(a.name).localeCompare(order(b.name)));
  $('stageList').innerHTML = sorted.map((s) => `<div class="thumb ${S.underlay && S.underlay.file === s.file ? 'on' : ''} ${s.fresh ? 'fresh' : ''}" data-stage="${esc(s.file)}">`
    + `<img src="${esc(s.url)}" alt="" loading="lazy"><span>${esc(s.name.replace(/_/g, ' '))}</span></div>`).join('')
    || '<p class="muted small">No step images yet for this track. Run the detector to see each step.</p>';
  list.forEach((s) => { s.fresh = false; });
}

$('stageList').addEventListener('click', (e) => {
  const t = e.target.closest('[data-stage]');
  if (!t) return;
  const list = (S.preview && S.watchKey !== S.open) ? (S.previewStages || []) : S.stages;
  const st = list.find((s) => s.file === t.dataset.stage);
  if (st) setUnderlay({ ...st, file: st.file }, S.preview ? S.watchKey : null);
});

$('underNone').addEventListener('click', () => { S.underlay = null; renderAll(); renderStages(); });

function renderJob() {
  const j = S.jobs[S.watchJob];
  if (!j) { $('jobState').textContent = ''; return; }
  $('jobState').textContent = j.status === 'running' ? '— ' + (j.step || 'starting') : '— ' + j.status;
  if (j.status !== 'running' && S.preview && S.preview.key === j.key && S.open !== j.key) endPreview();
  if (j.status !== 'running') {
    $('jobLog').textContent = j.lines.join('\n') + '\n';
    $('jobLog').scrollTop = $('jobLog').scrollHeight;
    if (j.kind === 'detect') toast('Detection ' + j.status + (j.status === 'done' ? ': the draft is open to edit.' : ' — see the log.'), j.status !== 'done');
  }
}

$('promoteBtn').addEventListener('click', async () => {
  if (!S.open || !S.open.startsWith('draft:')) return;
  const id = S.open.slice(6);
  if (!confirm(`Write this draft to tracks/${id}.json and regenerate its Lua module?`)) return;
  let r = null;
  try {
    r = await api('POST', '/api/promote', { key: S.open, author: 'user' });
  } catch (e) {
    if (/edited by hand/.test(e.message) && confirm(e.message + '\n\nReplace it anyway?')) {
      r = await act('/api/promote', { key: S.open, force: true });
    } else {
      toast(e.message, true);
    }
  }
  if (r) toast('Promoted to ' + r.path);
});

// Dropping an image anywhere on the board runs the detector on it.
const stage = $('stage');
stage.addEventListener('dragover', (e) => {
  if ([...(e.dataTransfer.items || [])].some((i) => i.kind === 'file')) { e.preventDefault(); $('dropHint').hidden = false; }
});
stage.addEventListener('dragleave', () => { $('dropHint').hidden = true; });
stage.addEventListener('drop', (e) => {
  e.preventDefault();
  $('dropHint').hidden = true;
  const file = e.dataTransfer.files[0];
  if (file && file.type.startsWith('image/')) uploadAndDetect(file);
  else toast('That is not an image.', true);
});

// Toolbar ------------------------------------------------------------------------

$('undoBtn').onclick = undo;
$('redoBtn').onclick = redo;
$('saveBtn').onclick = save;
$('revertBtn').onclick = () => { if (confirm('Throw away every unsaved edit to this track?')) act('/api/revert'); };
for (const id of ['lyBoard', 'lyCars', 'lyLinks', 'lyIds', 'lyUnder']) $(id).addEventListener('change', renderAll);
// The car style and opacity are this viewer's own, kept between visits.
try {
  const saved = JSON.parse(localStorage.getItem('fdCars') || '{}');
  if (saved.style) $('carStyle').value = saved.style;
  if (saved.opacity) $('carOpacity').value = saved.opacity;
} catch (e) { /* no storage: defaults */ }
function keepCarLook() {
  try { localStorage.setItem('fdCars', JSON.stringify({ style: $('carStyle').value, opacity: $('carOpacity').value })); } catch (e) { /* fine */ }
}
$('carStyle').addEventListener('change', () => { keepCarLook(); renderCars(); });
$('carOpacity').addEventListener('input', () => { keepCarLook(); $('gCars').style.opacity = $('carOpacity').value / 100; });
// Hold H to see the board bare.
document.addEventListener('keydown', (e) => {
  if (e.key.toLowerCase() === 'h' && !e.ctrlKey && !e.metaKey && !(e.target.matches && e.target.matches('input, textarea, select'))) svg.classList.add('peek');
});
document.addEventListener('keyup', (e) => { if (e.key.toLowerCase() === 'h') svg.classList.remove('peek'); });
window.addEventListener('blur', () => svg.classList.remove('peek'));
$('underOpacity').addEventListener('input', () => { $('under').style.opacity = $('underOpacity').value / 100; });
$('diceBtn').onclick = () => setMode(S.mode === 'dice' ? null : 'dice', 'Click where the dice tray goes');
$('panelBtn').onclick = () => setMode(S.mode === 'panel' ? null : 'panel', 'Click where the race panel goes');
$('turnDiceBtn').onclick = () => {
  const t = S.track;
  if (!t || !t.dice) { toast('Put the dice somewhere first.', true); return; }
  const sides = ['up', 'right', 'down', 'left'];
  const i = sides.indexOf(t.dice_side || 'up');
  ops([{ op: 'dice_side', side: sides[(i + 1) % 4] }]);
};
$('panelSmaller').onclick = () => S.track && S.track.panel && ops([{ op: 'panel', width: S.track.panel.width / 1.15 }]);
$('panelLarger').onclick = () => S.track && S.track.panel && ops([{ op: 'panel', width: S.track.panel.width * 1.15 }]);
$('clearGridBtn').onclick = () => { if (confirm('Take every space off the grid?')) ops([{ op: 'grid_set', ids: [] }]); };
$('adjBtn').onclick = async () => {
  const r = await act('/api/adjacency');
  if (r) { watch(r.job); showTab('detect'); }
};

let toastTimer = null;
function toast(text, err) {
  const t = $('toast');
  t.textContent = text;
  t.className = err ? 'err' : '';
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, err ? 6000 : 3500);
}

connect();
applyView();
// #detect, #chat, ... opens on that tab; #box=x0,y0,x1,y1 on that part of the board.
const hash = location.hash.slice(1);
if (hash && $('tab-' + hash)) showTab(hash);
const hashBox = /^box=([\d.,-]+)$/.exec(hash);
if (hashBox) S.startBox = hashBox[1].split(',').map(Number);
