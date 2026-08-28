module Approval.Render where

open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.String using (String)
open import Approval.Domain
open import Approval.Engine
open import Approval.Util using (_++_; showNat)

renderRole : Role → String
renderRole employee = "employee"
renderRole manager = "manager"
renderRole finance = "finance"
renderRole director = "director"

renderCategory : Category → String
renderCategory travel = "travel"
renderCategory equipment = "equipment"
renderCategory training = "training"
renderCategory customerEvent = "customer-event"

renderStatus : Status → String
renderStatus draft = "draft"
renderStatus submitted = "submitted"
renderStatus managerApproved = "manager-approved"
renderStatus financeApproved = "finance-approved"
renderStatus approved = "approved"
renderStatus rejected = "rejected"

renderAction : Action → String
renderAction submit = "submit"
renderAction approveByManager = "manager-approve"
renderAction approveByFinance = "finance-approve"
renderAction approveByDirector = "director-approve"
renderAction reject = "reject"

renderError : WorkflowError → String
renderError permissionDenied = "permission-denied"
renderError invalidTransition = "invalid-transition"
renderError selfApproval = "self-approval"

renderEvent : Event → String
renderEvent current =
  renderAction (eventAction current) ++ ":" ++ actorId (eventActor current) ++
  ":" ++ renderStatus (previousStatus current) ++ "->" ++
  renderStatus (nextStatus current)

renderEvents : List Event → String
renderEvents [] = "none"
renderEvents (current ∷ []) = renderEvent current
renderEvents (current ∷ remaining) = renderEvent current ++ "," ++ renderEvents remaining

renderResult : Outcome → String
renderResult (completed current) = "ok:" ++ renderStatus (workflowStatus current)
renderResult (stopped problem _) = "error:" ++ renderError problem

renderReport : String → Outcome → String
renderReport scenario result =
  "scenario=" ++ scenario ++ "\n" ++
  "request=" ++ requestId request ++ "\n" ++
  "requester=" ++ requesterId request ++ "\n" ++
  "amount=" ++ showNat (amount request) ++ "\n" ++
  "category=" ++ renderCategory (category request) ++ "\n" ++
  "result=" ++ renderResult result ++ "\n" ++
  "status=" ++ renderStatus (workflowStatus current) ++ "\n" ++
  "events=" ++ renderEvents (workflowEvents current)
  where
    current = outcomeWorkflow result
    request = workflowExpense current
