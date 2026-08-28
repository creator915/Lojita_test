# Term transport path

## 任务

跨进程边界只搬运经检查的 Agda `Term + Type` 及其最小定义/上下文身份。线上的表示必须版本化，并能在消费端还原和重新检查；它不是 NbE 求值器内部的值表示。

## 接口边界

- 生产者和消费者必须是两个真实进程。
- 允许序列化稳定的 `Term + Type` wire packet、闭合定义切片和身份信息。
- 禁止序列化 NbE semantic value、Haskell closure、`TCState`、`TCM` 或进程指针。
- 该目录不得调用 runtime NbE 完成自己的验收。

## 验收标准

- 相同输入经独立进程写入、读取、重建并 recheck，结果保持类型正确。
- packet 包含 schema、provider/Agda、模块、上下文、依赖和内容完整性身份。
- 损坏、截断、未知构造、版本/上下文不匹配、开放 meta/free variable、资源超限全部 fail-closed。
- 证明失败时不消费部分数据、不沿用旧 packet、不留下可发布产物。
- 提供本目录独立测试入口，并在至少一种文件通道和一种流式通道上验证真实进程边界。

