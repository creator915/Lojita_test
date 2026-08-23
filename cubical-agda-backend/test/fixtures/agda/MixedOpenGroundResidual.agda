{-# OPTIONS --cubical --safe #-}

module MixedOpenGroundResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenGroundResidualClosure : Set₁
OpenGroundResidualClosure = Bool → Nat → Residual

chooseGround : {A : Set} → Bool → Nat → A → A → A
chooseGround true zero left _ = left
chooseGround true (suc _) _ right = right
chooseGround false _ _ right = right

-- The blocker is open in two independent ground variables. Its packet must
-- preserve the checked telescope order Bool, Nat even though Treeless keeps
-- the nearest binder first in its de Bruijn environment.
main : Bool → Nat → Σ Bool (λ _ → Residual)
main = λ capturedBool capturedNat →
  true , (λ A left right →
    primTransp A i0
      (chooseGround capturedBool capturedNat left right))

consume : (Bool → Nat → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry true zero
... | static , _ = static

consumeClosure : OpenGroundResidualClosure → Bool
consumeClosure closure =
  closure true zero (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
