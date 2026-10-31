#!/bin/bash
# 编译 universal 二进制（arm64 + x86_64），输出到 build/：
#   xyzlcu       C 写的轻量客户端（转发给守护进程，没有守护进程时 exec 主程序）
#   xyzlcu-core  主程序（Swift）
# 用法: ./build.sh [--install]   加 --install 会把两个文件都装到 ~/.local/bin/
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
SRC=Sources/xyzlcu/main.swift
FW=(-wmo -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit -framework CoreMedia -framework VideoToolbox -lz)
swiftc -O -target arm64-apple-macos13 "$SRC" "${FW[@]}" -o build/xyzlcu-core-arm64
if swiftc -O -target x86_64-apple-macos13 "$SRC" "${FW[@]}" -o build/xyzlcu-core-x86_64 2>/dev/null; then
  lipo -create build/xyzlcu-core-arm64 build/xyzlcu-core-x86_64 -output build/xyzlcu-core
else
  echo "warning: x86_64 编译失败，只生成 arm64" >&2
  cp build/xyzlcu-core-arm64 build/xyzlcu-core
fi
rm -f build/xyzlcu-core-arm64 build/xyzlcu-core-x86_64
clang -O2 -Wall -arch arm64 -arch x86_64 -mmacosx-version-min=13 Sources/client/xyzlcu.c -o build/xyzlcu
codesign -s - -f -i com.xyztech.xyzlcu build/xyzlcu-core >/dev/null 2>&1 || true
codesign -s - -f -i com.xyztech.xyzlcu.client build/xyzlcu >/dev/null 2>&1 || true
lipo -info build/xyzlcu-core build/xyzlcu
if [[ "${1:-}" == "--install" ]]; then
  B="$HOME/.local/bin"
  mkdir -p "$B"
  # 先写到临时文件再 mv：直接覆盖正在使用的已签名二进制会让新进程被系统以 SIGKILL 杀掉。先装主程序，再装客户端
  cp build/xyzlcu-core "$B/.xyzlcu-core.new" && mv -f "$B/.xyzlcu-core.new" "$B/xyzlcu-core"
  cp build/xyzlcu "$B/.xyzlcu.new" && mv -f "$B/.xyzlcu.new" "$B/xyzlcu"
  echo "installed: $B/xyzlcu (client) + $B/xyzlcu-core"
fi
