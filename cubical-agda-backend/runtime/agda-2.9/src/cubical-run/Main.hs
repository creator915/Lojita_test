-- | Standalone entry point which adds the Cubical runtime backend to Agda.
-- Runtime v2 also exposes typed eta-long read-back and cross-process Term
-- packets; all implementation remains in the backend module.
module Main (main) where

import Prelude (IO)

import Agda.Main (runAgda)
import Agda.TypeChecking.Primitive.Cubical.Runtime
  (cubicalRuntimeBackend)

main :: IO ()
main = runAgda [cubicalRuntimeBackend]
