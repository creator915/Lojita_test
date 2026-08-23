module NbeAdapterSpikeData where

open import Agda.Builtin.Nat using (Nat; zero; suc)

data Tree : Set where
  leaf : Nat → Tree
  node : Tree → Tree → Tree

plus : Nat → Nat → Nat
plus zero right = right
plus (suc left) right = suc (plus left right)

sum : Tree → Nat
sum (leaf value) = value
sum (node left right) = plus (sum left) (sum right)

main : Nat
main = sum (node (leaf 2) (node (leaf 3) (leaf 4)))
