module RuntimeNbeFinal where

open import Agda.Builtin.IO
open import Agda.Builtin.Unit

postulate runLinkedRuntimeNbe : IO ⊤

{-# FOREIGN GHC import qualified Cubical.Runtime.Nbe.Embedded as RuntimeNbe #-}
{-# COMPILE GHC runLinkedRuntimeNbe = RuntimeNbe.runEmbedded #-}

main : IO ⊤
main = runLinkedRuntimeNbe
