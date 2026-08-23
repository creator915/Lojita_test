{-# OPTIONS --cubical --guardedness --safe #-}

module TypedResidual where

open import Cubical.Data.Bool using (Bool; true; false; not)
open import Cubical.Data.Nat using (ℕ)
open import Cubical.Data.Vec using (Vec) renaming (_∷_ to _∷v_; [] to []v)
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Univalence

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  notPath : Bool ≡ Bool
  notPath = ua notEq

-- Cubical Agda intentionally leaves this indexed transport at transpX-Vec.
-- The erased Chez path must reject it and retain typed residual evidence.
main : Vec Bool 2
main = transport (λ i → Vec (notPath i) 2) (true ∷v (false ∷v []v))

-- Used by the Agda 2.9 compatibility gate to prove that the archived v2
-- consumer can decode and independently typecheck our packet.
consume : Vec Bool 2 → Bool
consume _ = true
