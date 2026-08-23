{-# OPTIONS --cubical --safe #-}

module MixedOpenDependentIntResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Int using (Int; negsuc; pos)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

Slot : Bool → Set
Slot true = Int
Slot false = Nat

OpenDependentIntResidualClosure : Set₁
OpenDependentIntResidualClosure = (flag : Bool) → Slot flag → Residual

chooseInt : {A : Set} → Int → A → A → A
chooseInt (pos _) left _ = left
chooseInt (negsuc _) _ right = right

chooseNat : {A : Set} → Nat → A → A → A
chooseNat zero left _ = left
chooseNat (suc _) _ right = right

chooseSlot : {A : Set} → (flag : Bool) → Slot flag → A → A → A
chooseSlot true integer = chooseInt integer
chooseSlot false natural = chooseNat natural

main : (flag : Bool) → Slot flag → Σ Bool (λ _ → Residual)
main = λ flag slot →
  true , (λ A left right →
    primTransp A i0 (chooseSlot flag slot left right))

consume :
  ((flag : Bool) → Slot flag → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry true (pos zero)
... | static , _ = static

consumeClosure : OpenDependentIntResidualClosure → Bool
consumeClosure closure =
  closure true (pos zero) (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false
