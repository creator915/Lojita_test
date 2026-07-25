# G0 恢复演练报告

## 结论

**PASS。** 精确 Codex Rust 基线可离线构建，且只依靠 GitHub 与 Library
即可在全新目录恢复源码、依赖、工具链、参考二进制和 Haskell 参考包，并完成
规定的 smoke 与 differential。

本报告不批准 Haskell authority 实现；它只关闭 G0。

## 权威身份

| 项目 | 冻结值 |
|---|---|
| 上游 commit | `98d28aab54ed86714901b6619400598598876dd0` |
| 源码 ZIP SHA-256 | `aa55787e86544740aaa3f068859479f4cca5655355975d81f02ff020c61ba21d` |
| Cargo.lock SHA-256 | `d0751922957c36865b9b963926884e40ff7deb61ed2aa177979e8574bd353a88` |
| Cargo.toml SHA-256 | `44bd68cb903e1e09bea5e32bba311425545556414170f252ac10de200d3b07d6` |
| Cabal freeze SHA-256 | `8728368e93c0b8fedf854d2520a62d94de0d1df662cbd96ff75404533192ae69` |
| Rust / Cargo | `1.95.0` / `1.95.0` |
| GHC / Cabal | `9.14.1` / `3.16.1.0` |
| HLS | `2.14.0.0` |
| target | `x86_64-unknown-linux-gnu` |
| profile / features | `release` / `codex-cli` default |

## Vendor 闭包

- `cargo vendor --locked --versioned-dirs`
- 1,205 个外部 package 目录，73,500 个文件
- archive SHA-256：
  `65a71ebcdb849ed409645bd9c3a924b64dbd1bdb86b485a3a3d450e1cbd8dc68`
- `tungstenite 0.27.0`：
  `4fffad30fe373adbdcffab9545e9e9bf4f2fc19f`
- `tokio-tungstenite 0.28.0`：
  `0e5b2d73aa18dd9f0a50ee9ff199d5aef7594186`
- 缺失的生产 crate `getopts 0.2.24` 也包含在完整 vendor 中
- Rusty V8 `149.2.0` archive 与 binding 均按冻结哈希校验

完整重编使用空 `CARGO_HOME`、`CARGO_NET_OFFLINE=true`、`--frozen` 和
`--offline`。没有 npm binary、不同 commit binary 或网络依赖参与 oracle。

## 恢复结果

| 检查 | 结果 |
|---|---|
| GitHub 检查点 clone | PASS；`597f9a375a431aa6d58e875b076350dcf6b1362c` |
| 七个 Library 资产 SHA-256 | PASS |
| 源码 ZIP comment / 完整性 | PASS |
| 工具链 payload、签名、安装及 smoke compile | PASS |
| exact reference binary 字节恢复 | PASS |
| exact reference 四项 CLI smoke | PASS |
| Haskell 38/38 模块 offline build | PASS |
| Haskell differential | PASS |
| Rust frozen/offline release build | PASS；17m31s |
| 新构建四项 CLI smoke | PASS |

四项 CLI smoke 是：

1. `codex --version`
2. `codex --help`
3. `codex exec --help`
4. `codex app-server --help`

## 二进制身份

| 产物 | bytes | SHA-256 | ELF build ID |
|---|---:|---|---|
| exact reference | 1,288,986,208 | `88b3f7c8868db75a7bda36fb080ea500949a10fa59dce325ee71d7371ca1129b` | `c237d3bde8b173c560614a9cdeda560a82d296cd` |
| fresh recovery rebuild | 1,289,143,040 | `4edda46b1bbedeb47c3782b7db1b446ec18b96c66727a437bb514b13b162ae7f` | `a0852615d7dcb1e8e8409633d78f726ae83b5c58` |

两者都带 `.debug_info` 和 `.debug_line`。原 binary 内含原绝对源码目录，
新 binary 内含新恢复目录，所以不把不同路径下的逐字节相等作为恢复通过条件。
exact reference 本身则已从远端恢复并与冻结 SHA-256 完全相同。

## G0 判定

以下三个条件同时成立：

1. 精确源码和所有锁定输入可获得且可验证；
2. 精确源码可在无 Cargo 网络访问下完成 release 构建并 smoke；
3. GitHub 与 Library 足以在新目录重建同一验证环境。

因此 G0 关闭，可以进入 G1 decision ledger。不得跳过 G1 直接恢复旧的
36 文件翻译路线。
