module RuntimeNbe.CleanOutput (cleanRequestedOutput) where

import Control.Monad (when)
import Data.List (stripPrefix)
import System.Directory (doesFileExist, removeFile)
import System.Environment (getArgs)


-- Agda can reject source before a backend's preCompile hook.  Remove only the
-- explicitly requested result file before entering Agda so early parse/type
-- failures cannot leave a stale success artifact.
cleanRequestedOutput :: IO ()
cleanRequestedOutput = do
  arguments <- getArgs
  case outputArgument arguments of
    Nothing -> pure ()
    Just path -> do
      exists <- doesFileExist path
      when exists (removeFile path)

outputArgument :: [String] -> Maybe FilePath
outputArgument [] = Nothing
outputArgument (argument : rest) = case
  stripPrefix "--runtime-nbe-output=" argument of
    Just path | not (null path) -> Just path
    _ | argument == "--runtime-nbe-output" -> case rest of
          path : _ | not (null path) -> Just path
          _ -> Nothing
      | otherwise -> outputArgument rest
