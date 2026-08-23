{-# OPTIONS --cubical --safe #-}

module MixedOpenWord64GroundResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Builtin.Word using
  (Word64; primWord64FromNat; primWord64ToNat)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenWord64ResidualClosure : Set₁
OpenWord64ResidualClosure = Bool → Word64 → Residual

chooseNat : {A : Set} → Nat → A → A → A
chooseNat zero left _ = left
chooseNat (suc _) _ right = right

chooseWord64 : {A : Set} → Word64 → A → A → A
chooseWord64 word = chooseNat (primWord64ToNat word)

-- The blocker is open under two checked binders. The Bool stays visible in
-- the erased shell, while the Word64 selects the transported endpoint inside
-- the typed hole.
-- This gives the ordered codec gate distinguishable Bool and Word64 domains
-- without asking erased Chez code to implement Cubical transport.
main : Bool → Word64 → Σ Bool (λ _ → Residual)
main = λ static captured →
  static , (λ A left right →
    primTransp A i0 (chooseWord64 captured left right))

consume : (Bool → Word64 → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry true (primWord64FromNat 7)
... | static , _ = static

consumeClosure : OpenWord64ResidualClosure → Bool
consumeClosure closure =
  closure true (primWord64FromNat 0) (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
