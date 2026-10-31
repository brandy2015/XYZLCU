#!/usr/bin/env python3
"""XYZLCU 基准测试（可选与 LCU 对比）/ XYZLCU benchmark, optionally against LCU.

用法 / usage:
  python3 scripts/bench.py [path/to/xyzlcu] [--runs 10] [--mode both|daemon|inproc] [--gui]
                           [--lcu /path/to/lcu [--lcu-allow-session]] [--json out.json]

  --mode     daemon = 经守护进程（没在跑就临时启动，测完停掉）；inproc = XYZLCU_DAEMON=0 进程内执行
  --gui      打开一个临时「文本编辑」文稿，测 click / type / key；每次输入前确认前台窗口就是这份文稿，
             结束时核对文稿内容并关闭、删除它。不会碰其它窗口。
  --lcu      同时测 LCU（https://github.com/amontlabs/lcu）。需要 node；通过 LCU 自带的
             adapters/client.mjs 走 stdio MCP，每个操作一次 `js` 调用（scripts/bench_lcu.mjs）。
  --lcu-allow-session  对 LCU 的单应用授权弹询回答「仅本次会话」（只针对文本编辑，不会选「始终允许」）。

计时：每个操作重复 --runs 次，取中位数和 p90（毫秒）。XYZLCU 计的是一次完整的命令行调用
（启动进程 + 执行 + 输出 JSON），这就是智能体从 shell 调用时付出的代价；LCU 计的是已连接的
MCP 客户端发一次 `js` 工具调用的往返时间。
"""
import json, math, os, shutil, statistics, subprocess, sys, tempfile, time

args = sys.argv[1:]
def opt(name, dflt=None):
    if name in args:
        i = args.index(name); v = args[i + 1]; del args[i:i + 2]; return v
    return dflt
def flag(name):
    if name in args: args.remove(name); return True
    return False

runs = int(opt("--runs", 10))
mode = opt("--mode", "both")
lcu = opt("--lcu")
json_out = opt("--json")
gui = flag("--gui")
lcu_allow = flag("--lcu-allow-session")
B = args[0] if args else (shutil.which("xyzlcu") or "xyzlcu")
HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.gettempdir()
DOC_NAME = "xyzlcu-bench.txt"
DOC = os.path.join(TMP, DOC_NAME)

def run(cmd, env_daemon="0", stdin=None):
    return subprocess.run([B] + cmd, input=stdin, capture_output=True, text=True,
                          env=dict(os.environ, XYZLCU_DAEMON=env_daemon))

def stats(ts):
    if not ts: return None
    s = sorted(ts)
    return {"median": round(statistics.median(s), 1), "p90": round(s[math.ceil(0.9 * len(s)) - 1], 1),
            "min": round(s[0], 1), "n": len(s)}

def frontmost():
    apps = json.loads(run(["apps"]).stdout)
    return next((a for a in apps if a.get("active")), {})

def focused_ok():
    """前台是文本编辑，并且最前面的窗口就是测试文稿 / TextEdit is frontmost and its front window is our doc."""
    if frontmost().get("bundleId") != "com.apple.TextEdit": return False
    first = run(["ax", "TextEdit", "--depth", "0"]).stdout.splitlines()
    return len(first) > 1 and f'title="{DOC_NAME}"' in first[1]

def rect(line):
    x, y, wh = line.rsplit("[", 1)[1].rstrip("]").replace(",", " ").split()[:3]
    w, h = wh.split("x"); return int(x), int(y), int(w), int(h)

def bench_xyz(d, ops):
    out = {}
    for name, cmd, guard in ops:
        ts = []
        for _ in range(runs):
            if guard and not focused_ok():
                print(f"  {name}: 测试文稿不在前台，停止 / scratch doc lost focus, stopped"); ts = None; break
            t = time.perf_counter(); r = run(cmd, d); ts.append((time.perf_counter() - t) * 1000)
            if r.returncode != 0:
                print(f"  {name}: FAILED rc={r.returncode} {r.stderr.strip()[:200]}"); ts = None; break
        out[name] = stats(ts)
    return out

# ---------- 准备 / setup ----------
started_daemon = None
# 先测进程内、再测守护进程：同一个 xyzlcu 的守护进程在运行时，进程内的 ScreenCaptureKit 截图会拿不到回调
# (macOS 行为)，只能退回 screencapture，数字不代表正常情况。
# In-process first: while a daemon of the same binary is running, in-process ScreenCaptureKit captures stall
# and fall back to /usr/sbin/screencapture, so those numbers would not be representative.
modes = {"both": ["inproc", "daemon"], "daemon": ["daemon"], "inproc": ["inproc"]}[mode]
daemon_was_running = bool(json.loads(run(["serve", "--status"]).stdout or "{}").get("running"))
if "inproc" in modes and daemon_was_running:
    print("注意：守护进程已在运行，进程内截图会退回 screencapture（偏慢）。想测干净的进程内数字请先 `xyzlcu serve --stop`。\n"
          "Note: a daemon is running; in-process screenshots will fall back to screencapture. Run `xyzlcu serve --stop` first for clean numbers.")

def ensure_daemon():
    global started_daemon
    if not json.loads(run(["serve", "--status"]).stdout or "{}").get("running"):
        started_daemon = subprocess.Popen([B, "serve"], stderr=subprocess.DEVNULL, env=dict(os.environ, XYZLCU_DAEMON="0"))
        time.sleep(1)

