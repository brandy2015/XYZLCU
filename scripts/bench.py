#!/usr/bin/env python3
"""XYZLCU 基准测试 / benchmark.
用法: python3 scripts/bench.py [path/to/xyzlcu] [--runs 10] [--gui]
--gui 会打开一个临时文本编辑文稿，测试 click/type/key（会确认前台应用后才输入）。
"""
import os, subprocess, sys, time, json, statistics, tempfile

args = sys.argv[1:]
runs = 10
if "--runs" in args:
    i = args.index("--runs"); runs = int(args[i + 1]); del args[i:i + 2]
gui = "--gui" in args
if gui: args.remove("--gui")
B = args[0] if args else "xyzlcu"

def run(cmd, stdin=None):
    return subprocess.run([B] + cmd, input=stdin, capture_output=True, text=True)

def bench(name, cmd, stdin=None, n=runs, guard=False):
    ts = []
    for _ in range(n):
        if guard and not focused_ok():
            print(f"{name}: 测试文稿失去焦点，停止"); return None
        t = time.perf_counter(); r = run(cmd, stdin); ts.append((time.perf_counter() - t) * 1000)
        if r.returncode != 0:
            print(f"{name}: FAILED rc={r.returncode} {r.stderr.strip()}"); return None
    med = statistics.median(ts)
    print(f"{name:<28} median {med:7.1f} ms   min {min(ts):7.1f} ms")
    return med

def frontmost():
    apps = json.loads(run(["apps"]).stdout)
    return next((a for a in apps if a["active"]), {})

def focused_ok():
    """前台是文本编辑，并且焦点窗口就是测试文稿"""
    if frontmost().get("bundleId") != "com.apple.TextEdit": return False
    first = run(["ax", "TextEdit", "--depth", "0"]).stdout.splitlines()
    return any("xyzlcu-bench.txt" in l for l in first[:2])

res = {}
tmp = tempfile.gettempdir()
res["check"] = bench("check", ["check"])
res["apps"] = bench("apps", ["apps"])
res["windows"] = bench("windows", ["windows"])
res["cursor"] = bench("cursor", ["cursor"])
res["ax Finder depth3"] = bench("ax Finder --depth 3", ["ax", "Finder", "--depth", "3"])
res["screenshot full"] = bench("screenshot full", ["screenshot", f"{tmp}/xyzlcu-bench.png"], n=min(runs, 5))
res["screenshot 0.5"] = bench("screenshot --scale 0.5", ["screenshot", f"{tmp}/xyzlcu-bench.png", "--scale", "0.5"], n=min(runs, 5))
if run(["help"]).stdout.find("--format") >= 0:
    res["screenshot jpg 0.5"] = bench("screenshot 0.5 jpg", ["screenshot", f"{tmp}/xyzlcu-bench.jpg", "--scale", "0.5", "--format", "jpg"], n=min(runs, 5))
for f in ("xyzlcu-bench.png", "xyzlcu-bench.jpg"):
    try: os.remove(f"{tmp}/{f}")
    except FileNotFoundError: pass

pos = json.loads(run(["cursor"]).stdout)
res["move"] = bench("move", ["move", str(pos["x"]), str(pos["y"])])

if gui:
    prev = frontmost().get("name")
    doc = os.path.join(tmp, "xyzlcu-bench.txt"); open(doc, "w").close()
    subprocess.run(["open", "-a", "TextEdit", doc]); time.sleep(2)
    run(["activate", "TextEdit"]); time.sleep(0.5)
    if not focused_ok():
        print("测试文稿不在前台，跳过 GUI 测试")
    else:
        tree = run(["ax", "TextEdit", "--depth", "3"]).stdout
        line = next(l for l in tree.splitlines() if "AXTextArea" in l)
        x, y, wh = line.rsplit("[", 1)[1].rstrip("]").replace(",", " ").split()[:3]
        w, h = wh.split("x"); cx, cy = int(x) + int(w) // 2, int(y) + int(h) // 2
        res["click"] = bench("click", ["click", str(cx), str(cy)], n=3, guard=True)
        res["type short"] = bench("type 你好abc (5)", ["type", "你好abc"], n=5, guard=True)
        long_s = "你好，这是一段用于测试输入速度的中文文本 XYZLCU 123。" * 4
        res["type long"] = bench(f"type long ({len(long_s)})", ["type", long_s], n=3, guard=True)
        res["key"] = bench("key right", ["key", "right"], guard=True)
        if run(["help"]).stdout.find("batch") >= 0:
            script = "type a\nkey right\ntype b\nkey right\ntype c\n"
            res["batch 5 actions"] = bench("batch (5 actions)", ["batch"], stdin=script, n=5, guard=True)
        # 清理：确认前台仍是文本编辑后再关闭
        if focused_ok():
            run(["key", "cmd+s"]); time.sleep(0.5); run(["key", "cmd+w"]); time.sleep(0.5)
        got = open(doc, encoding="utf-8").read()
        want = "你好abc" * 5 + long_s * 3 + ("abc" * 5 if "batch 5 actions" in res else "")
        print("文本校验:", "OK" if got == want else f"不一致 ({len(got)} vs {len(want)})")
        res["text_ok"] = got == want
        os.remove(doc)
    if prev: run(["activate", prev])
print(json.dumps(res, ensure_ascii=False))
