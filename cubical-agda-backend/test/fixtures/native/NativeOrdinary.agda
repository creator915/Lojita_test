module NativeOrdinary where

open import Agda.Builtin.IO
open import Agda.Builtin.String
open import Agda.Builtin.Unit

postulate putStrLn : String -> IO ⊤

{-# FOREIGN GHC import qualified Data.Text.IO as Text #-}
{-# COMPILE GHC putStrLn = Text.putStrLn #-}

identity : {A : Set} -> A -> A
identity x = x

main : IO ⊤
main = putStrLn (identity "goal1-native-42")

