{-# OPTIONS --cubical --safe #-}

-- Low-memory, independent reproduction of test/fixtures/TransportTests.agda t05/t06.
-- Source SHA-256: 8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b

module TransportInt where

open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Univalence

open import Cubical.Data.Int using (ℤ; pos; negsuc; sucℤ; predℤ; sucPred; predSuc)

private
  sucEq : ℤ ≃ ℤ
  sucEq = isoToEquiv (iso sucℤ predℤ sucPred predSuc)

  sucPath : ℤ ≡ ℤ
  sucPath = ua sucEq

t05 : ℤ
t05 = transport sucPath (pos 0)

e05 : ℤ
e05 = pos 1

_ : t05 ≡ e05
_ = refl

t06 : ℤ
t06 = transport (sym sucPath) (pos 0)

e06 : ℤ
e06 = negsuc 0

_ : t06 ≡ e06
_ = refl

-- Local negative control: this family is extensionally constant at the
-- endpoint, but its nested interval expression is not the canonical
-- univalence geometry admitted by the test-only adapter.
nonCanonicalEndpoint : ℤ
nonCanonicalEndpoint = transport (λ i → sucPath (i ∨ ~ i)) (pos 0)
