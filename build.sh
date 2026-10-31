#!/bin/bash
# 编译 universal 二进制（arm64 + x86_64），输出到 build/xyzlcu
# 用法: ./build.sh [--install]   加 --install 会复制到 ~/.local/bin/xyzlcu
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
SRC=Sources/xyzlcu/main.swift
FW=(-wmo -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit)
swiftc -O -target arm64-apple-macos13 "$SRC" "${FW[@]}" -o build/xyzlcu-arm64
if swiftc -O -target x86_64-apple-macos13 "$SRC" "${FW[@]}" -o build/xyzlcu-x86_64 2>/dev/null; then
  lipo -create build/xyzlcu-arm64 build/xyzlcu-x86_64 -output build/xyzlcu
else
  echo "warning: x86_64 编译失败，只生成 arm64" >&2
  cp build/xyzlcu-arm64 build/xyzlcu
fi
rm -f build/xyzlcu-arm64 build/xyzlcu-x86_64
codesign -s - -f -i com.xyztech.xyzlcu build/xyzlcu >/dev/null 2>&1 || true
lipo -info build/xyzlcu
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/.local/bin"
  # 先写到临时文件再 mv：直接覆盖正在使用的已签名二进制会让新进程被系统以 SIGKILL 杀掉
  cp build/xyzlcu "$HOME/.local/bin/.xyzlcu.new" && mv -f "$HOME/.local/bin/.xyzlcu.new" "$HOME/.local/bin/xyzlcu"
  echo "installed: $HOME/.local/bin/xyzlcu"
fi
