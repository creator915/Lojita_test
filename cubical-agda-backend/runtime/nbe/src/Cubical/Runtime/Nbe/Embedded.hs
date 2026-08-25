-- | Entry point called from a Stock Agda/MAlonzo-generated user program.
-- It invokes the linked evaluator as an ordinary library in the same process.
module Cubical.Runtime.Nbe.Embedded (runEmbedded) where

import Cubical.Runtime.Nbe
import Control.Exception (evaluate)
import Data.List (stripPrefix)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (IOMode(ReadMode), hFileSize, hGetContents, withFile)
import Text.Read (readMaybe)

runEmbedded :: IO ()
runEmbedded = do
  arguments <- getArgs
  case parseArguments arguments of
    Right (limits, expectedContext, packetFile) -> do
      packetSize <- withFile packetFile ReadMode hFileSize
      if packetSize > fromIntegral (limitPacketBytes limits)
        then finish $ RuntimeFailed $ RuntimeError
          "CCZ-RUNTIME-NBE-PACKET-LIMIT" "packet exceeds configured byte limit"
        else do
          bytes <- withFile packetFile ReadMode $ \handle -> do
            contents <- hGetContents handle
            _ <- evaluate $ length contents
            pure contents
          case decodePacket limits bytes of
            Left failure -> finish $ RuntimeFailed failure
            Right packet -> finish $ runPacket limits expectedContext packet
    Left message -> do
      putStrLn $ "ERROR\tCCZ-RUNTIME-NBE-USAGE\t" ++ message
      exitFailure
  where
    finish response = do
      putStrLn $ renderResponse response
      case response of
        RuntimeOk{} -> pure ()
        RuntimeFailed{} -> exitFailure

parseArguments :: [String] -> Either String (Limits, String, FilePath)
parseArguments = go defaultLimits
  where
    go limits [context, packetFile] = Right (limits, context, packetFile)
    go limits (argument : rest)
      | Just raw <- stripPrefix "--fuel=" argument =
          bounded "fuel" raw (limitFuel defaultLimits)
            (\value -> limits { limitFuel = value }) rest
      | Just raw <- stripPrefix "--allocations=" argument =
          bounded "allocations" raw (limitAllocations defaultLimits)
            (\value -> limits { limitAllocations = value }) rest
      | Just raw <- stripPrefix "--packet-bytes=" argument =
          bounded "packet-bytes" raw (limitPacketBytes defaultLimits)
            (\value -> limits { limitPacketBytes = value }) rest
    go _ _ = Left "expected [--fuel=N] [--allocations=N] [--packet-bytes=N] CONTEXT PACKET"

    bounded label raw maximumValue update rest = case readMaybe raw of
      Just value | value > 0 && value <= maximumValue -> go (update value) rest
      _ -> Left $ label ++ " must be in 1.." ++ show maximumValue
