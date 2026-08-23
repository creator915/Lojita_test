{-# OPTIONS --cubical --safe #-}

module NbeTransportS1Control where

open import Cubical.Foundations.Prelude
open import Cubical.Data.Int using (ℤ)
open import Cubical.HITs.S1 using (loop; winding)

-- The exact t12 gate admits the canonical intLoop-generated composition
-- shell.  This closed loop instead hides a constant path behind a
-- non-canonical interval expression.  It must remain outside the slice and
-- fail before Treeless, Scheme, or staging publication.
nonCanonicalWinding : ℤ
nonCanonicalWinding = winding (λ i → loop (i ∨ ~ i))

-- This has the same outer "two forward, one reverse" composition shape as
-- t13, but the reversed segment is the non-canonical constant loop above.
-- The recursive HComp rule must inspect and reject that inner segment.
nonCanonicalInverse : ℤ
nonCanonicalInverse =
  winding (loop ∙ loop ∙ sym (λ i → loop (i ∨ ~ i)))
