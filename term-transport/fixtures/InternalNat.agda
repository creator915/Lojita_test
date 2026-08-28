module InternalNat where

open import Agda.Builtin.Bool
open import Agda.Builtin.Nat

value : Nat
value = 7

other : Nat
other = 8

flag : Bool
flag = true

identity : Nat → Nat
identity number = number
