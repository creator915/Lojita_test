module ApprovalMain where

open import Agda.Builtin.IO using (IO)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.String using (String)
open import Agda.Builtin.Unit using (⊤)
open import Approval.Proofs
open import Approval.Render
open import Approval.Scenarios

infixl 1 _>>=_

postulate
  getArgs : IO (List String)
  putStrLn : String → IO ⊤
  die : String → IO ⊤
  _>>=_ : {A B : Set} → IO A → (A → IO B) → IO B

{-# FOREIGN GHC import qualified Data.Text.IO as Text #-}
{-# FOREIGN GHC import qualified System.Environment as Environment #-}
{-# FOREIGN GHC import qualified System.Exit as Exit #-}
{-# FOREIGN GHC import qualified System.IO as IO #-}
{-# COMPILE GHC getArgs = fmap (map Data.Text.pack) Environment.getArgs #-}
{-# COMPILE GHC putStrLn = Text.putStrLn #-}
{-# COMPILE GHC die = \message -> Text.hPutStrLn IO.stderr message >> Exit.exitFailure #-}
{-# COMPILE GHC _>>=_ = \_ _ -> (>>=) #-}

dispatch : List String → IO ⊤
dispatch ("small" ∷ []) = putStrLn (renderReport "small" small)
dispatch ("medium" ∷ []) = putStrLn (renderReport "medium" medium)
dispatch ("large" ∷ []) = putStrLn (renderReport "large" large)
dispatch ("reject" ∷ []) = putStrLn (renderReport "reject" rejectedRequest)
dispatch ("unauthorized" ∷ []) = putStrLn (renderReport "unauthorized" unauthorised)
dispatch ("self-approval" ∷ []) = putStrLn (renderReport "self-approval" selfApprovalAttempt)
dispatch ("invalid-order" ∷ []) = putStrLn (renderReport "invalid-order" invalidOrder)
dispatch _ = die "usage: approval-workflow small|medium|large|reject|unauthorized|self-approval|invalid-order"

main : IO ⊤
main = getArgs >>= dispatch
