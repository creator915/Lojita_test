{-# OPTIONS --cubical --safe #-}

module MixedResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i1

-- The pair constructor is static while its second field needs typed Cubical
-- execution. The current whole-entry implementation must report mixed and
-- residualize the pair without claiming definition-internal specialization.
main : Σ Bool (λ _ → Residual)
main = true , (λ A x → primTransp A i0 x)

-- The Agda 2.9 gate consumes the current whole-entry packet while deliberately
-- observing only the static shell field. This does not claim that the dynamic
-- hole has already been materialized as an independent artifact.
consume : (Σ Bool (λ _ → Residual)) → Bool
consume (value , _) = value

-- Independent consumer for the checked Internal typed-hole packet.  Applying
-- transport to a constant Bool family makes the expected result observable.
consumeHole : Residual → Bool
consumeHole residual = residual (λ _ → Bool) true

consumeHoleNat : Residual → Nat
consumeHoleNat residual with residual (λ _ → Bool) true
... | false = 0
... | true = 42
