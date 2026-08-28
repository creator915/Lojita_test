{-# LANGUAGE TemplateHaskell #-}

module RuntimeNbe.EmbeddedPolicy
  ( preserveDisabledIr
  , preserveEnabledIr
  ) where

import Language.Haskell.TH.Syntax (lift, runIO)


preserveDisabledIr :: String
preserveDisabledIr = $(runIO (readFile "embedded/preserve-disabled.ir") >>= lift)

preserveEnabledIr :: String
preserveEnabledIr = $(runIO (readFile "embedded/preserve-enabled.ir") >>= lift)
