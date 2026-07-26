# G1 决策账本：范围复审检查点

## 结论

**STOP_REVIEW。** G1 尚未通过，完整决策账本没有生成，G2 不得开始。

审计从冻结的 13 个主控制流文件开始。在最先检查的
`core/src/tasks/regular.rs` 与 `core/src/session/handlers.rs` 中，已分别确认
一个属于 `startup` 和一个属于 `Guardian` 的 `Authority` 分支。根据 G1
硬停止规则，发现后已立即中断其余文件审计，没有沿调用图扩张，也没有修改
Rust 或 Haskell 产品实现。

`checkpoints/020-closure-map/` 继续保留为九域全系统审计地图；本检查点没有把它
重新解释为施工范围，也没有修改其中任何文件。

## 冻结身份

- 上游源码 commit：
  `98d28aab54ed86714901b6619400598598876dd0`
- 源码 ZIP SHA-256：
  `aa55787e86544740aaa3f068859479f4cca5655355975d81f02ff020c61ba21d`
- G0 关闭提交：
  `f8151ae272b611e320acd9e74e384cb5a84bf4e9`
- G1 工作分支：
  `agent/haskell-orchestration-kernel`
- 旧语义参考包（只读取 `closure-manifest.tsv`）SHA-256：
  `ff131f6b1f0d5d2d829e684c4d0e546620ac63c7410d23a4f89164bce78edc21`

## 分类准则

| 标签 | 本检查点采用的判据 |
|---|---|
| `Authority` | 读取编排状态或已发生事实，在两个以上语义动作之间选择，并改变冻结的可观察行为 |
| `Effect` | 执行已决定的外部动作，或报告平台/传输结果；不自行选择下一条语义动作 |
| `Invariant` | 验证合法性、身份、形状、唯一性或 fail-closed 条件；不作产品策略选择 |
| `Presentation` | 格式化、投影、渲染或协议表示，不改变 Turn 决策语义 |

## 原始施工入口：13 个主控制流文件

1. `codex-rs/cli/src/main.rs`
2. `codex-rs/exec/src/lib.rs`
3. `codex-rs/app-server/src/request_processors/thread_processor.rs`
4. `codex-rs/core/src/thread_manager.rs`
5. `codex-rs/core/src/session/session.rs`
6. `codex-rs/core/src/session/handlers.rs`
7. `codex-rs/core/src/tasks/regular.rs`
8. `codex-rs/core/src/session/turn.rs`
9. `codex-rs/core/src/client.rs`
10. `codex-rs/core/src/stream_events_utils.rs`
11. `codex-rs/core/src/tools/router.rs`
12. `codex-rs/core/src/tools/parallel.rs`
13. `codex-rs/core/src/tools/registry.rs`

其中旧 manifest 只把第 4–8、10–13 项列为 `control/state`；第 1–3 项是
`boundary`，第 9 项是 `transport`。后四类文件不能因为位于 13 文件入口中就
自动获得迁移资格。

## 旧清单：17 个 control/state 候选

以下集合来自旧失败包的 `closure-manifest.tsv`。它仅锁定可复审候选上界，
不证明其中每个分支都是 Authority，也不恢复旧的 36 文件逐文件翻译路线。

| 旧序号 | 类别 | Rust 文件 | 是否属于 13 文件入口 |
|---:|---|---|:---:|
| 4 | state | `codex-rs/core/src/thread_manager.rs` | 是 |
| 5 | state | `codex-rs/core/src/session/session.rs` | 是 |
| 6 | control | `codex-rs/core/src/session/handlers.rs` | 是 |
| 7 | control | `codex-rs/core/src/tasks/regular.rs` | 是 |
| 8 | control | `codex-rs/core/src/session/turn.rs` | 是 |
| 10 | control | `codex-rs/core/src/stream_events_utils.rs` | 是 |
| 11 | control | `codex-rs/core/src/tools/router.rs` | 是 |
| 12 | control | `codex-rs/core/src/tools/parallel.rs` | 是 |
| 13 | control | `codex-rs/core/src/tools/registry.rs` | 是 |
| 14 | control | `codex-rs/core/src/tools/spec_plan.rs` | 否 |
| 16 | control | `codex-rs/core/src/tools/code_mode/delegate.rs` | 否 |
| 20 | control | `codex-rs/core/src/tools/handlers/apply_patch.rs` | 否 |
| 22 | control | `codex-rs/core/src/tools/events.rs` | 否 |
| 23 | state | `codex-rs/core/src/turn_diff_tracker.rs` | 否 |
| 24 | control | `codex-rs/apply-patch/src/lib.rs` | 否 |
| 26 | state | `codex-rs/core/src/session/mod.rs` | 否 |
| 31 | control | `codex-rs/core/src/tasks/mod.rs` | 否 |

