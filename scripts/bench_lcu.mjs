// LCU (Local Computer Use, https://github.com/amontlabs/lcu) side of scripts/bench.py.
// It talks to LCU the way an agent harness does: one stdio MCP connection (LCU's own
// adapters/client.mjs), then one `js` tool call per measured operation.
//
// node scripts/bench_lcu.mjs --lcu /path/to/lcu [--runs 10] [--app com.apple.TextEdit]
//      [--gui --win-w 656 --click 320,340] [--allow-session]
//
// --allow-session answers LCU's per-app approval for --app with scope "session" (this LCU
// session only, never "always"). Without it the approval is cancelled and only app-independent
// operations are measured. --gui types into the focused window of --app: bench.py opens its own
// scratch document and checks it is frontmost before calling this script.
import { realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';

const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i < 0 ? dflt : argv[i + 1]; };
const flag = name => argv.includes(name);
const lcu = opt('--lcu');
if (!lcu) { console.error('usage: bench_lcu.mjs --lcu /path/to/lcu [...]'); process.exit(2); }
const runs = Number(opt('--runs', 10));
const appId = opt('--app', 'com.apple.TextEdit');
const gui = flag('--gui');
const allowSession = flag('--allow-session');
const winW = Number(opt('--win-w', 0));
const click = (opt('--click', '') || '').split(',').filter(Boolean).map(Number);

// <prefix>/current/bin/lcu -> <prefix>/current/adapters/client.mjs
const root = dirname(dirname(realpathSync(lcu)));
const { createCuaClient } = await import(join(root, 'adapters', 'client.mjs'));

const approvals = [];
const cua = createCuaClient({
  command: [lcu],
  onElicitation: async params => {
    const app = params?._meta?.tool_params?.app;
    approvals.push(app);
    if (allowSession && app === appId) return { action: 'accept', content: {}, _meta: { persist: 'session' } };
    return { action: 'cancel' };
  },
});

const ids = { sessionId: `xyzlcu-bench-${process.pid}`, turnId: `turn-${randomUUID()}` }; // turn ids must be fresh
const now = () => performance.now();
const res = { tool: 'lcu', ops: {}, notes: [] };

async function js(code) {
  const r = await cua.call('js', { code, timeout_ms: 60000 }, ids);
  const text = (r.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
  if (r.isError) throw new Error(text.split('\n')[0]);
  return text;
}
async function bench(name, code, n = runs) {
  const ts = [];
  try {
    for (let i = 0; i < n; i++) { const t = now(); await js(code); ts.push(now() - t); }
    res.ops[name] = ts;
  } catch (e) { res.ops[name] = null; res.notes.push(`${name}: ${e.message}`); }
}

let t = now();
await cua.connect();
res.connect_ms = now() - t;
t = now();
await js('await cua.getState({ emit: false })');          // first call: starts the CUA runtime
res.first_call_ms = now() - t;

await bench('apps', 'await cua.listApps({ emit: false })');
t = now();
let appOk = true;
try { await js(`globalThis.app = await cua.getApp(${JSON.stringify(appId)})`); res.get_app_ms = now() - t; }
catch (e) { appOk = false; res.notes.push(`getApp: ${e.message}`); }
if (appOk) {
  await bench('ax_tree', 'await app.getAXState({ disableDiffing: true, emit: false })');
  await bench('screenshot_window', 'await app.getScreenshot({ emit: false })');
  if (gui) {
    // LCU clicks in screenshot pixels relative to the window; convert from window points.
    const shot = await js(`const s = await app.getScreenshot({ emit: false });
      let i = 2; while (i < s.length) { if (s[i] !== 0xFF) { i++; continue; } const m = s[i + 1];
        if (m >= 0xC0 && m <= 0xC2) { nodeRepl.write(String(s.readUInt16BE(i + 7))); break; } i += 2 + s.readUInt16BE(i + 2); }`);
    const scale = winW ? Number(shot) / winW : 1;
    if (click.length === 2) await bench('click', `await app.click([${Math.round(click[0] * scale)}, ${Math.round(click[1] * scale)}])`);
    await bench('type', 'await app.typeText("abc")');
    await bench('type_zh', 'await app.typeText("你好abc")');
    await bench('key', 'await app.pressKey("super+Right")');
  }
}
res.approvals = approvals;
try { await cua.turnEnded({ ...ids, event: 'Stop' }); } catch {}
await cua.close();
console.log(JSON.stringify(res));
process.exit(0);
