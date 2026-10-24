/* Tribes TD · 引导与输入
 * 统一用 Pointer 事件处理鼠标与触摸，避免两套逻辑漂移。
 */
'use strict';

let stageEl, cvEl, bootEl, bootBar, bootErr;
let lastT = 0, acc = 0;

// ---------------------------------------------------------------- 坐标换算
function screenToLogical(clientX, clientY) {
  const r = cvEl.getBoundingClientRect();
  return {
    x: (clientX - r.left) / r.width * LAYOUT.W,
    y: (clientY - r.top) / r.height * LAYOUT.H,
  };
}

function logicalToCell(x, y) {
  const bx = x - LAYOUT.boardX, by = y - LAYOUT.boardY;
  if (bx < 0 || by < 0 || bx >= BOARD.w || by >= BOARD.h) return null;
  return { x: Math.floor(bx / LAYOUT.cell), y: Math.floor(by / LAYOUT.cell) };
}

// ---------------------------------------------------------------- 自适应
function resizeStage() {
  const vw = window.innerWidth, vh = window.innerHeight;
  const pad = vw > 620 ? 24 : 0;
  const s = Math.min((vw - pad) / LAYOUT.W, (vh - pad) / LAYOUT.H);
  stageEl.style.width = Math.floor(LAYOUT.W * s) + 'px';
  stageEl.style.height = Math.floor(LAYOUT.H * s) + 'px';
  // 大屏时给个圆角，手机上满屏
  stageEl.style.borderRadius = s < 0.98 ? '10px' : '0';
}

// ---------------------------------------------------------------- 命中测试
function hitTopBar(x, y) {
  if (y >= LAYOUT.topH) return false;
  // 部族切换
  const pcx = LAYOUT.W - 208, pcy = 88, pcw = 184, pch = 34;
  if (x >= pcx && x <= pcx + pcw && y >= pcy && y <= pcy + pch) {
    G.profIndex = (G.profIndex + 1) % G.professions.length;
    G.buildId = curProf().towers[0];
    G.selected = null;
    const p = curProf();
    pushToast(`${p.name}：${p.desc}`);
    return true;
  }
  // 解锁进度条（可点）
  if (x >= 268 && x <= 470 && y >= 84) {
    tryUnlockTier();
    return true;
  }
  return true; // 顶部其余区域吞掉点击
}

function hitActionBar(x, y) {
  const t = G.selected;
  if (!t) return false;
  if (y < LAYOUT.actionY || y > LAYOUT.actionY + LAYOUT.actionH) return false;
  if (x >= LAYOUT.W - 328 && x <= LAYOUT.W - 182) { tryUpgrade(t); return true; }
  if (x >= LAYOUT.W - 172 && x <= LAYOUT.W - 32) { trySell(t); return true; }
  return true;
}

function hitCards(x, y) {
  if (y < LAYOUT.cardY || y > LAYOUT.cardY + LAYOUT.cardH) return false;
  const ids = curProf().towers;
  for (let i = 0; i < ids.length; i++) {
    const r = cardRect(i, ids.length);
    if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) {
      G.buildId = ids[i];
      G.selected = null;
      const d = towerDef(ids[i]);
      if (!isUnlocked(d.tier)) {
        const req = requiredMerit(d.tier);
        pushToast(`第 ${d.tier} 档未解锁，需累计 ${req} 功勋`);
      } else {
        pushToast(`${d.name}（${d.cost} 金币）`);
      }
      return true;
    }
  }
  return false;
}

function hitSkills(x, y) {
  if (y < LAYOUT.skillY || y > LAYOUT.skillY + LAYOUT.skillH) return false;
  for (let i = 0; i < SKILLS.length; i++) {
    const r = skillRect(i, SKILLS.length);
    if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) {
      useSkill(SKILLS[i].id);
      return true;
    }
  }
  return true;
}

function onPointerDown(ev) {
  if (!G.cfg) return;
  ev.preventDefault();
  const p = screenToLogical(ev.clientX, ev.clientY);

  // 结束页：任意点击按钮区域重开
  if (G.gameOver) {
    const btn = { x: LAYOUT.W / 2 - 110, y: 820, w: 220, h: 56 };
    if (p.x >= btn.x && p.x <= btn.x + btn.w && p.y >= btn.y && p.y <= btn.y + btn.h) {
      resetGame();
      R.terrain = buildTerrain();
    }
    return;
  }

  if (hitTopBar(p.x, p.y)) return;
  if (hitActionBar(p.x, p.y)) return;
  if (hitCards(p.x, p.y)) return;
  if (hitSkills(p.x, p.y)) return;

  // 棋盘
  const cell = logicalToCell(p.x, p.y);
  if (!cell) return;
  const exist = towerAtCell(cell.x, cell.y);
  if (exist) {
    G.selected = exist === G.selected ? null : exist;
  } else {
    placeTower(cell.x, cell.y);
  }
}

function onPointerMove(ev) {
  if (!G.cfg) return;
  const p = screenToLogical(ev.clientX, ev.clientY);
  const cell = logicalToCell(p.x, p.y);
  G.hoverCell = cell;
}

function onKey(ev) {
  if (!G.cfg) return;
  const k = ev.key.toLowerCase();
  if (k === '1') useSkill('rally');
  else if (k === '2') useSkill('freeze');
  else if (k === '3') useSkill('verdict');
  else if (k === 'k') tryUnlockTier();
  else if (k === 'tab') { ev.preventDefault(); G.profIndex = (G.profIndex + 1) % G.professions.length; G.buildId = curProf().towers[0]; G.selected = null; }
  else if (k === 'u') tryUpgrade(G.selected);
  else if (k === 's') trySell(G.selected);
  else if (k === 'r') { resetGame(); R.terrain = buildTerrain(); }
}

