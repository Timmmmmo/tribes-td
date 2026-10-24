/* Tribes TD · 渲染层
 * 全部程序化绘制，零图片依赖。
 * 地形一次性预渲染到离屏 canvas，每帧只贴一次，保证中低端机的帧率。
 */
'use strict';

const R = {
  cv: null, ctx: null, dpr: 1,
  terrain: null,
  font: '"PingFang SC","Microsoft YaHei","Noto Sans CJK SC",sans-serif',
  mono: '"SF Mono",Consolas,monospace',
};

// roundRect 兼容
if (typeof CanvasRenderingContext2D !== 'undefined' && !CanvasRenderingContext2D.prototype.roundRect) {
  CanvasRenderingContext2D.prototype.roundRect = function (x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    this.beginPath();
    this.moveTo(x + r, y);
    this.arcTo(x + w, y, x + w, y + h, r);
    this.arcTo(x + w, y + h, x, y + h, r);
    this.arcTo(x, y + h, x, y, r);
    this.arcTo(x, y, x + w, y, r);
    this.closePath();
    return this;
  };
}

function initRender(canvas) {
  R.cv = canvas;
  R.ctx = canvas.getContext('2d', { alpha: false });
  R.dpr = Math.min(window.devicePixelRatio || 1, 2.5);
  canvas.width = LAYOUT.W * R.dpr;
  canvas.height = LAYOUT.H * R.dpr;
  canvas.style.width = '100%';
  canvas.style.height = '100%';
  R.terrain = buildTerrain();
}

// ---------------------------------------------------------------- 地形预渲染
function buildTerrain() {
  const c = document.createElement('canvas');
  c.width = LAYOUT.W * R.dpr;
  c.height = LAYOUT.H * R.dpr;
  const g = c.getContext('2d');
  g.scale(R.dpr, R.dpr);

  // 整体底色
  const bg = g.createRadialGradient(360, 520, 60, 360, 520, 780);
  bg.addColorStop(0, '#1D303C');
  bg.addColorStop(0.55, '#132430');
  bg.addColorStop(1, '#0A141C');
  g.fillStyle = bg;
  g.fillRect(0, 0, LAYOUT.W, LAYOUT.H);

  g.save();
  g.translate(LAYOUT.boardX, LAYOUT.boardY);

  // ---- 草地底：多层随机草叶
  g.fillStyle = '#22392C';
  g.fillRect(0, 0, BOARD.w, BOARD.h);
  const grassGrad = g.createLinearGradient(0, 0, BOARD.w, BOARD.h);
  grassGrad.addColorStop(0, 'rgba(72,124,94,.66)');
  grassGrad.addColorStop(0.5, 'rgba(44,86,66,.56)');
  grassGrad.addColorStop(1, 'rgba(28,58,48,.58)');
  g.fillStyle = grassGrad;
  g.fillRect(0, 0, BOARD.w, BOARD.h);

  for (let i = 0; i < 2600; i++) {
    const x = Math.random() * BOARD.w;
    const y = Math.random() * BOARD.h;
    const len = 2 + Math.random() * 5;
    const lean = (Math.random() - 0.5) * 3;
    const a = 0.07 + Math.random() * 0.20;
    g.strokeStyle = Math.random() > 0.72
      ? `rgba(150,205,160,${a})`
      : `rgba(78,140,112,${a})`;
    g.lineWidth = 0.8 + Math.random() * 0.7;
    g.beginPath();
    g.moveTo(x, y);
    g.quadraticCurveTo(x + lean * 0.5, y - len * 0.6, x + lean, y - len);
    g.stroke();
  }

  // ---- 路径：石板
  const cell = LAYOUT.cell;
  const cells = [...G.map.pathCells].map(k => k.split(',').map(Number));

  // 先铺一层外扩阴影，让路"陷"进地面
  for (const pass of [{ off: 5, a: 0.30 }, { off: 2.5, a: 0.22 }]) {
    g.fillStyle = `rgba(0,0,0,${pass.a})`;
    for (const [cx, cy] of cells) {
      g.beginPath();
      g.roundRect(cx * cell - pass.off + 3, cy * cell - pass.off + 4,
        cell + pass.off * 2 - 6, cell + pass.off * 2 - 6, 10);
      g.fill();
    }
  }

  // 石板主体：每格切 2×2 小块，随机抖动，做出石缝
  const stones = [
    { base: '#3A4756', hi: '#4D6070', lo: '#232E38' },
    { base: '#354250', hi: '#475868', lo: '#1F2831' },
    { base: '#3E4C5B', hi: '#526576', lo: '#26313B' },
  ];
  for (const [cx, cy] of cells) {
    const ox = cx * cell, oy = cy * cell;
    for (let sy = 0; sy < 2; sy++) {
      for (let sx = 0; sx < 2; sx++) {
        const jw = 2 + Math.random() * 3;
        const jh = 2 + Math.random() * 3;
        const px = ox + sx * cell / 2 + 0.9 + Math.random() * 0.8;
        const py = oy + sy * cell / 2 + 0.9 + Math.random() * 0.8;
        const pw = cell / 2 - 1.8 - jw * 0.12;
        const ph = cell / 2 - 1.8 - jh * 0.12;
        const st = stones[(Math.random() * stones.length) | 0];
        const gr = g.createLinearGradient(px, py, px + pw, py + ph);
        gr.addColorStop(0, st.hi);
        gr.addColorStop(0.45, st.base);
        gr.addColorStop(1, st.lo);
        g.fillStyle = gr;
        g.beginPath();
        g.roundRect(px, py, pw, ph, 3.5);
        g.fill();
        // 上沿高光
        g.strokeStyle = 'rgba(190,220,240,.22)';
        g.lineWidth = 1;
        g.beginPath();
        g.moveTo(px + 2, py + 0.8);
        g.lineTo(px + pw - 2, py + 0.8);
        g.stroke();
      }
    }
  }

  // 路径轮廓：沿整条路描一层冷光，让路面从草地"浮"出来
  g.save();
  g.globalCompositeOperation = 'lighter';
  g.strokeStyle = 'rgba(120,190,230,.13)';
  g.lineWidth = 9;
  g.lineJoin = 'round';
  g.lineCap = 'round';
  g.beginPath();
  for (let i = 0; i < G.map.poly.length; i++) {
    const p = G.map.poly[i];
    i === 0 ? g.moveTo(p.x, p.y) : g.lineTo(p.x, p.y);
  }
  g.stroke();
  g.strokeStyle = 'rgba(150,210,245,.22)';
  g.lineWidth = 3;
  g.stroke();
  g.restore();

  // ---- 起点与终点标记
  const p0 = G.map.poly[1] || G.map.poly[0];
  const pEnd = G.map.poly[G.map.poly.length - 1];

  // 出生门
  const gx = clamp(p0.x, 20, BOARD.w - 20);
  const gg = g.createRadialGradient(gx, p0.y, 4, gx, p0.y, 62);
  gg.addColorStop(0, 'rgba(224,75,110,.55)');
  gg.addColorStop(1, 'rgba(224,75,110,0)');
  g.fillStyle = gg;
  g.beginPath(); g.arc(gx, p0.y, 62, 0, Math.PI * 2); g.fill();

  // 基地
  const bx = clamp(pEnd.x, 26, BOARD.w - 26);
  const by = clamp(pEnd.y, 26, BOARD.h - 26);
  const bg2 = g.createRadialGradient(bx, by, 4, bx, by, 76);
  bg2.addColorStop(0, 'rgba(90,200,255,.55)');
  bg2.addColorStop(1, 'rgba(90,200,255,0)');
  g.fillStyle = bg2;
  g.beginPath(); g.arc(bx, by, 76, 0, Math.PI * 2); g.fill();

  g.restore();

  // ---- 棋盘外框
  g.strokeStyle = 'rgba(120,170,200,.14)';
  g.lineWidth = 1;
  g.strokeRect(LAYOUT.boardX - 6.5, LAYOUT.boardY - 6.5, BOARD.w + 13, BOARD.h + 13);

  return c;
}

