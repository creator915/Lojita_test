module Main (main) where

import Agda.Main (runAgda)
import Prelude (IO, (>>))
import RuntimeNbe.AgdaProducer (runtimeNbeProducerBackend)
import RuntimeNbe.CleanOutput (cleanRequestedOutput)

main :: IO ()
main = cleanRequestedOutput >> runAgda [runtimeNbeProducerBackend]
