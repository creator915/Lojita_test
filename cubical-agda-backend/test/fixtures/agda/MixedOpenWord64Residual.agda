{-# OPTIONS --cubical --safe #-}

module MixedOpenWord64Residual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Builtin.Word using
  (Word64; primWord64FromNat; primWord64ToNat)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenResidualClosure : Set₁
OpenResidualClosure = Word64 → Residual

chooseNat : {A : Set} → Nat → A → A → A
chooseNat 0 left _ = left
chooseNat _ _ right = right

chooseWord64 : {A : Set} → Word64 → A → A → A
chooseWord64 word = chooseNat (primWord64ToNat word)

-- The blocker is open under one checked Word64 binder. Zero selects the left
-- endpoint and every nonzero value selects the right, making lexical capture
-- observable only after the captured value is replayed inside Agda.
main : Word64 → Σ Bool (λ _ → Residual)
main = λ captured →
  true , (λ A left right →
    primTransp A i0 (chooseWord64 captured left right))

consume : (Word64 → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry (primWord64FromNat 0)
... | static , _ = static

consumeClosure : OpenResidualClosure → Bool
consumeClosure closure =
  closure (primWord64FromNat 0) (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
