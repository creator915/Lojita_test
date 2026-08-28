{-# OPTIONS --cubical #-}

module PolicyRepresentationUpgrade where

open import Agda.Primitive using (lzero)
open import Agda.Primitive.Cubical
  renaming (primINeg to ~_; primIMax to _∨_)
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Glue
open import PolicyEquivalence

-- The old representation interprets the bit with reversed polarity.  This
-- Glue path exposes an ordinary Bool at both endpoints but transports through
-- the explicit non-identity policyNotEquiv in between.
upgradeApproved : Bool
upgradeApproved = primTransp {ℓ = λ _ → lzero}
  (λ i → primGlue Bool
    (λ { (~ i = i1) → Bool ; (i = i1) → Bool })
    (λ { (~ i = i1) → policyNotEquiv
       ; (i = i1) → pathToEquiv (λ _ → Bool) }))
  i0 true

upgradeRejected : Bool
upgradeRejected = primTransp {ℓ = λ _ → lzero}
  (λ i → primGlue Bool
    (λ { (~ i = i1) → Bool ; (i = i1) → Bool })
    (λ { (~ i = i1) → policyNotEquiv
       ; (i = i1) → pathToEquiv (λ _ → Bool) }))
  i0 false

-- Same covered Glue shape but no polarity change.  The nontrivial-upgrade
-- adapter must not silently label this different equivalence as policyNot.
unsupportedIdentityUpgrade : Bool
unsupportedIdentityUpgrade = primTransp {ℓ = λ _ → lzero}
  (λ i → primGlue Bool
    (λ { (~ i = i1) → Bool ; (i = i1) → Bool })
    (λ { (~ i = i1) → pathToEquiv (λ _ → Bool)
       ; (i = i1) → pathToEquiv (λ _ → Bool) }))
  i0 true
