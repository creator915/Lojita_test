module Handoff.Proofs where

open import Agda.Builtin.Equality using (_≡_; refl)
open import Handoff.Domain
open import Handoff.Policy
open import Handoff.Samples
open import Handoff.Summary
open import Handoff.Util using (length)

approved-is-ready : classify approvedEnvelope ≡ readyToPay
approved-is-ready = refl

pending-awaits-review : classify pendingEnvelope ≡ awaitingReview
pending-awaits-review = refl

denial-is-final : classify deniedEnvelope ≡ denied
denial-is-final = refl

approved-review-count : summaryReviewCount (summarise approvedEnvelope) ≡ 3
approved-review-count = refl

batch-size : length handoffBatch ≡ 3
batch-size = refl
