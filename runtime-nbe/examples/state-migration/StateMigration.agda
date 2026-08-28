{-# OPTIONS --cubical #-}

module StateMigration where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Path
open import Agda.Builtin.Sigma

-- The first transport slice models a rollout whose representation remains Bool
-- across the version line.  It is deliberately a real primTransp term, not a
-- verifier parameter or a hand-written provider expression.
migrateApproved : Bool
migrateApproved = primTransp (λ _ → Bool) i0 true

migrateRejected : Bool
migrateRejected = primTransp (λ _ → Bool) i0 false

unsupportedActiveFace : Bool
unsupportedActiveFace = primTransp (λ _ → Bool) i1 true

unsupportedSigmaFamily : Σ Bool (λ _ → Bool)
unsupportedSigmaFamily =
  primTransp (λ _ → Σ Bool (λ _ → Bool)) i0 (true , true)

approvedExpected : migrateApproved ≡ true
approvedExpected _ = true

rejectedExpected : migrateRejected ≡ false
rejectedExpected _ = false
