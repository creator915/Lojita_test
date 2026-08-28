module Main (main) where

import System.Environment (getArgs)
import System.Exit (die)
import System.IO (hPutStrLn, stderr)
import qualified Data.ByteString as ByteString

import RuntimeNbe.CcttProvider
  ( normalizeCheckedDefinition, normalizeRuntimeIr, providerEvalQuoteAudit
  , providerName, providerRevision )
import RuntimeNbe.PacketDigest (packetSha256Hex)


main :: IO ()
main = do
  arguments <- getArgs
  case arguments of
    ["--identity"] -> do
      putStrLn ("provider=" ++ providerName)
      putStrLn ("revision=" ++ providerRevision)
    ["--audit-eval-quote"] -> do
      status <- providerEvalQuoteAudit
      if status == 0
        then putStrLn "provider-eval-quote=ok"
        else die "CCNBE-PROVIDER-AUDIT-FAILED"
    ["--packet-sha256", packet] ->
      putStrLn . packetSha256Hex =<< ByteString.readFile packet
    ["--runtime-ir", runtimeIr] -> do
      result <- normalizeRuntimeIr runtimeIr
      case result of
        Left failure -> die ("CCNBE-PROVIDER-REJECT: " ++ show failure)
        Right normalForm -> do
          hPutStrLn stderr ("provider=" ++ providerName)
          hPutStrLn stderr ("revision=" ++ providerRevision)
          hPutStrLn stderr "input=agda-runtime-ir-v1"
          putStrLn normalForm
    [source, definition] -> do
      result <- normalizeCheckedDefinition source definition
      case result of
        Left failure -> die ("CCNBE-PROVIDER-REJECT: " ++ show failure)
        Right normalForm -> do
          hPutStrLn stderr ("provider=" ++ providerName)
          hPutStrLn stderr ("revision=" ++ providerRevision)
          hPutStrLn stderr ("definition=" ++ definition)
          putStrLn normalForm
    _ -> die "usage: runtime-nbe-provider SOURCE.cctt DEFINITION | --runtime-ir FILE | --identity | --audit-eval-quote | --packet-sha256 FILE"
