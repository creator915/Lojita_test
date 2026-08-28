{-# OPTIONS --cubical #-}

module AuditLoop where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Cubical.Path

-- A closed interval HIT is the first deliberately supported HIT shape.  The
-- two runtime entries use distinct endpoints of the path constructor, so the
-- lowerer must preserve path-constructor input rather than replace it with a
-- verifier-selected point.
data AuditTrace : Set where
  auditOpened : AuditTrace
  auditClosed : AuditTrace
  auditTransition : auditOpened ≡ auditClosed

open AuditTrace

resumeFromCycleStart : AuditTrace
resumeFromCycleStart =
  primHComp {A = AuditTrace} {φ = i0} (λ _ → isOneEmpty) (auditTransition i0)

resumeFromCycleEnd : AuditTrace
resumeFromCycleEnd =
  primHComp {A = AuditTrace} {φ = i0} (λ _ → isOneEmpty) (auditTransition i1)

-- A genuinely higher-dimensional active tube.  The forward composition moves
-- an opened audit record to the closed endpoint; the reverse tube uses interval
-- negation and moves a closed record back to the opened endpoint.
closeThroughActiveTube : AuditTrace
closeThroughActiveTube =
  primHComp {A = AuditTrace} {φ = i1}
    (λ j _ → auditTransition j) auditOpened

reopenThroughActiveTube : AuditTrace
reopenThroughActiveTube =
  primHComp {A = AuditTrace} {φ = i1}
    (λ j _ → auditTransition (primINeg j)) auditClosed

-- Ordinary datatypes and unary-loop HITs are outside this
-- declared shape and must not be silently translated as AuditTrace.
data UnsupportedTrace : Set where
  root : UnsupportedTrace
  cycle : root ≡ root

open UnsupportedTrace

unsupportedMultiPoint : UnsupportedTrace
unsupportedMultiPoint =
  primHComp {A = UnsupportedTrace} {φ = i0} (λ _ → isOneEmpty) root
