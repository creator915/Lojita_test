module NbeAdapterSpikePrimitiveUnsupported where

open import Agda.Builtin.String using (String; primStringAppend)

main : String
main = primStringAppend "left" "right"
