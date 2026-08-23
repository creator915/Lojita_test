{-# OPTIONS --cubical --safe #-}

module MixedOpenDependentWord64Residual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Builtin.Word using
  (Word64; primWord64FromNat; primWord64ToNat)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

Slot : Bool → Set
Slot true = Word64
Slot false = Nat

OpenDependentWord64ResidualClosure : Set₁
OpenDependentWord64ResidualClosure = (flag : Bool) → Slot flag → Residual

chooseNat : {A : Set} → Nat → A → A → A
chooseNat zero left _ = left
chooseNat (suc _) _ right = right

chooseSlot : {A : Set} → (flag : Bool) → Slot flag → A → A → A
chooseSlot true word = chooseNat (primWord64ToNat word)
chooseSlot false natural = chooseNat natural

-- Word64 and Nat share an erased integer representation. The dependent
-- binding therefore preserves the actual Chez values, while the explicit CLI
-- codec chooses the typed literal and Agda checks the complete application.
main : (flag : Bool) → Slot flag → Σ Bool (λ _ → Residual)
main = λ flag slot →
  true , (λ A left right →
    primTransp A i0 (chooseSlot flag slot left right))

consume :
  ((flag : Bool) → Slot flag → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry true (primWord64FromNat 0)
... | static , _ = static

consumeClosure : OpenDependentWord64ResidualClosure → Bool
consumeClosure closure =
  closure true (primWord64FromNat 0) (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
