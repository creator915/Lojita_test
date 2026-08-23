module NbeAdapterSpikePrimitiveImpostor where

open import Agda.Builtin.Nat using (Nat)

infixl 6 _+_

postulate
  _+_ : Nat → Nat → Nat

main : Nat
main = 20 + 22
