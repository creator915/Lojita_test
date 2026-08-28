{-# OPTIONS --cubical #-}

module ApprovalEvidence where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Path
open import Agda.Builtin.Sigma

-- A decision is returned together with a separately consumable audit bit.
-- The two valid scenarios exercise the same Sigma runtime path with opposite
-- structured results.
DecisionEvidence : Set
DecisionEvidence = Σ Bool (λ _ → Bool)

approvedWithEvidence : Σ Bool (λ _ → Bool)
approvedWithEvidence =
  primHComp {A = Σ Bool (λ _ → Bool)} {φ = i0} (λ _ → isOneEmpty)
    (true , true)

rejectedWithEvidence : Σ Bool (λ _ → Bool)
rejectedWithEvidence =
  primHComp {A = Σ Bool (λ _ → Bool)} {φ = i0} (λ _ → isOneEmpty)
    (false , false)

approvedExpected : approvedWithEvidence ≡ (true , true)
approvedExpected _ = true , true

rejectedExpected : rejectedWithEvidence ≡ (false , false)
rejectedExpected _ = false , false
