# Approval handoff 验收标准

- 数据必须来自真实 Agda Internal `Term + Type`，不能由 Python/custom AST 伪造。
- `Envelope` 同时覆盖自定义 record/ADT、String、Nat、Bool、嵌套 `List Review` 与 `List String`。
- 已批准、待审批、已拒绝、三项 batch 和派生 `Summary` 都要经过独立生产者/消费者进程。
- 消费端必须在源码树身份一致时重建真实 Internal 值，并执行 `checkType`、`checkInternal`。
- 非入口依赖变化、顶层模块变化、packet 内容损坏和已有输出必须 fail-closed。
- packet 不得包含 NbE semantic value、Haskell closure、`TCState`、`TCM` 或进程指针。
- 构建期证明批准状态、拒绝状态、review 数量和 batch 数量。
- Web 未对指定提交 fresh-clone 复核前只能报告 `IMPLEMENTED-LOCAL`。
