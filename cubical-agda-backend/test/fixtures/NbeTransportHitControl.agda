{-# OPTIONS --cubical --safe #-}

module NbeTransportHitControl where

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

-- The inner transport is canonical, but the outer family deliberately hides
-- a constant endpoint behind a non-canonical interval expression.  The spike
-- may reduce the inner value while evaluating arguments, but must reject the
-- enclosing request without publishing Treeless, Scheme, or staging output.
nonCanonicalRepeated : Bool
nonCanonicalRepeated =
  transport (λ i → notPath (i ∨ ~ i)) (transport notPath true)
