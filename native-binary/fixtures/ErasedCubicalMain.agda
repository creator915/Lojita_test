{-# OPTIONS --erased-cubical --erasure #-}
module ErasedCubicalMain where

open import Agda.Builtin.Cubical.Path
open import Agda.Builtin.IO
open import Agda.Builtin.Nat
open import Agda.Builtin.String
open import Agda.Builtin.Unit

@0 erasedPath : 2 ≡ 2
erasedPath _ = 2

postulate putStrLn : String → IO ⊤

{-# FOREIGN GHC import qualified Data.Text.IO as Text #-}
{-# COMPILE GHC putStrLn = Text.putStrLn #-}

main : IO ⊤
main = putStrLn "erased-cubical-ok"
