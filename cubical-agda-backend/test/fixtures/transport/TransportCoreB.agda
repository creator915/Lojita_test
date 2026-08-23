{-# OPTIONS --cubical --safe #-}

-- Low-memory, independent reproduction of test/fixtures/TransportTests.agda t09-t10.
-- Source SHA-256: 8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b

module TransportCoreB where

open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Univalence

open import Cubical.Data.Bool using (Bool; true; false; not)
open import Cubical.Data.Nat using (ℕ)
open import Cubical.Data.Sigma using (_×_; _,_)
open import Cubical.Data.List using (List; _∷_; [])

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true  = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  notPath : Bool ≡ Bool
  notPath = ua notEq

t09 : Bool × ℕ
t09 = transport (λ i → notPath i × ℕ) (true , 3)

e09 : Bool × ℕ
e09 = (false , 3)

_ : t09 ≡ e09
_ = refl

t10 : List Bool
t10 = transport (λ i → List (notPath i)) (true ∷ false ∷ true ∷ [])

e10 : List Bool
e10 = false ∷ true ∷ false ∷ []

_ : t10 ≡ e10
_ = refl

-- Local negative controls for the deliberately narrow structured rules.
nonCanonicalSigma : Bool × Bool
nonCanonicalSigma =
  transport (λ i → notPath i × notPath i) (true , true)

nonCanonicalList : List Bool
nonCanonicalList =
  transport (λ i → List (notPath (i ∨ ~ i))) (true ∷ [])
