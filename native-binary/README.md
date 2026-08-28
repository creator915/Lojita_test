# Native binary 路径

本路径使用未修改的 Stock Agda 完成 type-check → MAlonzo → 类型擦除 Haskell，再由独立 GHC 生成最终二进制。它支持单文件入口，也支持由 `--project-root` 明确圈定的多模块 Agda 工程；工程只能导入自身源码或 Agda builtins，超出边界就 fail-closed。

支持 `ordinary` 和由 Stock Agda 强制擦除约束的 `erased-cubical` profile。需要运行时 Cubical 计算的完整 `--cubical` 项不属于本路径，会被拒绝。

## 正式参考项目

`examples/approval-workflow/` 是 8 个 Agda 模块、416 行源码的费用审批 CLI，包含：

- 员工、经理、财务、总监的权限模型。
- 小额、中额、大额三级金额策略。
- 提交、审批、拒绝、越权、自批和错误顺序状态机。
- 每次有效迁移的人员、动作、前后状态审计。
- 成功终态、事件数量和失败状态保持的 Agda 编译期证明。
- 七个确定性业务场景和未知命令失败测试。

它没有预生成 Haskell；验收时必须从 Agda 源码重新生成并链接二进制。项目要求见 `examples/approval-workflow/ACCEPTANCE.md`。

## 构建

需要 Python、支持 MAlonzo 的 Stock Agda、兼容 GHC、`nm`，以及 `otool`/`ldd`/`objdump`/`dumpbin` 之一。工具默认从 `PATH` 探测，也可通过环境变量或命令行参数覆盖，不限定宿主系统版本和安装目录。

```sh
python3 native-binary/build.py \
  --project-root native-binary/examples/approval-workflow/src \
  --source native-binary/examples/approval-workflow/src/ApprovalMain.agda \
  --profile ordinary \
  --binary-name approval-workflow \
  --output build/approval-workflow
```

输出目录是一次性发布单元，已存在时拒绝覆盖：

- `bin/`：最终二进制。
- `generated/`：本轮生成的 MAlonzo Haskell。
- `audit/`：源码模块、生成源码、符号和动态依赖审计。
- `logs/`：Agda 与 GHC 的真实命令及输出。
- `provenance.json`：全部输入文件、源码树、工具、命令和产物身份。

## 测试

审批项目独立测试：

```sh
python3 native-binary/examples/approval-workflow/verify.py
```

Native 路径统一测试：

```sh
python3 native-binary/verify.py
```

统一测试还覆盖普通/擦除 Cubical 冒烟输入、完整 Cubical 与类型错误、外部源码导入、缺失工具、陈旧输出、入口及非入口源码竞争变更。测试使用临时目录，不调用 Term、NbE 或分流器路径。

## 尚未实现

- 第三方 Agda library 及其锁定依赖图。
- 需要运行时 Cubical/NbE 计算的程序。
- Dispatcher 自动选择和第二宿主/Web 独立复核。

因此正式多模块 Native 调用链已经存在，但完整跨环境交付尚未验收。
