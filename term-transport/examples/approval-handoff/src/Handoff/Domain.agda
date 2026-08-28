module Handoff.Domain where

open import Agda.Builtin.Bool using (Bool)
open import Agda.Builtin.List using (List)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

data Department : Set where
  sales engineering operations : Department

data Decision : Set where
  accept deny : Decision

record Review : Set where
  constructor review
  field
    reviewer : String
    reviewerDepartment : Department
    decision : Decision
    comment : String

open Review public

record Envelope : Set where
  constructor envelope
  field
    requestId : String
    requester : String
    amount : Nat
    ownerDepartment : Department
    urgent : Bool
    reviews : List Review
    tags : List String
    revision : Nat

open Envelope public

data HandoffState : Set where
  awaitingReview readyToPay denied : HandoffState

record Summary : Set where
  constructor summary
  field
    summaryRequestId : String
    summaryAmount : Nat
    summaryReviewCount : Nat
    summaryState : HandoffState

open Summary public
