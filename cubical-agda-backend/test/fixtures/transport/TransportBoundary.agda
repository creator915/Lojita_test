{-# OPTIONS --cubical --safe #-}

-- Low-memory, independent reproduction of test/fixtures/TransportTests.agda t11/t11b.
-- Source SHA-256: 8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b

module TransportBoundary where

open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Univalence

open import Cubical.Data.Bool using (Bool; true; false; not)
open import Cubical.Data.Nat using (ℕ)
open import Cubical.Data.Nat.Properties using (+-comm; isSetℕ)
open import Cubical.Data.Sigma using (_×_; _,_)
open import Cubical.Foundations.Transport using (isSet-subst)
open import Cubical.Data.Vec using (Vec; head; tail) renaming (_∷_ to _∷v_; [] to []v)

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true  = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  notPath : Bool ≡ Bool
  notPath = ua notEq

t11 : Vec Bool 2
t11 = transport (λ i → Vec (notPath i) 2) (true ∷v (false ∷v []v))

e11 : Vec Bool 2
e11 = false ∷v (true ∷v []v)

-- The raw Vec transport is residual in Agda's pretty-printer.  Eliminating
-- the same checked value to two Bool observations forces its computational
-- content and gives the differential harness a canonical oracle result.
t11-observation : Bool × Bool
t11-observation = head t11 , head (tail t11)

t11b : Vec Bool 2
t11b = subst (Vec Bool) (+-comm 1 1) (true ∷v (false ∷v []v))

e11b : Vec Bool 2
e11b = true ∷v (false ∷v []v)

t11b-observation : Bool × Bool
t11b-observation = head t11b , head (tail t11b)

_ : t11b ≡ e11b
_ = isSet-subst {B = Vec Bool} isSetℕ (+-comm 1 1) e11b
