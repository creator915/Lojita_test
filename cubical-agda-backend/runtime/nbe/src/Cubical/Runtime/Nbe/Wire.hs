{-# LANGUAGE DeriveGeneric #-}

-- | Compiler/runtime narrow waist.  This module deliberately has no Agda
-- dependency: the checked Agda producer translates Internal syntax into these
-- immutable values, while the final user program only needs this wire model.
module Cubical.Runtime.Nbe.Wire
  ( Ty (..)
  , Equiv (..)
  , Family (..)
  , Face (..)
  , Term (..)
  , Definition (..)
  , Request (..)
  , Packet (..)
  , abiVersion
  , providerIdentity
  , packetMagic
  , encodePacket
  ) where

import GHC.Generics (Generic)

abiVersion :: String
abiVersion = "runtime-nbe-abi-v1"

providerIdentity :: String
providerIdentity = "cctt-core-runtime-v1@ba16f3758a322e9be77ada1da2b93f45d500192e"

packetMagic :: String
packetMagic = "CCZ-RUNTIME-NBE\t1\n"

encodePacket :: Packet -> String
encodePacket packet = packetMagic ++ show packet ++ "\n"

data Ty
  = TyUniverse
  | TyBool
  | TyNat
  | TyInt
  | TyS1
  | TyVec Ty Int
  | TyPi Ty Ty
  | TySigma Ty Ty
  | TyPath Ty Term Term
  deriving (Eq, Read, Show, Generic)

data Equiv
  = EquivIdentity Ty
  | EquivBoolNot
  | EquivIntSucc
  | EquivCompose Equiv Equiv
  | EquivInverse Equiv
  deriving (Eq, Read, Show, Generic)

data Family
  = FamilyConst Ty
  | FamilyGlue Equiv
  | FamilyVec Family Int
  | FamilyPi Family Family
  | FamilySigma Family Family
  | FamilyCompose Family Family
  deriving (Eq, Read, Show, Generic)

data Face = FaceZero | FaceOne
  deriving (Eq, Read, Show, Generic)

data Term
  = Var Int
  | Def String
  | Lam Ty Term
  | App Term Term
  | Type Ty
  | BoolLit Bool
  | NatLit Integer
  | IntLit Integer
  | VecLit Ty [Term]
  | Pair Term Term
  | Not Term
  | IntSucc Term
  | IntPred Term
  | TypePath Family
  | Transp Term Term
  | Refl Ty Term
  | Concat Term Term
  | S1Base
  | Loop
  | Winding Term
  | HComp Ty Face Term Term
  | Glue Equiv Term
  | Unglue Equiv Term
  deriving (Eq, Read, Show, Generic)

data Definition = Definition
  { definitionName :: String
  , definitionType :: Ty
  , definitionTerm :: Term
  } deriving (Eq, Read, Show, Generic)

data Request = Request
  { requestTerm :: Term
  , requestType :: Ty
  , requestDefinitions :: [Definition]
  } deriving (Eq, Read, Show, Generic)

data Packet = Packet
  { packetAbi :: String
  , packetProvider :: String
  , packetContext :: String
  , packetRequest :: Request
  } deriving (Eq, Read, Show, Generic)
