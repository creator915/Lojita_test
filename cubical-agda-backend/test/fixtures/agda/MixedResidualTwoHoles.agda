{-# OPTIONS --cubical --safe #-}

module MixedResidualTwoHoles where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i1

ResidualWithFlag : Set₁
ResidualWithFlag = Bool → Residual

-- Negative control for the callable proxy's packet-domain equality gate.
NestedResidualWithFlag : Set₁
NestedResidualWithFlag = Bool → ResidualWithFlag

-- Both blocker-headed functions are closed, but their checked types differ.
-- The static nested Sigma shell must therefore publish two addressable holes.
main : Σ Bool (λ _ → Σ Residual (λ _ → ResidualWithFlag))
main =
  true ,
    ((λ A x → primTransp A i0 x) ,
     (λ _ A x → primTransp A i0 x))

consume : (Σ Bool (λ _ → Σ Residual (λ _ → ResidualWithFlag))) → Bool
consume (value , _) = value

consumeHole1 : Residual → Bool
consumeHole1 residual = residual (λ _ → Bool) true

consumeHole2 : ResidualWithFlag → Nat
consumeHole2 residual with residual false (λ _ → Bool) true
... | false = 0
... | true = 42
