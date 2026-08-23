module NbeAdapterSpikeRecord where

open import Agda.Builtin.Nat using (Nat)

record Pair : Set where
  constructor pair
  field
    left : Nat
    right : Nat

open Pair

projectRight : Pair → Nat
projectRight value = right value

main : Nat
main = projectRight (pair 7 42)
