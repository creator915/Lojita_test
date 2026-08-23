{-# OPTIONS --cubical --safe #-}

module MixedOpenDependentChainResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

Slot : Bool → Set
Slot true = Nat
Slot false = Bool

NextSlot : (flag : Bool) → Slot flag → Set
NextSlot true zero = Bool
NextSlot true (suc _) = Nat
NextSlot false true = Nat
NextSlot false false = Bool

OpenDependentChainResidualClosure : Set₁
OpenDependentChainResidualClosure =
  (flag : Bool) → (slot : Slot flag) → NextSlot flag slot → Residual

ResidualWithCount : Set₁
ResidualWithCount = Nat → Residual

chooseChain :
  {A : Set} →
  (flag : Bool) →
  (slot : Slot flag) →
  NextSlot flag slot →
  A → A → A
chooseChain true zero true left _ = left
chooseChain true zero false _ right = right
chooseChain true (suc _) zero left _ = left
chooseChain true (suc _) (suc _) _ right = right
chooseChain false true zero left _ = left
chooseChain false true (suc _) _ right = right
chooseChain false false true left _ = left
chooseChain false false false _ right = right

main :
  (flag : Bool) →
  (slot : Slot flag) →
  NextSlot flag slot →
  Σ Bool (λ _ → Residual)
main = λ flag slot next →
  true , (λ A left right →
    primTransp A i0 (chooseChain flag slot next left right))

consume :
  ((flag : Bool) →
   (slot : Slot flag) →
   NextSlot flag slot →
   Σ Bool (λ _ → Residual)) →
  Bool
consume entry with entry true zero true
... | static , _ = static

consumeClosure : OpenDependentChainResidualClosure → Bool
consumeClosure closure =
  closure true zero true (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false

wrapResidual : Residual → ResidualWithCount
wrapResidual residual _ = residual

consumeResidualWithCount : ResidualWithCount → Bool
consumeResidualWithCount residual = consumeResidual (residual zero)
