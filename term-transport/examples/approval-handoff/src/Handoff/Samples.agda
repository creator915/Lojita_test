module Handoff.Samples where

open import Agda.Builtin.Bool using (false; true)
open import Agda.Builtin.List using (List; []; _∷_)
open import Handoff.Domain

managerReview : Review
managerReview = review "bob" operations accept "budget checked"

financeReview : Review
financeReview = review "carol" operations accept "invoice checked"

directorReview : Review
directorReview = review "diana" sales accept "strategic approval"

denialReview : Review
denialReview = review "carol" operations deny "missing receipt"

approvedEnvelope : Envelope
approvedEnvelope = envelope
  "REQ-300" "alice" 8000 sales true
  (managerReview ∷ financeReview ∷ directorReview ∷ [])
  ("customer-event" ∷ "priority" ∷ [])
  4

approvedEnvelopeAlt : Envelope
approvedEnvelopeAlt = envelope
  "REQ-309" "alice" 8001 sales true
  (managerReview ∷ financeReview ∷ directorReview ∷ [])
  ("customer-event" ∷ "priority" ∷ [])
  5

pendingEnvelope : Envelope
pendingEnvelope = envelope
  "REQ-301" "alice" 8000 engineering false
  (managerReview ∷ [])
  ("equipment" ∷ [])
  2

deniedEnvelope : Envelope
deniedEnvelope = envelope
  "REQ-302" "erin" 3200 operations false
  (managerReview ∷ denialReview ∷ [])
  ("training" ∷ "receipt-required" ∷ [])
  3

handoffBatch : List Envelope
handoffBatch = approvedEnvelope ∷ pendingEnvelope ∷ deniedEnvelope ∷ []
