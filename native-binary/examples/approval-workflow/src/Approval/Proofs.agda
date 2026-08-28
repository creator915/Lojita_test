module Approval.Proofs where

open import Agda.Builtin.Equality using (_≡_; refl)
open import Approval.Domain
open import Approval.Engine
open import Approval.Scenarios
open import Approval.Util using (length)

small-finishes-approved : workflowStatus (outcomeWorkflow small) ≡ approved
small-finishes-approved = refl

medium-finishes-approved : workflowStatus (outcomeWorkflow medium) ≡ approved
medium-finishes-approved = refl

large-finishes-approved : workflowStatus (outcomeWorkflow large) ≡ approved
large-finishes-approved = refl

large-has-four-audit-events : length (workflowEvents (outcomeWorkflow large)) ≡ 4
large-has-four-audit-events = refl

unauthorised-keeps-submitted-state :
  workflowStatus (outcomeWorkflow unauthorised) ≡ submitted
unauthorised-keeps-submitted-state = refl

self-approval-keeps-submitted-state :
  workflowStatus (outcomeWorkflow selfApprovalAttempt) ≡ submitted
self-approval-keeps-submitted-state = refl
