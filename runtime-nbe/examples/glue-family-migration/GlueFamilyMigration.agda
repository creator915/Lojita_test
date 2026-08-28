{-# OPTIONS --cubical #-}

module GlueFamilyMigration where

open import Agda.Primitive.Cubical
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Glue

RuntimeFamily : I → Set
RuntimeFamily i =
  primGlue Bool {φ = i} (λ _ → Bool)
    (λ _ → pathToEquiv (λ _ → Bool))

oldApproved : RuntimeFamily i0
oldApproved =
  prim^glue
    {A = Bool} {φ = i0} {T = λ _ → Bool}
    {e = λ _ → pathToEquiv (λ _ → Bool)}
    isOneEmpty true

oldRejected : RuntimeFamily i0
oldRejected =
  prim^glue
    {A = Bool} {φ = i0} {T = λ _ → Bool}
    {e = λ _ → pathToEquiv (λ _ → Bool)}
    isOneEmpty false

migrateApproved : Bool
migrateApproved =
  primTransp
    (λ i → primGlue Bool {φ = i} (λ _ → Bool)
      (λ _ → pathToEquiv (λ _ → Bool)))
    i0
    (prim^glue
      {A = Bool} {φ = i0} {T = λ _ → Bool}
      {e = λ _ → pathToEquiv (λ _ → Bool)}
      isOneEmpty true)

migrateRejected : Bool
migrateRejected =
  primTransp
    (λ i → primGlue Bool {φ = i} (λ _ → Bool)
      (λ _ → pathToEquiv (λ _ → Bool)))
    i0
    (prim^glue
      {A = Bool} {φ = i0} {T = λ _ → Bool}
      {e = λ _ → pathToEquiv (λ _ → Bool)}
      isOneEmpty false)

-- Same endpoint types but a different family identity must not be guessed.
UnsupportedFamily : I → Set
UnsupportedFamily _ = Bool

unsupportedNamedFamily : Bool
unsupportedNamedFamily = primTransp UnsupportedFamily i0 true
