{-# OPTIONS --cubical --safe #-}

module NbeAdapterSpikeCubicalGround where

open import Agda.Builtin.Nat using (Nat)
open import Agda.Primitive.Cubical
  using (I; i0; i1; primIMin; primIMax; primINeg; primTransp; primHComp)

main : Nat
main =
  primHComp
    {A = Nat}
    {φ = primIMin i0 (primINeg i1)}
    (\ _ ())
    (primTransp (\ _ → Nat) (primIMax i0 (primINeg i0)) 42)
