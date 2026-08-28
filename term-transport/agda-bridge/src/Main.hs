module Main (main) where

import Agda.Main (runAgda)
import Prelude (IO)
import TermTransport.Bridge (termTransportBackend)

main :: IO ()
main = runAgda [termTransportBackend]
