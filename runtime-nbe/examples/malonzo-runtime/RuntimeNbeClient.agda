{-# OPTIONS --cubical-compatible --level-universe #-}

module RuntimeNbeClient where

open import Agda.Builtin.IO using (IO)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.String using (String)
open import Agda.Builtin.Unit using (⊤)

infixl 1 _>>=_

postulate
  getArgs : IO (List String)
  putStrLn : String → IO ⊤
  die : String → IO ⊤
  normalizeCheckedRuntimePacket : String → String → IO String
  _>>=_ : {A B : Set} → IO A → (A → IO B) → IO B

{-# FOREIGN GHC import qualified Data.Text.IO as Text #-}
{-# FOREIGN GHC import qualified System.Environment as Environment #-}
{-# FOREIGN GHC import qualified System.Exit as Exit #-}
{-# FOREIGN GHC import qualified System.IO as IO #-}
{-# FOREIGN GHC import qualified RuntimeNbe.MAlonzoRuntime as Runtime #-}
{-# COMPILE GHC getArgs = fmap (map Data.Text.pack) Environment.getArgs #-}
{-# COMPILE GHC putStrLn = Text.putStrLn #-}
{-# COMPILE GHC die = \message -> Text.hPutStrLn IO.stderr message >> Exit.exitFailure #-}
{-# COMPILE GHC normalizeCheckedRuntimePacket = Runtime.normalizeCheckedRuntimePacket #-}
{-# COMPILE GHC _>>=_ = \_ _ -> (>>=) #-}

printResult : String → String → IO ⊤
printResult packet checked =
  normalizeCheckedRuntimePacket packet checked >>= putStrLn

dispatch : List String → IO ⊤
dispatch (packet ∷ checked ∷ []) = printResult packet checked
dispatch _ = die "usage: runtime-nbe-client PACKET.ir CHECKED.result"

main : IO ⊤
main = getArgs >>= dispatch
