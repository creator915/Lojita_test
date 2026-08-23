{-# OPTIONS --cubical --safe #-}

module NbeAdapterSpikeNeutralCofibration where

open import Agda.Builtin.Nat using (Nat; suc)
open import Agda.Primitive.Cubical
  using (I; i0; i1; primIMin; primIMax; primINeg; primTransp)

main : I → Nat
main = \ φ →
  primTransp
    (\ _ → Nat)
    (primINeg (primINeg (primIMax (primIMin φ i1) i0)))
    42

groundZero : Nat
groundZero = primTransp (\ _ → Nat) i0 42

functionZero : Nat
functionZero = primTransp (\ _ → Nat → Nat) i0 suc 3
