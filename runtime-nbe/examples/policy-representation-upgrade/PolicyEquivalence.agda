{-# OPTIONS --cubical #-}

module PolicyEquivalence where

open import Agda.Primitive.Cubical
  renaming (primINeg to ~_; primIMin to _∧_)
open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Path
open import Agda.Builtin.Cubical.Glue
open import Agda.Builtin.Sigma
open Helpers

pathJ : ∀ {ℓ} {A : Set ℓ} {x : A}
  (P : ∀ y → x ≡ y → Set) (d : P x refl)
  (y : A) (p : x ≡ y) → P y p
pathJ P d _ p =
  primTransp (λ i → P (p i) (λ j → p (i ∧ j))) i0 d

policyNot : Bool → Bool
policyNot true = false
policyNot false = true

policyNotInvolutive : ∀ value → value ≡ policyNot (policyNot value)
policyNotInvolutive true = refl
policyNotInvolutive false = refl

policyNotFiber : ∀ expected
  (candidate : Σ Bool λ value → policyNot value ≡ expected) →
  (policyNot expected , sym (policyNotInvolutive expected)) ≡ candidate
policyNotFiber expected (true , equality) =
  pathJ (λ value proof →
    (policyNot value , sym (policyNotInvolutive value)) ≡ (true , proof))
    refl _ equality
policyNotFiber expected (false , equality) =
  pathJ (λ value proof →
    (policyNot value , sym (policyNotInvolutive value)) ≡ (false , proof))
    refl _ equality

policyNotEquiv : Bool ≃ Bool
policyNotEquiv =
  policyNot , (λ { .equiv-proof expected →
    (policyNot expected , sym (policyNotInvolutive expected)) ,
    policyNotFiber expected })
