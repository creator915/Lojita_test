module Main (main) where

import Agda.Main (runAgda)
import Prelude (IO, (>>))
import RuntimeNbe.Integrated (runtimeNbeIntegratedBackend)
import RuntimeNbe.CleanOutput (cleanRequestedOutput)


main :: IO ()
main = cleanRequestedOutput >> runAgda [runtimeNbeIntegratedBackend]
