/* Tribes TD · 核心逻辑
 * 纯数据与状态推进，完全不碰 canvas —— 渲染全部在 render.js。
 * 这样同一套规则可以被 web 版和 Godot 版各自消费，数值只有一个来源。
 */
'use strict';

// ---------------------------------------------------------------- 布局常量
const LAYOUT = {
  W: 720, H: 1280,
  topH: 150,          // 顶部资源条
  boardX: 72, boardY: 150,
  cell: 64, cols: 9, rows: 15,
  cardY: 1100, cardH: 96, cardW: 92, cardGap: 8,
  skillY: 1200, skillH: 72, skillW: 150, skillGap: 14,
  actionY: 1012, actionH: 78,
};
const BOARD = {
  w: LAYOUT.cols * LAYOUT.cell,
  h: LAYOUT.rows * LAYOUT.cell,
};

const WAVE_GAP = 2.0;      // 波次之间的自动间隔
const TIER_REQ = { 2: 14, 3: 34, 4: 70, 5: 130, 6: 210, 7: 320 };
const POP_BASE = 4, POP_MAX = 12;

const SKILLS = [
  { id: 'rally',   name: '增援', cost: 8,  desc: '立刻获得 90 金币', key: '1' },
  { id: 'freeze',  name: '冰封', cost: 18, desc: '全场减速 55%，4 秒', key: '2' },
  { id: 'verdict', name: '裁决', cost: 40, desc: '对最强敌人造成 420 真实伤害（不计功勋）', key: '3' },
];

// ---------------------------------------------------------------- 状态
const G = {
  cfg: null,
  map: null,          // {cols, rows, cell, pathCells:Set('x,y'), blocked:Set, poly:[{x,y}], totalLen}
  towers: [],
  enemies: [],
  particles: [],
  floaters: [],
  rings: [],          // 溅射/死亡波纹
  gold: 0, merit: 0, lives: 0,
  unlocked: { 1: true }, maxTier: 1,
  waves: [], waveIndex: -1,
  spawnQueue: [], spawnTimer: 0, active: false,
  waveGapTimer: 0,
  gameOver: false, won: false,
  buildId: null,
  selected: null,
  hoverCell: null,
  professionalism: 0,
  professions: [],
  profIndex: 0,
  toast: '', toastT: 0,
  time: 0,
  shake: 0,
  flashes: [],        // 屏幕闪红
};

