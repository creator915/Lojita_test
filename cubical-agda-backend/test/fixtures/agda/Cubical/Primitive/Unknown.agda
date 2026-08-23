module Cubical.Primitive.Unknown where

open import Agda.Builtin.Nat using (Nat)

-- Simulates a primitive QName introduced by a future Agda/Cubical upgrade.
-- The backend must reject this executable reference until it is reviewed and
-- added to the pinned primitive catalog.
postulate
  primFuture : Nat

main : Nat
main = primFuture
