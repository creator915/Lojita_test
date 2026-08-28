{-# OPTIONS --cubical #-}

module PolicyDecision where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Path
open import PolicyRules

-- An offline client has no active override face.  Its fallback is computed by
-- a function from another module, so a correct runtime packet needs a genuine
-- Pi definition slice in addition to the hcomp node.
requestedEscalation : Bool
requestedEscalation =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty)
    (preserveRequested true)

blockedDuringFreeze : Bool
blockedDuringFreeze =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty)
    (denyDuringFreeze true)

reviewedEscalation : Bool
reviewedEscalation =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty)
    (reviewRequestedAgain true)

unsupportedPatternDecision : Bool
unsupportedPatternDecision =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty)
    (patternDecision true)

requestedExpected : requestedEscalation ≡ true
requestedExpected _ = true

blockedExpected : blockedDuringFreeze ≡ false
blockedExpected _ = false

reviewedExpected : reviewedEscalation ≡ true
reviewedExpected _ = true
