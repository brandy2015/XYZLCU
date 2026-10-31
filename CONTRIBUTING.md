# Contributing to XYZLCU

Thanks for your interest in XYZLCU, a zero-dependency macOS computer-use CLI and MCP server for AI agents. Bug reports, agent compatibility reports and pull requests are welcome.

[中文说明见下方](#中文)

## Reporting bugs

Open an [issue](https://github.com/brandy2015/XYZLCU/issues/new/choose) with the bug template and include:

- `xyzlcu version`, macOS version, Apple Silicon or Intel
- the exact command and its full JSON output (remove anything private first)
- `xyzlcu whoami` / `xyzlcu check` output if it looks like a permission problem
- which agent or app launched `xyzlcu` (Terminal, Grok, Codex, Claude Code, …)

## Agent compatibility reports

If you got XYZLCU working with an agent marked "compatible, not tested" in the [Supported agents](README.md#supported-agents) table (ChatGPT, Claude, DeepSeek, Cursor, Gemini CLI, …), please open an issue or PR with the agent version and how you connected it (shell tool or `xyzlcu mcp`), so it can be marked as tested.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Build with `./build.sh` (Swift toolchain from Xcode or the Command Line Tools; no third-party dependencies).
3. Keep it dependency-free: no new packages, no network access, no telemetry.
4. Test the commands you touched on a real Mac, and update both `README.md` and `README.zh-CN.md` if behavior or options change.
5. Keep PRs focused, and describe what you changed and how you tested it.

Out of scope: features meant to evade bot detection, solve captchas, or disguise automated input as human input.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).

## 中文

欢迎提 issue 和 PR。报 bug 时请附上 `xyzlcu version`、macOS 版本、芯片类型、完整命令和输出（先去掉隐私内容），以及是哪个 App / 智能体启动的 `xyzlcu`。在「支持的智能体」表里标为「兼容，未实测」的智能体，如果你跑通了，欢迎提 issue / PR 改成已实测。PR 请保持零依赖、不联网，改了行为请同时更新中英文 README。