// ---------------------------------------------------------------- 工具
const clamp = (v, a, b) => v < a ? a : (v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;
const rnd = (a, b) => a + Math.random() * (b - a);
const cellKey = (x, y) => x + ',' + y;

function hexToRgb(h) {
  h = h.replace('#', '');
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}
function rgba(h, a) {
  const [r, g, b] = hexToRgb(h);
  return `rgba(${r},${g},${b},${a})`;
}
function shade(h, k) {
  const [r, g, b] = hexToRgb(h);
  return `rgb(${clamp(Math.round(r * k), 0, 255)},${clamp(Math.round(g * k), 0, 255)},${clamp(Math.round(b * k), 0, 255)})`;
}

// ---------------------------------------------------------------- 初始化
function normalizeData(raw) {
  const cfg = raw;
  cfg.towersById = {};
  for (const t of cfg.towers) cfg.towersById[t.id] = t;
  cfg.enemiesById = {};
  for (const e of cfg.enemies) cfg.enemiesById[e.id] = e;
  return cfg;
}

function buildMap(m) {
  const out = {
    cols: m.cols, rows: m.rows, cell: m.cell,
    pathCells: new Set(),
    blocked: new Set((m.blocked || []).map(([x, y]) => cellKey(x, y))),
    poly: [],
    totalLen: 0,
  };
  // 航点 → 世界坐标折线（每段严格水平或垂直，与 gen_content.py 的断言一致）
  const c = m.cell;
  for (const [x, y] of m.path) out.poly.push({ x: x * c + c / 2, y: y * c + c / 2 });
  for (let i = 1; i < out.poly.length; i++) {
    const a = out.poly[i - 1], b = out.poly[i];
    out.totalLen += Math.hypot(b.x - a.x, b.y - a.y);
  }
  // 路径格集合（用于禁止建塔 + 铺石板）
  for (let i = 1; i < m.path.length; i++) {
    let [ax, ay] = m.path[i - 1], [bx, by] = m.path[i];
    const sx = Math.sign(bx - ax), sy = Math.sign(by - ay);
    let x = ax, y = ay;
    let guard = 0;
    while ((x !== bx || y !== by) && guard++ < 500) {
      out.pathCells.add(cellKey(x, y));
      x += sx; y += sy;
    }
    out.pathCells.add(cellKey(bx, by));
  }
  return out;
}

function resetGame() {
  G.towers = []; G.enemies = []; G.particles = []; G.floaters = []; G.rings = []; G.flashes = [];
  G.gold = G.cfg.start_gold;
  G.merit = 0;
  G.lives = G.cfg.lives;
  G.unlocked = { 1: true };
  G.maxTier = 1;
  G.waveIndex = -1;
  G.spawnQueue = []; G.spawnTimer = 0; G.active = false; G.waveGapTimer = 0;
  G.gameOver = false; G.won = false;
  G.selected = null; G.hoverCell = null;
  G.time = 0; G.shake = 0;
  G.toast = ''; G.toastT = 0;
  G.profIndex = 0;
  G.buildId = G.professions[0].towers[0];
  pushToast('选一个部族，点地图造塔。塔的击杀会攒功勋。');
}

// ---------------------------------------------------------------- 派族 / 塔
function curProf() { return G.professions[G.profIndex]; }
function towerDef(id) { return G.cfg.towersById[id] || null; }
function tierOf(id) { return towerDef(id) ? towerDef(id).tier : 1; }
function isUnlocked(tier) { return !!G.unlocked[tier]; }
function nextLockedTier() {
  for (let t = 1; t <= 7; t++) if (!G.unlocked[t]) return t;
  return 0;
}
function popCap() { return Math.min(POP_MAX, POP_BASE + (G.maxTier - 1)); }
function popUsed() { return G.towers.length; }

function requiredMerit(tier) { return TIER_REQ[tier] || 0; }

function tryUnlockTier() {
  const t = nextLockedTier();
  if (!t) { pushToast('全部档位已解锁'); return false; }
  const req = requiredMerit(t);
  if (G.merit < req) { pushToast(`第 ${t} 档需 ${req} 功勋（现有 ${G.merit}）`); return false; }
  G.merit -= req;
  G.unlocked[t] = true;
  G.maxTier = Math.max(G.maxTier, t);
  pushToast(`第 ${t} 档解锁 · 人口上限 ${popCap()}`);
  return true;
}

function buildBlockReason(cx, cy) {
  const def = towerDef(G.buildId);
  if (!def) return '没有选中单位';
  if (!isUnlocked(def.tier)) return `第 ${def.tier} 档未解锁，需累计 ${requiredMerit(def.tier)} 功勋`;
  if (popUsed() >= popCap()) return `人口已满 ${popUsed()}/${popCap()}`;
  if (cx < 0 || cy < 0 || cx >= G.map.cols || cy >= G.map.rows) return '';
  if (G.map.pathCells.has(cellKey(cx, cy))) return '不能建在路径上';
  if (G.map.blocked.has(cellKey(cx, cy))) return '这块地不能建塔';
  if (towerAtCell(cx, cy)) return '这里已经有塔了';
  if (G.gold < def.cost) return `金币不足（需 ${def.cost}）`;
  return '';
}

function towerAtCell(cx, cy) {
  for (const t of G.towers) if (t.cx === cx && t.cy === cy) return t;
  return null;
}

function placeTower(cx, cy) {
  const why = buildBlockReason(cx, cy);
  if (why) { pushToast(why); return false; }
  const def = towerDef(G.buildId);
  G.gold -= def.cost;
  const c = LAYOUT.cell;
  const t = {
    uid: ++uidSeq,
    id: def.id, def,
    cx, cy,
    x: cx * c + c / 2, y: cy * c + c / 2,
    level: 1,
    cooldown: 0,
    kills: 0,
    killsSeen: 0,
    spent: def.cost,
    angle: -Math.PI / 2,
    born: G.time,
    fireFlash: 0,
    reportKills: 0,   // 由 update 结算到功勋
  };
  G.towers.push(t);
  G.selected = t;
  pushToast(`${def.name} 已就位`);
  spawnRing(t.x, t.y, def.range, rgba(def.color, .5), .45);
  return true;
}

function statOf(t) {
  // 档内升级：1 / 2 / 3 级，数值来自 levels 数组
  const d = t.def;
  if (t.level <= 1) return { damage: d.damage, range: d.range, interval: d.interval };
  const lv = d.levels[Math.min(t.level - 2, d.levels.length - 1)];
  return { damage: lv.damage, range: lv.range, interval: lv.interval };
}
function upgradeCost(t) {
  if (t.level >= 4) return 0;
  const d = t.def;
  if (t.level === 1) return Math.round(d.cost * 1.1);
  return d.levels[Math.min(t.level - 2, d.levels.length - 1)].cost;
}
function tryUpgrade(t) {
  if (!t) return;
  if (t.level >= 4) { pushToast(`${t.def.name} 已满级`); return; }
  const c = upgradeCost(t);
  if (G.gold < c) { pushToast(`金币不足（需 ${c}）`); return; }
  G.gold -= c; t.spent += c; t.level++;
  spawnRing(t.x, t.y, 42, 'rgba(224,168,60,.8)', .5);
  pushToast(`${t.def.name} 升到 ${t.level} 级`);
}
function trySell(t) {
  if (!t) return;
  const refund = Math.floor(t.spent * 0.7);
  G.gold += refund;
  G.towers = G.towers.filter(x => x !== t);
  G.selected = null;
  spawnRing(t.x, t.y, 40, 'rgba(224,168,60,.7)', .4);
  pushToast(`已出售，退回 ${refund} 金币`);
}

// ---------------------------------------------------------------- 波次
function startNextWave() {
  if (G.active || G.gameOver) return false;
  if (G.waveIndex + 1 >= G.waves.length) return false;
  G.waveIndex++;
  const w = G.waves[G.waveIndex];
  const q = [];
  for (const g of w.groups) {
    for (let i = 0; i < g.count; i++) q.push({ enemy: g.enemy, t: i * g.interval });
  }
  q.sort((a, b) => a.t - b.t);
  G.spawnQueue = q;
  G.spawnTimer = 0;
  G.active = true;
  return true;
}

function spawnEnemy(enemyId) {
  const def = G.cfg.enemiesById[enemyId];
  if (!def) return;
  const scale = Math.pow(G.cfg.hp_scale_per_wave, Math.max(G.waveIndex, 0));
  const hp = def.hp * scale;
  G.enemies.push({
    uid: ++uidSeq,
    id: enemyId, def,
    hp, maxHp: hp,
    dist: 0,
    speed: def.speed,
    armor: def.armor || 0,
    bounty: def.bounty,
    leak: def.leak,
    flying: !!def.flying,
    slowFactor: 1, slowTime: 0,
    dead: false, leaked: false,
    hitFlash: 0,
    born: G.time,
    bob: rnd(0, Math.PI * 2),
    facing: 1,
  });
}

// 路径采样：dist → 世界坐标
function samplePath(dist) {
  const poly = G.map.poly;
  let left = dist;
  for (let i = 1; i < poly.length; i++) {
    const a = poly[i - 1], b = poly[i];
    const seg = Math.hypot(b.x - a.x, b.y - a.y);
    if (left <= seg) {
      const t = seg <= 0 ? 0 : left / seg;
      return { x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), dx: (b.x - a.x) / (seg || 1), dy: (b.y - a.y) / (seg || 1) };
    }
    left -= seg;
  }
  const a = poly[poly.length - 2] || poly[0], b = poly[poly.length - 1];
  return { x: b.x, y: b.y, dx: Math.sign(b.x - a.x), dy: Math.sign(b.y - a.y) };
}

