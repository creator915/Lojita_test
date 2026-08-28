module Approval.Util where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat; _+_; _<_)
open import Agda.Builtin.String
  using (String; primShowNat; primStringAppend; primStringEquality)

infixr 5 _++_

_++_ : String → String → String
_++_ = primStringAppend

showNat : Nat → String
showNat = primShowNat

_≤ᵇ_ : Nat → Nat → Bool
left ≤ᵇ right with right < left
... | true = false
... | false = true

_==ˢ_ : String → String → Bool
_==ˢ_ = primStringEquality

snoc : {A : Set} → List A → A → List A
snoc [] value = value ∷ []
snoc (head ∷ tail) value = head ∷ snoc tail value

length : {A : Set} → List A → Nat
length [] = 0
length (_ ∷ tail) = 1 + length tail
