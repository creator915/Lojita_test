{-# OPTIONS --cubical #-}

module GlueMigration where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Path
open import Agda.Builtin.Cubical.Glue

glueApproved : Bool
glueApproved =
  prim^unglue
    {A = Bool} {φ = i0} {T = λ _ → Bool} {e = isOneEmpty}
    (prim^glue
      {A = Bool} {φ = i0} {T = λ _ → Bool} {e = isOneEmpty}
      isOneEmpty true)

glueRejected : Bool
glueRejected =
  prim^unglue
    {A = Bool} {φ = i0} {T = λ _ → Bool} {e = isOneEmpty}
    (prim^glue
      {A = Bool} {φ = i0} {T = λ _ → Bool} {e = isOneEmpty}
      isOneEmpty false)

namedApproved : Bool
namedApproved = true

unsupportedNamedPayload : Bool
unsupportedNamedPayload =
  prim^unglue
    {A = Bool} {φ = i0} {T = λ _ → Bool} {e = isOneEmpty}
    (prim^glue
      {A = Bool} {φ = i0} {T = λ _ → Bool} {e = isOneEmpty}
      isOneEmpty namedApproved)

approvedExpected : glueApproved ≡ true
approvedExpected _ = true

rejectedExpected : glueRejected ≡ false
rejectedExpected _ = false
