# 交付验收清单

> 范围基准：[`GOALS.md`](GOALS.md) 定义的三路架构。
> 当前结论：目标 1 **已实现并通过 clean-clone 验收**；目标 2 **已有实现，待 clean-clone 验收**；目标 3 **未实现**。
> 新范围统计：30/56 项已完成（53.6%）；目标 1 为 9/9，目标 2 为 8/9，目标 3 为 1/11。
> 旧的 `224/321` 统计针对 Chez/编译期 NbE 旧范围，不再代表当前三路目标的完成度。

## 勾选规则

- `[x]`：实现完成且可由仓库内源码、测试或记录定位。
- `[ ]`：未实现、待决策或待独立验证。
- P0 为整体交付阻塞；P1 为正式交付必需。
- 清单项数不按工作量加权；不得用勾选比例掩盖目标 1/3 未完成。

## A. 仓库与交付边界

- [x] 项目以仓库根目录为构建根，不再嵌套 `backend/` 工作树。
- [x] 根目录保留 `README.md`、`GOALS.md` 和 `DELIVERY_CHECKLIST.md`。
- [x] 源码、运行时、配置、测试和文档分别放入明确目录。
- [x] 原始聊天、临时回答、旧技术结论和 ZIP 不进入 Git 交付树。
- [x] 原始单体测试已收编为 `test/fixtures/TransportTests.agda`。
- [x] `build/`、Cabal/Stack 中间物和 `.agdai` 都被 Git 忽略。
- [ ] **P1** 从 clean clone 验证不需要任何未跟踪的本机原始包。

## B. 共享类型与安全边界

- [x] 以 Agda type checker/`TCState` 作为类型和定义的真理源。
- [x] 引擎边界传递 checked Internal `Term + Type`。
- [x] 引擎结果在进入 Treeless/擦除路径前重新检查类型。
- [x] 有残余 Cubical primitive 的项不得进入无类型静态产物。
- [x] 引擎不可用、不支持、失败和超时具有分离的 fail-closed 状态。
- [x] 默认 `nbe` 在未正式晋级时安全拒绝。

## C. 目标 1：Stock Agda -> MAlonzo -> GHC

**本节已由独立的 stock MAlonzo/GHC 路径关闭。static Chez 结果未被用于本节验收。**

- [x] **P0** 定义“无需运行时高阶搬运”的可审计分类规则。
- [x] **P0** 在 driver 中实现 native lane，调用锁定的 stock Agda compiler。
- [x] **P0** 确认 native lane 生成 MAlonzo 类型擦除 Haskell。
- [x] **P0** 由锁定 GHC 将 Haskell 构建为可执行二进制。
- [x] **P0** 审计二进制，证明未链接 `Term` / `Type` / `TCState` / runtime NbE。
- [x] **P1** 普通 Agda 程序从源码到二进制端到端 PASS。
- [x] **P1** 对“含 Cubical 语法但可静态消除”的范围获得书面验收定义。
- [x] **P1** native lane 与 stock Agda 的输出、退出码和错误行为差分一致。
- [x] **P1** 建立 native lane 的 clean-clone 和 CI 验收。

## D. 目标 2：跨进程 Term + Type 协议

- [x] 产生端保留 checked Internal `Term + Type`，不传 NbE 语义域内部值。
- [x] packet 包含版本、模块名和完整 interface identity。
- [x] 只允许闭项且拒绝 unresolved metavariable。
- [x] 消费端在应用前重新检查 `Term : Type`。
- [x] 文件通道与 stdin/stdout 管道都有实现。
- [x] 模块、interface 或消费者类型不匹配时安全拒绝。
- [x] 包大小受限，破损/截断 packet 被转化为稳定错误。
- [x] v2 生产者/消费者和运行时测试源码已从归档中收编到 `runtime/agda-2.9/`。
- [ ] **P1** clean clone 从锁定上游 Agda 源码安装 overlay、构建 runner 并运行 file/pipe/负例全部 PASS。

## E. 目标 3：最终程序进程内 runtime NbE

**本节整体未完成。当前 NbE candidate 只在编译器进程中运行。**

- [x] **P0** 固定“进程内”指最终用户程序进程，并固定运行时数据边界。
- [ ] **P0** 选定可作为 runtime library 的成熟 NbE 源码、revision 和许可证。
- [ ] **P0** 定义 runtime NbE ABI，包括输入 Term/Type、上下文和结果/错误。
- [ ] **P0** 将 runtime NbE 库链接进最终程序产物。
- [ ] **P1** 实现运行时 `Term + Type -> semantic domain` reflect。
- [ ] **P1** 实现运行时 environment/closure 语义和必要的 definition lookup。
- [ ] **P1** 实现验收片段需要的 `transp` / `hcomp` / Glue / Pi / record / HIT 语义。
- [ ] **P1** 实现类型导向 reify/readback 和结果重检。
- [ ] **P1** 实现 fuel、内存/包大小限额、缓存生命周期和 fail-closed 错误。
- [ ] **P1** 验收证明运行时不启动 Agda 子进程、不调用编译期 `normalise`。
- [ ] **P1** 对 `t11/t11b/t16` 及新增进程内用例执行 Agda oracle 差分验收。

## F. 三路调度与端到端集成

- [ ] **P0** 一次类型/binding-time 分析产生稳定的 native/packet/runtime-nbe 调度决策。
- [ ] **P0** 目标 1 程序必须绕过 packet 和 runtime NbE。
- [ ] **P0** 跨进程边界必须只发布 Term packet，禁止序列化 semantic closure/TCState。
- [ ] **P0** 目标 3 调度必须进入已链接 runtime NbE，不得假冒 compiler candidate。
- [ ] **P1** 每条路径发布独立 provenance，能从产物判定实际路径。
- [ ] **P1** 失败或取消后不留下过期二进制、Scheme 或 packet。
- [ ] **P1** 三路正例、类型错配、身份错配和资源超限负例全部自动化。
- [ ] **P1** 完整验收在 clean clone 和 CI 上可重现。

## G. 发布门禁

- [ ] **P0** 目标 1 全部 P0/P1 勾选。
- [ ] **P0** 目标 3 全部 P0/P1 勾选。
- [ ] **P0** NbE provider 仓库、revision、内容身份和许可证获得批准。
- [ ] **P1** 官方回归、三路端到端、安全负例和性能门禁全部 PASS。
- [ ] **P1** `README.md`、`GOALS.md`、本清单与测试证据状态一致。
- [ ] **P1** 老板确认交付范围、性能阈值、产物形式和发布时间。

## 验收结论

当前仅能对外说“候选后端、typed packet 和编译期 NbE 验证基础可用”。
C 节已经关闭，可以声称目标 1 已完成。E 节关闭前不得声称目标 3 或整个项目已完整验收。
