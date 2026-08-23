{-# OPTIONS --cubical --safe #-}

module MixedOpenIntResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Int using (Int; negsuc; pos)
open import Agda.Builtin.Nat using (zero)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenIntResidualClosure : Set₁
OpenIntResidualClosure = Int → Residual

chooseInt : {A : Set} → Int → A → A → A
chooseInt (pos _) left _ = left
chooseInt (negsuc _) _ right = right

main : Int → Σ Bool (λ _ → Residual)
main = λ integer →
  true , (λ A left right →
    primTransp A i0 (chooseInt integer left right))

consume : (Int → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry (pos zero)
... | static , _ = static

consumeClosure : OpenIntResidualClosure → Bool
consumeClosure closure =
  closure (pos zero) (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
