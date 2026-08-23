module Main (main) where

import Agda.Main (runAgda)
import CubicalChez.Backend (chezBackend)

main :: IO ()
main = runAgda [chezBackend]
