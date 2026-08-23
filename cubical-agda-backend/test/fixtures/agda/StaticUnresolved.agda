module StaticUnresolved where

open import Agda.Builtin.Nat using (Nat)

-- A checked, closed, non-Cubical term can still have an incomplete runtime
-- definition closure.  It must not receive permission to erase types.
postulate
  opaqueNat : Nat

main : Nat
main = opaqueNat
