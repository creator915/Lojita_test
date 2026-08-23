module NbeAdapterSpikeCycle where

open import Agda.Builtin.Nat

{-# TERMINATING #-}
loop : Nat → Nat
loop value = loop value

main : Nat
main = loop 0
