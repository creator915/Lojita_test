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
    Right (observation, limits, context, packetFile) -> do
      packetSize <- withFile packetFile ReadMode hFileSize
      if packetSize > fromIntegral (limitPacketBytes limits)
        then emit observation (RuntimeFailed (RuntimeError "CCZ-RUNTIME-NBE-PACKET-LIMIT" "packet exceeds configured byte limit"))
        else do
          bytes <- readFile packetFile
          case decodePacket limits bytes of
            Left failure -> emit observation (RuntimeFailed failure)
            Right packet -> emit observation (runPacket limits context packet)

emit :: Bool -> Response -> IO ()
emit observation response = do
  case (observation, response) of
    (True, RuntimeOk term ty _) -> case renderObservation term ty of
      Left failure -> putStrLn (renderResponse (RuntimeFailed failure)) >> exitWith (ExitFailure 65)
      Right value -> putStrLn value
    _ -> putStrLn (renderResponse response)
  case response of
    RuntimeOk {} -> pure ()
    RuntimeFailed {} -> exitWith (ExitFailure 65)

parseArguments :: [String] -> Either String (Bool, Limits, String, FilePath)
parseArguments = go False defaultLimits
  where
    go observation limits [context, packetFile] = Right (observation, limits, context, packetFile)
    go _ limits ("--observation" : rest) = go True limits rest
    go observation limits (argument : rest)
      | Just raw <- stripPrefix "--fuel=" argument = bounded "fuel" raw (limitFuel defaultLimits)
          observation (\value -> limits { limitFuel = value }) rest
      | Just raw <- stripPrefix "--allocations=" argument = bounded "allocations" raw (limitAllocations defaultLimits)
          observation (\value -> limits { limitAllocations = value }) rest
      | Just raw <- stripPrefix "--packet-bytes=" argument = bounded "packet-bytes" raw (limitPacketBytes defaultLimits)
          observation (\value -> limits { limitPacketBytes = value }) rest
    go _ _ _ = Left "usage: cubical-runtime-nbe [--observation] [--fuel=N] [--allocations=N] [--packet-bytes=N] CONTEXT PACKET"

    bounded label raw maximumValue observation update rest = case readMaybe raw of
      Just value | value > 0 && value <= maximumValue -> go observation (update value) rest
      _ -> Left (label ++ " must be in 1.." ++ show maximumValue)
