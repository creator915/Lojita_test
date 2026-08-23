{-# OPTIONS --cubical --safe #-}

-- Low-memory, independent reproduction of test/fixtures/TransportTests.agda t16a-t16c.
-- Source SHA-256: 8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b

module TransportHigher where

open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Univalence

open import Cubical.Data.Bool using (Bool; true; false; not)
open import Cubical.Data.Int using (ℤ; pos; sucℤ; predℤ; sucPred; predSuc)
open import Cubical.HITs.S1 using (base; loop; winding)

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true  = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  sucEq : ℤ ≃ ℤ
  sucEq = isoToEquiv (iso sucℤ predℤ sucPred predSuc)

  notPath : Bool ≡ Bool
  notPath = ua notEq

  sucPath : ℤ ≡ ℤ
  sucPath = ua sucEq

p16a : Bool → Bool
p16a = transport (λ i → notPath i → notPath i) (λ b → b)

p16b : ℤ ≡ ℤ
p16b = sucPath ∙ sucPath

p16c : base ≡ base
p16c = loop ∙ loop

c16a : (Bool → Bool) → Bool
c16a f = f true

c16b : ℤ ≡ ℤ → ℤ
c16b p = transport p (pos 0)

c16c : base ≡ base → ℤ
c16c = winding

t16a : Bool
t16a = c16a p16a

e16a : Bool
e16a = true

_ : t16a ≡ e16a
_ = refl

t16b : ℤ
t16b = c16b p16b

e16b : ℤ
e16b = pos 2

_ : t16b ≡ e16b
_ = refl

t16c : ℤ
t16c = c16c p16c

e16c : ℤ
e16c = pos 2

_ : t16c ≡ e16c
_ = refl
