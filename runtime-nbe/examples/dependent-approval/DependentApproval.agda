{-# OPTIONS --cubical #-}

module DependentApproval where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import Agda.Builtin.Sigma

data DecisionEvidence : Bool → Set where
  approvedEvidence : DecisionEvidence true
  rejectedEvidence : DecisionEvidence false

ApprovalResult : Set
ApprovalResult = Σ Bool DecisionEvidence

approvedResult : Σ Bool DecisionEvidence
approvedResult =
  primHComp {A = Σ Bool DecisionEvidence} {φ = i0} (λ _ → isOneEmpty)
    (true , approvedEvidence)

rejectedResult : Σ Bool DecisionEvidence
rejectedResult =
  primHComp {A = Σ Bool DecisionEvidence} {φ = i0} (λ _ → isOneEmpty)
    (false , rejectedEvidence)

-- A differently indexed family must not be guessed as DecisionEvidence.
data UnsupportedEvidence : Bool → Set where
  onlyApproved : UnsupportedEvidence true

unsupportedFamily : Σ Bool UnsupportedEvidence
unsupportedFamily =
  primHComp {A = Σ Bool UnsupportedEvidence} {φ = i0} (λ _ → isOneEmpty)
    (true , onlyApproved)
