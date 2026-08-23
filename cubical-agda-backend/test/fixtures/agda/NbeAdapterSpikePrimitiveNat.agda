module NbeAdapterSpikePrimitiveNat where

open import Agda.Builtin.Nat
  renaming (_+_ to natPlus; _-_ to natMinus; _*_ to natTimes)

main : Nat
main = natPlus (natTimes 6 7) (natMinus 5 5)
