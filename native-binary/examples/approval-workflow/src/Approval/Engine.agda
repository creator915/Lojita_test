module Approval.Engine where

open import Agda.Builtin.Bool using (false; true)
open import Agda.Builtin.List using (List; []; _∷_)
open import Approval.Domain
open import Approval.Policy
open import Approval.Util using (snoc)

data Result : Set where
  success : Workflow → Result
  failure : WorkflowError → Workflow → Result

resultWorkflow : Result → Workflow
resultWorkflow (success current) = current
resultWorkflow (failure _ current) = current

record Step : Set where
  constructor step
  field
    stepActor : Actor
    stepAction : Action

open Step public

advance : Actor → Action → Status → Workflow → Workflow
advance who operation target current =
  workflow
    (workflowExpense current)
    target
    (snoc (workflowEvents current)
      (event who operation (workflowStatus current) target))

applySubmit : Actor → Workflow → Result
applySubmit who current with workflowStatus current
... | draft = success (advance who submit submitted current)
... | _ = failure invalidTransition current

applyManagerAt : Status → Actor → Workflow → Result
applyManagerAt submitted who current with sameRequester who current
...   | true = failure selfApproval current
...   | false with managerMayFinish (amount (workflowExpense current))
...     | true = success (advance who approveByManager approved current)
...     | false = success (advance who approveByManager managerApproved current)
applyManagerAt _ who current = failure invalidTransition current

applyManager : Actor → Workflow → Result
applyManager who current = applyManagerAt (workflowStatus current) who current

applyFinanceAt : Status → Actor → Workflow → Result
applyFinanceAt managerApproved who current with sameRequester who current
...   | true = failure selfApproval current
...   | false with financeMayFinish (amount (workflowExpense current))
...     | true = success (advance who approveByFinance approved current)
...     | false = success (advance who approveByFinance financeApproved current)
applyFinanceAt _ who current = failure invalidTransition current

applyFinance : Actor → Workflow → Result
applyFinance who current = applyFinanceAt (workflowStatus current) who current

applyDirectorAt : Status → Actor → Workflow → Result
applyDirectorAt financeApproved who current with sameRequester who current
...   | true = failure selfApproval current
...   | false = success (advance who approveByDirector approved current)
applyDirectorAt _ who current = failure invalidTransition current

applyDirector : Actor → Workflow → Result
applyDirector who current = applyDirectorAt (workflowStatus current) who current

applyReject : Actor → Workflow → Result
applyReject who current with actorRole who | workflowStatus current
... | manager | submitted = success (advance who reject rejected current)
... | finance | managerApproved = success (advance who reject rejected current)
... | director | financeApproved = success (advance who reject rejected current)
... | _ | _ = failure invalidTransition current

applyAuthorised : Actor → Action → Workflow → Result
applyAuthorised who submit = applySubmit who
applyAuthorised who approveByManager = applyManager who
applyAuthorised who approveByFinance = applyFinance who
applyAuthorised who approveByDirector = applyDirector who
applyAuthorised who reject = applyReject who

apply : Actor → Action → Workflow → Result
apply who operation current with authorised (actorRole who) operation
... | false = failure permissionDenied current
... | true = applyAuthorised who operation current

data Outcome : Set where
  completed : Workflow → Outcome
  stopped : WorkflowError → Workflow → Outcome

outcomeWorkflow : Outcome → Workflow
outcomeWorkflow (completed current) = current
outcomeWorkflow (stopped _ current) = current

run : Workflow → List Step → Outcome
run current [] = completed current
run current (step who operation ∷ remaining) with apply who operation current
... | success next = run next remaining
... | failure problem unchanged = stopped problem unchanged
