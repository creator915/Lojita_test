-- | The compiler-independent semantic domain for the supported Goal 3 runtime
-- fragment. A compiler-side bridge translates checked Agda Internal Term/Type
-- into the shared wire model; this final-process module does not link Agda.
--
-- Cubical primitive reduction is guarded by the linked cctt evaluator at the
-- pinned revision.  The Agda wire adapter supplies the datatype/literal
-- semantics which are outside cctt's small core language.
module Cubical.Runtime.Nbe
  ( module Cubical.Runtime.Nbe.Wire
  , Limits (..)
  , Stats (..)
  , RuntimeError (..)
  , Response (..)
  , defaultLimits
  , decodePacket
  , runPacket
  , renderResponse
  , renderObservation
  ) where

import Control.Monad (unless, when)
import Data.Char (isAlphaNum)
import Data.List (find, intercalate, nub)
import GHC.Generics (Generic)
import Text.Read (readMaybe)
import Cubical.Runtime.Nbe.Cctt
import Cubical.Runtime.Nbe.Wire

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
  , statsProviderCalls :: Int
  } deriving (Eq, Read, Show, Generic)

data RuntimeError = RuntimeError
  { runtimeErrorCode :: String
  , runtimeErrorDetail :: String
  } deriving (Eq, Read, Show, Generic)

data Response
  = RuntimeOk Term Ty Stats
  | RuntimeFailed RuntimeError
  deriving (Eq, Read, Show, Generic)

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

-- | Render the closed observable subset in the same textual form as the Agda
-- oracle backend.  The differential harness invokes this only after the typed
-- runtime response has succeeded; it is a structural rendering, not an
-- expected-value table.
renderObservation :: Term -> Ty -> Either RuntimeError String
renderObservation term ty = case (term, ty) of
  (BoolLit bool, TyBool) -> Right (if bool then "true" else "false")
  (NatLit natural, TyNat) -> Right (show natural)
  (IntLit integer, TyInt)
    | integer >= 0 -> Right ("pos " ++ show integer)
    | otherwise -> Right ("negsuc " ++ show ((-integer) - 1))
  (Pair first second, TySigma firstTy secondTy) -> do
    firstText <- renderObservation first firstTy
    secondText <- renderObservation second secondTy
    Right (firstText ++ " , " ++ secondText)
  (VecLit TyBool [first, second], TyVec TyBool 2) -> do
    firstText <- renderObservation first TyBool
    secondText <- renderObservation second TyBool
    Right (firstText ++ " , " ++ secondText)
  _ -> Left (err "CCZ-RUNTIME-NBE-OBSERVATION"
    ("no Agda observation renderer for " ++ show term ++ " at " ++ show ty))