// ---------------------------------------------------------------- 伤害
function damageEnemy(e, amount, source) {
  if (e.dead || e.leaked) return 0;
  const real = Math.max(1, amount - (e.armor || 0));
  e.hp -= real;
  e.hitFlash = 0.12;
  if (e.hp <= 0) {
    e.dead = true;
    // 击杀归属：只有 source === 'tower' 才计入塔的 kills → 才产生功勋
    if (source && source.tower) {
      source.tower.kills++;
      source.tower.reportKills++;
      const bonus = source.tower.def.bonus_gold || 0;
      if (bonus > 0) G.gold += bonus;
    }
    onEnemyKilled(e, source);
  }
  return real;
}

function onEnemyKilled(e) {
  G.gold += e.bounty;
  spawnDeath(e);
  pushFloater(e.x, e.y - 10, '+' + e.bounty, '#E0A83C', 15);
}

function leakEnemy(e) {
  e.leaked = true;
  G.lives -= e.leak;
  G.shake = Math.min(1, G.shake + .5);
  G.flashes.push({ t: .45, max: .45 });
  if (G.lives <= 0) { G.lives = 0; G.gameOver = true; pushToast('基地失守'); }
}

// ---------------------------------------------------------------- 技能
function canUseSkill(id) {
  const s = SKILLS.find(x => x.id === id);
  return !!s && G.merit >= s.cost;
}
function useSkill(id) {
  const s = SKILLS.find(x => x.id === id);
  if (!s) return false;
  if (G.merit < s.cost) { pushToast(`功勋不足（${s.name} 需 ${s.cost}）`); return false; }
  if (id === 'rally') {
    G.merit -= s.cost; G.gold += 90;
    pushFloater(LAYOUT.boardX + BOARD.w / 2, LAYOUT.boardY + 200, '+90 金币', '#E0A83C', 26);
    pushToast('增援到位：+90 金币');
  } else if (id === 'freeze') {
    G.merit -= s.cost;
    for (const e of G.enemies) { e.slowFactor = Math.min(e.slowFactor, .45); e.slowTime = Math.max(e.slowTime, 4); }
    for (let i = 0; i < 3; i++) spawnRing(BOARD.w / 2, BOARD.h / 2, 180 + i * 120, 'rgba(120,200,255,.55)', .7);
    pushToast('冰封：全场减速 55%，4 秒');
  } else if (id === 'verdict') {
    let target = null;
    for (const e of G.enemies) if (!e.dead && !e.leaked && (!target || e.hp > target.hp)) target = e;
    if (!target) { pushToast('场上没有目标'); return false; }
    G.merit -= s.cost;
    spawnRing(target.x, target.y, 110, 'rgba(224,168,60,.9)', .6);
    // 关键：source 为 null → 不计功勋。与原版「召唤物/技能击杀不给功勋」一致
    damageEnemy(target, 420, null);
    pushToast('裁决命中');
  }
  return true;
}

