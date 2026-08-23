module Main (main) where

import Cubical.Runtime.Nbe
import Data.List (stripPrefix)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (IOMode (ReadMode), hFileSize, withFile)
import Text.Read (readMaybe)

main :: IO ()
main = do
  arguments <- getArgs
  case parseArguments arguments of
    Left message -> putStrLn ("ERROR\tCCZ-RUNTIME-NBE-USAGE\t" ++ message) >> exitWith (ExitFailure 64)
    Right (limits, context, packetFile) -> do
      packetSize <- withFile packetFile ReadMode hFileSize
      if packetSize > fromIntegral (limitPacketBytes limits)
        then emit (RuntimeFailed (RuntimeError "CCZ-RUNTIME-NBE-PACKET-LIMIT" "packet exceeds configured byte limit"))
        else do
          bytes <- readFile packetFile
          case decodePacket limits bytes of
            Left failure -> emit (RuntimeFailed failure)
            Right packet -> emit (runPacket limits context packet)

emit :: Response -> IO ()
emit response = do
  putStrLn (renderResponse response)
  case response of
    RuntimeOk {} -> pure ()
    RuntimeFailed {} -> exitWith (ExitFailure 65)

parseArguments :: [String] -> Either String (Limits, String, FilePath)
parseArguments = go defaultLimits
  where
    go limits [context, packetFile] = Right (limits, context, packetFile)
    go limits (argument : rest)
      | Just raw <- stripPrefix "--fuel=" argument = bounded "fuel" raw (limitFuel defaultLimits)
          (\value -> limits { limitFuel = value }) rest
      | Just raw <- stripPrefix "--allocations=" argument = bounded "allocations" raw (limitAllocations defaultLimits)
          (\value -> limits { limitAllocations = value }) rest
      | Just raw <- stripPrefix "--packet-bytes=" argument = bounded "packet-bytes" raw (limitPacketBytes defaultLimits)
          (\value -> limits { limitPacketBytes = value }) rest
    go _ _ = Left "usage: cubical-runtime-nbe [--fuel=N] [--allocations=N] [--packet-bytes=N] CONTEXT PACKET"

    bounded label raw maximumValue update rest = case readMaybe raw of
      Just value | value > 0 && value <= maximumValue -> go (update value) rest
      _ -> Left (label ++ " must be in 1.." ++ show maximumValue)
