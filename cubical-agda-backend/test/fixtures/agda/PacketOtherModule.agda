{-# OPTIONS --cubical --safe #-}

module PacketOtherModule where

open import Agda.Builtin.Bool using (Bool; true)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1)

-- Its consumer has the right domain, but the top-level module deliberately
-- differs from the packet producer.
consume : ((A : I → Set) → A i0 → A i1) → Bool
consume _ = true
