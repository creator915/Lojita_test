{-# OPTIONS --cubical #-}

module EvidenceModel where

open import Agda.Builtin.Bool

data DecisionEvidence : Bool → Set where
  approvedEvidence : DecisionEvidence true
  rejectedEvidence : DecisionEvidence false

open DecisionEvidence public

decideWithEvidence : (decision : Bool) → DecisionEvidence decision → Bool
decideWithEvidence decision _ = decision

-- Valid but intentionally outside the exact two-constructor dependent clause
-- mapping: a constant result must not be guessed as decideWithEvidence.
constantDecision : (decision : Bool) → DecisionEvidence decision → Bool
constantDecision _ _ = false
