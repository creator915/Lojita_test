module NativeTypeError where

open import Agda.Builtin.Bool
open import Agda.Builtin.IO
open import Agda.Builtin.Unit

postulate main : IO ⊤

bad : Bool
bad = true false

