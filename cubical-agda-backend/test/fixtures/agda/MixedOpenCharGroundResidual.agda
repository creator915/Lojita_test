{-# OPTIONS --cubical --safe #-}

module MixedOpenCharGroundResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Char using
  (Char; primCharEquality; primNatToChar)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenCharGroundResidualClosure : Set₁
OpenCharGroundResidualClosure = Bool → Char → Residual

chooseBool : {A : Set} → Bool → A → A → A
chooseBool true left _ = left
chooseBool false _ right = right

chooseChar : {A : Set} → Char → A → A → A
chooseChar character =
  chooseBool (primCharEquality character (primNatToChar 65))

main : Bool → Char → Σ Bool (λ _ → Residual)
main = λ static character →
  static , (λ A left right →
    primTransp A i0 (chooseChar character left right))

consume : (Bool → Char → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry true (primNatToChar 65)
... | static , _ = static

consumeClosure : OpenCharGroundResidualClosure → Bool
consumeClosure closure =
  closure true (primNatToChar 65) (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
