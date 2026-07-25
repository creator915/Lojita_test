# G0：精确 Rust 基线与可恢复输入

## 当前状态

`baseline_build = PASS`，`persistent_assets = PASS`，
`fresh_recovery_rehearsal = PASS`。

G0 已关闭。本检查点证明精确基线可构建、可启动，并可只依靠 GitHub 与
Library 从新目录恢复。它不开始 Haskell authority 开发，也不继承
`020-closure-map` 的施工范围。

## 冻结身份

- 上游仓库：`openai/codex`
- commit：`98d28aab54ed86714901b6619400598598876dd0`
- GitHub commit 时间：`2026-07-04T00:18:26Z`
- `codex-main.zip` SHA-256：
  `aa55787e86544740aaa3f068859479f4cca5655355975d81f02ff020c61ba21d`
- `Cargo.lock` SHA-256：
  `d0751922957c36865b9b963926884e40ff7deb61ed2aa177979e8574bd353a88`
- Rust/Cargo：`1.95.0`
- GHC：`9.14.1`
- Cabal：`3.16.1.0`
- 构建 target：`x86_64-unknown-linux-gnu`
- profile：源码内的 `release`
- features：`codex-cli` 默认 feature 集；没有使用 `--all-features`

GitHub 已独立确认该 commit 存在；ZIP comment、ZIP SHA 和锁文件哈希均匹配。

## 精确离线构建

实际执行：

```bash
cargo build \
  --manifest-path codex-rs/Cargo.toml \
  --frozen \
  --offline \
  --target x86_64-unknown-linux-gnu \
  --release \
  -p codex-cli \
  --bin codex
```

同时冻结：

```text
CARGO_NET_OFFLINE=true
RUSTY_V8_ARCHIVE=<frozen v149.2.0 GNU archive>
RUSTY_V8_SRC_BINDING_PATH=<frozen v149.2.0 GNU binding>
OPENSSL_INCLUDE_DIR=/usr/include
OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu
CODEX_BWRAP_SHA256 is unset
```

结果：

- release 构建：PASS，`15m 57s`
- 二进制大小：`1,288,986,208` bytes
- ELF build ID：`c237d3bde8b173c560614a9cdeda560a82d296cd`
- reference binary SHA-256：
  `88b3f7c8868db75a7bda36fb080ea500949a10fa59dce325ee71d7371ca1129b`
- `codex --version`：`codex-cli 0.0.0`
- `--help`、`exec --help`、`app-server --help`：PASS

该哈希是这一个未 strip、带 line tables 的 reference binary 的精确身份。
由于调试行表会记录绝对构建路径，后续在另一绝对目录重编所得二进制不预设必须
逐字节相同；恢复演练会分别验证“原 reference 字节可恢复”和“源码可离线重建并
启动”。

## Vendor 修正

最初旧缓存缺少生产 crate `getopts 0.2.24`；只补
`tungstenite-rs` 不能形成完整的离线闭包。因此本检查点用锁定的
`Cargo.lock` 执行了正式 `cargo vendor --locked --versioned-dirs`，冻结：

- 1,205 个外部 package 目录；
- 73,500 个文件；
- vendor content-tree SHA-256：
  `9ce2d75981e7c4b16e3c50ee0f7991ebdb37b4bcb81885f4e46ac3ecae96ffc0`；
- `tungstenite 0.27.0 @ 4fffad30fe373adbdcffab9545e9e9bf4f2fc19f`；
- `tokio-tungstenite 0.28.0 @ 0e5b2d73aa18dd9f0a50ee9ff199d5aef7594186`；
- 其余五个主 workspace Git source；
- OpenAI Rusty V8 `v149.2.0` GNU archive 与 binding。

用空 `CARGO_HOME`、网络禁用和该 vendor 配置重新执行依赖解析及完整 feature
tree 均通过。

## Haskell 参考基线

旧 `codex-kernel-hs-0.1.0.0` 仍只作为语义参考，不是 drop-in CLI。

- 新生成 `cabal.project.freeze`：
  `8728368e93c0b8fedf854d2520a62d94de0d1df662cbd96ff75404533192ae69`
- 38/38 library modules：PASS
- differential：
  - 23 个 Rust `apply_patch` golden；
  - tool turn replay；
  - parallel gate；
  - incremental request；
  - router namespace；
  - responses-lite；
  - turn diff；
  全部 PASS。

## 新目录恢复演练

恢复演练从 GitHub commit
`597f9a375a431aa6d58e875b076350dcf6b1362c` 和下列七个锁定资产开始，
没有读取原源码树、原 Cargo cache 或原工具链安装目录。

结果：

- 七个远端资产 SHA-256 与源码 ZIP comment：PASS；
- Rust 1.95.0、GHC 9.14.1、Cabal 3.16.1.0、HLS 2.14.0.0 恢复与
  smoke compilation：PASS；
- 原 reference binary 字节恢复：
  `88b3f7c8868db75a7bda36fb080ea500949a10fa59dce325ee71d7371ca1129b`；
- 原 reference 的 version/help/exec/app-server smoke：PASS；
- 冻结 Haskell reference 38/38 模块离线构建：PASS；
- Haskell differential：PASS；
- 精确 Rust 源码 `--frozen --offline` release 重编：PASS，`17m 31s`；
- 恢复重编 binary SHA-256：
  `4edda46b1bbedeb47c3782b7db1b446ec18b96c66727a437bb514b13b162ae7f`；
- 恢复重编 binary 的四项 smoke：PASS。

恢复重编 binary 与原 reference 不逐字节相同。两者都包含 `.debug_info` 和
`.debug_line`；字符串表分别记录原构建目录和新恢复目录。因此 G0 分开证明：

1. exact reference 字节可恢复且哈希完全相同；
2. 精确源码可在不同绝对目录离线重建并正常启动。

详细证据见 `recovery-report.md`。

## 持久资产

源码、小锁文件、feature tree 和恢复脚本保存在本分支。大型输入和结果保存在
Library：

- `/codex-main.zip`
- `/codex-kernel-hs-0.1.0.0.tar.gz`
- `/lojita-haskell-core-ghc-9.14.1-cabal-3.16.1.0-ubuntu24.04-x86_64.tar`
- `/lojita-haskell-hls-2.14.0.0-ubuntu24.04-x86_64.tar`
- `/lojita-rust-1.95.0-linux-x86_64.tar`
- `/Lojita_test/codex-g0-offline-deps-98d28a.tar.gz`
- `/Lojita_test/codex-98d28a-x86_64-unknown-linux-gnu-release.gz`
- `/Lojita_test/G0-exact-baseline-recovery-report.zh-CN.md`
- `/Lojita_test/G0-exact-baseline-recovery-evidence.tar.gz`

这些远端输入已在全新目录完成恢复、重编和 smoke。G0 关闭，下一步只允许
进入 G1 decision ledger；本提交不授权直接开始 Haskell authority 实现。
