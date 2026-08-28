{-# OPTIONS --cubical #-}

module RuntimePolicyOverride where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Path

-- A policy snapshot with no active override is represented by an empty face.
-- Runtime composition must preserve the stored fallback.  This is the first
-- useful fail-safe case for an offline client.

preserveDisabled : Bool
preserveDisabled =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty) false

preserveEnabled : Bool
preserveEnabled =
  primHComp {A = Bool} {φ = i0} (λ _ → isOneEmpty) true

disabledExpected : preserveDisabled ≡ false
disabledExpected _ = false

enabledExpected : preserveEnabled ≡ true
enabledExpected _ = true

activeOverride : Bool
activeOverride =
  primHComp {A = Bool} {φ = i1} (λ _ _ → true) true

namedOverride : Bool
namedOverride = true

-- Valid Agda but outside the literal-tube grammar.  The backend must not
-- normalize this name and silently pretend it reflected the original term.
unsupportedNamedActiveTube : Bool
unsupportedNamedActiveTube =
  primHComp {A = Bool} {φ = i1} (λ _ _ → namedOverride) namedOverride
