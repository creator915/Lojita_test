{-# OPTIONS --cubical #-}

module EmergencyOverride where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Path

-- These are genuinely active systems.  At phi=i1 Agda requires the tube at
-- the composition start to agree with the base, while cctt still performs the
-- non-empty hcom rather than treating it as the empty-system shortcut.
allowOverride : Bool
allowOverride = primHComp {A = Bool} {φ = i1} (λ _ _ → true) true

denyOverride : Bool
denyOverride = primHComp {A = Bool} {φ = i1} (λ _ _ → false) false

namedAllow : Bool
namedAllow = true

-- Valid Agda, but outside the literal-tube grammar.  This is a fail-closed
-- boundary test, not a request for the lowerer to normalize a named value.
unsupportedNamedTube : Bool
unsupportedNamedTube =
  primHComp {A = Bool} {φ = i1} (λ _ _ → namedAllow) namedAllow

allowExpected : allowOverride ≡ true
allowExpected _ = true

denyExpected : denyOverride ≡ false
denyExpected _ = false
