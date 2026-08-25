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
open import Cubical.Data.Vec using (Vec; head; tail; map) renaming (_∷_ to _∷v_; [] to []v)

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true  = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  notPath : Bool ≡ Bool
  notPath = ua notEq

  map-id : ∀ {n} {A : Type} (xs : Vec A n) → map (λ x → x) xs ≡ xs
  map-id []v = refl
  map-id (x ∷v xs) i = x ∷v map-id xs i

  -- This proof uses equivalence induction, so it is independent of the
  -- generated transpX-Vec normal form.  It connects the actual transported
  -- value to a canonical pointwise oracle without assuming the result.
  transportVecUa : ∀ {A B : Type} {n} (e : A ≃ B) (xs : Vec A n) →
    transport (cong (λ X → Vec X n) (ua e)) xs ≡ map (equivFun e) xs
  transportVecUa {B = B} {n = n} = EquivJ
    (λ A e → (xs : Vec A n) →
      transport (cong (λ X → Vec X n) (ua e)) xs ≡ map (equivFun e) xs)
    (λ xs →
      cong (λ p → transport (cong (λ X → Vec X n) p) xs) (uaIdEquiv {A = B})
      ∙ transportRefl xs
      ∙ sym (map-id xs))

t11-input : Vec Bool 2
t11-input = true ∷v (false ∷v []v)

t11 : Vec Bool 2
t11 = transport (λ i → Vec (notPath i) 2) t11-input

e11 : Vec Bool 2
e11 = false ∷v (true ∷v []v)

-- Agda intentionally leaves the raw indexed transport residual.  The oracle
-- is computed from the same input and equivalence, and this checked theorem
-- proves that it denotes the actual t11 value.
t11-oracle : Vec Bool 2
t11-oracle = map not t11-input

t11-sound : t11 ≡ t11-oracle
t11-sound = transportVecUa notEq t11-input

t11-oracle-observation : Bool × Bool
t11-oracle-observation = head t11-oracle , head (tail t11-oracle)

t11b-input : Vec Bool 2
t11b-input = true ∷v (false ∷v []v)

t11b : Vec Bool 2
t11b = subst (Vec Bool) (+-comm 1 1) t11b-input

e11b : Vec Bool 2
e11b = true ∷v (false ∷v []v)

t11b-oracle : Vec Bool 2
t11b-oracle = t11b-input

t11b-sound : t11b ≡ t11b-oracle
t11b-sound = isSet-subst {B = Vec Bool} isSetℕ (+-comm 1 1) t11b-input

t11b-oracle-observation : Bool × Bool
t11b-oracle-observation = head t11b-oracle , head (tail t11b-oracle)
