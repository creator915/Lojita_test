# Runtime NbE path

## 任务

把经确认的成熟 Cubical NbE provider 作为运行时组件链接进最终用户程序，在该程序进程内对经检查的 `Term + Type` 执行 reflect → evaluate/transport → reify → recheck。

## 接口边界

- 输入来自真实 Agda Internal `Term + Type` bridge，并带闭合定义切片及上下文身份。
- 输出为重新检查通过的 `Term + Type` 或稳定的封闭错误。
- 禁止启动 Agda 子进程、回调编译期 `normalise`、传递 `TCState/TCM` 或 Haskell semantic closure。
- reference-only、源码哈希 probe、布尔授权、自定义玩具 AST 均不算 provider 接入。

## 验收标准

- provider 固定不可变 revision、来源和许可证；实际源码被构建并链接到最终二进制。
- 通过符号、调用链和输入敏感反例证明真实 provider 结果进入最终程序。
- 覆盖约定的 `transp`、`hcomp`、`Glue`、`Pi`、record/Sigma、HIT；未覆盖构造稳定拒绝。
- t11/t11b/t16 等用例使用同一真实输入与 Agda oracle 比较；手写期望或证明关联只能标为相关性证据。
- packet、fuel、递归深度和 allocation 均有边界，失败不产生半成品。
- 提供本目录独立测试入口，并包含无子进程、错误码和混用 provider/context 的负例。