renderStats :: Stats -> String
renderStats stats = intercalate ","
  [ "steps=" ++ show (statsSteps stats)
  , "allocations=" ++ show (statsAllocations stats)
  , "definition-lookups=" ++ show (statsDefinitionLookups stats)
  , "cache-hits=" ++ show (statsCacheHits stats)
  , "transports=" ++ show (statsTransports stats)
  , "hcomps=" ++ show (statsHComps stats)
  , "provider-calls=" ++ show (statsProviderCalls stats)
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
            , stateProviderCalls = 0
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
  Var index | index < 0 ->
    Left (err "CCZ-RUNTIME-NBE-OPEN-TERM" ("negative de Bruijn index " ++ show index))
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
  | NeutralApp Neutral Ty Value
  | NeutralNot Neutral
  | NeutralIntSucc Neutral
  | NeutralIntPred Neutral
  deriving Show

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
  | VNeutral Ty Neutral
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
  , stateProviderCalls :: Int
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
    Var index | index < 0 ->
      throwNbe "CCZ-RUNTIME-NBE-OPEN-TERM" ("runtime negative index " ++ show index)
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
      VNeutral TyBool neutral -> pure (VNeutral TyBool (NeutralNot neutral))
      _ -> throwNbe "CCZ-RUNTIME-NBE-INTERNAL-TYPE" "not received a non-Bool semantic value"
    IntSucc value -> eval environment value >>= \result -> case result of
      VInt integer -> pure (VInt (integer + 1))
      VNeutral TyInt neutral -> pure (VNeutral TyInt (NeutralIntSucc neutral))
      _ -> throwNbe "CCZ-RUNTIME-NBE-INTERNAL-TYPE" "suc received a non-Int semantic value"
    IntPred value -> eval environment value >>= \result -> case result of
      VInt integer -> pure (VInt (integer - 1))
      VNeutral TyInt neutral -> pure (VNeutral TyInt (NeutralIntPred neutral))
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
    HComp ty face system base -> do
      systemValue <- eval environment system
      baseValue <- eval environment base
      selected <- providerSelectValue ty face systemValue baseValue
      modifyState $ \state -> state { stateHComps = stateHComps state + 1 }
      pure selected
    Glue equivalence value -> do
      inner <- eval environment value
      VGlue equivalence <$> providerPreserveValue inner
    Unglue equivalence value -> do
      glued <- eval environment value
      case glued of
        VGlue actual inner | actual == equivalence ->
          providerEquivalence ProviderForward equivalence inner
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
    VNeutral (TyPi domain codomain) neutral ->
      pure (VNeutral codomain (NeutralApp neutral domain argument))
    _ -> throwNbe "CCZ-RUNTIME-NBE-NOT-A-FUNCTION" "semantic application head is not callable"

concatValues :: Value -> Value -> Nbe Value
concatValues left right = case (left, right) of
  (VTypePath first, VTypePath second) -> do
    -- The composed family is kept symbolically.  Its eventual action is sent
    -- to cctt with the real transported value, never authorized by a probe.
    pure (VTypePath (FamilyCompose first second))
  (VS1Path first, VS1Path second) ->
    VS1Path <$> withProvider (providerAddInt first second)
  (VPathRefl ty _, VPathRefl ty' value') | ty == ty' ->
    VPathRefl ty <$> providerPreserveValue value'
  _ -> throwNbe "CCZ-RUNTIME-NBE-PATH-COMPOSE" "semantic paths do not compose"

transportForward :: Family -> Value -> Nbe Value
transportForward family value = do
  step
  allocate
  modifyState $ \state -> state { stateTransports = stateTransports state + 1 }
  case family of
    FamilyPi domainFamily codomainFamily -> pure (VTransportPi domainFamily codomainFamily value)
    _ -> providerTransportValue ProviderForward family value

transportBackward :: Family -> Value -> Nbe Value
transportBackward family value = do
  step
  allocate
  modifyState $ \state -> state { stateTransports = stateTransports state + 1 }
  case family of
    FamilyPi domainFamily codomainFamily ->
      transportForward (FamilyPi (reverseFamily domainFamily) (reverseFamily codomainFamily)) value
    _ -> providerTransportValue ProviderBackward family value

reverseFamily :: Family -> Family
reverseFamily family = case family of
  FamilyConst ty -> FamilyConst ty
  FamilyGlue equivalence -> FamilyGlue (EquivInverse equivalence)
  FamilyVec element size -> FamilyVec (reverseFamily element) size
  FamilyPi domain codomain -> FamilyPi (reverseFamily domain) (reverseFamily codomain)
  FamilySigma first second -> FamilySigma (reverseFamily first) (reverseFamily second)
  FamilyCompose first second -> FamilyCompose (reverseFamily second) (reverseFamily first)

providerTransportValue :: ProviderDirection -> Family -> Value -> Nbe Value
providerTransportValue direction family value = do
  input <- eitherProvider (valueToProvider value)
  result <- withProvider (providerTransport direction family input)
  (sourceTy, targetTy) <- eitherToNbe (familyEndpoints family)
  let resultTy = case direction of
        ProviderForward -> targetTy
        ProviderBackward -> sourceTy
  eitherProvider (providerToValue resultTy result)

providerEquivalence :: ProviderDirection -> Equiv -> Value -> Nbe Value
providerEquivalence direction equivalence =
  providerTransportValue direction (FamilyGlue equivalence)

providerPreserveValue :: Value -> Nbe Value
providerPreserveValue value = do
  input <- eitherProvider (valueToProvider value)
  result <- withProvider (providerPreserve input)
  eitherProvider (providerToValueLike value result)

providerSelectValue :: Ty -> Face -> Value -> Value -> Nbe Value
providerSelectValue ty face system base = do
  systemInput <- eitherProvider (valueToProvider system)
  baseInput <- eitherProvider (valueToProvider base)
  result <- withProvider (providerSelect face systemInput baseInput)
  eitherProvider (providerToValue ty result)

withProvider :: Either String a -> Nbe a
withProvider result = do
  modifyState $ \state -> state
    { stateProviderCalls = stateProviderCalls state + 1 }
  eitherProvider result

eitherProvider :: Either String a -> Nbe a
eitherProvider result = case result of
  Left detail -> throwNbe "CCZ-RUNTIME-NBE-PROVIDER-REJECTED" detail
  Right value -> pure value

valueToProvider :: Value -> Either String ProviderValue
valueToProvider value = case value of
  VBool bool -> Right (ProviderBool bool)
  VNat natural -> Right (ProviderNat natural)
  VInt integer -> Right (ProviderInt integer)
  VVec _ elements -> ProviderVec <$> mapM valueToProvider elements
  VPair first second -> ProviderPair <$> valueToProvider first <*> valueToProvider second
  _ -> Left ("unsupported semantic value at cctt provider boundary: " ++ show value)

providerToValue :: Ty -> ProviderValue -> Either String Value
providerToValue ty value = case (ty, value) of
  (TyBool, ProviderBool bool) -> Right (VBool bool)
  (TyNat, ProviderNat natural) -> Right (VNat natural)
  (TyInt, ProviderInt integer) -> Right (VInt integer)
  (TyVec elementTy size, ProviderVec elements)
    | size == length elements -> VVec elementTy <$> mapM (providerToValue elementTy) elements
  (TySigma firstTy secondTy, ProviderPair first second) ->
    VPair <$> providerToValue firstTy first <*> providerToValue secondTy second
  _ -> Left ("cctt provider result " ++ show value ++ " does not inhabit " ++ show ty)

providerToValueLike :: Value -> ProviderValue -> Either String Value
providerToValueLike shape value = case (shape, value) of
  (VBool _, ProviderBool bool) -> Right (VBool bool)
  (VNat _, ProviderNat natural) -> Right (VNat natural)
  (VInt _, ProviderInt integer) -> Right (VInt integer)
  (VVec elementTy shapes, ProviderVec elements)
    | length shapes == length elements ->
        VVec elementTy <$> sequence (zipWith providerToValueLike shapes elements)
  (VPair firstShape secondShape, ProviderPair first second) ->
    VPair <$> providerToValueLike firstShape first <*> providerToValueLike secondShape second
  _ -> Left ("cctt provider result changed semantic shape: " ++ show value)

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
      body <- apply function (VNeutral domain (NeutralVar level))
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
    (_, VNeutral actualTy neutral)
      | ty == actualTy -> quoteNeutral level neutral
    (_, VGlue equivalence inner) ->
      providerEquivalence ProviderForward equivalence inner >>= quote level ty
    _ -> throwNbe "CCZ-RUNTIME-NBE-READBACK-SHAPE"
      ("cannot quote semantic value " ++ show value ++ " at " ++ show ty)

quoteNeutral :: Int -> Neutral -> Nbe Term
quoteNeutral level neutral = case neutral of
  NeutralVar variableLevel -> pure (Var (level - variableLevel - 1))
  NeutralApp headNeutral domain argument ->
    App <$> quoteNeutral level headNeutral <*> quote level domain argument
  NeutralNot inner -> Not <$> quoteNeutral level inner
  NeutralIntSucc inner -> IntSucc <$> quoteNeutral level inner
  NeutralIntPred inner -> IntPred <$> quoteNeutral level inner

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
  , statsProviderCalls = stateProviderCalls state
  }

err :: String -> String -> RuntimeError
err = RuntimeError

stripPrefix :: Eq a => [a] -> [a] -> Maybe [a]
stripPrefix [] ys = Just ys
stripPrefix _ [] = Nothing
stripPrefix (x : xs) (y : ys)
  | x == y = stripPrefix xs ys
  | otherwise = Nothing
{-# LANGUAGE DeriveGeneric #-}
