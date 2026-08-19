{-# OPTIONS --cubical --safe #-}

------------------------------------------------------------------------
-- TransportTests: 运行期搬运后端测试电池
--
-- 设计原则:
--   * 每个测试 tNN 是一个【封闭的一阶项】(canonicity 适用,可读回)
--   * 每个 tNN 配一个 eNN(期望值)和一个匿名 refl 证明
--     → 文件通过类型检查 = 期望值经 Agda 本机求值器认证
--   * 你的 harness 协议:对每对 (tNN, eNN) 分别 normalise,
--     比较两个规范形 Term 是否相等(比读回再比较更稳,
--     绕开 harness 自己的读回 bug)
--
-- 覆盖矩阵(对应 primTransHComp 的分派表):
--   t01        φ = i1 快速通道(transp 恒等)
--   t02        compData / 普通归纳类型(ℕ)
--   t03,t04    Glue / ua ⭐(执行等价——擦除不健全的核心场景)
--   t05,t06    Glue 双向(suc/pred,方向敏感)
--   t07        Pi 行 + nelims > 0 守门
--   t08        Pi + Glue 混合(定义域是 ua)
--   t09        recComp kit(Σ / record)
--   t10        compData 带参数(List 沿 ua 搬运)
--   t11        边界哨兵:indexed data 的 transp 停在 transpX-Vec
--              (Cubical Agda 已知限制;协议同 t11b,禁 refl/比较)
--   t11b       边界:非 refl 路径的 subst → 规范形含 Kan 残余
--              (只测 harness 不崩溃 + 头非构造子;不做 Term 比较)
--   t12,t13    HIT + 宇宙搬运(S¹ winding ——重量级集成测试)
--   t14        J 在 refl 上(嵌套 transp/hcomp 填充物)
--   t15        连续两次 Glue 搬运
--   t16a-c ⭐⭐⭐ 高阶值跨进程存活:A 端产出函数/路径/hcomp 塔,
--              序列化运到 B 端,拼进消费者,一阶读回对表
--
-- 注意:导入名按 agda/cubical 库惯例书写;库版本漂移可能需要
-- 微调个别名字(notEquiv 等我们在本地重建以减少依赖)。
------------------------------------------------------------------------

module TransportTests where

open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Univalence

open import Cubical.Data.Bool using (Bool; true; false; not)
open import Cubical.Data.Nat using (ℕ; zero; suc; _+_)
open import Cubical.Data.Nat.Properties using (+-comm; isSetℕ)
open import Cubical.Foundations.Transport using (isSet-subst)
open import Cubical.Data.Int using (ℤ; pos; negsuc; sucℤ; predℤ; sucPred; predSuc)
open import Cubical.Data.Sigma using (_×_; _,_)
open import Cubical.Data.List using (List; _∷_; [])
open import Cubical.Data.Vec using (Vec) renaming (_∷_ to _∷v_; [] to []v)
open import Cubical.HITs.S1 using (S¹; base; loop; winding; intLoop)

------------------------------------------------------------------------
-- 本地建材(自己造,免受库版本影响)
------------------------------------------------------------------------

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true  = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  sucEq : ℤ ≃ ℤ
  sucEq = isoToEquiv (iso sucℤ predℤ sucPred predSuc)

  notPath : Bool ≡ Bool
  notPath = ua notEq

  sucPath : ℤ ≡ ℤ
  sucPath = ua sucEq

------------------------------------------------------------------------
-- t01 【φ = i1 快速通道】transp 在 i1 处定义为恒等
------------------------------------------------------------------------

t01 : ℕ
t01 = transp (λ _ → ℕ) i1 7

e01 : ℕ
e01 = 7

_ : t01 ≡ e01
_ = refl

------------------------------------------------------------------------
-- t02 【compData:普通归纳类型】沿常值族搬运 ℕ(逐构造子递归)
------------------------------------------------------------------------

t02 : ℕ
t02 = transport (λ _ → ℕ) 7

e02 : ℕ
e02 = 7

_ : t02 ≡ e02
_ = refl

------------------------------------------------------------------------
-- t03 ⭐【Glue / ua】沿 ua notEq 搬运必须真的执行 not
------------------------------------------------------------------------

t03 : Bool
t03 = transport notPath true

e03 : Bool
e03 = false

_ : t03 ≡ e03
_ = refl

------------------------------------------------------------------------
-- t04 ⭐【HCompU + Glue】复合路径 = 宇宙中的 hcomp,再沿它搬运
------------------------------------------------------------------------

t04 : Bool
t04 = transport (notPath ∙ notPath) true

e04 : Bool
e04 = true

_ : t04 ≡ e04
_ = refl

------------------------------------------------------------------------
-- t05 / t06 【Glue 方向敏感】suc 与它的逆(pred)
------------------------------------------------------------------------

t05 : ℤ
t05 = transport sucPath (pos 0)

e05 : ℤ
e05 = pos 1

_ : t05 ≡ e05
_ = refl

t06 : ℤ
t06 = transport (sym sucPath) (pos 0)

e06 : ℤ
e06 = negsuc 0

_ : t06 ≡ e06
_ = refl

------------------------------------------------------------------------
-- t07 【Pi 行 + nelims 守门】搬运函数后必须应用它,归约才发生
------------------------------------------------------------------------

t07 : ℕ
t07 = (transport (λ _ → ℕ → ℕ) suc) 3

e07 : ℕ
e07 = 4

_ : t07 ≡ e07
_ = refl

------------------------------------------------------------------------
-- t08 【Pi × Glue 混合】定义域沿 ua 变化:搬运恒等函数
--     搬运后的函数 = 先逆向搬输入(执行 not),再正向搬输出
------------------------------------------------------------------------

t08 : Bool
t08 = (transport (λ i → notPath i → Bool) (λ b → b)) true

e08 : Bool
e08 = false

_ : t08 ≡ e08
_ = refl

------------------------------------------------------------------------
-- t09 【recComp kit:Σ/record】逐字段搬运
------------------------------------------------------------------------

t09 : Bool × ℕ
t09 = transport (λ i → notPath i × ℕ) (true , 3)

e09 : Bool × ℕ
e09 = (false , 3)

_ : t09 ≡ e09
_ = refl

------------------------------------------------------------------------
-- t10 【compData 带参数】List 的参数沿 ua 走:相当于 map not
------------------------------------------------------------------------

t10 : List Bool
t10 = transport (λ i → List (notPath i)) (true ∷ false ∷ true ∷ [])

e10 : List Bool
e10 = false ∷ true ∷ false ∷ []

_ : t10 ≡ e10
_ = refl

------------------------------------------------------------------------
-- t11 【边界哨兵:indexed data 的定义计算空洞】
--     实测:即使索引恒定、只有参数沿 ua 变化,indexed 数据的
--     transp 也停在生成的 transpX-Vec 上,不归约到构造子。
--     这是 Cubical Agda 的已知粗糙面(indexed inductive 的
--     Kan 操作定义行为差),不是后端 bug。
--     harness 协议(同 t11b):normalise 终止 + 头非构造子即过;
--     禁止 Term 比较,禁止 refl。
--     参数搬运的【正确性】已由 t10(List,非 indexed)定义档覆盖。
--     工程启示:领域里的 indexed 类型建议改用纤维化表示
--     Vec A n ≃ Σ (List A) (λ xs → length xs ≡ n),
--     把 indexed transp 换成 record(t09)+ data(t10)transp,
--     两者都定义计算。
------------------------------------------------------------------------

t11 : Vec Bool 2
t11 = transport (λ i → Vec (notPath i) 2) (true ∷v (false ∷v []v))

-- 预期值(仅文档用途,命题上成立;不做任何机器断言)
e11 : Vec Bool 2
e11 = false ∷v (true ∷v []v)

------------------------------------------------------------------------
-- t11b 【边界测试:非规范的规范形】沿非 refl 路径 subst
--     +-comm 1 1 : 2 ≡ 2 命题上是 refl,定义上不是!
--     → 规范形含 transp/hcomp 残余,构造子头读回必然失败
--     → 这测的是 harness 的边界处理,不是搬运的正确性
--     harness 协议(特殊):normalise t11b,断言【头不是构造子】
--     且过程不崩溃;禁止与 e11b 做 Term 比较(它们规范形不同)
--     正确性由下面的命题证明(isSet-subst)担保,无需 harness 复核
------------------------------------------------------------------------

t11b : Vec Bool 2
t11b = subst (Vec Bool) (+-comm 1 1) (true ∷v (false ∷v []v))

e11b : Vec Bool 2
e11b = true ∷v (false ∷v []v)

_ : t11b ≡ e11b
_ = isSet-subst {B = Vec Bool} isSetℕ (+-comm 1 1) e11b

------------------------------------------------------------------------
-- t12 / t13 ⭐⭐【HIT + 宇宙】S¹ winding:沿 helix 在宇宙里搬运
--     重量级集成测试:HIT 胞腔 + transp in Type + hcomp 全上阵
------------------------------------------------------------------------

t12 : ℤ
t12 = winding (intLoop (pos 2))

e12 : ℤ
e12 = pos 2

_ : t12 ≡ e12
_ = refl

t13 : ℤ
t13 = winding (loop ∙ loop ∙ sym loop)

e13 : ℤ
e13 = pos 1

_ : t13 ≡ e13
_ = refl

------------------------------------------------------------------------
-- t14 【J 在 refl 上】cubical 的 J 不在 refl 上判等计算,
--     求值要穿过一串 transp 填充物 → 嵌套 Kan 操作的压力测试
------------------------------------------------------------------------

t14 : ℕ
t14 = J {x = zero} (λ _ _ → ℕ) 41 refl

e14 : ℕ
e14 = 41

_ : t14 ≡ e14
_ = refl

------------------------------------------------------------------------
-- t15 【连续 Glue】搬过去再搬回来(两次独立的 Glue 分派)
------------------------------------------------------------------------

t15 : Bool
t15 = transport notPath (transport notPath true)

e15 : Bool
e15 = true

_ : t15 ≡ e15
_ = refl

------------------------------------------------------------------------
-- t16 ⭐⭐⭐【高阶值的跨进程存活】生产者/消费者拆开定义
--
-- 协议(harness 侧,进程 A → 进程 B):
--   A: normalise pNN → 高阶规范形 Term(Lam 头 / 含 Glue、hcomp 塔)
--      序列化,发过管道/socket
--   B: 加载同一模块(signature 对齐)→ 反序列化/重检查
--      拼 Def cNN [Apply 收到的Term] → normalise → 一阶读回
--
-- 本文件内的 refl 检查 = 单进程 ground truth:
--   跨进程跑出来的答案必须与之一致
-- 禁止:对 pNN 的规范形做 Term 相等比较(高阶,无意义)
-- 必须:pNN 的规范形是封闭项(canonicity 保 B 端消费必达构造子)
------------------------------------------------------------------------

-- 生产者 a:搬运出来的【函数】(Lam 头,体内含 Glue 残余)
p16a : Bool → Bool
p16a = transport (λ i → notPath i → notPath i) (λ b → b)

-- 生产者 b:宇宙中的【路径】(区间 Lam,体是 Glue/hcomp 结构)
p16b : ℤ ≡ ℤ
p16b = sucPath ∙ sucPath

-- 生产者 c:HIT 上的【回路】(规范形是 hcomp 塔——真正的高维货物)
p16c : base ≡ base
p16c = loop ∙ loop

-- 消费者:吃高阶值,吐一阶读数
c16a : (Bool → Bool) → Bool
c16a f = f true

c16b : ℤ ≡ ℤ → ℤ
c16b p = transport p (pos 0)

c16c : base ≡ base → ℤ
c16c = winding

-- 单进程 ground truth(跨进程结果必须与此一致)
t16a : Bool
t16a = c16a p16a

e16a : Bool
e16a = true

_ : t16a ≡ e16a
_ = refl

t16b : ℤ
t16b = c16b p16b

e16b : ℤ
e16b = pos 2

_ : t16b ≡ e16b
_ = refl

t16c : ℤ
t16c = c16c p16c

e16c : ℤ
e16c = pos 2

_ : t16c ≡ e16c
_ = refl

