{-# OPTIONS --cubical #-}

module ResidualDependencyClosure where

open import Agda.Builtin.Bool using (Bool)
open import Agda.Builtin.Sigma using (Σ; _,_)
open import Agda.Primitive using (Set)
open import Agda.Primitive.Cubical using (I; i0; i1; primTransp)

-- The residual payload mentions hiddenValue directly. Its checked type reaches Bool
-- only through Alias, so a complete dependency graph must expand
-- hiddenValue -> Alias -> Agda.Builtin.Bool.Bool.
Alias : Set
Alias = Bool

postulate
  hiddenValue : Alias
  presentationOnly : Alias

-- DISPLAY metadata deliberately mentions an otherwise unreachable QName.
-- It must remain auditable without entering the executable dependency slice.
{-# DISPLAY hiddenValue = presentationOnly #-}

main : Σ Bool (λ _ → (B : I → Set) → B i0 → B i1)
main = hiddenValue , λ B x → primTransp B i0 x
