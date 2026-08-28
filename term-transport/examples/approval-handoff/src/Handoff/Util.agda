module Handoff.Util where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat; _+_; _<_)

not : Bool → Bool
not false = true
not true = false

infixr 6 _&&_

_&&_ : Bool → Bool → Bool
true && right = right
false && _ = false

length : {A : Set} → List A → Nat
length [] = 0
length (_ ∷ rest) = 1 + length rest

_≤ᵇ_ : Nat → Nat → Bool
left ≤ᵇ right = not (right < left)
