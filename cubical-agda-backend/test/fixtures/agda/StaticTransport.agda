{-# OPTIONS --cubical --guardedness #-}

module StaticTransport where

open import Agda.Builtin.Nat
open import Cubical.Data.Bool.Base using (Bool; false; true)
open import Cubical.Data.Bool.Properties using (notEq)
open import Cubical.Foundations.Prelude using (_≡_; refl; transport)

toNat : Bool → Nat
toNat false = 0
toNat true = 1

main : Nat
main = toNat (transport notEq true)

main-is-zero : main ≡ 0
main-is-zero = refl