// ---------------------------------------------------------------- 主循环
function loop(t) {
  if (!lastT) lastT = t;
  let dt = (t - lastT) / 1000;
  lastT = t;
  // 防止切后台回来后一次跳太多
  dt = Math.min(dt, 0.05);

  if (G.cfg) {
    updateGame(dt);
    drawFrame();
  }
  requestAnimationFrame(loop);
}

// ---------------------------------------------------------------- 启动
async function boot() {
  stageEl = document.getElementById('stage');
  cvEl = document.getElementById('cv');
  bootEl = document.getElementById('boot');
  bootBar = document.getElementById('bootbar');
  bootErr = document.getElementById('booterr');

  bootBar.style.width = '22%';

  let raw;
  if (window.__CONTENT__) {
    // 单文件构建：数据已内联，零网络请求（打包路径）
    raw = window.__CONTENT__;
  } else {
    const url = window.__CONTENT_URL__ || 'content.json';
    try {
      const res = await fetch(url, { cache: 'no-cache' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      raw = await res.json();
    } catch (e) {
      bootErr.textContent = '加载内容数据失败：' + e.message +
        '\n请改用 http 服务打开（例如 python -m http.server），或直接打开打包好的单文件版本。';
      return;
    }
  }
  bootBar.style.width = '60%';

  G.cfg = normalizeData(raw);
  G.map = buildMap(raw.map);
  G.professions = raw.professions.filter(p => p.towers && p.towers.length);
  G.waves = raw.waves;

  resizeStage();
  window.addEventListener('resize', resizeStage);
  window.addEventListener('orientationchange', () => setTimeout(resizeStage, 120));

  initRender(cvEl);
  resetGame();
  bootBar.style.width = '100%';

  cvEl.addEventListener('pointerdown', onPointerDown, { passive: false });
  cvEl.addEventListener('pointermove', onPointerMove, { passive: true });
  cvEl.addEventListener('pointerleave', () => { G.hoverCell = null; });
  window.addEventListener('keydown', onKey);
  // 阻止移动端双击缩放与长按菜单
  cvEl.addEventListener('contextmenu', e => e.preventDefault());
  document.addEventListener('gesturestart', e => e.preventDefault());

  setTimeout(() => {
    bootEl.classList.add('gone');
    setTimeout(() => { bootEl.style.display = 'none'; }, 520);
  }, 260);

  if (new URLSearchParams(location.search).has('demo')) applyDemo();
  requestAnimationFrame(loop);
}

window.addEventListener('DOMContentLoaded', boot);


// ---------------------------------------------------------------- 演示模式
// 访问 ?demo=1 自动布防并开波 —— 用于截图验证与给别人看效果，不影响正式玩法。
function applyDemo() {
  const spots = [
    [0, 0, 'r4'], [4, 2, 'o4'], [0, 3, 'h3'],
    [3, 6, 'b4'], [5, 8, 's4'], [1, 11, 'r5'], [5, 12, 'g4'],
  ];
  G.merit = 260;
  for (let t = 2; t <= 6; t++) G.unlocked[t] = true;
  G.maxTier = 6;
  G.gold = 4200;

  for (const [cx, cy, id] of spots) {
    const def = towerDef(id);
    if (!def) continue;
    G.buildId = id;
    if (buildBlockReason(cx, cy)) continue;
    G.gold -= def.cost;
    const c = LAYOUT.cell;
    const t = {
      uid: ++uidSeq, id: def.id, def, cx, cy,
      x: cx * c + c / 2, y: cy * c + c / 2,
      level: 1 + ((cx + cy) % 3), cooldown: 0,
      kills: 0, killsSeen: 0, spent: def.cost,
      angle: -Math.PI / 2, born: G.time, fireFlash: 0, reportKills: 0,
    };
    G.towers.push(t);
  }
  G.selected = G.towers[0] || null;
  G.profIndex = 0;
  G.buildId = curProf().towers[0];
  // 直接跳到第 6 波（有飞行、有重装），画面更有内容
  for (let i = 0; i < 5; i++) {
    G.waveIndex = i;
    const q = [];
    for (const g of G.waves[i].groups) {
      for (let k = 0; k < g.count; k++) q.push({ enemy: g.enemy, t: 0 });
    }
    // 只补钱不真的刷怪，避免开局的怪堆积
    G.gold += G.waves[i].bonus || 0;
  }
  G.waveIndex = 4;
  G.waveGapTimer = 0;

  // 摆一批敌人分布在路径上，让画面有内容（截图/演示用）
  const types = ['soldier', 'scout', 'brute', 'flyer', 'soldier', 'brute', 'scout', 'flyer', 'soldier'];
  for (let i = 0; i < types.length; i++) {
    spawnEnemy(types[i]);
    const e = G.enemies[G.enemies.length - 1];
    e.dist = G.map.totalLen * (0.06 + i * 0.095);
    e.hp = e.maxHp * (0.45 + 0.45 * ((i * 37) % 100) / 100);
    const p = samplePath(e.dist);
    e.x = p.x; e.y = p.y;
  }
  // BOSS 单独放在后半段
  G.waveIndex = 9;
  spawnEnemy('boss');
  const boss = G.enemies[G.enemies.length - 1];
  boss.dist = G.map.totalLen * 0.62;
  const bp = samplePath(boss.dist);
  boss.x = bp.x; boss.y = bp.y;
  G.waveIndex = 5;

  pushToast('演示模式：已自动布防，波次进行中');
}
