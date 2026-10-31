# Security Policy

## Supported versions

Only the [latest release](https://github.com/brandy2015/XYZLCU/releases/latest) receives security fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Report them privately through GitHub's
[private vulnerability reporting](https://github.com/brandy2015/XYZLCU/security/advisories/new)
(Security tab → "Report a vulnerability"). Include the version, macOS version, steps to reproduce and the impact.
You should get a response within a few days.

## Scope notes

XYZLCU controls the local GUI through macOS Accessibility and Screen Recording permissions, which are granted to the app that launches it. It makes no network connections; the only socket is the local daemon's Unix socket. Reports about the daemon socket, permission handling, the lock-screen guard, recording files, or the MCP server are especially welcome.

## 安全问题（中文）

请不要在公开 issue 里报告安全漏洞，请通过上面的 GitHub「私密漏洞报告」提交。
