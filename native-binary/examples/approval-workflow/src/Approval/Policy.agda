module Approval.Policy where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat)
open import Approval.Domain
open import Approval.Util using (_≤ᵇ_; _==ˢ_)

managerLimit : Nat
managerLimit = 1000

financeLimit : Nat
financeLimit = 5000

authorised : Role → Action → Bool
authorised employee submit = true
authorised manager approveByManager = true
authorised manager reject = true
authorised finance approveByFinance = true
authorised finance reject = true
authorised director approveByDirector = true
authorised director reject = true
authorised _ _ = false

managerMayFinish : Nat → Bool
managerMayFinish value = value ≤ᵇ managerLimit

financeMayFinish : Nat → Bool
financeMayFinish value = value ≤ᵇ financeLimit

sameRequester : Actor → Workflow → Bool
sameRequester who current = actorId who ==ˢ requesterId (workflowExpense current)
