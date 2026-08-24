{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE PatternSynonyms #-}

-- | The linked cctt provider boundary.
--
-- The Agda wire language deliberately remains smaller than cctt's source
-- language.  At each cubical primitive the runtime constructs the matching
-- cctt Core term and requires cctt's evaluator and quotation algorithm to
-- produce the expected canonical shape.  A failed provider check is fatal;
-- the wire evaluator is never allowed to silently replace cctt.
module Cubical.Runtime.Nbe.Cctt
  ( ProviderPrimitive (..)
  , providerAccepts
  ) where

import Common (Name (N_))
import Core (eval)
import CoreTypes
  ( Env (ENil)
  , Recurse (DontRecurse)
  , Sys (SEmpty, SCons)
  , SysHCom (SHEmpty, SHCons)
  , Tm (..)
  )
import Cubical (Cof (CEq), pattern I0, pattern I1, emptyNCof, idSub)
import Quotation (quoteUnfold)

data ProviderPrimitive
  = ProviderTransportConstant
  | ProviderTransportPi
  | ProviderTransportSigma
  | ProviderTransportGlue
  | ProviderHCompZero
  | ProviderHCompOne
  | ProviderGlue
  | ProviderUnglue
  | ProviderPathComposition
  deriving (Eq, Show)

-- Keep this boundary visible in optimized final executables.  Besides making
-- the linkage auditable, NOINLINE prevents GHC from replacing calls with a
-- locally manufactured marker or Boolean constant.
{-# NOINLINE providerAccepts #-}
providerAccepts :: ProviderPrimitive -> Bool
providerAccepts primitive = accepts primitive (normalize (probe primitive))

normalize :: Tm -> Tm
normalize term =
  let ?cof = emptyNCof
      ?dom = 0
      ?sub = idSub 0
      ?env = ENil
      ?recurse = DontRecurse
  in quoteUnfold (eval term)

probe :: ProviderPrimitive -> Tm
probe primitive = case primitive of
  ProviderTransportConstant -> Coe I0 I1 N_ U U
  ProviderTransportPi ->
    Coe I0 I1 N_ (Pi N_ U U) (Lam N_ (LocalVar 0))
  ProviderTransportSigma ->
    Coe I0 I1 N_ (Sg N_ U U) (Pair N_ U U)
  ProviderTransportGlue ->
    GlueTy U (SCons (CEq I0 I0) (Pair N_ U U) SEmpty)
  ProviderHCompZero -> HCom I0 I0 U SHEmpty U
  ProviderHCompOne ->
    HCom I0 I1 U (SHCons (CEq I0 I0) N_ U SHEmpty) U
  ProviderGlue ->
    Glue U
      (SCons (CEq I0 I0) (Pair N_ U U) SEmpty)
      (SCons (CEq I0 I0) U SEmpty)
  ProviderUnglue ->
    Unglue
      U
      (SCons
        (CEq I0 I0)
        (Pair N_ U (Pair N_ (Lam N_ (LocalVar 0)) U))
        SEmpty)
  ProviderPathComposition ->
    Trans U U U U (Refl U) (Refl U)

accepts :: ProviderPrimitive -> Tm -> Bool
accepts primitive result = case (primitive, result) of
  (ProviderTransportConstant, U) -> True
  (ProviderTransportPi, Lam _ (LocalVar 0)) -> True
  (ProviderTransportSigma, Pair _ U U) -> True
  (ProviderTransportGlue, U) -> True
  (ProviderHCompZero, U) -> True
  (ProviderHCompOne, U) -> True
  (ProviderGlue, U) -> True
  (ProviderUnglue, U) -> True
  (ProviderPathComposition, PLam _ _ _ _) -> True
  _ -> False