// ---------------------------------------------------------------- 主绘制
function drawFrame() {
  const ctx = R.ctx;
  const now = performance.now() / 1000;
  ctx.save();
  ctx.scale(R.dpr, R.dpr);

  ctx.fillStyle = '#070D13';
  ctx.fillRect(0, 0, LAYOUT.W, LAYOUT.H);

  // 震屏
  let sx = 0, sy = 0;
  if (G.shake > 0.01) {
    sx = (Math.random() - 0.5) * 9 * G.shake;
    sy = (Math.random() - 0.5) * 9 * G.shake;
  }
  ctx.save();
  ctx.translate(sx, sy);

  // 地形（含草地与石板）
  if (R.terrain) ctx.drawImage(R.terrain, 0, 0, LAYOUT.W, LAYOUT.H);

  ctx.save();
  ctx.translate(LAYOUT.boardX, LAYOUT.boardY);

  drawPathFlow(ctx, now);
  drawGrid(ctx);
  drawBaseMarkers(ctx, now);
  drawRings(ctx);
  drawTowers(ctx, now);
  drawEnemies(ctx, now);
  drawParticles(ctx);
  drawFloaters(ctx);
  if (G.hoverCell) drawHover(ctx, now);

  ctx.restore();  // board 坐标结束

  ctx.restore();  // 震屏结束

  // 屏幕级效果
  drawFlash(ctx);
  drawVignette(ctx);
  drawHUD(ctx, now);
  drawToast(ctx);
  drawGameOver(ctx);

  ctx.restore();
}

