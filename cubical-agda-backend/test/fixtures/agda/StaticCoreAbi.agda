module StaticCoreAbi where

open import Agda.Builtin.Nat

record Box : Set where
  constructor box
  field
    value : Nat

data Choice : Set where
  empty  : Choice
  picked : Box → Choice

-- Keeping both arguments abstract prevents normalization from erasing the
-- function call and the two constructor layouts before Treeless lowering.
transform : (Nat → Nat) → Choice → Choice
transform f empty = empty
transform f (picked (box n)) = picked (box (f (n + 2)))

main : (Nat → Nat) → Choice → Choice
main = transform
