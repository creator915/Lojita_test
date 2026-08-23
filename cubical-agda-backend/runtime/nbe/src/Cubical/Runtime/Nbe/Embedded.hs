-- | Entry point called from a Stock Agda/MAlonzo-generated user program.
-- It invokes the linked evaluator as an ordinary library in the same process.
module Cubical.Runtime.Nbe.Embedded (runEmbedded) where

import Cubical.Runtime.Nbe
import Control.Exception (evaluate)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (IOMode(ReadMode), hGetContents, withFile)

runEmbedded :: IO ()
runEmbedded = do
  arguments <- getArgs
  case arguments of
    [expectedContext, packetFile] -> do
      let byteLimit = limitPacketBytes defaultLimits
      bytes <- withFile packetFile ReadMode $ \handle -> do
        contents <- hGetContents handle
        let bounded = take (byteLimit + 1) contents
        _ <- evaluate $ length bounded
        pure bounded
      if length bytes > byteLimit
        then finish $ RuntimeFailed $ RuntimeError
          "CCZ-RUNTIME-NBE-PACKET-LIMIT" "packet exceeds compiled byte limit"
        else do
          case decodePacket defaultLimits bytes of
            Left failure -> finish $ RuntimeFailed failure
            Right packet -> finish $ runPacket defaultLimits expectedContext packet
    _ -> do
      putStrLn "ERROR\tCCZ-RUNTIME-NBE-USAGE\texpected CONTEXT PACKET"
      exitFailure
  where
    finish response = do
      putStrLn $ renderResponse response
      case response of
        RuntimeOk{} -> pure ()
        RuntimeFailed{} -> exitFailure
