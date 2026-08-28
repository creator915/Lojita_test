{-# OPTIONS --cubical #-}

module DependentRules where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import EvidenceModel

approvedRequest : Bool
approvedRequest =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty)
    (decideWithEvidence true approvedEvidence)

rejectedRequest : Bool
rejectedRequest =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty)
    (decideWithEvidence false rejectedEvidence)

unsupportedConstantRule : Bool
unsupportedConstantRule =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty)
    (constantDecision true approvedEvidence)
