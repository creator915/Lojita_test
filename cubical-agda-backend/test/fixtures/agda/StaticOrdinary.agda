module StaticOrdinary where

open import Agda.Builtin.Nat

double : Nat → Nat
double zero = zero
double (suc n) = suc (suc (double n))

main : Nat
main = double 21
