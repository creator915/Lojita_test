{-# OPTIONS --cubical --safe #-}

module MixedResidualNatCallable where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i1

ResidualWithCount : Set₁
ResidualWithCount = Nat → Residual

-- Negative control for the callable proxy's packet-domain equality gate.
NestedResidualWithCount : Set₁
NestedResidualWithCount = Nat → ResidualWithCount

main : Σ Bool (λ _ → ResidualWithCount)
main = true , (λ _ A x → primTransp A i0 x)

consume : (Σ Bool (λ _ → ResidualWithCount)) → Bool
consume (value , _) = value

consumeResidualNat : Residual → Nat
consumeResidualNat residual with residual (λ _ → Bool) true
... | false = 0
... | true = 42

consumeResidualWithCountNat : ResidualWithCount → Nat
consumeResidualWithCountNat residual = consumeResidualNat (residual 0)

wrapResidual : Residual → ResidualWithCount
wrapResidual residual _ = residual
