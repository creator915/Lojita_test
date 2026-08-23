{-# OPTIONS --cubical --safe #-}

module MixedResidualWord64Callable where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Builtin.Word using
  (Word64; primWord64FromNat; primWord64ToNat)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

ResidualWithWord64 : Set₁
ResidualWithWord64 = Word64 → Residual

-- Negative control for the callable packet-domain equality gate.
NestedResidualWithWord64 : Set₁
NestedResidualWithWord64 = Word64 → ResidualWithWord64

chooseNat : {A : Set} → Nat → A → A → A
chooseNat 0 left _ = left
chooseNat _ _ right = right

chooseWord64 : {A : Set} → Word64 → A → A → A
chooseWord64 word = chooseNat (primWord64ToNat word)

main : Σ Bool (λ _ → ResidualWithWord64)
main = true , (λ word A left right →
  primTransp A i0 (chooseWord64 word left right))

consume : (Σ Bool (λ _ → ResidualWithWord64)) → Bool
consume (value , _) = value

consumeClosure : ResidualWithWord64 → Bool
consumeClosure closure =
  closure (primWord64FromNat 0) (λ _ → Bool) true false

consumeResidualNat : Residual → Nat
consumeResidualNat residual with residual (λ _ → Bool) true false
... | false = 0
... | true = 42

consumeResidualWithWord64Nat : ResidualWithWord64 → Nat
consumeResidualWithWord64Nat residual =
  consumeResidualNat (residual (primWord64FromNat 0))
