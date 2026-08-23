{-# OPTIONS --cubical --safe #-}

module NbeAdapterSpikeGlueCancellation where

open import Agda.Builtin.Nat using (Nat)
open import Agda.Primitive.Cubical using (i0; Partial; PartialP)
open import Agda.Builtin.Cubical.Glue using (_≃_; prim^glue; prim^unglue)

T : Partial i0 Set
T ()

e : PartialP i0 (λ o → T o ≃ Nat)
e ()

t : PartialP i0 T
t ()

main : Nat
main =
  prim^unglue {A = Nat} {φ = i0}
    {T = T} {e = e}
    (prim^glue {A = Nat} {φ = i0} {T = T} {e = e} t 42)