计数：`control = 13`，`state = 4`，总计 `17`。

## 硬停止触发器

### G1-STOP-001：startup prewarm 决定 Turn 是否继续

| 必填项 | 记录 |
|---|---|
| 分类 | `Authority` |
| 源码位置 | `codex-rs/core/src/tasks/regular.rs:64-70`，`RegularTask::run` |
| 读取的状态/事实 | `SessionStartupPrewarmResolution`：`Cancelled`、`Unavailable`、`Ready`；该事实同时反映 startup prewarm 与当前 cancellation |
| 可选动作 | `Cancelled` → `return Ok(None)`；`Unavailable` → 以 `None` 继续；`Ready` → 携带预热 `ModelClientSession` 继续 |
| 可观察结果 | 是否进入 `run_turn`/模型采样，以及首次采样使用预热还是普通 client session；`TurnStarted` 已在等待该事实前发出 |
| 对应测试场景 | 现有 `core/src/session/tests.rs:329`（不等待 prewarm 即发 `TurnStarted`）、`:419`（等待期间中断并产生 `TurnAborted`）；`core/tests/suite/agent_websocket.rs:151,208,343,398` 覆盖首次 turn 的 prewarm 行为 |
| 迁移后的 Haskell 构造器 | **未分配：命中禁止的 `startup` 域，必须先复审范围** |

该分支位于 17 个候选之内，但语义直接属于被明确排除的 `startup` 域，因此仍
触发停止。

### G1-STOP-002：Guardian denial 是否转成 history 注入

| 必填项 | 记录 |
|---|---|
| 分类 | `Authority` |
| 源码位置 | `codex-rs/core/src/session/handlers.rs:864-870`，`approve_guardian_denied_action` |
| 读取的状态/事实 | `GuardianAssessmentEvent.status` |
| 可选动作 | 非 `Denied` → 记录 warning 并忽略；`Denied` → 构造精确 action 授权 developer message，并通过 `inject_no_new_turn` 注入 |
| 可观察结果 | 后续 history/模型请求是否包含该授权消息；不另启新 turn |
| 对应测试场景 | 当前固定源码中未找到该函数的直接单元测试；复审后至少需要“非 Denied 不注入”和“Denied 只注入原 action、且不启新 turn”两个场景 |
| 迁移后的 Haskell 构造器 | **未分配：命中禁止的 `Guardian` 域，必须先复审范围** |

## 未完成范围

硬停止发生后，下列工作均未继续：

- 13 文件的完整语法分支枚举；
- 每个分支的四类标签；
- 其余 Authority 的必填六项记录；
- 17 候选内其余 15 文件的扩展审计；
- 任何 Haskell `Fact`、`Command` 或状态构造器设计；
- Rust `Fact → reducer → Command` 参考机实现。

因此本检查点不能被解释为“G1 账本部分通过”，也不能用来授权 G2。

## 复审问题

继续前必须明确选择新的施工规则。至少需要决定：

1. `startup` prewarm 是从 Turn 内核中剥离为 Rust 已决事实，还是正式纳入
   Authority 范围；
2. `ApproveGuardianDeniedAction` 整条路径是明确排除、保留 Rust 决策，还是正式
   纳入 Authority 范围；
3. 若选择排除，怎样定义可机械检查的函数/事件 denylist，确保后续 13 文件审计
   遇到这些域时分类为“范围外”，而不是静默漏记。

范围复审完成前，`development_allowed = false`。
