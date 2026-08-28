module Main (main) where

import qualified Data.ByteString.Char8 as ByteString
import System.Environment (getArgs)
import System.Exit (die)
import System.IO (hPutStrLn, stderr)

import RuntimeNbe.CcttProvider
  ( normalizeRuntimeIrBytes, providerName, providerRevision )
import RuntimeNbe.EmbeddedPolicy
  ( preserveDisabledIr, preserveEnabledIr )


main :: IO ()
main = do
  arguments <- getArgs
  embedded <- case arguments of
    ["disabled"] -> pure preserveDisabledIr
    ["enabled"] -> pure preserveEnabledIr
    _ -> die "usage: runtime-policy-user disabled|enabled"
  result <- normalizeRuntimeIrBytes (ByteString.pack embedded)
  case result of
    Left failure -> die ("CCNBE-USER-REJECT: " ++ show failure)
    Right normalForm -> do
      hPutStrLn stderr ("provider=" ++ providerName)
      hPutStrLn stderr ("revision=" ++ providerRevision)
      hPutStrLn stderr "input=compile-time-embedded-agda-runtime-ir"
      putStrLn normalForm
