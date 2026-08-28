# Runtime NbE 能力与证据矩阵

> 本文件只记录技术覆盖、缺口和证据入口，不是正式进度清单。
> 根目录 [`ACCEPTANCE.md`](../ACCEPTANCE.md) 是唯一验收状态来源；只有代码、可重复测试、
> 当前提交证据和独立核验同时成立时，才允许在那里勾选。

## 状态定义

| 状态 | 含义 |
| --- | --- |
| `MISSING` | 尚无进入真实数据流的实现。 |
| `PARTIAL` | 有真实实现，但只覆盖受限形状或缺少完整闭环。 |
| `LOCAL-PASS` | 本机用真实输入重复通过，尚无独立环境证据。 |
| `WEB-PASS` | Web 核验者在指定 SHA 的 fresh clone 中独立通过。 |
| `FAIL` | 实现或正式验证入口在目标环境失败。 |
| `NOT-RUN` | 由于依赖或环境原因没有执行，不得视为通过。 |
| `UNSUPPORTED-FAIL-CLOSED` | 明确不支持，稳定拒绝且不留下半成品。 |

状态必须附测试入口或具体缺口。单独的 README 描述、手写预期、证明关联、程序退出 0
或某个符号字符串都不能独立构成验收证据。

## 端到端处理阶段

| 能力 | 当前状态 | 当前证据 | 关闭缺口所需结果 |
| --- | --- | --- | --- |
| provider revision、来源与源码身份 | `LOCAL-PASS` | `provider.lock.json`; `verify-provider.py` | 指定 SHA 的 Web 与第二宿主复现。 |
| provider 及源码依赖许可证 | `LOCAL-PASS` | cctt、`strict-impl-params` 为 MIT；`primdata` 精确升级到作者加入 MIT 文件的 `f7bd45a`，许可证/源码/package 哈希和 Stack resolved lock 均受检 | 指定 SHA 的 Web 与第二宿主复核。 |
| provider 链入最终程序 | `LOCAL-PASS`（Web 重验待跑） | 稳定 C ABI `runtime_nbe_cctt_eval_quote_v1` 直接执行 eval/quote；archive 审计 + strip 后最终程序审计/行为；`verify-symbol-audit.py` 7/7，provider 19/19 | 在原失败 ELF 环境重跑正式 verifier，确认 Stock strip 后退出 0。 |
| 真实 Agda Internal `Term + Type` 输入 | `LOCAL-PASS`（声明子集） | 十个正式场景全部生成同一 v14 recursive `type-ast`/`term-ast`；provider 完全消费 AST，integrated/MAlonzo 从类型 AST 与闭包身份 reify | 指定 SHA 的 Web 与第二宿主复核；矩阵外 Agda 语法仍明确 fail-closed。 |
| 闭合定义切片 | `LOCAL-PASS`（声明子集） | 普通/依赖函数、证据 family/构造器、HIT 类型/点/路径及 Glue 等价均使用统一 definition entry 与 `def(N)`；QName 唯一性、后向引用、开放项、深度和数量受检 | 指定 SHA 的 Web 与第二宿主复核。 |
| reflect 到 provider | `LOCAL-PASS`（声明子集） | 全部正式场景走唯一 v14 AST parser/type-shape checker/interpreter；v1–v13 只作读兼容，正式 producer 不再生成 | 指定 SHA 的 Web 与第二宿主复核。 |
| evaluate/transport | `LOCAL-PASS`（声明子集） | 所有约定构造生成 cctt program 并经过 `Core.eval`/`quoteUnfold`；非平凡 Glue 真实得到 `true→false`、`false→true` | Web 复核。 |
| reify 为 Agda Term | `LOCAL-PASS`（声明子集） | Bool、依赖 Sigma 和 interval HIT normal form 均无歧义重建为原上下文 Agda term；结果 packet 带输入 schema/SHA/QName/定义数 | Web 复核。 |
| recheck | `LOCAL-PASS`（声明子集） | 所有矩阵场景在原 `defType` 下调用 `checkType/checkInternal` 后原子发布；损坏、错配及 unsupported 不留旧产物 | Web 复核。 |
| MAlonzo 最终用户程序接线 | `LOCAL-PASS`（声明子集） | Stock Agda 生成的 MAlonzo 程序运行时接收 v14 packet/result 文件，从 `type-ast`/definition closure 推导结果类型，复算 SHA-256、再次执行 cctt 并消费经 Agda recheck 的 Bool/Sigma/HIT 结果；旧 schema 保留读兼容；矩阵 10/10 | Web 复核。 |
| 禁止 Agda 子进程/编译期 normalise/closure | `LOCAL-PASS`（声明子集） | producer/integrated/MAlonzo 的 PATH trap 均未触发；正式 adapter 无 `normalise`、Agda runtime 回调或 subprocess；oracle 是隔离的 test-only 二进制 | Web 复核。 |
| 资源配额与稳定错误 | `LOCAL-PASS` | IR 16 KiB、result 64 KiB、定义 32、表达式深度 32；adapter 语义工作量 fuel 默认 4096；真实 cctt eval 另受 256 MiB allocation 与 5 s timeout；三者均有低限额反例，provider 19/19 | Web 复核。adapter fuel 不宣称是 cctt 内部 reduction-step 计数。 |
| 同输入 Agda oracle 差分 | `LOCAL-PASS`（声明子集） | 隔离 test-only oracle 对每个现实场景的同一 QName 求正规形；Bool、Sigma 观察和 HIT point/path 结构与 runtime 输出一致 | Web 复核。 |
| 环境矩阵 | `PARTIAL` | 当前 macOS/arm64 锁定 GHC 9.10.3 集成、GHC 9.8.2 provider、Stock strip、空 PATH、离线 build 与统一矩阵均通过；先前 Web 失败所指两项已本机修复 | 提交后由指定 SHA fresh clone 在 Web/原 ELF 环境和至少一个第二宿主复跑。 |

