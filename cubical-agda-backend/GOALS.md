# 交付目标

本文档定义仓库的最终产品边界。实现状态以根目录
[`DELIVERY_CHECKLIST.md`](DELIVERY_CHECKLIST.md) 为准。

## 最终三路架构

```text
Agda 源程序
   |
   +-- 1. 不需要运行时高阶同伦搬运
   |      stock Agda -> MAlonzo -> 类型擦除 Haskell -> GHC 二进制
   |
   +-- 2. 需要跨进程搬运
   |      checked Internal Term + Type packet
   |      只跨进程传 Term 协议数据，不传 NbE 语义值/closure/TCState
   |
   +-- 3. 需要最终程序进程内的高阶同伦计算
          linked runtime NbE -> reflect/evaluate/reify
```

## 目标 1：原版编译器的本地二进制路径

**状态：已实现并通过专项及 clean-clone 验收。**

对不需要运行时搬运高阶同伦结构的程序，使用原版 Agda
MAlonzo 路径编译为类型擦除的 Haskell，再由 GHC 生成单个本地二进制。

必须证明：

- 该路径确实调用 stock Agda/MAlonzo，不是现有 Chez 输出的改名。
- 生成物不链接 `Term` / `Type` / `TCState` 或 NbE runtime。
- 程序输出与 stock Agda 基线一致。
- 路径分类错误时 fail closed，不得把未处理的 Cubical 原语擦除后编译。

## 目标 2：跨进程 Term 搬运

**状态：已有实现，仍需完成 clean-clone 集成验收。**

跨进程边界传输 Agda 已检查的 Internal `Term + Type`，并携带模块与
interface identity。消费端必须重新检查闭性、metavariable、类型与依赖身份。

仓库保留了产生端、v2 消费端源码、文件/stdio 协议和错误消费者拒绝测试。

## 目标 3：最终程序进程内的 runtime NbE

**状态：未实现。**

这里的“进程内”明确指最终用户程序的运行进程，不是 Agda
编译器进程。必须把成熟 NbE 作为 runtime 组件链接到最终产物，在同一进程内
完成 Term 到语义域的 reflect、搬运/计算和 reify。

必须证明：

- 运行时没有启动 Agda 子进程，也没有回调编译期 `normalise`。
- 链接的确实是受版本与许可证锁定的 NbE 实现。
- 运行时高阶/Cubical 结果与 Agda oracle 差分一致。
- 资源超限、不支持语义和身份不匹配都安全拒绝。

## 当前代码不得被误解为的内容

- 现有 compiler-process NbE candidate 不等于目标 3。
- 目标 1 使用独立的 stock MAlonzo/GHC 路径；现有 static Chez 输出未作为其证据。
- 候选 NbE 的 8 组/42 行差分通过，不等于已通过 runtime NbE 验收。
- 目标 3 及总体发布门禁关闭前，项目不得声称“完整交付”。
