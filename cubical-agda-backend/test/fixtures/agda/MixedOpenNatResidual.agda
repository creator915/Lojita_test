{-# OPTIONS --cubical --safe #-}

module MixedOpenNatResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenResidualClosure : Set₁
OpenResidualClosure = Nat → Residual

chooseNat : {A : Set} → Nat → A → A → A
chooseNat zero left _ = left
chooseNat (suc _) _ right = right

-- The lifted hole has one checked Nat environment. Zero selects the left
-- endpoint and every successor selects the right, making lexical replay
-- semantically observable after transport.
main : Nat → Σ Bool (λ _ → Residual)
main = λ captured →
  true , (λ A left right →
    primTransp A i0 (chooseNat captured left right))

consume : (Nat → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry zero
... | static , _ = static

consumeClosure : OpenResidualClosure → Bool
consumeClosure closure = closure zero (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
