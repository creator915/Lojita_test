module PolicyRules where

open import Agda.Builtin.Bool

-- The request-specific decision is supplied by a separately reviewed policy
-- module.  The runtime slice must carry this definition rather than replace it
-- with a verifier flag or a hand-written expected value.
preserveRequested : Bool → Bool
preserveRequested requested = requested

denyDuringFreeze : Bool → Bool
denyDuringFreeze _ = false

-- Two reviewed layers make the runtime packet carry a recursive minimum
-- definition closure rather than a single fixture-shaped function.
reviewRequested : Bool → Bool
reviewRequested requested = preserveRequested requested

reviewRequestedAgain : Bool → Bool
reviewRequestedAgain requested = reviewRequested requested

-- Valid Agda but deliberately outside the first definition-slice grammar.
-- It ensures the backend does not silently normalize or guess multi-clause
-- functions when only the single-clause Pi slice has been implemented.
patternDecision : Bool → Bool
patternDecision false = false
patternDecision true = true
