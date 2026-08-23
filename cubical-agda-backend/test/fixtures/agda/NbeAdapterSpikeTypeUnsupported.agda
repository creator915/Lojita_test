module NbeAdapterSpikeTypeUnsupported where

record Box : Set₁ where
  field
    Carrier : Set

open Box

postulate
  box : Box

main : (value : Carrier box) → Carrier box
main = λ value → value
