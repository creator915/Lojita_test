# 审批流验收标准

- 八个 Agda 模块分别承载领域、工具、策略、引擎、渲染、场景、证明和 CLI，不使用预生成 Haskell。
- 金额 `≤1000` 由经理终审，`1001..5000` 增加财务审批，`>5000` 再增加总监审批。
- 正常拒绝进入终态；越权、自批和顺序错误不改变失败前状态或审计记录。
- 每次有效迁移写入包含人员、操作和前后状态的审计事件。
- 编译期证明三个成功场景均为 `approved`、大额场景有四条事件、两个安全失败保持 `submitted`。
- CLI 七个业务场景输出与验收文本逐字一致，未知命令非零退出。
- 构建 provenance 绑定全部源码；MAlonzo、符号及动态依赖审计不得出现另外两条路径或 Agda type-checker 运行时。

独立入口：

```sh
python3 native-binary/examples/approval-workflow/verify.py
```

Web 未对指定提交独立复核前，只能报告 `IMPLEMENTED-LOCAL`。
