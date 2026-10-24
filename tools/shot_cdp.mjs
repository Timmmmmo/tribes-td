// 用 CDP 给「需要真实等待」的页面截图。
//
// 为什么不用 `chrome --screenshot --virtual-time-budget`：那个会把虚拟时间快进，
// 定时器跑了，但 wasm 下载和编译是真实耗时，快进不到，截到的永远是启动条。
// Godot Web 版有 38MB wasm，必须真的等。
//
// 用法：
//   node tools/shot_cdp.mjs <url> <输出png> [等待毫秒] [端口]

import { writeFileSync } from 'node:fs';

const [, , url, out, waitMsArg, portArg] = process.argv;
if (!url || !out) {
  console.error('用法: node tools/shot_cdp.mjs <url> <out.png> [waitMs] [port]');
  process.exit(1);
}
const waitMs = Number(waitMsArg || 45000);
const port = Number(portArg || 9222);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  // 等到调试端口起来
  let targets = null;
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/list`);
      targets = await res.json();
      if (targets.length) break;
    } catch {
      /* 还没起来 */
    }
    await sleep(500);
  }
  if (!targets || !targets.length) throw new Error('拿不到调试目标');

  const page = targets.find((t) => t.type === 'page') || targets[0];
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  const logs = [];

  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
      return;
    }
    if (msg.method === 'Runtime.consoleAPICalled') {
      logs.push('[console] ' + msg.params.args.map((a) => a.value ?? a.description ?? '').join(' '));
    }
    if (msg.method === 'Runtime.exceptionThrown') {
      logs.push('[exception] ' + (msg.params.exceptionDetails?.text || ''));
    }
    if (msg.method === 'Log.entryAdded') {
      logs.push('[log:' + msg.params.entry.level + '] ' + msg.params.entry.text);
    }
  });

  await new Promise((r) => ws.addEventListener('open', r));
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const myId = ++id;
      pending.set(myId, resolve);
      ws.send(JSON.stringify({ id: myId, method, params }));
    });

  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', {
    width: 720, height: 1280, deviceScaleFactor: 1, mobile: false,
  });
  await send('Page.navigate', { url });

  await sleep(waitMs);

  const shot = await send('Page.captureScreenshot', { format: 'png' });
  if (!shot.result || !shot.result.data) throw new Error('截图失败: ' + JSON.stringify(shot).slice(0, 300));
  writeFileSync(out, Buffer.from(shot.result.data, 'base64'));

  console.log('saved ' + out);
  if (logs.length) {
    console.log('--- 页面日志（最多 40 条） ---');
    for (const l of logs.slice(0, 40)) console.log(l);
  } else {
    console.log('--- 页面无 console 输出 ---');
  }
  ws.close();
}

main().catch((e) => {
  console.error('ERR', e.message);
  process.exit(1);
});
