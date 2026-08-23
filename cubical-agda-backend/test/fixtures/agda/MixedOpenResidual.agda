{-# OPTIONS --cubical --safe #-}

module MixedOpenResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenResidualClosure : Set₁
OpenResidualClosure = Bool → Residual

choose : {A : Set} → Bool → A → A → A
choose false _ right = right
choose true left _ = left

-- The blocker-headed Residual is open in captured. The backend lambda-lifts
-- that one-variable environment, so the independent packet has the closed
-- type OpenResidualClosure instead of leaking a de Bruijn variable.
main : Bool → Σ Bool (λ _ → Residual)
main = λ captured →
  true , (λ A left right →
    primTransp A i0 (choose captured left right))

consume : (Bool → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry true
... | static , _ = static

consumeClosure : OpenResidualClosure → Bool
consumeClosure closure = closure true (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
