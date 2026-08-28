module Approval.Scenarios where

open import Agda.Builtin.List using ([]; _∷_)
open import Approval.Domain
open import Approval.Engine

alice : Actor
alice = actor "alice" employee

bob : Actor
bob = actor "bob" manager

carol : Actor
carol = actor "carol" finance

diana : Actor
diana = actor "diana" director

aliceManager : Actor
aliceManager = actor "alice" manager

smallRequest : Expense
smallRequest = expense "REQ-100" "alice" 750 travel "customer visit"

mediumRequest : Expense
mediumRequest = expense "REQ-200" "alice" 3200 equipment "developer workstation"

largeRequest : Expense
largeRequest = expense "REQ-300" "alice" 8000 customerEvent "annual customer summit"

small : Outcome
small = run (initial smallRequest)
  (step alice submit ∷ step bob approveByManager ∷ [])

medium : Outcome
medium = run (initial mediumRequest)
  (step alice submit ∷ step bob approveByManager ∷
   step carol approveByFinance ∷ [])

large : Outcome
large = run (initial largeRequest)
  (step alice submit ∷ step bob approveByManager ∷
   step carol approveByFinance ∷ step diana approveByDirector ∷ [])

rejectedRequest : Outcome
rejectedRequest = run (initial mediumRequest)
  (step alice submit ∷ step bob reject ∷ [])

unauthorised : Outcome
unauthorised = run (initial mediumRequest)
  (step alice submit ∷ step alice approveByManager ∷ [])

selfApprovalAttempt : Outcome
selfApprovalAttempt = run (initial mediumRequest)
  (step alice submit ∷ step aliceManager approveByManager ∷ [])

invalidOrder : Outcome
invalidOrder = run (initial mediumRequest)
  (step alice submit ∷ step carol approveByFinance ∷ [])
