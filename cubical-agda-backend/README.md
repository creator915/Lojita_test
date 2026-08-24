# Cubical Agda backend

这是 Cubical Agda 的类型安全后端与运行时集成仓库。最终产品是
[`GOALS.md`](GOALS.md) 中定义的三路架构，不是单独的 Chez 试验。

## 当前状态

| 目标 | 状态 | 当前边界 |
| --- | --- | --- |
| 1. stock Agda -> MAlonzo -> Haskell -> GHC 二进制 | **已实现并验收** | 锁定 Stock Agda 2.9.0 / MAlonzo / GHC 9.10.3；独立二进制审计 |
| 2. 跨进程 `Term + Type` packet | **已有实现** | 仍需 clean-clone overlay 构建验收 |
| 3. 最终程序进程内 runtime NbE | **技术证据完成（11/11），待独立验收** | cctt 对实际输入归一化；t11/t11b 使用证明关联的同输入精确差分 |

当前可用的是候选 CubicalChez 后端、checked typed residual/packet、编译期
NbE adapter 候选与完整的安全拒绝门禁。当前目标 1 已关闭，目标 3 技术证据完成但未独立验收；
三路调度和总体发布门禁未关闭前，不得将仓库标记为完整交付。

## 目标数据流

```text
Agda source
   |
   +-- native-safe ------> stock Agda/MAlonzo -> erased Haskell -> binary   [IMPLEMENTED]
   +-- cross-process ----> checked Term + Type packet                       [IMPLEMENTED]
   `-- runtime-higher ---> linked in-process runtime NbE      [IMPLEMENTED; EVIDENCE: 11/11]
