{-# OPTIONS --cubical=erased --erasure #-}

module NativeErasedCubical where

open import Agda.Builtin.Cubical.Path
open import Agda.Builtin.IO
open import Agda.Builtin.String
open import Agda.Builtin.Unit

postulate putStrLn : String -> IO ⊤

{-# FOREIGN GHC import qualified Data.Text.IO as Text #-}
{-# COMPILE GHC putStrLn = Text.putStrLn #-}

@0 erasedPath : PathP (λ _ → String) "erased" "erased"
erasedPath i = "erased"

identity : {A : Set} -> A -> A
identity x = x

main : IO ⊤
main = putStrLn (identity "goal1-erased-cubical-42")
