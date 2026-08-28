# 正式 Native 示例：费用审批流

这是 Native 路径的多模块业务验收项目，不是 mock。领域、策略、状态机、审计渲染、场景和可归约证明都用 Agda 编写，再由未修改的 Stock Agda 生成 MAlonzo Haskell，最后交给独立 GHC 链接成 CLI 二进制。

覆盖场景：小额经理直批、中额财务审批、大额总监审批、业务拒绝、越权操作、自批拒绝和顺序错误。`Approval.Proofs` 还在编译期证明三个成功场景的最终状态、大额审计事件数量及失败后的状态保持。

构建：

```sh
python3 native-binary/build.py \
  --project-root native-binary/examples/approval-workflow/src \
  --source native-binary/examples/approval-workflow/src/ApprovalMain.agda \
  --profile ordinary \
  --binary-name approval-workflow \
  --output build/approval-workflow
```

运行示例：

```sh
build/approval-workflow/bin/approval-workflow large
```

项目可独立验收：

```sh
python3 native-binary/examples/approval-workflow/verify.py
```

统一入口 `python3 native-binary/verify.py` 还会连同小型冒烟用例、编译失败和构建竞争反例一起执行。详细要求见 `ACCEPTANCE.md`。
