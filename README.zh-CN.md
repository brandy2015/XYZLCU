# XYZLCU 0.8.0

[English](README.md) · [更新记录](CHANGELOG.md) · [验证报告](docs/IDENTITY_PROOF_VERIFICATION.md)

本地 macOS CLI，提供执行时身份观察、结构化协议和保守的目标检查。要求 macOS 13+，支持 Apple Silicon / Intel，无需云服务或 CI。

**0.8.0 主动关闭旧输入和截图路径。** CG/AX 公共元数据无法证明窗口、控件在检查期间从未被替换，也无法证明当前组合表面始终安全。要求这些保证的请求在读取内容或执行动作前拒绝。全局/前台覆盖、PID 投递、旧锁、MCP 通用入口均不能解除限制。XYZStudio 的电脑操作继续不可用。

| 已交付入口 | 行为 |
| --- | --- |
| `capabilities --json` | 实际执行器身份、被动 TCC 状态、能力和限制 |
| `identity-observe --pid N --nonce TOKEN --json` | 前后重新读取内核启动时间、可执行文件、静态/动态签名；仅诊断元数据 |
| `identity-check --request-fd N --json` | 执行时验证完整预期进程对象，回显规范 nonce；任何不匹配均拒绝 |
| `windows --thumbnails --json [--show-all]` | 有界候选目录、随机发现 token、受保护条目脱敏、逐项不可用原因；不获取通用缩略图 |
| `open-app --bundle-id ID --json` | 类型化入口；缺少经审查的无提示信任/精确启动 provider 时返回 `APP_TRUST_UNPROVABLE` |
| 结构化内容 proof | 严格 schema、可注入执行协调器和真实单元测试；生产 consumer 会话接入未启用 |
| `apps/windows/displays/cursor/check/whoami` | 被动元数据/诊断；普通 `windows` 保持数组输出 |

原生 SCK 服务使用同一个已验证 `SCWindow`，交叉检查 CG/SC 所有者和几何，一次性截图，不回退到桌面或 CLI。原生 AppKit 启动器固定无参数、URL、文档，不激活、不替换、不请求提示。二者都没有可用的生产接入 adapter。窗口/控件/表面连续性、认证 consumer 传输、系统启动信任及精确启动明确延期，不能从相同描述符推断成功。新截图服务在 macOS 13/14.0 无法建立子表面排除时提前拒绝，不宣称已验证这些系统上的截图功能。

## 构建、测试、安装

```sh
./build.sh
./scripts/unit_test.sh
./scripts/selftest.sh
./scripts/identity_integration_test.sh
./build.sh --install
xyzlcu --version  # xyzlcu 0.8.0
```

单元测试为真实 Swift XCTest target，使用可注入 provider。集成测试只构建并后台启动自己的双窗口 fixture，不激活其他 app，不发送全局事件，不使用全局覆盖，不申请 TCC；缺少录屏/辅助功能权限时明确 SKIP。`scripts/bg_selftest.sh` 已转向此 fixture，旧 TextEdit 流程退役。历史 benchmark 不代表本版本验收。

构建通常输出 arm64+x86_64 universal；Intel 编译失败会明确报告。两个二进制使用本地 ad-hoc 签名并验证，原子安装至 `~/.local/bin`。这不是 Developer ID 分发信任或公证。发布 ZIP 含两个二进制及 SHA-256 清单。

TCC 归属取决于实际执行路径及负责宿主。替换 ad-hoc 二进制后旧授权可能失效；旧 XYZStudio 授权不能证明新 core/daemon 有权限。本版本仅被动检查，不弹权限请求、不点击对话框。安装后应重启驻留执行器；现有 MCP 宿主需重连才能加载新文件。

## XYZStudio 对接契约

`identity-check` 从私有继承 FD（至少 3）读取恰好以下对象：`{"schema_version":1,"nonce":"<32 字节规范 base64url，43 字符>","expected":<observed_pre 进程对象>}`。最大 256 KiB，拒绝重复/未知字段，读取后关闭 FD。完整对象固定 boot、PID、UID、秒/微秒启动时间、bundle/可执行路径、设备/inode/文件 SHA-256、签名种类、identifier、requirement、架构及 cdhash 算法。前后完整比较，PID 启动时间变化返回 `PID_REUSED`。

诊断成功为 `kind:"process-observation"`，包含 nonce、真实 executor、`observed_pre/post`、时序、`identity_check:"matched"` 和限制。它不属于内容 `identity-proof:1` Success，不是授权、原子 OS 证明或永久信任。ad-hoc 身份只用于诊断/fixture。失败为稳定字符串 code、数值退出码、phase、dispatch_state、side_effects_possible、nonce/null、mismatch_fields、`retryable:false`，不返回内容或成功 proof。

Consumer 模式在认证会话接入缺失时，读取敏感请求/key FD 前拒绝，不转发到旧协议 2，不自动重试。发现 token 不能创建窗口绑定或 owner 身份。宿主必须保留自身的审批、revision、撤销、期限与原子响应消费规则，不能看到版本号或诊断匹配就打开工具。已发布[机器可读 core schema](docs/schemas/identity-proof.v1.schema.json)及相邻 error/owner-policy schema。完整约束见[设计](docs/IDENTITY_PROOF_DESIGN.md)和[安全审查](docs/IDENTITY_PROOF_REVIEW.md)。

## 受保护应用与用户策略

内置种子覆盖密码管理器、Passwords/钥匙串、系统设置、终端、微信及支付客户端。缺少经审查 signer pin 的已知种子按可疑身份拒绝，重命名 app 不改变其 bundle 身份。基础策略报告 unknown；XYZStudio 对未知表面继续拒绝。辅助进程归属、宿主扩展、浏览器内敏感页面仍需可信 provider，不能靠平面 denylist 推断安全。

固定读取用户账户 home 下 `Library/Application Support/XYZLCU/protected-apps.v1.json`，无模型/CLI 路径或环境覆盖。使用目录 FD、no-follow 打开；XYZLCU 目录须用户拥有且 0700，文件须普通单链接、用户拥有、0600、最大 256 KiB。Owner 同时维护 `protected-apps.state.v1.json`，精确字段为 `{"schema_version":1,"revision":"N","overlay_sha256":"<overlay 原始字节 SHA-256>"}`。缺失/不匹配 continuity、回退、同 revision 改内容、已接受 overlay 消失均拒绝。两者都不存在时仅用内置诊断策略，不能初始化 consumer 会话。本版本无策略写入命令。

Overlay 使用设计 §7.2 的封闭 schema，支持精确 ID 或末尾 `.*`、publisher requirement、signing IDs，不执行脚本/正则。移除内置项要求 `allow_builtin_removals:true` 及精确列表；本实现 rule ID 等于 bundle-ID 种子。XYZStudio 必须另行保持不可移除类别和可信 owner 高水位。0600 文件不能隔离恶意同 UID 进程。

## 兼容性

旧截图、AX 读写、键鼠/PID 事件、激活/open、创建 lock、菜单、回放及权限请求统一在动作前返回 `IDENTITY_UNPROVABLE`，覆盖别名和批处理/MCP 每个成员。禁用桌面预热和旧截图流获取。元数据和 daemon 生命周期仍可用。

旧说明与 benchmark 可在 [0.7.1 快照](https://github.com/brandy2015/XYZLCU/tree/cdcae1879cfda9c7a46aed161ee0412ba210d500)查阅，不适用于本版本。

受 [LCU](https://github.com/amontlabs/lcu) 启发，独立实现；见 [LICENSE](LICENSE)。
