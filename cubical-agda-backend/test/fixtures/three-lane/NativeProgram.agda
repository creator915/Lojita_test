module NativeProgram where

open import Agda.Builtin.IO
open import Agda.Builtin.Nat
open import Agda.Builtin.String
open import Agda.Builtin.Unit

postulate putStrLn : String -> IO ⊤

{-# FOREIGN GHC import qualified Data.Text.IO as Text #-}
{-# COMPILE GHC putStrLn = Text.putStrLn #-}

analysis : Nat
analysis = 42

main : IO ⊤
main = putStrLn "three-lane-native-42"
