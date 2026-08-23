{-# OPTIONS --cubical --safe #-}

module NbeTransportJControl where

open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Univalence

open import Cubical.Data.Bool using (Bool; true; false; not)

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true  = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  notPath : Bool ≡ Bool
  notPath = ua notEq

-- Exact t14 uses J only at refl with a constant Nat motive.  This closed
-- control instead asks J to eliminate a non-canonical universe loop into its
-- varying carrier.  The current slice must reject the outer transport even
-- though the endpoints are both Bool.
nonCanonicalJ : Bool
nonCanonicalJ =
  J {x = Bool} (λ X _ → X) true (λ i → notPath (i ∨ ~ i))