ops = [
    ("version", ["version"], False),
    ("apps", ["apps"], False),
    ("windows", ["windows"], False),
    ("cursor", ["cursor"], False),
]
pos = json.loads(run(["cursor"]).stdout)
ops.append(("move", ["move", str(pos["x"]), str(pos["y"])], False))
ops += [
    ("screenshot_full", ["screenshot", f"{TMP}/xyzlcu-bench.png"], False),
    ("screenshot_fast", ["screenshot", f"{TMP}/xyzlcu-bench.jpg", "--fast"], False),
]
win = None
if gui:
    prev = frontmost().get("name")
    open(DOC, "w").close()
    subprocess.run(["open", "-a", "TextEdit", DOC]); time.sleep(2)
    run(["activate", "TextEdit"]); time.sleep(0.5)
    if not focused_ok():
        print("测试文稿不在前台，跳过 GUI 测试 / scratch doc not frontmost, skipping GUI tests"); gui = False
    else:
        tree = run(["ax", "TextEdit", "--depth", "3"]).stdout.splitlines()
        win = rect(tree[1])
        ta = rect(next(l for l in tree if "AXTextArea" in l))
        cx, cy = ta[0] + ta[2] // 2, ta[1] + ta[3] - 20          # 文本区下方空白处 / empty spot near the bottom
        ops += [
            ("screenshot_window", ["screenshot", f"{TMP}/xyzlcu-bench.png", "--window", "TextEdit", "--title", DOC_NAME], False),
            ("ax_tree", ["ax", "TextEdit", "--depth", "3"], False),
            ("click", ["click", str(cx), str(cy)], True),
            ("type", ["type", "abc", "--window", DOC_NAME], True),
            ("type_zh", ["type", "你好abc", "--window", DOC_NAME], True),
            ("key", ["key", "cmd+right"], True),
        ]

results = {"runs": runs, "xyzlcu": {}, "lcu": None}
expected = ""
for d in modes:
    print(f"== xyzlcu ({d}) ==")
    if d == "daemon": ensure_daemon()
    results["xyzlcu"][d] = bench_xyz("1" if d == "daemon" else "0", ops)
    if gui and results["xyzlcu"][d].get("type_zh"): expected += ("abc" * runs) + ("你好abc" * runs)

if lcu:
    print("== LCU ==")
    if gui and not focused_ok():
        print("测试文稿不在前台，LCU 只测不输入的操作 / doc not frontmost, LCU GUI tests skipped"); gui_lcu = False
    else: gui_lcu = gui
    node = os.environ.get("NODE") or shutil.which("node")
    bundled = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(lcu))), "agent-tools", "node", "bin", "node")
    if os.path.exists(bundled) and not os.environ.get("NODE"): node = bundled
    cmd = [node, os.path.join(HERE, "bench_lcu.mjs"), "--lcu", lcu, "--runs", str(runs), "--app", "com.apple.TextEdit"]
    if lcu_allow: cmd.append("--allow-session")
    if gui_lcu:
        cmd += ["--gui", "--win-w", str(win[2]), "--click", f"{cx - win[0]},{cy - win[1]}"]
    r = subprocess.run(cmd, capture_output=True, text=True, env=dict(os.environ, LCU_NO_UPDATE_CHECK="1"))
    try:
        raw = json.loads(r.stdout.strip().splitlines()[-1])
        results["lcu"] = {k: v for k, v in raw.items() if k != "ops"}
        results["lcu"]["ops"] = {k: stats(v) for k, v in raw["ops"].items()}
        if gui_lcu and results["lcu"]["ops"].get("type_zh"): expected += ("abc" * runs) + ("你好abc" * runs)
    except Exception:
        print("LCU 运行失败 / LCU run failed:", r.stderr.strip()[-500:])

# ---------- 清理 / cleanup ----------
for f in ("xyzlcu-bench.png", "xyzlcu-bench.jpg"):
    try: os.remove(f"{TMP}/{f}")
    except FileNotFoundError: pass
if gui:
    got = json.loads(run(["value", "TextEdit", "--role", "AXTextArea", "--window", DOC_NAME]).stdout or "{}").get("value")
    results["text_ok"] = got == expected
    print("文本校验 / text check:", "OK" if got == expected else f"不一致 mismatch ({len(got or '')} vs {len(expected)})")
    if focused_ok():
        run(["key", "cmd+w"]); time.sleep(0.8)
    try: os.remove(DOC)
    except FileNotFoundError: pass
    if prev: run(["activate", prev])
if started_daemon:
    started_daemon.terminate(); started_daemon.wait()

# ---------- 输出 / report ----------
def cell(s): return f"{s['median']:.0f} / {s['p90']:.0f}" if s else "—"
cols = [(f"xyzlcu {d}", results["xyzlcu"][d]) for d in modes]
if results["lcu"]: cols.append(("LCU (MCP js)", results["lcu"]["ops"]))
names = list(dict.fromkeys([n for _, c in cols for n in c]))
print("\n| op | " + " | ".join(c for c, _ in cols) + " |  (median / p90 ms)")
print("|---|" + "---|" * len(cols))
for n in names:
    print(f"| {n} | " + " | ".join(cell(c.get(n)) for _, c in cols) + " |")
if results["lcu"]:
    l = results["lcu"]
    print(f"\nLCU connect {l.get('connect_ms', 0):.0f} ms, first call {l.get('first_call_ms', 0):.0f} ms, "
          f"getApp {l.get('get_app_ms', 0):.0f} ms; approvals asked: {l.get('approvals')}; notes: {l.get('notes')}")
if json_out:
    with open(json_out, "w") as f: json.dump(results, f, ensure_ascii=False, indent=1)