// ---------------------------------------------------------------- 路径流动
function drawPathFlow(ctx, now) {
  const poly = G.map.poly;
  const total = G.map.totalLen;
  if (total <= 0) return;
  ctx.save();
  for (let i = 0; i < 14; i++) {
    const d = ((now * 46 + i * (total / 14)) % total);
    const p = samplePath(d);
    const a = 0.10 + 0.10 * Math.sin(now * 2 + i);
    ctx.fillStyle = `rgba(140,200,230,${a})`;
    ctx.beginPath();
    ctx.arc(p.x, p.y, 2.6, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

function drawGrid(ctx) {
  const cell = LAYOUT.cell;
  ctx.save();
  ctx.strokeStyle = 'rgba(120,170,200,.055)';
  ctx.lineWidth = 1;
  for (let x = 0; x <= LAYOUT.cols; x++) {
    ctx.beginPath(); ctx.moveTo(x * cell, 0); ctx.lineTo(x * cell, BOARD.h); ctx.stroke();
  }
  for (let y = 0; y <= LAYOUT.rows; y++) {
    ctx.beginPath(); ctx.moveTo(0, y * cell); ctx.lineTo(BOARD.w, y * cell); ctx.stroke();
  }
  ctx.restore();
}

function drawBaseMarkers(ctx, now) {
  const pEnd = G.map.poly[G.map.poly.length - 1];
  const bx = clamp(pEnd.x, 26, BOARD.w - 26);
  const by = clamp(pEnd.y, 26, BOARD.h - 26);
  const pulse = 0.5 + 0.5 * Math.sin(now * 2.6);
  ctx.save();
  // 基地水晶
  ctx.translate(bx, by);
  ctx.rotate(now * 0.6);
  for (let i = 0; i < 3; i++) {
    ctx.beginPath();
    ctx.moveTo(0, -20 + i * 3);
    ctx.lineTo(14 - i * 2, 0);
    ctx.lineTo(0, 20 - i * 3);
    ctx.lineTo(-14 + i * 2, 0);
    ctx.closePath();
    ctx.strokeStyle = `rgba(120,210,255,${0.28 - i * 0.07 + pulse * 0.12})`;
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }
  ctx.restore();
}

// ---------------------------------------------------------------- 波纹
function drawRings(ctx) {
  for (const r of G.rings) {
    const k = r.t / r.life;
    const rad = lerp(r.r0, r.r1, k * k * 0.6 + k * 0.4);
    const a = (1 - k) * 0.85;
    ctx.save();
    ctx.strokeStyle = r.color.replace(/[\d.]+\)$/, a + ')');
    ctx.lineWidth = Math.max(0.6, 3.2 * (1 - k));
    ctx.beginPath();
    ctx.arc(r.x, r.y, rad, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }
}

// ---------------------------------------------------------------- 塔
function drawTowers(ctx, now) {
  // 按 y 排序，制造前后遮挡
  const list = [...G.towers].sort((a, b) => a.y - b.y);
  for (const t of list) drawTower(ctx, t, now);
}

function polyPoints(ctx, x, y, r, n, rot) {
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const a = rot + Math.PI * 2 * i / n;
    const px = x + Math.cos(a) * r, py = y + Math.sin(a) * r;
    i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
  }
  ctx.closePath();
}

function drawTower(ctx, t, now) {
  const def = t.def;
  const col = def.color;
  const st = statOf(t);
  const isSel = G.selected === t;
  const breathe = 1 + 0.03 * Math.sin(now * 2.2 + t.uid);
  const s = (20 + t.level * 2.4) * breathe;

  ctx.save();
  ctx.translate(t.x, t.y);

  // 地面投影
  ctx.fillStyle = 'rgba(0,0,0,.48)';
  ctx.beginPath();
  ctx.ellipse(0, s * 0.74, s * 0.94, s * 0.36, 0, 0, Math.PI * 2);
  ctx.fill();

  // 选中射程
  if (isSel) {
    const pr = 0.5 + 0.5 * Math.sin(now * 3);
    ctx.save();
    ctx.beginPath(); ctx.arc(0, 0, st.range, 0, Math.PI * 2);
    ctx.fillStyle = rgba(col, 0.055 + pr * 0.03);
    ctx.fill();
    ctx.strokeStyle = rgba(col, 0.45 + pr * 0.2);
    ctx.lineWidth = 1.6;
    ctx.setLineDash([7, 7]);
    ctx.lineDashOffset = -now * 22;
    ctx.stroke();
    ctx.restore();
  }

  // 外光环（呼吸）
  const halo = ctx.createRadialGradient(0, 0, s * 0.6, 0, 0, st.range * 0.34);
  halo.addColorStop(0, rgba(col, 0.16));
  halo.addColorStop(1, rgba(col, 0));
  ctx.fillStyle = halo;
  ctx.beginPath(); ctx.arc(0, 0, st.range * 0.34, 0, Math.PI * 2); ctx.fill();

  // 石台：八边形石座，压住场面
  const plinth = ctx.createLinearGradient(0, -s, 0, s);
  plinth.addColorStop(0, '#46586A');
  plinth.addColorStop(0.52, '#2B3541');
  plinth.addColorStop(1, '#151C24');
  polyPoints(ctx, 0, 0, s * 1.0, 8, Math.PI / 8);
  ctx.fillStyle = plinth;
  ctx.fill();
  ctx.strokeStyle = 'rgba(4,9,14,.9)';
  ctx.lineWidth = 2;
  ctx.stroke();

  // 石台内圈：部族色细线
  polyPoints(ctx, 0, 0, s * 0.90, 8, Math.PI / 8);
  ctx.strokeStyle = rgba(col, 0.42);
  ctx.lineWidth = 1.3;
  ctx.stroke();

  // 石台四角钉
  for (let i = 0; i < 4; i++) {
    const a = Math.PI / 4 + i * Math.PI / 2;
    ctx.beginPath();
    ctx.arc(Math.cos(a) * s * 0.80, Math.sin(a) * s * 0.80, 2, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(160,190,210,.34)';
    ctx.fill();
  }

  // 符文环：慢速旋转，暗示这是一座"施法建筑"
  ctx.save();
  ctx.rotate(now * 0.5 + t.uid);
  ctx.strokeStyle = rgba(col, 0.40);
  ctx.lineWidth = 1.4;
  ctx.setLineDash([4, 7]);
  ctx.beginPath(); ctx.arc(0, 0, s * 0.66, 0, Math.PI * 2); ctx.stroke();
  ctx.restore();

  // 炮管：先画，让它从塔身后面伸出来
  ctx.save();
  ctx.rotate(t.angle);
  const muz = t.fireFlash > 0 ? 1 + t.fireFlash * 10 : 1;
  const bx0 = s * 0.28, blen = s * 0.92 * muz;
  ctx.beginPath();
  ctx.roundRect(bx0, -s * 0.18, blen, s * 0.36, s * 0.16);
  ctx.fillStyle = '#141D25';
  ctx.fill();
  ctx.strokeStyle = 'rgba(4,9,14,.9)';
  ctx.lineWidth = 1.5;
  ctx.stroke();
  const mgg = ctx.createLinearGradient(bx0, 0, bx0 + blen, 0);
  mgg.addColorStop(0, rgba(col, 0.95));
  mgg.addColorStop(1, rgba(col, 0.18));
  ctx.beginPath();
  ctx.roundRect(bx0 + 2, -s * 0.09, Math.max(blen - 4, 3), s * 0.18, s * 0.09);
  ctx.fillStyle = mgg;
  ctx.fill();
  ctx.restore();

  // 塔身
  const bodyGrad = ctx.createLinearGradient(0, -s * 0.8, 0, s * 0.8);
  bodyGrad.addColorStop(0, shade(col, 1.55));
  bodyGrad.addColorStop(0.48, col);
  bodyGrad.addColorStop(1, shade(col, 0.48));

  ctx.save();
  ctx.rotate(t.angle + Math.PI / 2);
  const shape = def.shape || 'square';
  const bs = s * 0.64;
  if (shape === 'circle') {
    ctx.beginPath(); ctx.arc(0, 0, bs, 0, Math.PI * 2);
  } else if (shape === 'diamond') {
    polyPoints(ctx, 0, 0, bs * 1.16, 4, 0);
  } else if (shape === 'hex') {
    polyPoints(ctx, 0, 0, bs * 1.06, 6, 0);
  } else if (shape === 'star') {
    // 星形：外 10 点交替半径
    ctx.beginPath();
    for (let i = 0; i < 10; i++) {
      const rr = i % 2 === 0 ? bs * 1.2 : bs * 0.56;
      const a = -Math.PI / 2 + Math.PI * 2 * i / 10;
      const px = Math.cos(a) * rr, py = Math.sin(a) * rr;
      i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
    }
    ctx.closePath();
  } else {
    ctx.roundRect(-bs, -bs, bs * 2, bs * 2, bs * 0.34);
  }
  // 塔身自带辉光，让它在暗底上浮起来
  ctx.save();
  ctx.shadowColor = rgba(col, 0.55);
  ctx.shadowBlur = 9 + t.level * 2;
  ctx.fillStyle = bodyGrad;
  ctx.fill();
  ctx.restore();

  ctx.strokeStyle = 'rgba(4,9,14,.85)';
  ctx.lineWidth = 2.2;
  ctx.stroke();
  // 内高光
  ctx.strokeStyle = 'rgba(255,255,255,.40)';
  ctx.lineWidth = 1.2;
  ctx.save();
  ctx.scale(0.74, 0.74);
  ctx.stroke();
  ctx.restore();
  // 塔心
  ctx.beginPath();
  ctx.arc(0, 0, bs * 0.28, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(255,255,255,.62)';
  ctx.fill();
  ctx.restore();

  // 开火闪光
  if (t.fireFlash > 0) {
    const k = t.fireFlash / 0.09;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    const fg = ctx.createRadialGradient(0, 0, 0, 0, 0, s * 2.1 * k);
    fg.addColorStop(0, rgba('#FFFFFF', 0.55 * k));
    fg.addColorStop(0.4, rgba(col, 0.30 * k));
    fg.addColorStop(1, rgba(col, 0));
    ctx.fillStyle = fg;
    ctx.beginPath(); ctx.arc(0, 0, s * 2.1 * k, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  }

  // 弹道
  if (t.beamTarget) {
    const k = t.beamTarget.t / 0.09;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = rgba(col, 0.75 * k);
    ctx.lineWidth = 3 * k;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(t.beamTarget.x - t.x, t.beamTarget.y - t.y);
    ctx.stroke();
    ctx.restore();
  }

  // 等级徽章（升级过才显示，避免满屏数字）
  if (t.level > 1) {
    const bxx = s * 0.74, byy = s * 0.72, br = 9;
    ctx.beginPath(); ctx.arc(bxx, byy, br, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(8,14,20,.95)';
    ctx.fill();
    ctx.strokeStyle = rgba(col, 0.9);
    ctx.lineWidth = 1.5;
    ctx.stroke();
    txt(ctx, String(t.level), bxx, byy - 5, 10.5, '#EAF4FF', 'center', 800);
  }

  ctx.restore();
}

// ---------------------------------------------------------------- 敌人
function drawEnemies(ctx, now) {
  const list = [...G.enemies].sort((a, b) => a.y - b.y);
  for (const e of list) drawEnemy(ctx, e, now);
}

function drawEnemy(ctx, e, now) {
  const col = enemyColor(e);
  const boss = e.id === 'boss';
  const brute = e.id === 'brute';
  const flyer = e.flying;
  const baseR = boss ? 32 : (brute ? 22 : 16);
  const bob = Math.sin(e.bob) * (flyer ? 4.5 : 2.2);
  const y = e.y + (flyer ? -8 + bob : bob * 0.5);

  ctx.save();
  ctx.translate(e.x, y);

  // 影子
  ctx.fillStyle = 'rgba(0,0,0,.38)';
  ctx.beginPath();
  ctx.ellipse(0, baseR * 0.95 - bob * 0.3, baseR * 0.82, baseR * 0.32, 0, 0, Math.PI * 2);
  ctx.fill();

  // 减速：冰壳
  if (e.slowTime > 0) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    const ig = ctx.createRadialGradient(0, 0, baseR * 0.4, 0, 0, baseR * 2);
    ig.addColorStop(0, 'rgba(130,205,255,.30)');
    ig.addColorStop(1, 'rgba(130,205,255,0)');
    ctx.fillStyle = ig;
    ctx.beginPath(); ctx.arc(0, 0, baseR * 2, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  }

  // 身体
  const bodyGrad = ctx.createLinearGradient(0, -baseR, 0, baseR);
  bodyGrad.addColorStop(0, shade(col, 1.55));
  bodyGrad.addColorStop(0.55, col);
  bodyGrad.addColorStop(1, shade(col, 0.62));

  ctx.beginPath();
  if (flyer) {
    // 飞行：菱形
    ctx.moveTo(0, -baseR);
    ctx.lineTo(baseR * 0.95, 0);
    ctx.lineTo(0, baseR * 0.8);
    ctx.lineTo(-baseR * 0.95, 0);
    ctx.closePath();
  } else if (boss) {
    ctx.arc(0, 0, baseR, 0, Math.PI * 2);
  } else if (brute) {
    ctx.roundRect(-baseR, -baseR * 0.92, baseR * 2, baseR * 1.84, baseR * 0.3);
  } else {
    ctx.arc(0, 0, baseR, 0, Math.PI * 2);
  }
  ctx.fillStyle = bodyGrad;
  ctx.fill();
  ctx.strokeStyle = 'rgba(4,9,14,.85)';
  ctx.lineWidth = 2.6;
  ctx.stroke();

  // 内高光
  ctx.save();
  ctx.globalAlpha = .28;
  ctx.beginPath();
  ctx.ellipse(-baseR * 0.28, -baseR * 0.42, baseR * 0.44, baseR * 0.3, -0.5, 0, Math.PI * 2);
  ctx.fillStyle = '#FFFFFF';
  ctx.fill();
  ctx.restore();

  // 眼睛：朝行进方向的斜眼 + 压眉，做出凶相
  const fx = e.facing >= 0 ? 1 : -1;
  const eyeY = -baseR * 0.06;
  for (const sgn of [-1, 1]) {
    const ecx = sgn * baseR * 0.30 + fx * baseR * 0.10;
    ctx.beginPath();
    ctx.ellipse(ecx, eyeY, baseR * 0.19, baseR * 0.155, 0, 0, Math.PI * 2);
    ctx.fillStyle = boss ? '#FFE9A6' : '#F2F8FF';
    ctx.fill();
    ctx.beginPath();
    ctx.arc(ecx + fx * baseR * 0.05, eyeY + baseR * 0.02, baseR * 0.088, 0, Math.PI * 2);
    ctx.fillStyle = '#0A1218';
    ctx.fill();
    // 眉：内侧下压
    ctx.beginPath();
    ctx.moveTo(sgn * baseR * 0.52, eyeY - baseR * 0.30);
    ctx.lineTo(sgn * baseR * 0.10, eyeY - baseR * 0.10);
    ctx.strokeStyle = 'rgba(8,14,20,.88)';
    ctx.lineWidth = Math.max(1.3, baseR * 0.10);
    ctx.lineCap = 'round';
    ctx.stroke();
  }

  // BOSS 光环
  if (boss) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    const pr = 0.5 + 0.5 * Math.sin(now * 3.4);
    ctx.strokeStyle = `rgba(224,75,122,${0.35 + pr * 0.3})`;
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(0, 0, baseR * (1.35 + pr * 0.15), 0, Math.PI * 2); ctx.stroke();
    ctx.restore();
  }

  // 受击闪白
  if (e.hitFlash > 0) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = Math.min(1, e.hitFlash / 0.12) * 0.75;
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    if (boss) ctx.arc(0, 0, baseR, 0, Math.PI * 2);
    else ctx.arc(0, 0, baseR * 0.95, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  ctx.restore();

  // 血条（屏幕坐标，不随旋转）
  const hpRatio = clamp(e.hp / e.maxHp, 0, 1);
  {
    const bw = boss ? 86 : (brute ? 50 : 40);
    const bh = boss ? 7 : 5;
    const bxp = e.x - bw / 2;
    const byp = y - baseR - 7;
    ctx.save();
    ctx.fillStyle = 'rgba(0,0,0,.6)';
    ctx.beginPath(); ctx.roundRect(bxp - 1, byp - 1, bw + 2, bh + 2, (bh + 2) / 2); ctx.fill();
    const hg = ctx.createLinearGradient(bxp, 0, bxp + bw, 0);
    if (hpRatio > 0.55) { hg.addColorStop(0, '#4BE08A'); hg.addColorStop(1, '#2ECC71'); }
    else if (hpRatio > 0.28) { hg.addColorStop(0, '#FFD166'); hg.addColorStop(1, '#E8A93C'); }
    else { hg.addColorStop(0, '#FF6B6B'); hg.addColorStop(1, '#C43C3C'); }
    ctx.fillStyle = hg;
    ctx.beginPath(); ctx.roundRect(bxp, byp, bw * hpRatio, bh, bh / 2); ctx.fill();
    ctx.restore();
  }
}

// ---------------------------------------------------------------- 粒子 / 飘字
function drawParticles(ctx) {
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  for (const p of G.particles) {
    const k = 1 - p.t / p.life;
    ctx.globalAlpha = k * 0.9;
    ctx.fillStyle = p.color;
    ctx.beginPath();
    ctx.arc(p.x, p.y, p.r * (0.4 + k * 0.8), 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

function drawFloaters(ctx) {
  ctx.save();
  for (const f of G.floaters) {
    const k = 1 - f.t / f.life;
    ctx.globalAlpha = Math.min(1, k * 1.6);
    ctx.font = `700 ${f.size}px ${R.font}`;
    ctx.textAlign = 'center';
    ctx.lineWidth = 3.2;
    ctx.strokeStyle = 'rgba(4,8,12,.85)';
    ctx.strokeText(f.text, f.x, f.y);
    ctx.fillStyle = f.color;
    ctx.fillText(f.text, f.x, f.y);
  }
  ctx.restore();
}

// ---------------------------------------------------------------- 悬停预览
function drawHover(ctx, now) {
  const { x: cx, y: cy } = G.hoverCell;
  if (cx < 0 || cy < 0 || cx >= LAYOUT.cols || cy >= LAYOUT.rows) return;
  const cell = LAYOUT.cell;
  const ox = cx * cell, oy = cy * cell;
  const exists = towerAtCell(cx, cy);
  const ok = !exists && buildBlockReason(cx, cy) === '';

  ctx.save();
  if (ok) {
    ctx.fillStyle = 'rgba(46,204,113,.13)';
    ctx.fillRect(ox, oy, cell, cell);
    ctx.strokeStyle = 'rgba(46,204,113,.75)';
    ctx.lineWidth = 2;
    ctx.strokeRect(ox + 1, oy + 1, cell - 2, cell - 2);

    // 射程预览
    const def = towerDef(G.buildId);
    if (def) {
      const pr = 0.5 + 0.5 * Math.sin(now * 4);
      const cxx = ox + cell / 2, cyy = oy + cell / 2;
      ctx.beginPath(); ctx.arc(cxx, cyy, def.range, 0, Math.PI * 2);
      ctx.fillStyle = rgba(def.color, 0.06 + pr * 0.03);
      ctx.fill();
      ctx.strokeStyle = rgba(def.color, 0.4 + pr * 0.15);
      ctx.lineWidth = 1.6;
      ctx.setLineDash([6, 6]);
      ctx.stroke();
      ctx.setLineDash([]);
    }
  } else if (!exists) {
    ctx.fillStyle = 'rgba(225,85,85,.13)';
    ctx.fillRect(ox, oy, cell, cell);
    ctx.strokeStyle = 'rgba(225,85,85,.7)';
    ctx.lineWidth = 2;
    ctx.strokeRect(ox + 1, oy + 1, cell - 2, cell - 2);
  }
  ctx.restore();
}

// ---------------------------------------------------------------- 屏幕效果
function drawFlash(ctx) {
  if (!G.flashes.length) return;
  let a = 0;
  for (const f of G.flashes) a = Math.max(a, (f.t / f.max) * 0.30);
  if (a <= 0) return;
  const g = ctx.createRadialGradient(360, 640, 200, 360, 640, 760);
  g.addColorStop(0, `rgba(225,60,60,0)`);
  g.addColorStop(1, `rgba(225,60,60,${a})`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, LAYOUT.W, LAYOUT.H);
}

function drawVignette(ctx) {
  const g = ctx.createRadialGradient(360, 620, 300, 360, 620, 820);
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(0,0,0,.42)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, LAYOUT.W, LAYOUT.H);
}

// ================================================================ HUD
function rr(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}
function txt(ctx, s, x, y, size, color, align, weight) {
  ctx.font = `${weight || 400} ${size}px ${R.font}`;
  ctx.textAlign = align || 'left';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = color;
  ctx.fillText(s, x, y);
}
function txtW(ctx, s, size, weight) {
  ctx.font = `${weight || 400} ${size}px ${R.font}`;
  return ctx.measureText(s).width;
}

function glassPanel(ctx, x, y, w, h, r, tint) {
  ctx.save();
  const g = ctx.createLinearGradient(x, y, x, y + h);
  g.addColorStop(0, tint || 'rgba(28,44,58,.92)');
  g.addColorStop(1, 'rgba(12,22,32,.94)');
  ctx.fillStyle = g;
  rr(ctx, x, y, w, h, r);
  ctx.fill();
  ctx.strokeStyle = 'rgba(140,185,215,.16)';
  ctx.lineWidth = 1;
  ctx.stroke();
  // 顶部高光
  ctx.beginPath();
  ctx.moveTo(x + r, y + 0.6);
  ctx.lineTo(x + w - r, y + 0.6);
  ctx.strokeStyle = 'rgba(230,245,255,.13)';
  ctx.lineWidth = 1.2;
  ctx.stroke();
  ctx.restore();
}

function drawHUD(ctx, now) {
  drawTopBar(ctx, now);
  drawActionBar(ctx, now);
  drawCards(ctx, now);
  drawSkills(ctx, now);
}

function drawTopBar(ctx, now) {
  const H = LAYOUT.topH;
  ctx.save();
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, 'rgba(18,30,42,.97)');
  g.addColorStop(1, 'rgba(9,16,24,.97)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, LAYOUT.W, H);

  // 底部分隔线：青绿→琥珀渐变，带发光
  const lg = ctx.createLinearGradient(0, 0, LAYOUT.W, 0);
  lg.addColorStop(0, 'rgba(30,158,143,.9)');
  lg.addColorStop(0.55, 'rgba(224,168,60,.75)');
  lg.addColorStop(1, 'rgba(30,158,143,.25)');
  ctx.fillStyle = lg;
  ctx.fillRect(0, H - 2, LAYOUT.W, 2);
  ctx.save();
  ctx.globalAlpha = .35;
  ctx.fillStyle = lg;
  ctx.fillRect(0, H - 5, LAYOUT.W, 3);
  ctx.restore();

  // ---- 金币
  ctx.save();
  const cg = ctx.createRadialGradient(38, 42, 2, 38, 42, 26);
  cg.addColorStop(0, 'rgba(224,168,60,.55)');
  cg.addColorStop(1, 'rgba(224,168,60,0)');
  ctx.fillStyle = cg;
  ctx.beginPath(); ctx.arc(38, 42, 26, 0, Math.PI * 2); ctx.fill();
  ctx.restore();
  ctx.beginPath(); ctx.arc(38, 42, 8.5, 0, Math.PI * 2);
  ctx.fillStyle = '#E0A83C'; ctx.fill();
  ctx.beginPath(); ctx.arc(36, 39.5, 3, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(255,255,255,.55)'; ctx.fill();

  txt(ctx, '金币', 58, 30, 13, '#7C8FA0');
  txt(ctx, String(G.gold), 58, 54, 30, '#F0C060', 'left', 800);

  // ---- 功勋
  ctx.save();
  const mg = ctx.createRadialGradient(196, 42, 2, 196, 42, 26);
  mg.addColorStop(0, 'rgba(30,158,143,.55)');
  mg.addColorStop(1, 'rgba(30,158,143,0)');
  ctx.fillStyle = mg;
  ctx.beginPath(); ctx.arc(196, 42, 26, 0, Math.PI * 2); ctx.fill();
  ctx.restore();
  ctx.save();
  ctx.translate(196, 42);
  ctx.rotate(Math.PI / 4);
  ctx.beginPath(); ctx.roundRect(-6.5, -6.5, 13, 13, 2.5);
  ctx.fillStyle = '#2EC4A8'; ctx.fill();
  ctx.restore();

  txt(ctx, '功勋', 216, 30, 13, '#7C8FA0');
  txt(ctx, String(G.merit), 216, 54, 30, '#4FD6B8', 'left', 800);

  // ---- 生命 / 波次
  const liveCol = G.lives <= 5 ? '#FF6B6B' : '#E8EFF5';
  txt(ctx, '生命', 468, 26, 12, '#7C8FA0');
  txt(ctx, String(G.lives), 468, 52, 26, liveCol, 'left', 800);

  txt(ctx, '波次', 566, 26, 12, '#7C8FA0');
  const wv = Math.max(G.waveIndex + 1, 0);
  txt(ctx, `${wv}/${G.waves.length}`, 566, 52, 20, '#E8EFF5', 'left', 700);

  // 波次进度条
  const pw = 108, px = 566, py = 68;
  ctx.fillStyle = 'rgba(255,255,255,.10)';
  rr(ctx, px, py, pw, 4, 2); ctx.fill();
  ctx.fillStyle = 'rgba(90,200,255,.85)';
  rr(ctx, px, py, pw * clamp(wv / G.waves.length, 0, 1), 4, 2); ctx.fill();

  // ---- 第二行：人口 + 档位进度
  const y2 = 92;
  txt(ctx, '人口', 24, y2 + 6, 12, '#7C8FA0');
  const used = popUsed(), cap = popCap();
  txt(ctx, `${used}/${cap}`, 62, y2 + 6, 16, used >= cap ? '#FF6B6B' : '#D5E2EC', 'left', 700);

  // 人口小格
  for (let i = 0; i < cap && i < 12; i++) {
    const bx = 118 + i * 11;
    ctx.beginPath();
    ctx.arc(bx, y2 + 6, 3.2, 0, Math.PI * 2);
    ctx.fillStyle = i < used ? (used >= cap ? '#FF6B6B' : '#5BD1A6') : 'rgba(255,255,255,.13)';
    ctx.fill();
  }

  // 档位解锁进度
  const nxt = nextLockedTier();
  if (nxt) {
    const req = requiredMerit(nxt);
    const ratio = clamp(G.merit / Math.max(req, 1), 0, 1);
    const bx = 272, bw = 190, by = y2 + 3;
    ctx.fillStyle = 'rgba(255,255,255,.09)';
    rr(ctx, bx, by, bw, 9, 4.5); ctx.fill();
    const fg = ctx.createLinearGradient(bx, 0, bx + bw, 0);
    fg.addColorStop(0, '#1E9E8F');
    fg.addColorStop(1, '#5BD1A6');
    ctx.fillStyle = fg;
    rr(ctx, bx, by, bw * ratio, 9, 4.5); ctx.fill();
    // 扫光
    const sweep = ((now * 0.35) % 1) * bw;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = .28;
    const sg = ctx.createLinearGradient(bx + sweep - 24, 0, bx + sweep + 24, 0);
    sg.addColorStop(0, 'rgba(255,255,255,0)');
    sg.addColorStop(.5, 'rgba(255,255,255,.8)');
    sg.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = sg;
    rr(ctx, bx, by, bw * ratio, 9, 4.5); ctx.fill();
    ctx.restore();

    txt(ctx, `第 ${nxt} 档  ${G.merit}/${req}`, bx, by + 22, 12, '#8FA6B8');
  } else {
    txt(ctx, '全部档位已解锁', 272, y2 + 12, 12, '#8FA6B8');
  }

  // ---- 部族切换
  const p = curProf();
  const cx = LAYOUT.W - 208, cy = y2 - 4, cw = 184, ch = 34;
  glassPanel(ctx, cx, cy, cw, ch, 17, 'rgba(34,52,68,.95)');
  ctx.beginPath();
  ctx.roundRect(cx + 8, cy + 8, 5, ch - 16, 2.5);
  ctx.fillStyle = p.color; ctx.fill();
  txt(ctx, p.name, cx + 22, cy + 12, 15, '#E8EFF5', 'left', 700);
  txt(ctx, '点击换部族', cx + 22, cy + 26, 10, '#6F8798');

  // 波次间倒计时：画成进度条下方的一条细线，不用文字——
  // 这块地方被部族按钮和波次进度条夹着，塞文字必然压字。
  if (!G.active && !G.gameOver && G.waveIndex + 1 < G.waves.length) {
    const left = Math.max(0, WAVE_GAP - G.waveGapTimer);
    const frac = clamp(1 - left / WAVE_GAP, 0, 1);
    ctx.fillStyle = 'rgba(90,200,255,.18)';
    rr(ctx, 566, 78, 108, 2, 1); ctx.fill();
    ctx.fillStyle = 'rgba(120,220,255,.85)';
    rr(ctx, 566, 78, 108 * frac, 2, 1); ctx.fill();
  }
  ctx.restore();
}

function drawActionBar(ctx, now) {
  const t = G.selected;
  if (!t) return;
  const y = LAYOUT.actionY, h = LAYOUT.actionH;
  glassPanel(ctx, 16, y, LAYOUT.W - 32, h, 14);

  const st = statOf(t);
  txt(ctx, `${t.def.name}`, 36, y + 24, 20, '#E8EFF5', 'left', 800);
  const nw = txtW(ctx, t.def.name, 20, 800);
  // 等级徽章
  ctx.beginPath();
  ctx.roundRect(36 + nw + 8, y + 14, 42, 20, 10);
  ctx.fillStyle = rgba(t.def.color, .22); ctx.fill();
  ctx.strokeStyle = rgba(t.def.color, .6); ctx.lineWidth = 1; ctx.stroke();
  txt(ctx, `Lv.${t.level}`, 36 + nw + 29, y + 24, 12, t.def.color, 'center', 700);

  txt(ctx, `伤害 ${st.damage.toFixed(1)}   射程 ${Math.round(st.range)}   击杀 ${t.kills}`,
    36, y + 50, 12.5, '#8FA6B8');

  // 升级按钮
  const canUp = t.level < 4;
  const uc = canUp ? upgradeCost(t) : 0;
  const affordable = canUp && G.gold >= uc;
  const ub = { x: LAYOUT.W - 328, y: y + 12, w: 146, h: 54 };
  ctx.save();
  const ug = ctx.createLinearGradient(ub.x, ub.y, ub.x, ub.y + ub.h);
  if (affordable) { ug.addColorStop(0, 'rgba(46,196,168,.30)'); ug.addColorStop(1, 'rgba(20,90,80,.45)'); }
  else { ug.addColorStop(0, 'rgba(40,54,68,.6)'); ug.addColorStop(1, 'rgba(20,28,36,.7)'); }
  ctx.fillStyle = ug;
  rr(ctx, ub.x, ub.y, ub.w, ub.h, 10); ctx.fill();
  ctx.strokeStyle = affordable ? 'rgba(79,214,184,.75)' : 'rgba(120,150,175,.22)';
  ctx.lineWidth = 1.4; ctx.stroke();
  ctx.restore();
  txt(ctx, '升级', ub.x + ub.w / 2, ub.y + 18, 16, affordable ? '#E8EFF5' : '#6F8798', 'center', 700);
  txt(ctx, canUp ? `${uc} 金币` : '已满级', ub.x + ub.w / 2, ub.y + 38, 12,
    affordable ? '#F0C060' : '#6F8798', 'center', 600);

  // 出售按钮
  const sb = { x: LAYOUT.W - 172, y: y + 12, w: 140, h: 54 };
  ctx.save();
  const sg = ctx.createLinearGradient(sb.x, sb.y, sb.x, sb.y + sb.h);
  sg.addColorStop(0, 'rgba(180,60,60,.28)');
  sg.addColorStop(1, 'rgba(90,26,26,.45)');
  ctx.fillStyle = sg;
  rr(ctx, sb.x, sb.y, sb.w, sb.h, 10); ctx.fill();
  ctx.strokeStyle = 'rgba(225,110,110,.55)'; ctx.lineWidth = 1.4; ctx.stroke();
  ctx.restore();
  txt(ctx, '出售', sb.x + sb.w / 2, sb.y + 18, 16, '#E8EFF5', 'center', 700);
  txt(ctx, `+${Math.floor(t.spent * 0.7)} 金币`, sb.x + sb.w / 2, sb.y + 38, 12, '#E8A0A0', 'center', 600);
}

function cardRect(i, n) {
  const total = n * LAYOUT.cardW + (n - 1) * LAYOUT.cardGap;
  const x0 = (LAYOUT.W - total) / 2;
  return { x: x0 + i * (LAYOUT.cardW + LAYOUT.cardGap), y: LAYOUT.cardY, w: LAYOUT.cardW, h: LAYOUT.cardH };
}

function drawCards(ctx, now) {
  const p = curProf();
  if (!p) return;
  const ids = p.towers;
  for (let i = 0; i < ids.length; i++) {
    const def = towerDef(ids[i]);
    if (!def) continue;
    const r = cardRect(i, ids.length);
    const locked = !isUnlocked(def.tier);
    const sel = G.buildId === ids[i];
    const afford = G.gold >= def.cost;

    ctx.save();
    // 卡片底
    const g = ctx.createLinearGradient(r.x, r.y, r.x, r.y + r.h);
    if (locked) { g.addColorStop(0, 'rgba(22,32,42,.9)'); g.addColorStop(1, 'rgba(14,20,28,.92)'); }
    else if (sel) { g.addColorStop(0, rgba(def.color, .30)); g.addColorStop(1, 'rgba(14,24,32,.96)'); }
    else { g.addColorStop(0, 'rgba(30,46,60,.92)'); g.addColorStop(1, 'rgba(14,22,30,.94)'); }
    ctx.fillStyle = g;
    rr(ctx, r.x, r.y, r.w, r.h, 12); ctx.fill();

    if (sel) {
      ctx.strokeStyle = '#E0A83C'; ctx.lineWidth = 2.4;
      ctx.shadowColor = 'rgba(224,168,60,.7)'; ctx.shadowBlur = 14;
      ctx.stroke();
      ctx.shadowBlur = 0;
    } else {
      ctx.strokeStyle = locked ? 'rgba(120,150,175,.15)' : 'rgba(140,185,215,.20)';
      ctx.lineWidth = 1; ctx.stroke();
    }

    // 档位角标
    ctx.beginPath();
    rr(ctx, r.x + 5, r.y + 5, 25, 17, 8);
    ctx.fillStyle = locked ? 'rgba(120,150,175,.14)' : rgba(def.color, .9);
    ctx.fill();
    txt(ctx, `T${def.tier}`, r.x + 17.5, r.y + 14, 10.5, locked ? '#5F7A8E' : '#08120E', 'center', 800);

    // 图标：用塔的形状缩略
    const icx = r.x + r.w / 2, icy = r.y + 44;
    drawTowerGlyph(ctx, def, icx, icy, locked, now, i);

    // 名称
    txt(ctx, def.name, r.x + r.w / 2, r.y + 66, 13.5,
      locked ? '#5F7A8E' : '#E8EFF5', 'center', 700);

    if (locked) {
      const req = requiredMerit(def.tier);
      txt(ctx, `${req} 功勋`, r.x + r.w / 2, r.y + 84, 11, '#3FBFA6', 'center', 700);
      // 锁图标
      ctx.save();
      ctx.strokeStyle = 'rgba(120,150,175,.5)'; ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.arc(icx, icy - 4, 5, Math.PI, 0);
      ctx.stroke();
      ctx.restore();
    } else {
      txt(ctx, String(def.cost), r.x + r.w / 2, r.y + 84, 15,
        afford ? '#F0C060' : '#C4453F', 'center', 800);
    }
    ctx.restore();
  }
}

function drawTowerGlyph(ctx, def, x, y, locked, now, seed) {
  const s = 17;
  const col = locked ? '#4A5C6B' : def.color;
  ctx.save();
  ctx.translate(x, y);
  // 石台
  polyPoints(ctx, 0, 0, s * 1.02, 8, Math.PI / 8);
  ctx.fillStyle = locked ? 'rgba(44,56,68,.95)' : 'rgba(76,94,112,.98)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(4,9,14,.75)';
  ctx.lineWidth = 1.3;
  ctx.stroke();
  if (!locked) {
    polyPoints(ctx, 0, 0, s * 0.92, 8, Math.PI / 8);
    ctx.strokeStyle = rgba(def.color, .55);
    ctx.lineWidth = 1.1;
    ctx.stroke();
  }
  // 光晕
  if (!locked) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createRadialGradient(0, 0, 1, 0, 0, s * 2);
    g.addColorStop(0, rgba(def.color, .35));
    g.addColorStop(1, rgba(def.color, 0));
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(0, 0, s * 2, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  }
  const bg = ctx.createLinearGradient(0, -s, 0, s);
  bg.addColorStop(0, shade(col, 1.4));
  bg.addColorStop(1, shade(col, 0.6));
  const shape = def.shape || 'square';
  if (shape === 'circle') ctx.beginPath(), ctx.arc(0, 0, s * .82, 0, Math.PI * 2);
  else if (shape === 'diamond') polyPoints(ctx, 0, 0, s * .95, 4, 0);
  else if (shape === 'hex') polyPoints(ctx, 0, 0, s * .90, 6, 0);
  else if (shape === 'star') {
    ctx.beginPath();
    for (let i = 0; i < 10; i++) {
      const rr2 = i % 2 === 0 ? s : s * 0.46;
      const a = -Math.PI / 2 + Math.PI * 2 * i / 10;
      i === 0 ? ctx.moveTo(Math.cos(a) * rr2, Math.sin(a) * rr2)
              : ctx.lineTo(Math.cos(a) * rr2, Math.sin(a) * rr2);
    }
    ctx.closePath();
  } else ctx.roundRect(-s * .78, -s * .78, s * 1.56, s * 1.56, s * .28);

  ctx.fillStyle = bg;
  ctx.fill();
  ctx.strokeStyle = 'rgba(4,10,16,.65)';
  ctx.lineWidth = 1.4;
  ctx.stroke();
  ctx.restore();
}

function skillRect(i, n) {
  const w = LAYOUT.skillW, gap = LAYOUT.skillGap;
  const total = n * w + (n - 1) * gap;
  const x0 = (LAYOUT.W - total) / 2;
  return { x: x0 + i * (w + gap), y: LAYOUT.skillY, w, h: LAYOUT.skillH };
}

function drawSkills(ctx, now) {
  for (let i = 0; i < SKILLS.length; i++) {
    const s = SKILLS[i];
    const r = skillRect(i, SKILLS.length);
    const ok = G.merit >= s.cost;

    ctx.save();
    const g = ctx.createLinearGradient(r.x, r.y, r.x, r.y + r.h);
    if (ok) {
      g.addColorStop(0, 'rgba(30,110,100,.55)');
      g.addColorStop(1, 'rgba(12,40,38,.75)');
    } else {
      g.addColorStop(0, 'rgba(28,40,52,.6)');
      g.addColorStop(1, 'rgba(14,20,28,.7)');
    }
    ctx.fillStyle = g;
    rr(ctx, r.x, r.y, r.w, r.h, 12); ctx.fill();
    ctx.strokeStyle = ok ? 'rgba(79,214,184,.65)' : 'rgba(120,150,175,.16)';
    ctx.lineWidth = 1.4;
    ctx.stroke();

    // 图标区
    const icx = r.x + 30, icy = r.y + r.h / 2;
    drawSkillIcon(ctx, s.id, icx, icy, ok ? '#4FD6B8' : '#4A5C6B');

    txt(ctx, s.name, r.x + 54, r.y + 24, 16, ok ? '#E8EFF5' : '#6F8798', 'left', 700);
    txt(ctx, `${s.cost} 功勋`, r.x + 54, r.y + 46, 12, ok ? '#3FBFA6' : '#5A6E7E', 'left', 600);

    // 热键
    ctx.beginPath();
    rr(ctx, r.x + r.w - 24, r.y + 7, 17, 17, 5);
    ctx.fillStyle = 'rgba(255,255,255,.08)';
    ctx.fill();
    txt(ctx, s.key, r.x + r.w - 15.5, r.y + 15.5, 10, '#7C8FA0', 'center', 700);
    ctx.restore();
  }
}

function drawSkillIcon(ctx, id, x, y, col) {
  ctx.save();
  ctx.translate(x, y);
  ctx.strokeStyle = col;
  ctx.fillStyle = col;
  ctx.lineWidth = 2;
  ctx.lineCap = 'round';
  if (id === 'rally') {
    // 金币堆
    for (let i = 0; i < 3; i++) {
      ctx.beginPath();
      ctx.ellipse(0, 6 - i * 6, 11 - i * 2, 4, 0, 0, Math.PI * 2);
      ctx.globalAlpha = 0.35 + i * 0.2;
      ctx.fill();
    }
  } else if (id === 'freeze') {
    // 雪花
    for (let i = 0; i < 3; i++) {
      const a = i * Math.PI / 3;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a) * 11, Math.sin(a) * 11);
      ctx.lineTo(-Math.cos(a) * 11, -Math.sin(a) * 11);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.9;
    ctx.beginPath(); ctx.arc(0, 0, 3, 0, Math.PI * 2); ctx.fill();
  } else {
    // 裁决：向下的审判之矛
    ctx.beginPath();
    ctx.moveTo(0, -12); ctx.lineTo(7, -2); ctx.lineTo(2.5, -2);
    ctx.lineTo(2.5, 11); ctx.lineTo(-2.5, 11); ctx.lineTo(-2.5, -2);
    ctx.lineTo(-7, -2); ctx.closePath();
    ctx.fill();
  }
  ctx.restore();
}

function drawToast(ctx) {
  if (!G.toast || G.toastT <= 0) return;
  const a = Math.min(1, G.toastT / 0.6);
  const y = LAYOUT.actionY - 34;
  const w = txtW(ctx, G.toast, 14) + 44;
  ctx.save();
  ctx.globalAlpha = a;
  ctx.beginPath();
  rr(ctx, LAYOUT.W / 2 - w / 2, y - 17, w, 34, 17);
  ctx.fillStyle = 'rgba(8,16,24,.92)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(140,185,215,.28)';
  ctx.lineWidth = 1;
  ctx.stroke();
  txt(ctx, G.toast, LAYOUT.W / 2, y + 1, 14, '#D5E2EC', 'center', 600);
  ctx.restore();
}

function drawGameOver(ctx) {
  if (!G.gameOver) return;
  ctx.save();
  ctx.fillStyle = 'rgba(4,8,12,.82)';
  ctx.fillRect(0, 0, LAYOUT.W, LAYOUT.H);

  const win = G.won;
  const cy = 520;
  txt(ctx, win ? '通关' : '基地失守', LAYOUT.W / 2, cy, 52, win ? '#5BD1A6' : '#E15555', 'center', 800);
  txt(ctx, win ? '守住了全部波次' : '生命归零', LAYOUT.W / 2, cy + 46, 16, '#8FA6B8', 'center', 500);

  // 数据
  const rows = [
    ['波次', `${Math.max(G.waveIndex + 1, 0)} / ${G.waves.length}`],
    ['击杀功勋', String(G.merit)],
    ['剩余生命', String(G.lives)],
    ['建塔数', String(G.towers.length)],
  ];
  const bw = 340, bx = (LAYOUT.W - bw) / 2;
  ctx.beginPath();
  rr(ctx, bx, cy + 90, bw, rows.length * 40 + 24, 14);
  ctx.fillStyle = 'rgba(20,32,44,.9)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(140,185,215,.18)';
  ctx.lineWidth = 1; ctx.stroke();
  rows.forEach((r, i) => {
    const yy = cy + 116 + i * 40;
    txt(ctx, r[0], bx + 24, yy, 14, '#8FA6B8');
    txt(ctx, r[1], bx + bw - 24, yy, 16, '#E8EFF5', 'right', 700);
  });

  // 重开按钮
  const btn = { x: LAYOUT.W / 2 - 110, y: cy + 300, w: 220, h: 56 };
  const g = ctx.createLinearGradient(btn.x, btn.y, btn.x, btn.y + btn.h);
  g.addColorStop(0, 'rgba(46,196,168,.9)');
  g.addColorStop(1, 'rgba(20,110,95,.95)');
  ctx.beginPath();
  rr(ctx, btn.x, btn.y, btn.w, btn.h, 28);
  ctx.fillStyle = g;
  ctx.shadowColor = 'rgba(46,196,168,.5)'; ctx.shadowBlur = 22;
  ctx.fill();
  ctx.shadowBlur = 0;
  txt(ctx, '再来一局', LAYOUT.W / 2, btn.y + btn.h / 2, 20, '#04120E', 'center', 800);
  ctx.restore();
}
