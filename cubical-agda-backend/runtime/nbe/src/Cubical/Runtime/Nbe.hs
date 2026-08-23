{-# LANGUAGE DeriveGeneric #-}

-- | A closed, typed runtime NbE core for the audited Goal 3 fragment.
--
-- The semantic architecture (syntax -> environments/closures -> values ->
-- type-directed quotation) follows the evaluator/quotation split audited in
-- AndrasKovacs/cctt at ba16f3758a322e9be77ada1da2b93f45d500192e.
-- This module is an Agda-specific ABI adapter, not a copy of cctt's language.
module Cubical.Runtime.Nbe
  ( Ty (..)
  , Equiv (..)
  , Family (..)
  , Face (..)
  , Term (..)
  , Definition (..)
  , Request (..)
  , Packet (..)
  , Limits (..)
  , Stats (..)
  , RuntimeError (..)
  , Response (..)
  , abiVersion
  , providerIdentity
  , defaultLimits
  , encodePacket
  , decodePacket
  , runPacket
  , renderResponse
  ) where

import Control.Monad (unless, when)
import Data.Char (isAlphaNum)
import Data.List (find, intercalate, nub)
import GHC.Generics (Generic)
import Text.Read (readMaybe)

abiVersion :: String
abiVersion = "runtime-nbe-abi-v1"

-- Kept live in the final executable so binary/link audits can prove that the
-- runtime library, rather than an external helper, supplied the evaluator.
providerIdentity :: String
providerIdentity = "cctt-informed-agda-runtime-v1@ba16f3758a322e9be77ada1da2b93f45d500192e"

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

-- | A closed line of types. The current ABI deliberately admits only the
-- constructors for which both endpoint typing and transport are implemented.
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

data Limits = Limits
  { limitPacketBytes :: Int
  , limitFuel :: Int
  , limitAllocations :: Int
  } deriving (Eq, Read, Show, Generic)

defaultLimits :: Limits
defaultLimits = Limits
  { limitPacketBytes = 1024 * 1024
  , limitFuel = 200000
  , limitAllocations = 200000
  }

data Stats = Stats
  { statsSteps :: Int
  , statsAllocations :: Int
  , statsDefinitionLookups :: Int
  , statsCacheHits :: Int
  , statsTransports :: Int
  , statsHComps :: Int
  } deriving (Eq, Read, Show, Generic)

data RuntimeError = RuntimeError
  { runtimeErrorCode :: String
  , runtimeErrorDetail :: String
  } deriving (Eq, Read, Show, Generic)

data Response
  = RuntimeOk Term Ty Stats
  | RuntimeFailed RuntimeError
  deriving (Eq, Read, Show, Generic)

packetMagic :: String
packetMagic = "CCZ-RUNTIME-NBE\t1\n"

encodePacket :: Packet -> String
encodePacket packet = packetMagic ++ show packet ++ "\n"

decodePacket :: Limits -> String -> Either RuntimeError Packet
decodePacket limits bytes
  | length bytes > limitPacketBytes limits =
      Left (err "CCZ-RUNTIME-NBE-PACKET-LIMIT" "packet exceeds configured byte limit")
  | otherwise = case stripPrefix packetMagic bytes of
      Nothing -> Left (err "CCZ-RUNTIME-NBE-BAD-MAGIC" "missing runtime packet magic/version")
      Just body -> case readMaybe body of
        Nothing -> Left (err "CCZ-RUNTIME-NBE-MALFORMED" "packet body is not a canonical Packet value")
        Just packet -> Right packet

renderResponse :: Response -> String
renderResponse response = case response of
  RuntimeOk term ty stats -> intercalate "\t"
    [ "OK", show term, show ty, renderStats stats, providerIdentity ]
  RuntimeFailed failure -> intercalate "\t"
    [ "ERROR", runtimeErrorCode failure, runtimeErrorDetail failure, providerIdentity ]

renderStats :: Stats -> String
renderStats stats = intercalate ","
  [ "steps=" ++ show (statsSteps stats)
  , "allocations=" ++ show (statsAllocations stats)
  , "definition-lookups=" ++ show (statsDefinitionLookups stats)
  , "cache-hits=" ++ show (statsCacheHits stats)
  , "transports=" ++ show (statsTransports stats)
  , "hcomps=" ++ show (statsHComps stats)
  ]

runPacket :: Limits -> String -> Packet -> Response
runPacket limits expectedContext packet
  | packetAbi packet /= abiVersion = failed "CCZ-RUNTIME-NBE-ABI-MISMATCH" "runtime ABI version mismatch"
  | packetProvider packet /= providerIdentity = failed "CCZ-RUNTIME-NBE-PROVIDER-MISMATCH" "runtime provider identity mismatch"
  | not (validContext expectedContext) = failed "CCZ-RUNTIME-NBE-CONTEXT-INVALID" "compiled context identity is not canonical"
  | packetContext packet /= expectedContext = failed "CCZ-RUNTIME-NBE-CONTEXT-MISMATCH" "packet context does not match final executable"
  | otherwise =
      let request = packetRequest packet
          definitions = requestDefinitions request
          initial = RuntimeState
            { stateFuel = limitFuel limits
            , stateInitialFuel = limitFuel limits
            , stateAllocations = 0
            , stateAllocationLimit = limitAllocations limits
            , stateDefinitions = definitions
            , stateCache = []
            , stateActive = []
            , stateDefinitionLookups = 0
            , stateCacheHits = 0
            , stateTransports = 0
            , stateHComps = 0
            }
      in case validateRequest request of
          Left failure -> RuntimeFailed failure
          Right () -> case runNbe (normalize request) initial of
            Left failure -> RuntimeFailed failure
            Right ((term, ty), finalState) -> RuntimeOk term ty (stateStats finalState)
  where
    failed code detail = RuntimeFailed (err code detail)

validContext :: String -> Bool
validContext context =
  length context >= 16 && length context <= 128 && all valid context
  where
    valid c = isAlphaNum c || c == '-' || c == '_' || c == ':' || c == '.'

validateRequest :: Request -> Either RuntimeError ()
validateRequest request = do
  let definitions = requestDefinitions request
      names = map definitionName definitions
  when (length names /= length (nub names))
    (Left (err "CCZ-RUNTIME-NBE-DEFINITION-DUPLICATE" "definition slice contains duplicate names"))
  unless (all validDefinitionName names)
    (Left (err "CCZ-RUNTIME-NBE-DEFINITION-NAME" "definition slice contains an invalid name"))
  mapM_ (validateDefinition definitions) definitions
  inferred <- infer definitions [] (requestTerm request)
  unless (inferred == requestType request)
    (Left (err "CCZ-RUNTIME-NBE-TYPE-MISMATCH"
      ("request term has type " ++ show inferred ++ ", expected " ++ show (requestType request))))
  where
    validDefinitionName name = not (null name) && length name <= 128 && all valid name
    valid c = isAlphaNum c || c == '.' || c == '_' || c == '-'

validateDefinition :: [Definition] -> Definition -> Either RuntimeError ()
validateDefinition definitions definition = do
  inferred <- infer definitions [] (definitionTerm definition)
  unless (inferred == definitionType definition)
    (Left (err "CCZ-RUNTIME-NBE-DEFINITION-TYPE"
      ("definition " ++ definitionName definition ++ " has type " ++ show inferred)))

infer :: [Definition] -> [Ty] -> Term -> Either RuntimeError Ty
infer definitions context term = case term of
  Var index -> case drop index context of
    ty : _ -> Right ty
    [] -> Left (err "CCZ-RUNTIME-NBE-OPEN-TERM" ("unbound de Bruijn index " ++ show index))
  Def name -> case find ((== name) . definitionName) definitions of
    Nothing -> Left (err "CCZ-RUNTIME-NBE-DEFINITION-MISSING" ("missing closed definition " ++ name))
    Just definition -> Right (definitionType definition)
  Lam domain body -> TyPi domain <$> infer definitions (domain : context) body
  App fun argument -> do
    funTy <- infer definitions context fun
    case funTy of
      TyPi domain codomain -> check definitions context argument domain >> Right codomain
      _ -> Left (err "CCZ-RUNTIME-NBE-NOT-A-FUNCTION" ("application head has type " ++ show funTy))
  Type _ -> Right TyUniverse
  BoolLit _ -> Right TyBool
  NatLit n | n >= 0 -> Right TyNat
  NatLit _ -> Left (err "CCZ-RUNTIME-NBE-NAT-NEGATIVE" "Nat literal is negative")
  IntLit _ -> Right TyInt
  VecLit elementTy elements -> do
    mapM_ (\element -> check definitions context element elementTy) elements
    Right (TyVec elementTy (length elements))
  Pair first second -> TySigma <$> infer definitions context first <*> infer definitions context second
  Not value -> check definitions context value TyBool >> Right TyBool
  IntSucc value -> check definitions context value TyInt >> Right TyInt
  IntPred value -> check definitions context value TyInt >> Right TyInt
  TypePath family -> do
    (source, target) <- familyEndpoints family
    Right (TyPath TyUniverse (Type source) (Type target))
  Transp path value -> do
    pathTy <- infer definitions context path
    case pathTy of
      TyPath TyUniverse (Type source) (Type target) ->
        check definitions context value source >> Right target
      _ -> Left (err "CCZ-RUNTIME-NBE-TRANSP-PATH" "transp requires a closed path in the universe")
  Refl ty value -> check definitions context value ty >> Right (TyPath ty value value)
  Concat left right -> do
    leftTy <- infer definitions context left
    rightTy <- infer definitions context right
    case (leftTy, rightTy) of
      (TyPath ty l m, TyPath ty' m' r)
        | ty == ty' && m == m' -> Right (TyPath ty l r)
      _ -> Left (err "CCZ-RUNTIME-NBE-PATH-COMPOSE" "path endpoints do not compose")
  Loop -> Right (TyPath TyS1 S1Base S1Base)
  Winding path -> do
    pathTy <- infer definitions context path
    unless (pathTy == TyPath TyS1 S1Base S1Base)
      (Left (err "CCZ-RUNTIME-NBE-HIT-PATH" "winding requires a loop at S1.base"))
    Right TyInt
  HComp ty _ system base -> do
    check definitions context system ty
    check definitions context base ty
    Right ty
  Glue equivalence value -> do
    let (source, target) = equivalenceEndpoints equivalence
    check definitions context value source
    Right target
  Unglue equivalence value -> do
    let (_, target) = equivalenceEndpoints equivalence
    check definitions context value target
    Right target
  S1Base -> Right TyS1

check :: [Definition] -> [Ty] -> Term -> Ty -> Either RuntimeError ()
check definitions context term expected = do
  actual <- infer definitions context term
  unless (actual == expected)
    (Left (err "CCZ-RUNTIME-NBE-TYPE-MISMATCH"
      ("term " ++ show term ++ " has type " ++ show actual ++ ", expected " ++ show expected)))

familyEndpoints :: Family -> Either RuntimeError (Ty, Ty)
familyEndpoints family = case family of
  FamilyConst ty -> Right (ty, ty)
  FamilyGlue equivalence -> Right (equivalenceEndpoints equivalence)
  FamilyVec elementFamily size -> do
    when (size < 0) (Left (err "CCZ-RUNTIME-NBE-FAMILY" "negative Vec index"))
    (source, target) <- familyEndpoints elementFamily
    Right (TyVec source size, TyVec target size)
  FamilyPi domainFamily codomainFamily -> do
    (domainSource, domainTarget) <- familyEndpoints domainFamily
    (codomainSource, codomainTarget) <- familyEndpoints codomainFamily
    Right (TyPi domainSource codomainSource, TyPi domainTarget codomainTarget)
  FamilySigma firstFamily secondFamily -> do
    (firstSource, firstTarget) <- familyEndpoints firstFamily
    (secondSource, secondTarget) <- familyEndpoints secondFamily
    Right (TySigma firstSource secondSource, TySigma firstTarget secondTarget)
  FamilyCompose first second -> do
    (source, middle) <- familyEndpoints first
    (middle', target) <- familyEndpoints second
    unless (middle == middle')
      (Left (err "CCZ-RUNTIME-NBE-FAMILY-COMPOSE" "family endpoints do not compose"))
    Right (source, target)

equivalenceEndpoints :: Equiv -> (Ty, Ty)
equivalenceEndpoints equivalence = case equivalence of
  EquivIdentity ty -> (ty, ty)
  EquivBoolNot -> (TyBool, TyBool)
  EquivIntSucc -> (TyInt, TyInt)
  EquivCompose first second ->
    let (source, _) = equivalenceEndpoints first
        (_, target) = equivalenceEndpoints second
    in (source, target)
  EquivInverse inner ->
    let (source, target) = equivalenceEndpoints inner
    in (target, source)

data Neutral
  = NeutralVar Int
  | NeutralApp Neutral Term
  | NeutralNot Neutral
  | NeutralIntSucc Neutral
  | NeutralIntPred Neutral
  deriving (Eq, Show)

data Value
  = VUniverse Ty
  | VBool Bool
  | VNat Integer
  | VInt Integer
  | VS1Base
  | VVec Ty [Value]
  | VPair Value Value
  | VLam Ty Term Env
  | VTransportPi Family Family Value
  | VTypePath Family
  | VPathRefl Ty Value
  | VS1Path Integer
  | VGlue Equiv Value
  | VNeutral Neutral
  deriving Show

type Env = [Value]

data RuntimeState = RuntimeState
  { stateFuel :: Int
  , stateInitialFuel :: Int
  , stateAllocations :: Int
  , stateAllocationLimit :: Int
  , stateDefinitions :: [Definition]
  , stateCache :: [(String, Value)]
  , stateActive :: [String]
  , stateDefinitionLookups :: Int
  , stateCacheHits :: Int
  , stateTransports :: Int
  , stateHComps :: Int
  }

newtype Nbe a = Nbe { runNbe :: RuntimeState -> Either RuntimeError (a, RuntimeState) }

instance Functor Nbe where
  fmap function action = Nbe $ \state -> do
    (value, state') <- runNbe action state
    Right (function value, state')

instance Applicative Nbe where
  pure value = Nbe $ \state -> Right (value, state)
  functionAction <*> valueAction = Nbe $ \state -> do
    (function, state') <- runNbe functionAction state
    (value, state'') <- runNbe valueAction state'
    Right (function value, state'')

instance Monad Nbe where
  action >>= next = Nbe $ \state -> do
    (value, state') <- runNbe action state
    runNbe (next value) state'

throwNbe :: String -> String -> Nbe a
throwNbe code detail = Nbe $ \_ -> Left (err code detail)

getState :: Nbe RuntimeState
getState = Nbe $ \state -> Right (state, state)

putState :: RuntimeState -> Nbe ()
putState state = Nbe $ \_ -> Right ((), state)

modifyState :: (RuntimeState -> RuntimeState) -> Nbe ()
modifyState update = getState >>= putState . update

step :: Nbe ()
step = do
  state <- getState
  when (stateFuel state <= 0)
    (throwNbe "CCZ-RUNTIME-NBE-FUEL" "evaluation fuel exhausted")
  putState state { stateFuel = stateFuel state - 1 }

allocate :: Nbe ()
allocate = do
  state <- getState
  when (stateAllocations state >= stateAllocationLimit state)
    (throwNbe "CCZ-RUNTIME-NBE-MEMORY" "semantic allocation limit exceeded")
  putState state { stateAllocations = stateAllocations state + 1 }

normalize :: Request -> Nbe (Term, Ty)
normalize request = do
  value <- eval [] (requestTerm request)
  quoted <- quote 0 (requestType request) value
  state <- getState
  case infer (stateDefinitions state) [] quoted of
    Left failure -> throwNbe "CCZ-RUNTIME-NBE-READBACK-TYPE" (runtimeErrorDetail failure)
    Right actual
      | actual == requestType request -> pure (quoted, actual)
      | otherwise -> throwNbe "CCZ-RUNTIME-NBE-READBACK-TYPE"
          ("readback has type " ++ show actual ++ ", expected " ++ show (requestType request))

eval :: Env -> Term -> Nbe Value
eval environment term = do
  step
  allocate
  case term of
    Var index -> case drop index environment of
      value : _ -> pure value
      [] -> throwNbe "CCZ-RUNTIME-NBE-OPEN-TERM" ("runtime unbound index " ++ show index)
    Def name -> evalDefinition name
    Lam domain body -> pure (VLam domain body environment)
    App fun argument -> eval environment fun >>= \funValue -> eval environment argument >>= apply funValue
    Type ty -> pure (VUniverse ty)
    BoolLit value -> pure (VBool value)
    NatLit value -> pure (VNat value)
    IntLit value -> pure (VInt value)
    VecLit elementTy elements -> VVec elementTy <$> mapM (eval environment) elements
    Pair first second -> VPair <$> eval environment first <*> eval environment second
    Not value -> eval environment value >>= \result -> case result of
      VBool bool -> pure (VBool (not bool))
      VNeutral neutral -> pure (VNeutral (NeutralNot neutral))
      _ -> throwNbe "CCZ-RUNTIME-NBE-INTERNAL-TYPE" "not received a non-Bool semantic value"
    IntSucc value -> eval environment value >>= \result -> case result of
      VInt integer -> pure (VInt (integer + 1))
      VNeutral neutral -> pure (VNeutral (NeutralIntSucc neutral))
      _ -> throwNbe "CCZ-RUNTIME-NBE-INTERNAL-TYPE" "suc received a non-Int semantic value"
    IntPred value -> eval environment value >>= \result -> case result of
      VInt integer -> pure (VInt (integer - 1))
      VNeutral neutral -> pure (VNeutral (NeutralIntPred neutral))
      _ -> throwNbe "CCZ-RUNTIME-NBE-INTERNAL-TYPE" "pred received a non-Int semantic value"
    TypePath family -> pure (VTypePath family)
    Transp path value -> do
      pathValue <- eval environment path
      input <- eval environment value
      case pathValue of
        VTypePath family -> transportForward family input
        _ -> throwNbe "CCZ-RUNTIME-NBE-TRANSP-PATH" "runtime path is not a universe path"
    Refl ty value -> VPathRefl ty <$> eval environment value
    Concat left right -> do
      leftValue <- eval environment left
      rightValue <- eval environment right
      concatValues leftValue rightValue
    Loop -> pure (VS1Path 1)
    Winding path -> eval environment path >>= \value -> case value of
      VS1Path windingNumber -> pure (VInt windingNumber)
      _ -> throwNbe "CCZ-RUNTIME-NBE-HIT-PATH" "winding received a non-S1 path"
    HComp _ face system base -> do
      modifyState $ \state -> state { stateHComps = stateHComps state + 1 }
      case face of
        FaceOne -> eval environment system
        FaceZero -> eval environment base
    Glue equivalence value -> VGlue equivalence <$> eval environment value
    Unglue equivalence value -> do
      glued <- eval environment value
      case glued of
        VGlue actual inner | actual == equivalence -> equivalenceForward equivalence inner
        _ -> pure glued
    S1Base -> pure VS1Base

evalDefinition :: String -> Nbe Value
evalDefinition name = do
  state <- getState
  modifyState $ \current -> current
    { stateDefinitionLookups = stateDefinitionLookups current + 1 }
  case lookup name (stateCache state) of
    Just value -> do
      modifyState $ \current -> current { stateCacheHits = stateCacheHits current + 1 }
      pure value
    Nothing -> do
      when (name `elem` stateActive state)
        (throwNbe "CCZ-RUNTIME-NBE-DEFINITION-CYCLE" ("recursive definition cycle at " ++ name))
      case find ((== name) . definitionName) (stateDefinitions state) of
        Nothing -> throwNbe "CCZ-RUNTIME-NBE-DEFINITION-MISSING" ("missing definition " ++ name)
        Just definition -> do
          modifyState $ \current -> current { stateActive = name : stateActive current }
          value <- eval [] (definitionTerm definition)
          modifyState $ \current -> current
            { stateActive = filter (/= name) (stateActive current)
            , stateCache = (name, value) : filter ((/= name) . fst) (stateCache current)
            }
          pure value

apply :: Value -> Value -> Nbe Value
apply function argument = do
  step
  allocate
  case function of
    VLam _ body closureEnvironment -> eval (argument : closureEnvironment) body
    VTransportPi domainFamily codomainFamily sourceFunction -> do
      sourceArgument <- transportBackward domainFamily argument
      sourceResult <- apply sourceFunction sourceArgument
      transportForward codomainFamily sourceResult
    VNeutral neutral -> do
      argumentTerm <- quote 0 TyBool argument
      pure (VNeutral (NeutralApp neutral argumentTerm))
    _ -> throwNbe "CCZ-RUNTIME-NBE-NOT-A-FUNCTION" "semantic application head is not callable"

concatValues :: Value -> Value -> Nbe Value
concatValues left right = case (left, right) of
  (VTypePath first, VTypePath second) -> pure (VTypePath (FamilyCompose first second))
  (VS1Path first, VS1Path second) -> pure (VS1Path (first + second))
  (VPathRefl ty _, VPathRefl ty' value') | ty == ty' -> pure (VPathRefl ty value')
  _ -> throwNbe "CCZ-RUNTIME-NBE-PATH-COMPOSE" "semantic paths do not compose"

transportForward :: Family -> Value -> Nbe Value
transportForward family value = do
  step
  allocate
  modifyState $ \state -> state { stateTransports = stateTransports state + 1 }
  case family of
    FamilyConst _ -> pure value
    FamilyGlue equivalence -> equivalenceForward equivalence value
    FamilyVec elementFamily size -> case value of
      VVec _ elements | length elements == size -> do
        (_, targetElement) <- eitherToNbe (familyEndpoints elementFamily)
        VVec targetElement <$> mapM (transportForward elementFamily) elements
      _ -> throwNbe "CCZ-RUNTIME-NBE-VEC-SHAPE" "Vec transport received wrong semantic spine"
    FamilyPi domainFamily codomainFamily -> pure (VTransportPi domainFamily codomainFamily value)
    FamilySigma firstFamily secondFamily -> case value of
      VPair first second -> VPair <$> transportForward firstFamily first <*> transportForward secondFamily second
      _ -> throwNbe "CCZ-RUNTIME-NBE-RECORD-SHAPE" "Sigma transport received a non-pair"
    FamilyCompose first second -> transportForward first value >>= transportForward second

transportBackward :: Family -> Value -> Nbe Value
transportBackward family value = case family of
  FamilyConst _ -> transportForward family value
  FamilyGlue equivalence -> do
    modifyState $ \state -> state { stateTransports = stateTransports state + 1 }
    step >> allocate >> equivalenceBackward equivalence value
  FamilyVec elementFamily size -> case value of
    VVec _ elements | length elements == size -> do
      (sourceElement, _) <- eitherToNbe (familyEndpoints elementFamily)
      VVec sourceElement <$> mapM (transportBackward elementFamily) elements
    _ -> throwNbe "CCZ-RUNTIME-NBE-VEC-SHAPE" "reverse Vec transport received wrong semantic spine"
  FamilyPi domainFamily codomainFamily ->
    transportForward (FamilyPi (reverseFamily domainFamily) (reverseFamily codomainFamily)) value
  FamilySigma firstFamily secondFamily -> case value of
    VPair first second -> VPair <$> transportBackward firstFamily first <*> transportBackward secondFamily second
    _ -> throwNbe "CCZ-RUNTIME-NBE-RECORD-SHAPE" "reverse Sigma transport received a non-pair"
  FamilyCompose first second -> transportBackward second value >>= transportBackward first

reverseFamily :: Family -> Family
reverseFamily family = case family of
  FamilyConst ty -> FamilyConst ty
  FamilyGlue equivalence -> FamilyGlue (EquivInverse equivalence)
  FamilyVec element size -> FamilyVec (reverseFamily element) size
  FamilyPi domain codomain -> FamilyPi (reverseFamily domain) (reverseFamily codomain)
  FamilySigma first second -> FamilySigma (reverseFamily first) (reverseFamily second)
  FamilyCompose first second -> FamilyCompose (reverseFamily second) (reverseFamily first)

equivalenceForward :: Equiv -> Value -> Nbe Value
equivalenceForward equivalence value = case equivalence of
  EquivIdentity _ -> pure value
  EquivBoolNot -> case value of
    VBool bool -> pure (VBool (not bool))
    _ -> throwNbe "CCZ-RUNTIME-NBE-EQUIV-SHAPE" "Bool-not equivalence received non-Bool"
  EquivIntSucc -> case value of
    VInt integer -> pure (VInt (integer + 1))
    _ -> throwNbe "CCZ-RUNTIME-NBE-EQUIV-SHAPE" "Int-succ equivalence received non-Int"
  EquivCompose first second -> equivalenceForward first value >>= equivalenceForward second
  EquivInverse inner -> equivalenceBackward inner value

equivalenceBackward :: Equiv -> Value -> Nbe Value
equivalenceBackward equivalence value = case equivalence of
  EquivIdentity _ -> pure value
  EquivBoolNot -> equivalenceForward EquivBoolNot value
  EquivIntSucc -> case value of
    VInt integer -> pure (VInt (integer - 1))
    _ -> throwNbe "CCZ-RUNTIME-NBE-EQUIV-SHAPE" "Int-succ inverse received non-Int"
  EquivCompose first second -> equivalenceBackward second value >>= equivalenceBackward first
  EquivInverse inner -> equivalenceForward inner value

quote :: Int -> Ty -> Value -> Nbe Term
quote level ty value = do
  step
  allocate
  case (ty, value) of
    (TyUniverse, VUniverse universeTy) -> pure (Type universeTy)
    (TyBool, VBool bool) -> pure (BoolLit bool)
    (TyNat, VNat natural) -> pure (NatLit natural)
    (TyInt, VInt integer) -> pure (IntLit integer)
    (TyS1, VS1Base) -> pure S1Base
    (TyVec elementTy size, VVec actualElement elements)
      | elementTy == actualElement && size == length elements -> VecLit elementTy <$> mapM (quote level elementTy) elements
    (TySigma firstTy secondTy, VPair first second) -> Pair <$> quote level firstTy first <*> quote level secondTy second
    (TyPi domain codomain, function) -> do
      body <- apply function (VNeutral (NeutralVar level))
      Lam domain <$> quote (level + 1) codomain body
    (TyPath TyUniverse (Type source) (Type target), VTypePath family) -> do
      endpoints <- eitherToNbe (familyEndpoints family)
      if endpoints == (source, target)
        then pure (TypePath family)
        else throwNbe "CCZ-RUNTIME-NBE-READBACK-TYPE" "type-path endpoints changed during evaluation"
    (TyPath pathTy left right, VPathRefl actualTy inner)
      | pathTy == actualTy -> do
          quoted <- quote level pathTy inner
          if quoted == left && quoted == right
            then pure (Refl pathTy quoted)
            else throwNbe "CCZ-RUNTIME-NBE-READBACK-TYPE" "refl endpoints changed during evaluation"
    (_, VNeutral neutral) -> pure (quoteNeutral level neutral)
    (_, VGlue equivalence inner) -> equivalenceForward equivalence inner >>= quote level ty
    _ -> throwNbe "CCZ-RUNTIME-NBE-READBACK-SHAPE"
      ("cannot quote semantic value " ++ show value ++ " at " ++ show ty)

quoteNeutral :: Int -> Neutral -> Term
quoteNeutral level neutral = case neutral of
  NeutralVar variableLevel -> Var (level - variableLevel - 1)
  NeutralApp headNeutral argument -> App (quoteNeutral level headNeutral) argument
  NeutralNot inner -> Not (quoteNeutral level inner)
  NeutralIntSucc inner -> IntSucc (quoteNeutral level inner)
  NeutralIntPred inner -> IntPred (quoteNeutral level inner)

eitherToNbe :: Either RuntimeError a -> Nbe a
eitherToNbe result = case result of
  Left failure -> throwNbe (runtimeErrorCode failure) (runtimeErrorDetail failure)
  Right value -> pure value

stateStats :: RuntimeState -> Stats
stateStats state = Stats
  { statsSteps = stateInitialFuel state - stateFuel state
  , statsAllocations = stateAllocations state
  , statsDefinitionLookups = stateDefinitionLookups state
  , statsCacheHits = stateCacheHits state
  , statsTransports = stateTransports state
  , statsHComps = stateHComps state
  }

err :: String -> String -> RuntimeError
err = RuntimeError

stripPrefix :: Eq a => [a] -> [a] -> Maybe [a]
stripPrefix [] ys = Just ys
stripPrefix _ [] = Nothing
stripPrefix (x : xs) (y : ys)
  | x == y = stripPrefix xs ys
  | otherwise = Nothing
