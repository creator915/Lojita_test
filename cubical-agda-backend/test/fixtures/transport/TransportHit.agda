{-# OPTIONS --cubical --safe #-}

-- Low-memory, independent reproduction of test/fixtures/TransportTests.agda t12-t15.
-- Source SHA-256: 8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b

module TransportHit where

open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Univalence

open import Cubical.Data.Bool using (Bool; true; false; not)
open import Cubical.Data.Nat using (ℕ; zero)
open import Cubical.Data.Int using (ℤ; pos)
open import Cubical.HITs.S1 using (loop; winding; intLoop)

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true  = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  notPath : Bool ≡ Bool
  notPath = ua notEq

t12 : ℤ
t12 = winding (intLoop (pos 2))

e12 : ℤ
e12 = pos 2

_ : t12 ≡ e12
_ = refl

t13 : ℤ
t13 = winding (loop ∙ loop ∙ sym loop)

e13 : ℤ
e13 = pos 1

_ : t13 ≡ e13
_ = refl

t14 : ℕ
t14 = J {x = zero} (λ _ _ → ℕ) 41 refl

e14 : ℕ
e14 = 41

_ : t14 ≡ e14
_ = refl

t15 : Bool
t15 = transport notPath (transport notPath true)

e15 : Bool
e15 = true

_ : t15 ≡ e15
_ = refl
