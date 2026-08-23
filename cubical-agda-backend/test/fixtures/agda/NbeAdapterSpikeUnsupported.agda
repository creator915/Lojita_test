module NbeAdapterSpikeUnsupported where

open import Agda.Builtin.Bool using (Bool; true)

postulate
  opaqueFunction : Bool → Bool

main : Bool
main = opaqueFunction true
