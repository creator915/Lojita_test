module Approval.Domain where

open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

data Role : Set where
  employee manager finance director : Role

record Actor : Set where
  constructor actor
  field
    actorId : String
    actorRole : Role

open Actor public

data Category : Set where
  travel equipment training customerEvent : Category

record Expense : Set where
  constructor expense
  field
    requestId : String
    requesterId : String
    amount : Nat
    category : Category
    purpose : String

open Expense public

data Status : Set where
  draft submitted managerApproved financeApproved approved rejected : Status

data Action : Set where
  submit approveByManager approveByFinance approveByDirector reject : Action

data WorkflowError : Set where
  permissionDenied invalidTransition selfApproval : WorkflowError

record Event : Set where
  constructor event
  field
    eventActor : Actor
    eventAction : Action
    previousStatus : Status
    nextStatus : Status

open Event public

record Workflow : Set where
  constructor workflow
  field
    workflowExpense : Expense
    workflowStatus : Status
    workflowEvents : List Event

open Workflow public

initial : Expense → Workflow
initial request = workflow request draft []