## 语义覆盖矩阵

“求值已有”只表示 provider 具备相关上游能力；未通过 Agda 输入、通用 adapter、reify、
recheck 和最终程序闭环时，不能据此宣称该构造已支持。

| 构造 | Agda 输入/reflect | provider 求值 | reify/recheck | 差分 | 反例与边界 | 最终程序 | 总体 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 空面 `hcomp`（声明 Bool/Sigma/HIT 子集） | `LOCAL-PASS` | `LOCAL-PASS` | `LOCAL-PASS`（Bool/Sigma/HIT） | `LOCAL-PASS`（同 QName oracle） | `LOCAL-PASS`（篡改、格式、unsupported） | `LOCAL-PASS`（MAlonzo + recheck 绑定） | `LOCAL-PASS` |
| 活动面 `hcomp` | `LOCAL-PASS`（Bool literal tube + interval-HIT 前/反向高阶 tube） | `LOCAL-PASS`（真实非空 cctt system） | `LOCAL-PASS`（Bool/HIT Term+Type） | `LOCAL-PASS`（相反 active system/tube 的同 QName oracle） | `LOCAL-PASS`（命名 tube、冲突、方向/face 篡改、无陈旧产物） | `LOCAL-PASS`（Bool 7/7 + HIT 10/10） | `LOCAL-PASS`（声明支持 i1 Bool literal 与 interval-HIT path tube；其他 cofibration 稳定 unsupported） |
| `transp` | `LOCAL-PASS`（常量 Bool、identity Glue family、非平凡 Bool-negation Glue family） | `LOCAL-PASS`（真实 cctt `coe`） | `LOCAL-PASS`（Bool Term+Type） | `LOCAL-PASS`（保持与翻转结果均同输入 oracle） | `LOCAL-PASS`（活动 face/错误 family/伪造等价/篡改/无陈旧产物） | `LOCAL-PASS`（三类 family 均 MAlonzo + recheck） | `LOCAL-PASS`（声明支持三类精确 family；其他 family 稳定 unsupported） |
| `Glue` | `LOCAL-PASS`（空 system intro/elim + identity/negation 活动 endpoint systems） | `LOCAL-PASS`（真实 cctt `Glue/glue/unglue/coe`） | `LOCAL-PASS`（Bool Term+Type） | `LOCAL-PASS`（payload、identity 与 polarity-changing family） | `LOCAL-PASS`（命名 payload、不同等价、truth-table/system 篡改、无陈旧产物） | `LOCAL-PASS`（三个场景各 7/7） | `LOCAL-PASS`（声明支持 Bool identity 与已检查 negation 等价；其他等价稳定 unsupported） |
| `Pi` | `LOCAL-PASS`（递归 Bool→Bool + 依赖 `(d : Bool) → Evidence d → Bool`） | `LOCAL-PASS`（真实 dependent case） | `LOCAL-PASS`（Bool 结果） | `LOCAL-PASS`（普通/依赖调用同输入 oracle） | `LOCAL-PASS`（错误 body/index/定义引用/超限拒绝） | `LOCAL-PASS`（MAlonzo + SHA/recheck，dependent 7/7） | `LOCAL-PASS`（声明支持 Bool 闭包与 Bool 索引证据 Pi） |
| record/Sigma | `LOCAL-PASS`（`Σ (decision : Bool), DecisionEvidence decision`） | `LOCAL-PASS`（cctt indexed inductive + dependent Sg hcomp） | `LOCAL-PASS`（依赖 Sigma Term+Type） | `LOCAL-PASS`（决定、证据构造和索引类型观察） | `LOCAL-PASS`（错误索引/family/QName/SHA、无陈旧产物） | `LOCAL-PASS`（MAlonzo 结构化消费，7/7） | `LOCAL-PASS`（声明支持 Bool 索引证据 Sigma；其他 family 稳定 unsupported） |
| HIT | `LOCAL-PASS`（闭合 interval HIT：两个点和一条路径） | `LOCAL-PASS`（真实 cctt higher inductive + 空/活动 HIT `hcom`） | `LOCAL-PASS`（原 HIT Term+Type） | `LOCAL-PASS`（路径端点及前/反向 tube 产生不同正规形） | `LOCAL-PASS`（自环 HIT 拒绝、边界/方向/QName 篡改、无陈旧产物） | `LOCAL-PASS`（MAlonzo + SHA-256/recheck 绑定，10/10） | `LOCAL-PASS`（明确支持 interval HIT 及其 path tube；其他 HIT 稳定 unsupported） |

