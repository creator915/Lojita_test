# Term transport 路径

本路径跨进程搬运真实 Agda Internal `Term + Type`，不搬运 NbE 求值器的 semantic value。Stock Agda 2.8.0 被编译成带 backend 的可执行程序：生产端从 type-checker 取得、归约并检查闭合 Internal 值，reify 成版本化 wire syntax；另一个进程在相同源码身份下将 syntax 重建为真实 Internal `Term + Type`，再调用 `checkType` 和 `checkInternal`。

这不是 Python/custom AST 演示。wire syntax 是真实 Internal 值的进程无关序列化边界；packet 中没有 Haskell closure、`TCState`、`TCM`、meta、NbE value 或进程指针。

状态：`STRUCTURED-PROJECT-IMPLEMENTED-LOCAL / WEB-NOT-VERIFIED`。

## 正式参考项目

`examples/approval-handoff/` 是七模块审批交接工程。其 201 行 Agda 源码覆盖自定义 record/ADT、String、Nat、Bool、嵌套 review/tag List、三项 batch、派生 Summary 以及五个编译期证明。

独立验收会让五种结构化业务值经过十个真实生产/消费进程，并精确比较重建结果；还会验证 packet 内容损坏、非入口策略源码变化、顶层模块变化和陈旧输出拒绝。要求见 `examples/approval-handoff/ACCEPTANCE.md`。

## Packet 边界

- magic 和 schema version 当前为 wire v2。
- 绑定锁定 Agda revision、顶层模块名和 Agda full interface hash。
- 搬运 reified term syntax 与 type syntax，并带内容完整性 hash。
- 生产端拒绝开放变量、meta、超过 syntax 限制和非闭合值。
- 消费端限制 packet 大小，重新解析/检查 Type，以该 Type 检查 Term，再执行 Internal recheck。
- 内容 hash 发现意外损坏，但不提供来源认证；不可信通道仍需调用方认证。

## 构建

依赖 Python 3、Git、Cabal、满足锁定 Agda 包约束的 GHC，以及锁定官方 Agda Git checkout。工具通过参数、环境变量或 `PATH` 解析，不绑定操作系统、包管理器或安装目录。

```sh
git clone https://github.com/agda/agda.git "$AGDA_SOURCE_DIR"
git -C "$AGDA_SOURCE_DIR" checkout 3d04bacca842729f9c0869b9287256321b5f450f

python3 term-transport/build-internal.py \
  --agda-source "$AGDA_SOURCE_DIR" \
  --ghc "$GHC" \
  --cabal "$CABAL"
```

`GHC`、`CABAL` 参数可以省略并从 `PATH` 查找。构建脚本校验 revision、干净工作树、`Agda.cabal` 和 MIT 许可证文件 SHA-256；产物及 provenance 位于忽略的 `build/term-internal-bridge/`。已有 Cabal store/index 时可追加 `--offline`。

## 测试

正式项目独立测试：

```sh
python3 term-transport/examples/approval-handoff/verify.py \
  --bridge-bin build/term-internal-bridge/bin/agda-term-bridge
```

Term 路径统一测试：

```sh
python3 -B term-transport/verify-internal.py \
  --bridge-bin build/term-internal-bridge/bin/agda-term-bridge
```

统一测试为 14/14，包含正式项目 7/7，并补充 Nat、Bool、闭合函数、underconstrained/meta、截断、尾随、超限、模块身份和已有 packet 反例。输出 commit、项目/fixture/packet/bridge hash 以及实际 Agda/GHC/Python 身份。

## Web 沙箱依赖缓存

可在 Web 资料库保存锁定 revision 的官方 Agda Git bundle/干净 checkout、匹配宿主架构的官方 GHC 包、Cabal source cache/index，以及记录来源 URL、SHA-256、许可证、宿主和架构的 manifest。缓存可恢复到任意路径并通过参数传入，但不能替代源码校验或提交进仓库。

## 尚未实现

- 在 packet 内携带闭合定义切片；当前接收端必须拥有 full interface hash 一致的源码上下文。
- stdin/stdout 流式通道；当前只有文件 packet。
- 通用 Cubical/HIT syntax 兼容承诺及多 Agda wire 版本迁移。
- 认证/加密通道、更细的节点/fuel 预算和完整原子发布协议。
- 第二宿主环境和 Web 对指定提交的 fresh-clone 独立核验。

因此结构化正式调用路径已经存在，但完整 Term transport 产品仍未验收。
