module NbeAdapterSpike where

open import Agda.Builtin.Bool using (Bool; false; true)

flip : Bool → Bool
flip false = true
flip true = false

once : Bool
once = flip true

main : Bool
main = flip (flip true)
