module Main (main) where

import Cubical.Runtime.Nbe.Cctt
import Control.Monad (forM_, unless)
import System.Exit (die)

primitives :: [ProviderPrimitive]
primitives =
  [ ProviderTransportConstant
  , ProviderTransportPi
  , ProviderTransportSigma
  , ProviderTransportGlue
  , ProviderHCompZero
  , ProviderHCompOne
  , ProviderGlue
  , ProviderUnglue
  , ProviderPathComposition
  ]

main :: IO ()
main = do
  forM_ primitives $ \primitive ->
    unless (providerAccepts primitive)
      (die ("cctt provider rejected " ++ show primitive))
  putStrLn ("CcttProvider PASS (" ++ show (length primitives) ++ ")")