```

跨进程只传输 Agda Internal `Term + Type` 协议数据。NbE 语义值、closure 和
`TCState` 不得跨进程序列化。

## 仓库布局

```text
.
├── GOALS.md                     最终产品目标与三路边界
├── DELIVERY_CHECKLIST.md        唯一验收清单
├── src/                         CubicalChez 编译器后端
├── runtime/agda-2.9/            v2 typed Term 运行时 overlay 源码
├── runtime/nbe/                 独立 wire AST、语义域和最终进程内 runtime 库
├── config/                      NbE/provider/性能锁定信息
├── compat/                      锁定上游的显式兼容补丁
├── test/fixtures/               Agda 测试输入
├── test/scripts/                可重现验收门禁
├── docs/                        架构、支持矩阵、结果与故障码
├── Makefile                     根目录构建入口
└── build/                       本机生成物，不进 Git
```

聊天记录、临时回答、旧技术结论和 ZIP 归档不是构建输入，也不在 Git
交付树中。

## 依赖

当前快速构建环境已验证：

- Agda 2.8.0 及其 GHC package database；
- GHC 9.12.3；
- Chez Scheme 10.4.1；
- BSD/POSIX `make` 和 shell 工具。

锁定的 Agda 2.9 通道需要 Agda 2.9.0、GHC 9.6.7、兼容的 Cabal 客户端以及
对应 cubical checkout。

Homebrew 布局可以直接使用 Make 默认值。其他布局可传入：

- `AGDA_PREFIX`
- `AGDA_PACKAGE_DB`
- `AGDA_LIBRARY_REGISTRY`
- `GHC_PREFIX`
- `GHC`

目标 1 的锁定原生通道还使用：

- `NATIVE_AGDA`
- `NATIVE_AGDA_SOURCE_DIR`
- `NATIVE_AGDA_DATA_DIR`
- `NATIVE_GHC`

版本与官方源码 revision 固定在
[`config/native-toolchain.lock.tsv`](config/native-toolchain.lock.tsv)。

## 快速开始

从仓库根目录执行：

```sh
make build
make verify-readme-quickstart
```

快速门禁应包含：

```text
StaticOrdinary PASS (42)
StaticTransport PASS (0)
TypedResidual EXPECTED-REJECT (CCZ-RESIDUAL-REQUIRED)
```

第三行是安全成功：它证明带残余 Cubical 语义的项没有被静默发布为无类型
Scheme。

当前本地回归：

```sh
make verify
```

目标 1 的真实 Stock Agda/MAlonzo/GHC 验收：

```sh
NATIVE_AGDA=/path/to/agda \
NATIVE_AGDA_SOURCE_DIR=/path/to/clean/agda-source \
NATIVE_AGDA_DATA_DIR=/path/to/agda-data \
NATIVE_GHC=/path/to/ghc \
make verify-native-lane
```

长时间 Agda 2.9 验收需要显式的锁定路径：

```sh
AGDA29_SOURCE_DIR=/path/to/agda-source \
CUBICAL29_DIR=/path/to/clean-cubical-source \
GHC29=/path/to/ghc-9.6.7 \
CABAL29=/path/to/cabal \
make verify-formal-transport-production-candidate
```

## CLI

```text
--cubical-chez
--cubical-chez-engine=agda-baseline|nbe
--cubical-chez-nbe-fallback=reject|agda-baseline
--cubical-chez-residual=reject|manifest|packet
--cubical-chez-packet-file=FILE|-
--cubical-chez-output=DIRECTORY
--cubical-chez-entry=NAME
```

默认 `nbe` 仍为 `FAIL-CLOSED`：未选定并链接生产 provider 时返回
`CCZ-NBE-UNAVAILABLE`。候选测试构建的通过不会隐式改变默认二进制。

## 主要验收命令

```sh
make verify-status-guide
make verify-native-lane-contract
make verify-native-lane
make verify-runtime-nbe
make verify-runtime-nbe-cctt-provider
make verify-runtime-nbe-agda-bridge
make verify-runtime-nbe-differential
make verify-runtime-nbe-final-malonzo
make verify-support-matrix
make verify-nbe-adapter-spike
make verify-nbe-production-candidate
make verify-binding-time
make verify-typed-residual-contract
make verify-formal-transport-production-candidate
make verify-v2-runtime
```

`verify-v2-runtime` 当前还要求 `AGDA29_SOURCE_DIR` 中安装了仓库
`runtime/agda-2.9/` overlay。将这一步变成 clean-clone 自动化仍是目标 2 的最后开放项。

## 文档

- [`GOALS.md`](GOALS.md)：最终三路目标。
- [`DELIVERY_CHECKLIST.md`](DELIVERY_CHECKLIST.md)：验收唯一事实源。
- [`ARCHITECTURE.md`](docs/ARCHITECTURE.md)：现有编译期架构。
- [`NATIVE_LANE.md`](docs/NATIVE_LANE.md)：目标 1 分类、工具链锁与产物审计。
- [`RUNTIME_NBE_BOUNDARY.md`](docs/RUNTIME_NBE_BOUNDARY.md)：目标 3 最终进程与数据边界。
- [`RUNTIME_NBE_ABI.md`](docs/RUNTIME_NBE_ABI.md)：目标 3 ABI、provider 和资源边界。
- [`ENGINE_CONTRACT.md`](docs/ENGINE_CONTRACT.md)：引擎请求/结果与 typed residual 契约。
- [`SUPPORT-MATRIX.md`](docs/SUPPORT-MATRIX.md)：支持、候选、残余与拒绝状态。
- [`STATUS.md`](docs/STATUS.md)：当前实现与未交付项。
- [`TEST-RESULTS.md`](docs/TEST-RESULTS.md)：历史验证记录。
- [`BENCHMARKS.md`](docs/BENCHMARKS.md)：性能方法和结果。
- [`NBE_SELECTION.md`](docs/NBE_SELECTION.md)：NbE 候选与晋级阻塞。
- [`TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)：稳定错误码与安全恢复。

## 当前边界

- Chez 仍是独立候选静态目标；目标 1 由 `bin/cubical-agda-native` 的原版 MAlonzo/GHC 路径验收。
- 编译器进程内 adapter candidate 不是目标 3 证据。目标 3 的独立窄腰接收
  真实 Agda Internal definition slice，覆盖验收所需 Bool/Nat/Int/Vec/Pi/
  Sigma/Glue/S¹ 与 transport/composition，并链接进 Stock Agda/MAlonzo/GHC
  最终程序。cctt provider 的输出现在由实际 Bool/Int/Vec/Sigma 输入的 Core
  归一形解码得到，不再以固定 probe 授权本地结果。未声明的通用 Kan、indexed
  data 和任意 HIT 仍 fail closed。
- `t11/t11b` 等已知残余不得进入无类型执行路径。
- 编译器进程的默认 `nbe` provider lock 仍保持未选择和安全拒绝；它与目标 3
  最终进程 runtime 的独立 cctt lock 不同。后者已链接 vendored Core 的
  `eval`/`quoteUnfold`。provider 与 ELF 门禁已通过；新的 t11/t11b 精确同输入
  差分必须在锁定 CI 通过后再记为验收证据。