// ---------------------------------------------------------------- 提示/特效
function pushToast(msg) { G.toast = msg; G.toastT = 3.0; }
function pushFloater(x, y, text, color, size) {
  G.floaters.push({ x, y, text, color, size: size || 14, t: 0, life: 1.0, vy: -46 });
}
function spawnRing(x, y, r, color, life) {
  G.rings.push({ x, y, r0: 8, r1: r, color, t: 0, life: life || .5 });
}
function spawnDeath(e) {
  const n = e.id === 'boss' ? 44 : (e.id === 'brute' ? 18 : 11);
  const col = enemyColor(e);
  for (let i = 0; i < n; i++) {
    const a = rnd(0, Math.PI * 2), sp = rnd(40, 200);
    G.particles.push({
      x: e.x, y: e.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 40,
      t: 0, life: rnd(.28, .7), r: rnd(1.6, 4.2), color: col, grav: 320,
    });
  }
  spawnRing(e.x, e.y, e.id === 'boss' ? 150 : 46, rgba('#FFFFFF', .55), .38);
  if (e.id === 'boss') G.shake = 1;
}
function spawnHit(x, y, color) {
  for (let i = 0; i < 3; i++) {
    const a = rnd(0, Math.PI * 2), sp = rnd(30, 110);
    G.particles.push({
      x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp,
      t: 0, life: rnd(.12, .26), r: rnd(1.2, 2.6), color: color || '#FFE0A0', grav: 60,
    });
  }
}

