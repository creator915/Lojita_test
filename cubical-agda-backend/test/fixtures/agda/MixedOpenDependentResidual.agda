{-# OPTIONS --cubical --safe #-}

module MixedOpenDependentResidual where

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

OpenDependentResidualClosure : Set₁
OpenDependentResidualClosure = (flag : Bool) → Slot flag → Residual

chooseSlot : {A : Set} → (flag : Bool) → Slot flag → A → A → A
chooseSlot true zero left _ = left
chooseSlot true (suc _) _ right = right
chooseSlot false true left _ = left
chooseSlot false false _ right = right

-- Slot depends on the preceding Bool. The shell captures both ground values,
-- while Agda checks the complete dependent application during replay.
main : (flag : Bool) → Slot flag → Σ Bool (λ _ → Residual)
main = λ flag slot →
  true , (λ A left right →
    primTransp A i0 (chooseSlot flag slot left right))

consume : ((flag : Bool) → Slot flag → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry true zero
... | static , _ = static

consumeClosure : OpenDependentResidualClosure → Bool
consumeClosure closure =
  closure true zero (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
