XYZLCU 0.8.0 adds execution-time process identity diagnostics, a strict proof/schema module, protected-app owner policy, and local fixture verification.

- Native expected-process revalidation compares boot/PID/exact kernel start time, executable path/device/inode/digest, runtime/static signatures and architecture before and after. Canonical request nonces are echoed; mismatches fail closed.
- Closed JSON parsing/schema, single-use execution ledger, independent revoke/dispatch ordering and host pending-response consumption are covered by injectable-provider tests. User policy uses a fixed account-home path, no-follow directory descriptors, owner/mode/link/size checks and overlay continuity.
- A bounded owner catalog reports redacted protected entries and per-entry thumbnail unavailability. Native SCK exact-window capture and NSWorkspace no-argument background launch primitives are compiled behind unavailable reviewed-provider gates.
- Legacy content reads, input/PID/global routes, activation, broad capture, permission requests, aliases and MCP/batch paths now refuse before dispatch. Display prewarm is disabled; no global override or core environment override enables these paths.

**Scope:** XYZStudio consumer operations remain unavailable. Generic window/element/surface continuity, authenticated consumer bootstrap, no-prompt system launch trust and exact checked-code launch are deferred. Consequently this release does not provide production screenshots/thumbnails, AX content/actions or open-app dispatch. Diagnostic process observations are not content Success proofs or permission grants.

Validation: 62 Swift XCTest cases, 239 CLI/client/MCP assertions, and owned-background-fixture integration with 21 passes, 5 explicit SKIPs (4 provider limitations and 1 external pointer contention observation) and 0 failures. The current actual execution context had AX and Screen Recording grants; skips were due to missing reviewed providers, not permission requests. No global input, other-app activation, TCC interaction, CI or firewall changes were used.

The ZIP contains universal arm64+x86_64 client/core binaries with locally verified ad-hoc signatures and SHA-256 checksums. Runtime acceptance covers the native Apple Silicon slice on macOS 27.2.1; Intel and macOS 13/14 runtime behavior is not accepted. This is not a Developer ID/notarized distribution. See `docs/IDENTITY_PROOF_VERIFICATION.md` for evidence and limitations.

安装后需重连原有 MCP 宿主会话以加载新执行器。TCC 取决于实际执行路径和负责宿主；当前环境未申请或重新授予权限，其他宿主/新 ad-hoc 内容可能需要 owner 手动处理授权。XYZStudio 应继续保持电脑工具关闭。
