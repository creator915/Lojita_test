module Main (main) where

import Agda.Main (runAgda)
import Prelude (IO, (>>))
import RuntimeNbe.AgdaOracle (runtimeNbeOracleBackend)
import RuntimeNbe.CleanOutput (cleanRequestedOutput)

main :: IO ()
main = cleanRequestedOutput >> runAgda [runtimeNbeOracleBackend]
