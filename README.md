# cubical-agda-backend

本仓库把目标拆成三条可独立实现、独立测试的路径，最后由一个轻量分流器连接。原则是先分别跑稳，再做最小耦合集成。

| 目录 | 职责 |
| --- | --- |
| `native-binary/` | 无需运行时搬运高阶同伦数据时，走 Stock Agda → MAlonzo → 类型擦除 Haskell → 本机二进制 |
| `term-transport/` | 跨进程时搬运经检查的 `Term + Type` 数据，不搬运 NbE 语义值 |
| `runtime-nbe/` | 在最终用户程序进程内，以成熟 NbE 执行高阶同伦搬运/计算 |
| `dispatcher/` | 根据已验证的分析结果选择且只选择一条路径；初期只实现纯分流判断 |

## 当前状态

`native-binary` 已支持受控多模块费用审批工程；`term-transport` 已支持闭合结构化 Internal `Term + Type` 的 approval-handoff 跨进程工程。`runtime-nbe` 的统一 v14 typed-AST 声明能力矩阵覆盖递归/依赖 Pi、普通与依赖 Sigma、空面及活动面 `hcomp`、常量与 Glue-family `transp`、空/identity/非平凡 negation Glue，以及 interval HIT；真实 Agda Internal 输入及声明闭包经链接的 cctt eval/quote、原类型 recheck，再由 Stock MAlonzo 最终程序消费，v1–v13 仅保留读兼容。统一现实场景入口在本机为 10/10 PASS，provider 资源/strip 入口为 19/19 PASS。它仍不是任意 Agda 语法的通用 adapter，矩阵外输入 fail-closed；这些新结果尚无指定提交 SHA 的 Web fresh-clone 与第二宿主独立复核，dispatcher 也尚未验收，因此整个仓库仍不可称为完整后端。真实进度只看 [ACCEPTANCE.md](ACCEPTANCE.md)；文字说明、历史日志和 CI 绿灯不能替代对应代码与独立复测。

## 协作方式

- 本机 Codex：唯一实现角色，负责编码、测试和提交。
- Web Codex：只读核验角色，从指定提交 fresh clone 后执行测试并检查证据，不修改代码、不创建分支或 PR。
- 三条路径不得相互依赖；分流器只能依赖各路径公开的稳定接口。

## 环境原则

不得把操作系统版本、包管理器目录、用户名、绝对路径或某个工具可执行文件名写死。工具路径和版本约束通过参数、环境变量或配置传入，并在测试报告中记录实际探测结果。允许锁定影响语义的上游源码 revision，但不能把单一宿主环境误写成产品要求。
