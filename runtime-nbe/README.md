# Runtime NbE 路径

正式进度仍只看根目录 [`ACCEPTANCE.md`](../ACCEPTANCE.md)。本路径的逐构造覆盖、缺口和
证据入口记录在 [`CAPABILITY-MATRIX.md`](CAPABILITY-MATRIX.md)，持续自治实施顺序与测试
门槛记录在 [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md)。矩阵和计划不能代替正式验收。

本目录当前完成了真实 provider 门和统一 v14 typed-AST 的声明能力矩阵：锁定并构建
[`AndrasKovacs/cctt`](https://github.com/AndrasKovacs/cctt) 的实际源码，把其
`Core.eval` 与 `Quotation.quoteUnfold` 编入一个静态 Haskell library，并将该
library 链接进最终测试程序。它不是源码 probe，也不是按 cctt 思路重写的玩具
求值器。

## 运行时数据流

这不是 `term-transport` 路径。Agda producer/integrated backend 在编译上下文内读取
真实 Internal `Term + Type`；最终 Stock MAlonzo 用户程序只接收严格版本化的 runtime
IR 和已经由 Agda `checkInternal` 验证的 result packet，运行时不启动 Agda 或构建工具：

```text
checked Agda Internal Term + original defType
        → unified runtime-nbe-ir-v14 typed AST (legacy v1 … v13 read compatibility)
        → linked cctt elaborate → Core.eval → quoteUnfold
        → reify Agda term → checkType/checkInternal → SHA-bound result
        → Stock MAlonzo runtime repeats cctt evaluation and consumes checked result
```

## 当前能证明什么

- provider 固定为 `ba16f3758a322e9be77ada1da2b93f45d500192e`，MIT；源码 archive、
  许可证、package 与 Stack 配置都有 SHA-256 锁。
- build 使用 provider 自己声明的 Stack resolver，不写死操作系统、包管理器目录
  或用户名。`--provider-source`、`--output`、`--stack`、`--git` 均可配置。
- 产物包含可链接静态 archive 和最终可执行程序；符号审计要求两者都包含真实的
  `Core.eval`、`Quotation.quoteUnfold` 与本项目 adapter。
- 两个相反的、由 cctt 自己检查的输入分别归约为 `true` 和 `false`；上游自身的
  11 次 Glue transport 用例也在最终程序进程内归约为 `true`。
- 运行测试时清空 `PATH`，且 adapter 源码禁止 Agda/子进程/`normalise` 回调。
- 新 Agda lowerer 按不可伪造的 builtin QName 和 Internal 构造检查 `primHComp`、
  `Bool`、`i0`、空 partial system 及 Bool base；不调用 Agda `normalise`。
- 最终 `runtime-policy-user` 同时嵌入两份由真实 Agda 输入生成的 IR，空 `PATH`
  执行得到 `false/true`，证明 cctt 结果进入最终进程且受输入驱动。
- 旧 backend 只迁移了 exact-builtin registry、闭合项检查、构造形状检查和
  fail-closed 合同；旧 `SemanticValue`/TCM evaluator 没有迁入。
- 新 integrated binary 用同一 GHC ABI 链接 Agda 2.8.0 与 cctt；provider normal form
  被解析回真实 Agda Term，并在同一进程调用 `checkType/checkInternal` 后才原子发布。
- 十个现实场景覆盖递归 Bool/Pi、依赖 Pi、普通/依赖 Sigma、空面/活动面 `hcomp`、
  常量及非恒定 `transp`、Glue intro/elim、identity/negation Glue family 和 interval HIT；
  统一入口为 10/10 PASS，各场景都含相反有效输入、同输入 oracle、MAlonzo、篡改与
  unsupported/no-stale 反例。
- provider 另有 adapter semantic fuel、真实 cctt allocation limit 和 wall timeout；
  三者含独立低限额测试。semantic fuel 是反射工作量预算，不冒充 cctt reduction-step。

## 构建与测试

符号审计本身的跨 GHC/ELF/Mach-O 回归无需构建 provider：

```sh
python3 -B runtime-nbe/verify-symbol-audit.py
```

Agda 与 cctt 同进程链接、provider normal form 回到 Agda `checkInternal` 的测试入口：

```sh
python3 -B runtime-nbe/verify-integrated.py \
  --agda-source /path/to/agda-2.8.0 \
  --provider-source /path/to/cctt \
  --ghc /path/to/compatible-ghc
```

其中 `examples/policy-rules/` 是两模块现实用例：空面 hcomp 的 fallback 来自另一个
Agda 模块中的 `Bool → Bool` 策略。独立入口会验证两个相反策略、修改真实依赖改变结果、
多 clause unsupported、缺失定义、Agda recheck 和无外部工具调用。

若已有锁定 revision 的 cctt checkout：

```sh
python3 -B runtime-nbe/build-provider.py --provider-source /path/to/cctt
python3 -B runtime-nbe/verify-provider.py --provider-source /path/to/cctt
```

真实 Agda 纵向切片使用锁定的 Agda 2.8.0 source checkout，以及能构建它的 GHC：

```sh
python3 -B runtime-nbe/verify-agda-cctt-slice.py \
  --agda-source /path/to/agda-2.8.0 \
  --provider-source /path/to/cctt \
  --ghc /path/to/compatible-ghc
```

本机当前结果为 `10/10 PASS`：锁定构建、两个真实 Internal lower、两个嵌入式最终
程序结果、活动面拒绝、provider revision 篡改、重复字段和空 PATH/无残留全部
通过。观察到的 lowerer GHC 是 9.10.3；cctt 按上游 Stack resolver 使用 GHC
9.8.2。路径均通过参数或环境变量传入，没有把这些安装位置写进实现。

不传 `--provider-source` 时，构建器会把精确 revision 克隆到忽略的
`build/runtime-nbe/provider-source`。首次构建需要 Git、Stack、网络与足够空间；
Stack 根据上游 resolver 准备隔离 GHC，不要求客户预装某个固定系统路径的 GHC。

完整声明矩阵在已构建 producer/integrated/oracle/MAlonzo 后运行：

```sh
python3 -B runtime-nbe/verify-capability-matrix.py \
  --agda-source /path/to/agda-2.8.0 \
  --producer-bin /path/to/agda-runtime-nbe-producer \
  --runtime-bin /path/to/agda-cctt-runtime \
  --oracle-bin /path/to/agda-runtime-nbe-oracle \
  --malonzo-bin /path/to/runtime-nbe-client
```

构建器从 `--agda-source` 复制锁定的 `src/data` 到产物内相对目录 `agda-data`，忽略源
checkout 中任何旧 `_build`，再用同一锁定 Agda executable 对 `agda-builtins` 执行一次
冷 `--build-library`。正式验证只绑定这份私有 `Agda_datadir`，并校验关键 primitive
interface 哈希；不能让复制后的 backend 猜测全局 Cabal data 目录，也不能借用开发机
预热接口。CI 的 integrated、oracle、MAlonzo 与全部场景同样消费相应构建产物内的数据。
integrated Cabal 项目还通过 `cabal-packages.lock.json` 固定 `flatparse`、`microlens`、
`microlens-th` 的版本、包描述哈希和源码哈希，并与真实 `plan.json` 逐项核对；fresh CI
通过 Cabal 官方 `user-config update` 固定 HTTPS Hackage 入口后下载这些锁定包，后续
adapter 构建保持 `--offline`。

`.github/workflows/runtime-nbe-matrix.yml` 在 Ubuntu 与 macOS fresh checkout 上按锁定
revision 重建并运行正式入口；只有指定提交的实际运行结果才可作为环境矩阵证据。

## 尚未完成

当前能力仍按矩阵明确限定，并不接受任意 Agda Internal 语法、任意 cofibration、任意
Glue 等价或任意 HIT；超出 v14 声明形状的输入必须稳定拒绝。语义实现的本机矩阵已
收口，但根验收清单仍不勾选目标 3：当前工作树尚无指定提交 SHA，也没有 Web fresh-clone
和第二宿主的独立执行报告。Agda 文件中的等式只算 type-check/proof-linked 证据，真正
差分由隔离的 test-only oracle 对同一 QName 执行。

许可方面，cctt 与 `strict-impl-params` 使用 MIT。cctt 原始 Stack 配置所锁定的
`primdata` 只有 BSD3 package metadata、没有许可证文件；本路径将该依赖精确升级到
上游作者加入 MIT 文件的 `f7bd45a77fec79c29f4b7d506588d3cb4b0891f6`，同时锁定源码
archive、package 和许可证哈希。构建器会验证许可证证据及 Stack 实际 resolved lock；
provider 与完整 Agda→cctt 正式入口在该依赖 revision 上分别为 19/19 与 10/10 PASS。
