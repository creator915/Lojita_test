{-# OPTIONS --cubical --safe #-}

module PacketResidual where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

main : (A : I → Set) → A i0 → A i1
main = λ A x → primTransp A i0 x

consume : ((A : I → Set) → A i0 → A i1) → Bool
consume _ = true

-- The extra checked declaration changes the full interface hash while
-- retaining the same module name and consumer type.
hashWitness : Bool
hashWitness = false
