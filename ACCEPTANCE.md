# 交付与验收清单

状态定义：`[x]` 仅表示代码、测试、当前提交证据和独立核验全部成立。其余均保持 `[ ]`。

## 0. 仓库骨架

- [x] 四个职责目录已建立，边界明确。
- [x] 三条路径规定为可独立构建、独立测试。
- [x] 本机实现、Web 只读核验的角色已固定。
- [x] 已规定跨环境配置和禁止写死宿主环境。

## 1. Native binary 路径

- [ ] Stock Agda → MAlonzo → 类型擦除 Haskell → 二进制真实跑通。
- [ ] 普通程序与不需运行时高阶搬运的 Cubical 正例通过。
- [ ] 不适用输入 fail-closed，且不遗留可执行文件或陈旧产物。
- [ ] 独立测试在声明支持的环境矩阵通过。

本机实现状态：`FORMAL-PROJECT-IMPLEMENTED-LOCAL / WEB-NOT-VERIFIED`。`python3 native-binary/verify.py` 本机结果为 15/15 PASS：除普通与擦除 Cubical 冒烟测试外，还真实构建一个 8 模块、416 行 Agda 的费用审批项目，执行三级审批、拒绝、越权、自批、顺序错误和 CLI 反例，并校验编译期证明、整个源码树身份、MAlonzo、符号和动态依赖。项目自身的独立入口结果为 10/10 PASS。由于尚无 Web fresh-clone 复核和第二宿主环境证据，上述项目保持未勾选。

## 2. Term transport 路径

- [ ] 独立进程之间真实传递版本化 `Term + Type` packet。
- [ ] 消费端校验上下文、定义切片、类型和完整性后才能使用。
- [ ] 损坏、截断、版本/上下文不匹配及资源超限稳定拒绝。
- [ ] 证明未搬运 NbE 值、Haskell closure、`TCState` 或编译器进程状态。
- [ ] 独立测试在声明支持的环境矩阵通过。

本机实现状态：`STRUCTURED-PROJECT-IMPLEMENTED-LOCAL / WEB-NOT-VERIFIED`。`python3 -B term-transport/verify-internal.py --bridge-bin <built-bridge>` 本机结果为 14/14 PASS：生产端从真实 Agda type-checker 取得闭合 Internal `Term + Type`，reify 成版本化 syntax wire；另一进程重建真实 Internal 值并调用 `checkType/checkInternal`。正式 approval-handoff 项目含 7 个 Agda 模块，独立结果为 7/7 PASS，覆盖 record、自定义 ADT、String/Nat/Bool、嵌套 List、batch、派生 Summary、十个独立进程及身份/完整性反例。当前仍只支持文件通道，依赖接收端已有完全一致的源码上下文，不含闭合定义切片、通用 Cubical wire、Web fresh-clone 或第二宿主证据，因此上述完整路径项目保持未勾选。

## 3. Runtime NbE 路径

- [ ] 成熟 NbE provider 的不可变 revision、许可证和来源获确认。
- [ ] provider 真实链接进最终用户程序，而非 probe、mock 或自定义 AST 替代品。
- [ ] `Term + Type` 经 reflect → evaluate/transport → reify → recheck 进入真实数据流。
- [ ] 在最终程序进程内覆盖约定的 `transp`、`hcomp`、`Glue`、`Pi`、record/Sigma、HIT 语义面。
- [ ] 不启动 Agda 子进程，不回调编译期 `normalise`，不传递语义 closure。
- [ ] 资源限制、稳定错误和 unsupported fail-closed 完整。
- [ ] 对同一真实输入与 Agda oracle 做差分测试。
- [ ] 独立测试在声明支持的环境矩阵通过。

本机实现状态：`DECLARED-MATRIX-IMPLEMENTED / MACOS-CLEAN-PASS / UBUNTU-VM-CLEAN-PASS / WEB-REVERIFY-REQUIRED`。统一入口 `runtime-nbe/verify-capability-matrix.py` 对十个现实场景整批为 10/10 PASS；其内部覆盖跨模块递归 Bool/Pi、依赖 Pi、普通及依赖 Sigma、空面与活动面 `hcomp`、常量及非恒定 `transp`、Glue intro/elim、identity 与非平凡 Bool-negation Glue family，以及带前/反向高阶 tube 的 interval HIT。所有正式场景均从真实 Agda Internal `Term + Type` 进入同一 v14 recursive `type-ast`/`term-ast`/definition closure；HIT、依赖证据、函数和 Glue 等价身份均通过 `def(N)` 拓扑引用，旧 v1–v13 只保留读兼容。packet 经链接的 cctt `Core.eval/quoteUnfold`，在原 `defType` 下 `checkType/checkInternal`，再由 Stock Agda 生成的 MAlonzo 最终程序复算 packet SHA-256、重复 cctt 求值并消费检查结果。隔离 oracle 对每个同一 QName 做差分；unsupported、AST trailing/open/ill-typed/forward reference、身份/闭包/边界篡改、资源耗尽和陈旧产物均有反例。provider 正式入口为 19/19 PASS，含 adapter semantic fuel、真实 cctt allocation limit 和 wall timeout；符号审计覆盖 archive 与 strip 后最终 ABI。macOS fresh clone 在 `0c57b1f97bc42c9b4b506e70f62fa8dbdcbfcba8` 完成 fresh slice 10/10、provider 19/19、integrated 9/9、MAlonzo 8/8 和场景矩阵 10/10；之后仅修改 Hackage/CI 入口与文档的 `4f5cc7f738ae9a6336dd73c754c0414df9976331` 在独立 Ubuntu 24.04 arm64 VM clean checkout 完成同一全链。GitHub 双宿主任务因账户付款/额度问题未启动任何步骤，不能替代 Web fresh-clone 独立核验；因此本节仍全部保持未勾选。

## 4. Dispatcher

- [ ] 纯分流规则和表驱动测试完成。
- [ ] 输入分析与源码、入口、依赖身份绑定，并在执行前复核。
- [ ] 每次只执行一条路径；不适用或证据不完整时拒绝。
- [ ] 三条路径各自验收后再做真实端到端接线。

## 5. 整体验收

- [ ] fresh clone 可按文档发现依赖并运行全部测试。
- [ ] 至少两个不同宿主环境完成无硬编码复现。
- [ ] Web 核验者对指定 SHA 给出逐项独立结果。
- [ ] 所有未完成项及影响如实保留，得到交付批准。

当前结论：仓库骨架完成；Native 多模块审批工程、Term 结构化 approval-handoff 工程及 runtime-nbe 的声明语义矩阵与统一 v14 typed-AST 均有本机实现。runtime-nbe 仍需在形成提交 SHA 后执行 Web fresh-clone 与第二宿主独立复验；Native、Term、dispatcher 和跨环境总验收仍按各自未勾选项处理。