## 现实场景测试目录

测试必须表达一个可辨认的需求，并从真实 Agda 源码进入最终程序；不得只是向 verifier
传一个构造名或布尔参数，再比较脚本内写死的期望。

| 场景 | 对应语义 | 真实输入与成功终态 | 必须包含的反例 |
| --- | --- | --- | --- |
| 离线策略快照保留 | 空面 `hcomp` | 两份真实 Agda 策略快照分别保存关闭/开启决策，最终离线程序在无 Agda 环境中保持各自结果 | 活动 override 不得被误当空面；上下文或 IR 被修改时拒绝且无旧产物。 |
| 版本化审批状态迁移 | `transp` | 旧版审批记录沿已检查的类型族迁移到新版表示，身份、决定和审计字段保持约定语义 | 不匹配端点、缺定义、超深类型族和错误上下文拒绝。 |
| 分层紧急覆盖合并 | 活动面 `hcomp` | 基础策略、局部覆盖与边界条件共同决定最终授权；至少两个不同 boundary 输入产生不同结果 | 冲突/不完整 system、错误 face 和资源超限拒绝。 |
| 依赖型规则执行 | `Pi` | 规则结果依赖真实请求类别和已检查证据，不同请求走同一函数得到不同正规形 | 参数类型不匹配、开放项、伪造依赖身份拒绝。 |
| 带证据的审批结果 | record/Sigma | 最终结果同时含业务决定、原因和与决定相关的证据字段，并能被最终程序结构化消费 | 决定与证据不一致、字段缺失/错序、定义切片不一致拒绝。 |
| 策略表示兼容迁移 | `Glue` | 旧/新策略表示通过明确等价关系互操作，来回迁移保持可观察决定 | 非等价映射、伪造等价证据、往返结果不一致拒绝。 |
| 等价工作流状态 | HIT | 在明确选定且 provider 支持的 HIT 上，两个合法路径表示在业务观察下得到一致结果 | 未声明 HIT、非法路径构造或超出支持消去规则时拒绝。 |

HIT 场景只有在完成 provider 能力探测并写明具体 HIT 与消去规则后才能进入实现；不能为填满
矩阵而自造玩具语法。

## 每个纵向切片的完成定义

一个单元格从 `MISSING/PARTIAL` 提升前，至少需要：

1. 多模块或结构化真实 Agda 输入，包含两个会产生不同可观察结果的有效实例。
2. 真实 `Term + Type`、定义切片和身份进入 provider 数据流，禁止 fixture 专用求值捷径。
3. runtime 结果 reify 并 recheck；最终程序只消费检查后的结果。
4. 与同一输入的 Agda oracle 做结构化差分，不用手写字符串冒充 oracle。
5. 覆盖 malformed、身份不匹配、unsupported、资源超限和无陈旧产物。
6. 测试输出当前 commit、输入身份、provider/Agda revision、实际工具版本和退出码。
7. 先通过 `runtime-nbe` 独立入口，再运行受影响的仓库集成测试。