function enemyColor(e) {
  switch (e.id) {
    case 'brute': return '#B58A5B';
    case 'flyer': return '#7FC7E8';
    case 'boss': return '#E04B7A';
    case 'scout': return '#C8B87F';
    default: return '#9FB4C6';
  }
}

// ---------------------------------------------------------------- 主更新
let uidSeq = 0;

function updateGame(dt) {
  if (!G.cfg) return;
  G.time += dt;
  G.shake = Math.max(0, G.shake - dt * 2.2);
  if (G.toastT > 0) G.toastT -= dt;

  // 粒子
  for (const p of G.particles) {
    p.t += dt;
    p.x += p.vx * dt; p.y += p.vy * dt;
    p.vy += (p.grav || 0) * dt;
    p.vx *= (1 - dt * 1.6);
  }
  G.particles = G.particles.filter(p => p.t < p.life);

  for (const f of G.floaters) { f.t += dt; f.y += f.vy * dt; f.vy *= (1 - dt * 1.2); }
  G.floaters = G.floaters.filter(f => f.t < f.life);

  for (const r of G.rings) r.t += dt;
  G.rings = G.rings.filter(r => r.t < r.life);

  for (const f of G.flashes) f.t -= dt;
  G.flashes = G.flashes.filter(f => f.t > 0);

  if (G.gameOver) { resolveKills(); return; }

  // 波次调度
  const aliveOrQueued = G.active || G.enemies.length > 0 || G.spawnQueue.length > 0;
  if (!aliveOrQueued) {
    if (G.waveIndex + 1 < G.waves.length) {
      G.waveGapTimer += dt;
      if (G.waveGapTimer >= WAVE_GAP) {
        G.waveGapTimer = 0;
        startNextWave();
      }
    } else if (!G.won && G.waveIndex >= 0) {
      G.won = true; G.gameOver = true;
      pushToast('守住全部波次，通关');
    }
  }

  // 出怪
  if (G.active && G.spawnQueue.length > 0) {
    G.spawnTimer += dt;
    while (G.spawnQueue.length > 0 && G.spawnTimer >= G.spawnQueue[0].t) {
      spawnEnemy(G.spawnQueue.shift().enemy);
    }
    if (G.spawnQueue.length === 0) {
      // 队列空了但仍在波次中，等场上敌人清完
    }
  }

  // 敌人推进
  for (const e of G.enemies) {
    if (e.dead || e.leaked) continue;
    if (e.slowTime > 0) {
      e.slowTime -= dt;
      if (e.slowTime <= 0) e.slowFactor = 1;
    }
    if (e.hitFlash > 0) e.hitFlash -= dt;
    const v = e.speed * e.slowFactor;
    e.dist += v * dt;
    const s = samplePath(e.dist);
    e.x = s.x; e.y = s.y;
    if (Math.abs(s.dx) > 0.1) e.facing = Math.sign(s.dx);
    e.bob += dt * (4 + v * 0.04);
    if (e.dist >= G.map.totalLen) leakEnemy(e);
  }

  // 塔开火
  for (const t of G.towers) {
    const st = statOf(t);
    if (t.cooldown > 0) t.cooldown -= dt;
    if (t.fireFlash > 0) t.fireFlash -= dt;
    if (t.cooldown > 0) continue;
    const target = pickTarget(t, st.range);
    if (!target) continue;
    // 朝向插值（视觉）
    const ang = Math.atan2(target.y - t.y, target.x - t.x);
    let d = ang - t.angle;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    t.angle += d * Math.min(1, dt * 14);

    t.cooldown = st.interval;
    t.fireFlash = 0.09;

    const dmg = st.damage;
    const splash = t.def.splash || 0;
    const src = { tower: t };
    if (splash > 0) {
      spawnRing(target.x, target.y, splash, rgba(t.def.color, .5), .32);
      for (const e of G.enemies) {
        if (e.dead || e.leaked) continue;
        if (Math.hypot(e.x - target.x, e.y - target.y) <= splash) {
          if (applySlowIfAny(t, e)) { /* 减速 */ }
          const real = damageEnemy(e, dmg, src);
          if (e === target) pushFloater(e.x + rnd(-6, 6), e.y - 14, '-' + Math.round(real), '#FFD98A', 13);
        }
      }
    } else {
      applySlowIfAny(t, target);
      const real = damageEnemy(target, dmg, src);
      pushFloater(target.x + rnd(-6, 6), target.y - 14, '-' + Math.round(real), '#FFD98A', 13);
    }
    // 弹道视觉用一条快速衰减的线（hitscan 的观感补足）
    spawnHit(target.x, target.y, t.def.color);
    t.beamTarget = { x: target.x, y: target.y, t: 0.09 };
  }
  for (const t of G.towers) if (t.beamTarget) { t.beamTarget.t -= dt; if (t.beamTarget.t <= 0) t.beamTarget = null; }

  // 清理死亡/漏怪
  G.enemies = G.enemies.filter(e => !e.dead && !e.leaked);

  // 波次结束判定
  if (G.active && G.spawnQueue.length === 0 && G.enemies.length === 0) {
    G.active = false;
    const w = G.waves[G.waveIndex];
    if (w && w.bonus) {
      G.gold += w.bonus;
      pushFloater(BOARD.w / 2, 80, `清波奖励 +${w.bonus}`, '#5BD1A6', 20);
    }
  }

  resolveKills();
}

function applySlowIfAny(t, e) {
  const s = t.def.slow;
  if (!s || s >= 1) return false;
  e.slowFactor = Math.min(e.slowFactor, s);
  e.slowTime = Math.max(e.slowTime, t.def.slow_time || 1);
  return true;
}

// 功勋结算：只读塔自己的击杀增量 —— 这条规则是双资源的根基
function resolveKills() {
  for (const t of G.towers) {
    if (t.reportKills > 0) {
      G.merit += t.reportKills;
      t.reportKills = 0;
    }
  }
}

function pickTarget(t, range) {
  let best = null, bestScore = -Infinity;
  const mode = t.def.targeting || 'first';
  for (const e of G.enemies) {
    if (e.dead || e.leaked) continue;
    if (e.flying && t.def.hits_air === false) continue;
    if (!e.flying && t.def.hits_ground === false) continue;
    const d = Math.hypot(e.x - t.x, e.y - t.y);
    if (d > range) continue;
    let score;
    if (mode === 'strongest') score = e.hp;
    else if (mode === 'last') score = -e.dist;
    else if (mode === 'closest') score = -d;
    else score = e.dist;   // first
    if (score > bestScore) { bestScore = score; best = e; }
  }
  return best;
}
