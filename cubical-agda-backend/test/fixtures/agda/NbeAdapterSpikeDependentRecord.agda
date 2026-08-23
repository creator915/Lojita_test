module NbeAdapterSpikeDependentRecord where

record Family : Set₁ where
  field
    Carrier : Set

open Family

main : (family : Family) → Carrier family → Carrier family
main = λ family value → value
