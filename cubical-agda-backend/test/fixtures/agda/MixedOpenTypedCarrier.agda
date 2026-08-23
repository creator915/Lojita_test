{-# OPTIONS --cubical --safe #-}

module MixedOpenTypedCarrier where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

Residual : Set₁
Residual = (A : I → Set) → A i0 → A i0 → A i1

OpenResidualClosure : Set₁
OpenResidualClosure = Nat → Residual

record Payload : Set₁ where
  constructor payload
  field
    stored : Residual

data Wrapped : Set₁ where
  wrap : Payload → Wrapped

chooseNat : {A : Set} → Nat → A → A → A
chooseNat zero left _ = left
chooseNat (suc _) _ right = right

-- This is the same open Nat residual shape used by the lexical-capture
-- fixture.  The carrier tests deliberately move its non-ground result through
-- a record and then a data constructor without exposing an erased Chez value.
main : Nat → Σ Bool (λ _ → Residual)
main = λ captured →
  true , (λ A left right →
    primTransp A i0 (chooseNat captured left right))

consume : (Nat → Σ Bool (λ _ → Residual)) → Bool
consume entry with entry zero
... | static , _ = static

consumeClosure : OpenResidualClosure → Bool
consumeClosure closure = closure zero (λ _ → Bool) true false

consumeResidual : Residual → Bool
consumeResidual residual = residual (λ _ → Bool) true false

toPayload : Residual → Payload
toPayload residual = payload residual

toWrapped : Payload → Wrapped
toWrapped value = wrap value

consumeWrapped : Wrapped → Bool
consumeWrapped (wrap (payload residual)) = consumeResidual residual

idBool : Bool → Bool
idBool value = value
