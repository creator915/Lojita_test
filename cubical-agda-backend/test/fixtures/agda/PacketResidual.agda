{-# OPTIONS --cubical --safe #-}

module PacketResidual where

open import Agda.Builtin.Bool using (Bool; true)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

-- A closed higher-order value whose transport cannot reduce until the family
-- is supplied.  It exercises the typed packet path without loading the full
-- external cubical library.
main : (A : I → Set) → A i0 → A i1
main = λ A x → primTransp A i0 x

consume : ((A : I → Set) → A i0 → A i1) → Bool
consume _ = true

-- Negative-control consumer: its domain is deliberately incompatible with
-- the higher-order transport value carried by the packet.
consumeWrong : Bool → Bool
consumeWrong value = value
