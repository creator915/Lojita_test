{-# OPTIONS --cubical --safe #-}

module StaticTypeOnlyCubical where

open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0)

-- Cubical names occur only in the type.  The runtime term is identity, so
-- type erasure is safe and this must not be forced into typed residual mode.
main : (A : I → Set) → A i0 → A i0
main = λ _ x → x
