{-# OPTIONS --cubical --safe #-}

module MixedOpenIntGroundResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Int using (Int; negsuc; pos)
open import Agda.Builtin.Nat using (zero)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenIntGroundResidualClosure : Set₁
OpenIntGroundResidualClosure = Bool → Int → Residual

chooseInt : {A : Set} → Int → A → A → A
chooseInt (pos _) left _ = left
chooseInt (negsuc _) _ right = right

main : Bool → Int → Σ Bool (λ _ → Residual)
main = λ static integer →
  static , (λ A left right →
    primTransp A i0 (chooseInt integer left right))

consume : (Bool → Int → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry true (pos zero)
... | static , _ = static

consumeClosure : OpenIntGroundResidualClosure → Bool
consumeClosure closure =
  closure true (pos zero) (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
