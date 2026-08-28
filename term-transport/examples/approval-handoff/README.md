# 正式 Term 示例：审批交接包

该项目模拟审批系统把一批已检查业务数据交给另一个进程。七个 Agda 模块定义并证明 `Envelope`、嵌套 review、金额策略、状态分类、batch 和 summary；packet 覆盖自定义 record/ADT、String、Nat、Bool、嵌套 List 及派生值。

生产者从真实 Agda type-checker 取得并归约 Internal `Term + Type`，reify 成受版本和完整性保护的 wire syntax。另一个 Agda/backend 进程在相同源码树身份下将其重建为真实 Internal `Term + Type`，再执行 `checkType` 与 `checkInternal`。wire 中没有 NbE value 或编译器进程状态。

独立验收：

```sh
python3 term-transport/examples/approval-handoff/verify.py \
  --bridge-bin build/term-internal-bridge/bin/agda-term-bridge
```

该命令会启动十个独立生产/消费进程验证五种结构化值，并执行内容损坏、非入口依赖变化、顶层模块变化和陈旧输出反例。完整要求见 `ACCEPTANCE.md`。
