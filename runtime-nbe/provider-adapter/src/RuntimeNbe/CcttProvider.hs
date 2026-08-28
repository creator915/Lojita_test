{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE LambdaCase #-}

module RuntimeNbe.CcttProvider
  ( ProviderError(..)
  , normalizeCheckedDefinition
  , normalizeRuntimeIr
  , normalizeRuntimeIrBytes
  , providerEvalQuoteAudit
  , providerName
  , providerRevision
  ) where

import Control.Exception
  ( IOException, SomeAsyncException, SomeException, bracket, bracket_
  , displayException, evaluate, fromException, try, tryJust )
import Control.DeepSeq (force)
import Control.Monad (unless)
import qualified Data.ByteString.Char8 as ByteString
import Data.Char (isAlphaNum, isDigit)
import Data.Int (Int64)
import Data.List (stripPrefix)
import Data.Maybe (isJust)
import Foreign.C.Types (CInt(..))
import GHC.Conc (disableAllocationLimit, enableAllocationLimit, setAllocationCounter)
import GHC.IO.Exception (AllocationLimitExceeded)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory)
import System.IO (hClose, hPutStr, openTempFile)
import System.Timeout (timeout)
import Text.ParserCombinators.ReadP
  ( ReadP, char, eof, munch1, readP_to_S, sepBy, (<++) )
import Text.Read (readMaybe)

import CoreTypes
  ( DefInfo(defInfoDef), Env(ENil), Recurse(DontRecurse), Tm )
import qualified Core
import Cubical (emptyNCof, idSub)
import ElabState
  ( State(stateTop), TopEntry(TEDef), getState, resetElabState )
import Elaboration (elaborate)
import Pretty (Pretty(pretty0))
import Quotation (quoteUnfold)


data ProviderError
  = ProviderInputMissing FilePath
  | ProviderElaborationFailed String
  | ProviderDefinitionMissing String
  | ProviderDefinitionNotTerm String
  | ProviderEvaluationFailed String
  | ProviderRuntimeIrRejected String
  | ProviderResourceLimitExceeded String
  deriving (Eq, Show)

providerName :: String
providerName = "cctt"

providerRevision :: String
providerRevision = "ba16f3758a322e9be77ada1da2b93f45d500192e"

agdaRevision :: String
agdaRevision = "3d04bacca842729f9c0869b9287256321b5f450f"

maxRuntimeIrBytes :: Int
maxRuntimeIrBytes = 16 * 1024

defaultAllocationLimitBytes :: Int64
defaultAllocationLimitBytes = 256 * 1024 * 1024

defaultTimeoutMicroseconds :: Int
defaultTimeoutMicroseconds = 5 * 1000 * 1000

minimumSchedulableTimeoutMicroseconds :: Int
minimumSchedulableTimeoutMicroseconds = 1000

defaultSemanticFuel :: Int64
defaultSemanticFuel = 4096

normalizeTerm :: Tm -> String
normalizeTerm term =
  let ?sub = idSub 0
      ?cof = emptyNCof
      ?dom = 0
      ?env = ENil
      ?recurse = DontRecurse
  in pretty0 (quoteUnfold (Core.eval term) :: Tm)
{-# NOINLINE normalizeTerm #-}

-- Stable product ABI for link auditing.  Executing it forces the same checked
-- IR -> cctt evaluation -> quotation path used for normal runtime requests.
providerEvalQuoteAudit :: IO CInt
providerEvalQuoteAudit = do
  result <- normalizeRuntimeIrBytes $ ByteString.pack $ unlines
    [ "schema=runtime-nbe-ir-v1"
    , "operation=hcomp-empty-face"
    , "value-type=agda-builtin-bool"
    , "base=false"
    , "source-qname=RuntimeNbe.ProviderAudit"
    , "agda-revision=" ++ agdaRevision
    , "provider-revision=" ++ providerRevision
    ]
  pure $ case result of
    Right "false" -> 0
    _ -> 1
{-# NOINLINE providerEvalQuoteAudit #-}

foreign export ccall "runtime_nbe_cctt_eval_quote_v1"
  providerEvalQuoteAudit :: IO CInt

normalizeCheckedDefinition :: FilePath -> String -> IO (Either ProviderError String)
normalizeCheckedDefinition source definition = do
  exists <- doesFileExist source
  if not exists then
    pure (Left (ProviderInputMissing source))
  else do
    resetElabState
    elaborated <- trySynchronous (elaborate source)
    case elaborated of
      Left failure ->
        pure (Left (ProviderElaborationFailed (displayException failure)))
      Right () -> do
        entries <- stateTop <$> getState
        case Map.lookup (ByteString.pack definition) entries of
          Nothing -> pure (Left (ProviderDefinitionMissing definition))
          Just (TEDef info) -> do
            normalized <- trySynchronous $
              evaluate (force (normalizeTerm (defInfoDef info)))
            pure $ case normalized of
              Left failure ->
                Left (ProviderEvaluationFailed (displayException failure))
              Right result -> Right result
          Just _ -> pure (Left (ProviderDefinitionNotTerm definition))

trySynchronous :: IO a -> IO (Either SomeException a)
trySynchronous = tryJust $ \failure ->
  if isJust (fromException failure :: Maybe SomeAsyncException)
      || isJust (fromException failure :: Maybe AllocationLimitExceeded)
    then Nothing
    else Just failure

data BoolBase
  = BaseFalse
  | BaseTrue
  | BaseApply BoolFunction BoolBase
  | BaseProgram [BoolExpression] BoolExpression
  | BaseBoolPair BoolBase BoolBase
  | BaseTransp BoolBase
  | BaseActiveHComp BoolBase BoolBase
  | BaseGlue BoolBase
  | BaseHit HitBase
  | BaseActiveHit TubeOrientation
  | BaseDependentEvidence EvidenceKind
  | BaseDependentCall BoolBase BoolBase EvidenceKind
  | BaseGlueTransp BoolBase
  | BaseNegationGlueTransp BoolBase

data HitBase = HitLeft | HitRight | HitPathZero | HitPathOne
  deriving (Eq)
data TubeOrientation = TubeForward | TubeReverse
data EvidenceKind = EvidenceApproved | EvidenceRejected

data BoolFunction
  = BoolIdentity
  | BoolConstantFalse
  | BoolConstantTrue

data BoolExpression
  = ExprArgument
  | ExprFalse
  | ExprTrue
  | ExprApply Int BoolExpression

data V14Ast = V14Atom String | V14Node String [V14Ast]
  deriving (Eq, Show)

data V14Definition = V14Definition String V14Ast V14Ast
  deriving (Eq, Show)

normalizeRuntimeIr :: FilePath -> IO (Either ProviderError String)
normalizeRuntimeIr runtimeIr = do
  loaded <- try (ByteString.readFile runtimeIr)
    :: IO (Either IOException ByteString.ByteString)
  case loaded of
    Left failure -> pure $ Left $ ProviderRuntimeIrRejected $
      "unable to read runtime IR: " ++ displayException failure
    Right bytes -> normalizeRuntimeIrBytesAt (takeDirectory runtimeIr) bytes

normalizeRuntimeIrBytes :: ByteString.ByteString -> IO (Either ProviderError String)
normalizeRuntimeIrBytes bytes = do
  temporaryDirectory <- getTemporaryDirectory
  normalizeRuntimeIrBytesAt temporaryDirectory bytes

normalizeRuntimeIrBytesAt
  :: FilePath
  -> ByteString.ByteString
  -> IO (Either ProviderError String)
normalizeRuntimeIrBytesAt temporaryDirectory bytes
  | ByteString.length bytes > maxRuntimeIrBytes =
      pure $ Left $ ProviderRuntimeIrRejected "runtime IR exceeds 16 KiB"
  | otherwise = case parseRuntimeIr bytes of
      Left reason -> pure $ Left $ ProviderRuntimeIrRejected reason
      Right base -> do
        configured <- runtimeLimits
        case configured of
          Left reason -> pure $ Left $ ProviderRuntimeIrRejected reason
          Right (allocationBytes, timeoutMicroseconds, semanticFuel) ->
            if semanticFuelCost base > semanticFuel then
              pure $ Left $ ProviderResourceLimitExceeded $
                "adapter semantic fuel exhausted: required " ++
                show (semanticFuelCost base) ++ ", configured " ++ show semanticFuel
            else runResourceBounded allocationBytes timeoutMicroseconds $
              withReflectedProgram temporaryDirectory base $ \source ->
                normalizeCheckedDefinition source "runtimeResult"

runtimeLimits :: IO (Either String (Int64, Int, Int64))
runtimeLimits = do
  allocation <- readPositiveLimit
    "RUNTIME_NBE_MAX_ALLOCATION_BYTES" defaultAllocationLimitBytes
  wallTime <- readPositiveLimit
    "RUNTIME_NBE_TIMEOUT_MICROS" (fromIntegral defaultTimeoutMicroseconds)
  semanticFuel <- readPositiveLimit "RUNTIME_NBE_MAX_FUEL" defaultSemanticFuel
  pure $ do
    allocationValue <- allocation
    wallTimeValue <- wallTime
    semanticFuelValue <- semanticFuel
    unless (wallTimeValue <= fromIntegral (maxBound :: Int)) $
      Left "RUNTIME_NBE_TIMEOUT_MICROS is outside the supported integer range"
    Right (allocationValue, fromIntegral wallTimeValue, semanticFuelValue)

semanticFuelCost :: BoolBase -> Int64
semanticFuelCost = \case
  BaseFalse -> 1
  BaseTrue -> 1
  BaseApply _ argument -> 3 + semanticFuelCost argument
  BaseProgram definitions expression ->
    8 + sum (map expressionFuel definitions) + expressionFuel expression
  BaseBoolPair first second -> 8 + semanticFuelCost first + semanticFuelCost second
  BaseTransp value -> 12 + semanticFuelCost value
  BaseActiveHComp side base -> 16 + semanticFuelCost side + semanticFuelCost base
  BaseGlue value -> 20 + semanticFuelCost value
  BaseHit _ -> 24
  BaseActiveHit _ -> 40
  BaseDependentEvidence _ -> 32
  BaseDependentCall first second _ ->
    40 + semanticFuelCost first + semanticFuelCost second
  BaseGlueTransp value -> 48 + semanticFuelCost value
  BaseNegationGlueTransp value -> 256 + semanticFuelCost value
  where
    expressionFuel ExprArgument = 1
    expressionFuel ExprFalse = 1
    expressionFuel ExprTrue = 1
    expressionFuel (ExprApply _ argument) = 2 + expressionFuel argument

readPositiveLimit :: String -> Int64 -> IO (Either String Int64)
readPositiveLimit name defaultValue = do
  configured <- lookupEnv name
  pure $ case configured of
    Nothing -> Right defaultValue
    Just value -> case readMaybe value of
      Just parsed | parsed > 0 -> Right parsed
      _ -> Left (name ++ " must be a positive decimal integer")

runResourceBounded
  :: Int64 -> Int -> IO (Either ProviderError String)
  -> IO (Either ProviderError String)
runResourceBounded _ timeoutMicroseconds _
  | timeoutMicroseconds < minimumSchedulableTimeoutMicroseconds =
      pure $ Left $ ProviderResourceLimitExceeded "wall timeout exceeded"
runResourceBounded allocationBytes timeoutMicroseconds action = do
  bounded <- timeout timeoutMicroseconds $ runAllocationBounded allocationBytes action
  pure $ case bounded of
    Nothing -> Left $ ProviderResourceLimitExceeded "wall timeout exceeded"
    Just (Left _) -> Left $ ProviderResourceLimitExceeded "allocation budget exceeded"
    Just (Right result) -> result

runAllocationBounded
  :: Int64 -> IO a -> IO (Either AllocationLimitExceeded a)
runAllocationBounded allocationBytes action = try $
  bracket_
    (setAllocationCounter allocationBytes >> enableAllocationLimit)
    disableAllocationLimit
    action

parseRuntimeIr :: ByteString.ByteString -> Either String BoolBase
parseRuntimeIr bytes = do
  fields <- traverse parseField $ filter (not . ByteString.null) $
    ByteString.lines bytes
  let fieldMap = Map.fromList fields
  unless (length fields == Map.size fieldMap) $
    Left "runtime IR contains duplicate fields"
  schema <- lookupField fieldMap "schema"
  case schema of
    "runtime-nbe-ir-v1" -> parseRuntimeIrV1 fieldMap
    "runtime-nbe-ir-v2" -> parseRuntimeIrV2 fieldMap
    "runtime-nbe-ir-v3" -> parseRuntimeIrV3 fieldMap
    "runtime-nbe-ir-v4" -> parseRuntimeIrV4 fieldMap
    "runtime-nbe-ir-v5" -> parseRuntimeIrV5 fieldMap
    "runtime-nbe-ir-v6" -> parseRuntimeIrV6 fieldMap
    "runtime-nbe-ir-v7" -> parseRuntimeIrV7 fieldMap
    "runtime-nbe-ir-v8" -> parseRuntimeIrV8 fieldMap
    "runtime-nbe-ir-v9" -> parseRuntimeIrV9 fieldMap
    "runtime-nbe-ir-v10" -> parseRuntimeIrV10 fieldMap
    "runtime-nbe-ir-v11" -> parseRuntimeIrV11 fieldMap
    "runtime-nbe-ir-v12" -> parseRuntimeIrV12 fieldMap
    "runtime-nbe-ir-v13" -> parseRuntimeIrV13 fieldMap
    "runtime-nbe-ir-v14" -> parseRuntimeIrV14 fieldMap
    _ -> Left "runtime IR schema identity mismatch"

parseRuntimeIrV1 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV1 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "base", "source-qname"
    , "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "hcomp-empty-face"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  base <- lookupField fieldMap "base"
  parseBoolBase base

parseRuntimeIrV2 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV2 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "base-expression"
    , "definition-count", "def0-qname", "def0-type", "def0-body"
    , "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "hcomp-empty-face"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "definition-count" "1"
  requireField fieldMap "def0-type" "pi-bool-bool"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  validateQNameField fieldMap "def0-qname"
  body <- lookupField fieldMap "def0-body" >>= parseBoolFunction
  expression <- lookupField fieldMap "base-expression"
  argument <- case expression of
    "apply-def0-false" -> Right BaseFalse
    "apply-def0-true" -> Right BaseTrue
    _ -> Left "runtime IR base expression is not an application of def0 to Bool"
  pure $ BaseApply body argument

parseRuntimeIrV3 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV3 fieldMap = do
  countText <- lookupField fieldMap "definition-count"
  count <- parseBoundedCount countText
  let definitionFields = concatMap (\index ->
        [ "def" ++ show index ++ "-qname"
        , "def" ++ show index ++ "-type"
        , "def" ++ show index ++ "-body"
        ]) [0 .. count - 1]
  requireFieldSet fieldMap $
    [ "schema", "operation", "value-type", "base-expression"
    , "definition-count", "source-qname", "agda-revision", "provider-revision"
    ] ++ definitionFields
  requireField fieldMap "operation" "hcomp-empty-face"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  definitions <- traverse (parseDefinition fieldMap) [0 .. count - 1]
  mapM_ (validateDefinitionReferences count) (zip [0 ..] definitions)
  expression <- lookupField fieldMap "base-expression" >>= parseBoolExpression
  validateExpressionReferences count False expression
  pure $ BaseProgram definitions expression

parseRuntimeIrV4 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV4 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "base-first", "base-second"
    , "definition-count", "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "hcomp-empty-face"
  requireField fieldMap "value-type" "sigma-bool-bool"
  requireField fieldMap "definition-count" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  first <- lookupField fieldMap "base-first" >>= parseBoolBase
  second <- lookupField fieldMap "base-second" >>= parseBoolBase
  pure $ BaseBoolPair first second

parseRuntimeIrV5 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV5 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "type-family", "face", "base"
    , "definition-count", "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "transp"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "type-family" "constant-bool"
  requireField fieldMap "face" "i0"
  requireField fieldMap "definition-count" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  BaseTransp <$> (lookupField fieldMap "base" >>= parseBoolBase)

parseRuntimeIrV6 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV6 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "face", "side", "base"
    , "definition-count", "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "hcomp-active-face"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "face" "i1"
  requireField fieldMap "definition-count" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  side <- lookupField fieldMap "side" >>= parseBoolBase
  base <- lookupField fieldMap "base" >>= parseBoolBase
  pure $ BaseActiveHComp side base

parseRuntimeIrV7 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV7 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "face", "partial-type"
    , "equivalence-system", "base", "definition-count", "source-qname"
    , "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "glue-unglue"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "face" "i0"
  requireField fieldMap "partial-type" "constant-bool"
  requireField fieldMap "equivalence-system" "empty"
  requireField fieldMap "definition-count" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  BaseGlue <$> (lookupField fieldMap "base" >>= parseBoolBase)

parseRuntimeIrV8 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV8 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "hit-type-qname", "left-qname"
    , "right-qname", "path-qname", "path-boundary", "base-kind", "definition-count"
    , "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "hcomp-empty-face"
  requireField fieldMap "value-type" "interval-hit"
  requireField fieldMap "path-boundary" "left-to-right"
  requireField fieldMap "definition-count" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  mapM_ (validateQNameField fieldMap)
    [ "source-qname", "hit-type-qname", "left-qname", "right-qname"
    , "path-qname"
    ]
  typeName <- lookupField fieldMap "hit-type-qname"
  leftName <- lookupField fieldMap "left-qname"
  rightName <- lookupField fieldMap "right-qname"
  pathName <- lookupField fieldMap "path-qname"
  unless (Set.size (Set.fromList [typeName, leftName, rightName, pathName]) == 4) $
    Left "HIT type/left/right/path identities are not distinct"
  base <- lookupField fieldMap "base-kind" >>= \case
    "left" -> Right HitLeft
    "right" -> Right HitRight
    "path-i0" -> Right HitPathZero
    "path-i1" -> Right HitPathOne
    _ -> Left "HIT base-kind identity mismatch"
  pure $ BaseHit base

parseRuntimeIrV9 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV9 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "evidence-type-qname"
    , "approved-con-qname", "rejected-con-qname", "decision", "evidence-kind"
    , "definition-count", "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "hcomp-empty-face"
  requireField fieldMap "value-type" "dependent-bool-evidence-sigma"
  requireField fieldMap "definition-count" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  mapM_ (validateQNameField fieldMap)
    [ "source-qname", "evidence-type-qname", "approved-con-qname"
    , "rejected-con-qname"
    ]
  names <- traverse (lookupField fieldMap)
    ["evidence-type-qname", "approved-con-qname", "rejected-con-qname"]
  unless (Set.size (Set.fromList names) == 3) $
    Left "dependent evidence type/constructor identities are not distinct"
  decision <- lookupField fieldMap "decision"
  evidence <- lookupField fieldMap "evidence-kind"
  case (decision, evidence) of
    ("true", "approved") -> Right $ BaseDependentEvidence EvidenceApproved
    ("false", "rejected") -> Right $ BaseDependentEvidence EvidenceRejected
    _ -> Left "dependent decision/evidence indices do not correspond"

parseRuntimeIrV10 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV10 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "function-qname", "function-type"
    , "evidence-type-qname", "approved-con-qname", "rejected-con-qname"
    , "approved-result", "rejected-result", "call-decision", "call-evidence-kind"
    , "definition-count", "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "hcomp-empty-face"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "function-type" "dependent-decision-evidence-to-bool"
  requireField fieldMap "definition-count" "1"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  mapM_ (validateQNameField fieldMap)
    [ "source-qname", "function-qname", "evidence-type-qname"
    , "approved-con-qname", "rejected-con-qname"
    ]
  names <- traverse (lookupField fieldMap)
    [ "function-qname", "evidence-type-qname", "approved-con-qname"
    , "rejected-con-qname"
    ]
  unless (Set.size (Set.fromList names) == 4) $
    Left "dependent function/type/constructor identities are not distinct"
  approvedResult <- lookupField fieldMap "approved-result" >>= parseBoolBase
  rejectedResult <- lookupField fieldMap "rejected-result" >>= parseBoolBase
  decision <- lookupField fieldMap "call-decision"
  evidence <- lookupField fieldMap "call-evidence-kind"
  call <- case (decision, evidence) of
    ("true", "approved") -> Right EvidenceApproved
    ("false", "rejected") -> Right EvidenceRejected
    _ -> Left "dependent function call indices do not correspond"
  pure $ BaseDependentCall approvedResult rejectedResult call

parseRuntimeIrV11 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV11 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "type-family", "face"
    , "equivalence-qname", "base", "definition-count", "source-qname"
    , "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "transp"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "type-family" "glue-bool-identity"
  requireField fieldMap "face" "i0"
  requireField fieldMap "equivalence-qname"
    "Agda.Builtin.Cubical.Equiv._.pathToEquiv"
  requireField fieldMap "definition-count" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  BaseGlueTransp <$> (lookupField fieldMap "base" >>= parseBoolBase)

parseRuntimeIrV12 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV12 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "hit-type-qname", "left-qname"
    , "right-qname", "path-qname", "path-boundary", "tube-orientation", "face"
    , "definition-count", "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "hcomp-active-face"
  requireField fieldMap "value-type" "interval-hit"
  requireField fieldMap "path-boundary" "left-to-right"
  requireField fieldMap "face" "i1"
  requireField fieldMap "definition-count" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  mapM_ (validateQNameField fieldMap)
    [ "source-qname", "hit-type-qname", "left-qname", "right-qname"
    , "path-qname"
    ]
  names <- traverse (lookupField fieldMap)
    [ "hit-type-qname", "left-qname", "right-qname", "path-qname" ]
  unless (Set.size (Set.fromList names) == 4) $
    Left "active HIT type/left/right/path identities are not distinct"
  orientation <- lookupField fieldMap "tube-orientation" >>= \case
    "forward" -> Right TubeForward
    "reverse" -> Right TubeReverse
    _ -> Left "active HIT tube orientation identity mismatch"
  pure $ BaseActiveHit orientation

parseRuntimeIrV13 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV13 fieldMap = do
  requireFieldSet fieldMap
    [ "schema", "operation", "value-type", "type-family", "face"
    , "equivalence-qname", "equivalence-function-qname"
    , "equivalence-function-table", "base", "definition-count"
    , "source-qname", "agda-revision", "provider-revision"
    ]
  requireField fieldMap "operation" "transp"
  requireField fieldMap "value-type" "agda-builtin-bool"
  requireField fieldMap "type-family" "glue-bool-negation"
  requireField fieldMap "face" "i0"
  requireField fieldMap "equivalence-function-table"
    "false-to-true,true-to-false"
  requireField fieldMap "definition-count" "2"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  mapM_ (validateQNameField fieldMap)
    [ "source-qname", "equivalence-qname", "equivalence-function-qname" ]
  equivalenceName <- lookupField fieldMap "equivalence-qname"
  functionName <- lookupField fieldMap "equivalence-function-qname"
  unless (equivalenceName /= functionName) $
    Left "Glue equivalence and function identities are not distinct"
  BaseNegationGlueTransp <$> (lookupField fieldMap "base" >>= parseBoolBase)

parseRuntimeIrV14 :: Map.Map String String -> Either String BoolBase
parseRuntimeIrV14 fieldMap = do
  requireField fieldMap "language" "runtime-nbe-typed-ast-v1"
  requireField fieldMap "context-size" "0"
  requireField fieldMap "agda-revision" agdaRevision
  requireField fieldMap "provider-revision" providerRevision
  validateQNameField fieldMap "source-qname"
  count <- lookupField fieldMap "definition-count" >>= parseV14DefinitionCount
  let commonFields =
        [ "schema", "language", "context-size", "type-ast", "term-ast"
        , "definition-count", "source-qname", "agda-revision", "provider-revision"
        ]
      definitionFields = concat
        [ [ "def" ++ show index ++ "-qname"
          , "def" ++ show index ++ "-type-ast"
          , "def" ++ show index ++ "-body-ast"
          ]
        | index <- [0 .. count - 1]
        ]
  requireFieldSet fieldMap (commonFields ++ definitionFields)
  definitions <- traverse (parseV14Definition fieldMap) [0 .. count - 1]
  let names = [name | V14Definition name _ _ <- definitions]
  unless (Set.size (Set.fromList names) == length names) $
    Left "v14 definition QNames are not unique"
  typeAst <- lookupField fieldMap "type-ast" >>= parseV14Ast
  termAst <- lookupField fieldMap "term-ast" >>= parseV14Ast
  compileV14 typeAst termAst definitions

parseV14DefinitionCount :: String -> Either String Int
parseV14DefinitionCount value
  | null value || any (not . isDigit) value =
      Left "v14 definition-count is not a decimal integer"
  | otherwise = case reads value of
      [(count, "")]
        | count >= 0 && count <= 32 -> Right count
        | otherwise -> Left "v14 definition-count is outside 0..32"
      _ -> Left "v14 definition-count is malformed"

parseV14Definition
  :: Map.Map String String -> Int -> Either String V14Definition
parseV14Definition fields index = do
  let prefix = "def" ++ show index
  validateQNameField fields (prefix ++ "-qname")
  name <- lookupField fields (prefix ++ "-qname")
  definitionType <- lookupField fields (prefix ++ "-type-ast") >>= parseV14Ast
  body <- lookupField fields (prefix ++ "-body-ast") >>= parseV14Ast
  pure $ V14Definition name definitionType body

parseV14Ast :: String -> Either String V14Ast
parseV14Ast input = do
  validateV14TextDepth input
  case [ast | (ast, "") <- readP_to_S (v14AstP <* eof) input] of
    [ast] -> Right ast
    _ -> Left "v14 typed AST is malformed or has trailing input"

validateV14TextDepth :: String -> Either String ()
validateV14TextDepth = go 0
  where
    go depth [] = unless (depth == 0) $
      Left "v14 typed AST has unbalanced parentheses"
    go depth (character : rest)
      | character == '(' = do
          unless (depth < 32) $ Left "v14 typed AST exceeds depth 32"
          go (depth + 1) rest
      | character == ')' = do
          unless (depth > 0) $ Left "v14 typed AST has unbalanced parentheses"
          go (depth - 1) rest
      | otherwise = go depth rest

v14AstP :: ReadP V14Ast
v14AstP = do
  name <- munch1 validV14AstCharacter
  (do
      _ <- char '('
      children <- sepBy v14AstP (char ',')
      _ <- char ')'
      pure $ V14Node name children)
    <++ pure (V14Atom name)

validV14AstCharacter :: Char -> Bool
validV14AstCharacter character =
  isAlphaNum character || character `elem` ("._-" :: String)

compileV14 :: V14Ast -> V14Ast -> [V14Definition] -> Either String BoolBase
compileV14 typeAst termAst definitions = case (typeAst, termAst) of
  (V14Atom "bool", V14Node "hcomp" [V14Atom "i0", V14Atom "empty", body]) ->
    case definitions of
      [evidenceType, approved, rejected, definition]
        | isDependentDecisionDefinition definition -> do
            _ <- validateV14EvidenceDefinitions [evidenceType, approved, rejected]
            compileV14DependentCall definition body
      _ -> do
        boolDefinitions <- traverse parseV14BoolDefinition definitions
        mapM_ (validateDefinitionReferences (length boolDefinitions))
          (zip [0 ..] boolDefinitions)
        expression <- parseV14BoolExpression body
        validateExpressionReferences (length boolDefinitions) False expression
        pure $ BaseProgram boolDefinitions expression
  (V14Node "sigma" [V14Atom "bool", V14Atom "bool"],
      V14Node "hcomp" [V14Atom "i0", V14Atom "empty",
        V14Node "pair" [first, second]]) -> do
    requireNoV14Definitions definitions
    BaseBoolPair <$> parseV14ClosedBool first <*> parseV14ClosedBool second
  (V14Atom "bool", V14Node "transp"
      [V14Node "lambda-i" [V14Atom "bool"], V14Atom "i0", base]) -> do
    requireNoV14Definitions definitions
    BaseTransp <$> parseV14ClosedBool base
  (V14Atom "bool", V14Node "hcomp"
      [V14Atom "i1", V14Node "constant-system" [side], base]) -> do
    requireNoV14Definitions definitions
    BaseActiveHComp <$> parseV14ClosedBool side <*> parseV14ClosedBool base
  (V14Atom "bool", V14Node "unglue"
      [V14Node "glue" [V14Atom "bool", V14Atom "i0", V14Atom "empty", base]]) -> do
    requireNoV14Definitions definitions
    BaseGlue <$> parseV14ClosedBool base
  (V14Node "def" [V14Atom "0"], V14Node "hcomp"
      [V14Atom "i0", V14Atom "empty", base]) -> do
    _ <- validateV14HitDefinitions definitions
    BaseHit <$> parseV14HitBase base
  (V14Node "def" [V14Atom "0"], V14Node "hcomp"
      [V14Atom "i1", V14Node "hit-path-system" [orientation], base]) -> do
    _ <- validateV14HitDefinitions definitions
    parsedOrientation <- parseV14Orientation orientation
    expectedBase <- case parsedOrientation of
      TubeForward -> Right HitLeft
      TubeReverse -> Right HitRight
    actualBase <- parseV14HitBase base
    unless (actualBase == expectedBase) $
      Left "v14 active HIT tube orientation and base do not correspond"
    pure $ BaseActiveHit parsedOrientation
  (V14Node "sigma" [V14Atom "bool",
      V14Node "app" [V14Node "def" [V14Atom "0"], V14Node "var" [V14Atom "0"]]],
      V14Node "hcomp"
      [V14Atom "i0", V14Atom "empty", V14Node "pair" [decision, evidence]]) -> do
    _ <- validateV14EvidenceDefinitions definitions
    compileV14EvidencePair decision evidence
  (V14Atom "bool", V14Node "transp"
      [V14Node "glue-family"
        [V14Atom "identity", V14Node "def" [V14Atom "0"]],
        V14Atom "i0", base]) -> do
    validateV14IdentityEquivalence definitions
    BaseGlueTransp <$> parseV14ClosedBool base
  (V14Atom "bool", V14Node "transp"
      [V14Node "glue-family"
        [V14Atom "negation", V14Node "def" [V14Atom "0"],
          V14Node "def" [V14Atom "1"]], V14Atom "i0", base]) -> do
    validateV14NegationDefinitions definitions
    BaseNegationGlueTransp <$> parseV14ClosedBool base
  _ -> Left "v14 term does not check against its declared type in the supported grammar"

requireNoV14Definitions :: [V14Definition] -> Either String ()
requireNoV14Definitions definitions = unless (null definitions) $
  Left "v14 term carries definitions that are not referenced by its AST"

parseV14BoolDefinition :: V14Definition -> Either String BoolExpression
parseV14BoolDefinition (V14Definition _ definitionType body) = do
  unless (definitionType == V14Node "pi" [V14Atom "bool", V14Atom "bool"]) $
    Left "v14 Bool definition type is not pi(bool,bool)"
  parseV14BoolExpression body

parseV14BoolExpression :: V14Ast -> Either String BoolExpression
parseV14BoolExpression = \case
  V14Node "var" [V14Atom "0"] -> Right ExprArgument
  V14Atom "false" -> Right ExprFalse
  V14Atom "true" -> Right ExprTrue
  V14Node "app" [V14Node "def" [V14Atom indexText], argument]
    | not (null indexText) && all isDigit indexText -> do
        index <- maybe (Left "v14 definition index is malformed") Right $
          readMaybe indexText
        ExprApply index <$> parseV14BoolExpression argument
  _ -> Left "v14 Bool term is outside the typed AST grammar"

parseV14ClosedBool :: V14Ast -> Either String BoolBase
parseV14ClosedBool = \case
  V14Atom "false" -> Right BaseFalse
  V14Atom "true" -> Right BaseTrue
  _ -> Left "v14 closed Bool term is neither true nor false"

isDependentDecisionDefinition :: V14Definition -> Bool
isDependentDecisionDefinition (V14Definition _ definitionType body) =
  case (definitionType, body) of
    (V14Node "pi" [V14Atom "bool", V14Node "pi"
      [V14Node "app" [V14Node "def" [V14Atom "0"],
        V14Node "var" [V14Atom "0"]],
       V14Atom "bool"]], V14Node "case-evidence" [_, _]) -> True
    _ -> False

compileV14DependentCall :: V14Definition -> V14Ast -> Either String BoolBase
compileV14DependentCall
    (V14Definition _ definitionType (V14Node "case-evidence" [approved, rejected]))
    (V14Node "app" [V14Node "app"
      [V14Node "def" [V14Atom "3"], decision], evidence]) = do
  case definitionType of
    V14Node "pi" [V14Atom "bool", V14Node "pi"
      [V14Node "app" [V14Node "def" [V14Atom "0"],
        V14Node "var" [V14Atom "0"]], V14Atom "bool"]] -> Right ()
    _ -> Left "v14 dependent definition type is malformed"
  approvedResult <- parseV14ClosedBool approved
  rejectedResult <- parseV14ClosedBool rejected
  call <- compileV14EvidenceIndex decision evidence
  pure $ BaseDependentCall approvedResult rejectedResult call
compileV14DependentCall _ _ = Left "v14 dependent function call is malformed"

validateV14EvidenceDefinitions
  :: [V14Definition] -> Either String (String, String, String)
validateV14EvidenceDefinitions = \case
  [ V14Definition evidenceName (V14Node "pi" [V14Atom "bool", V14Atom "u"])
      (V14Node "evidence-family"
        [V14Node "def" [V14Atom "1"], V14Node "def" [V14Atom "2"]])
    , V14Definition approvedName
      (V14Node "evidence-constructor"
        [V14Node "def" [V14Atom "0"], V14Atom "true"])
      (V14Atom "approved-con")
    , V14Definition rejectedName
      (V14Node "evidence-constructor"
        [V14Node "def" [V14Atom "0"], V14Atom "false"])
      (V14Atom "rejected-con")
    ] -> Right (evidenceName, approvedName, rejectedName)
  _ -> Left "v14 evidence declaration closure is malformed"

compileV14EvidencePair :: V14Ast -> V14Ast -> Either String BoolBase
compileV14EvidencePair decision evidence =
  BaseDependentEvidence <$> compileV14EvidenceIndex decision evidence

compileV14EvidenceIndex :: V14Ast -> V14Ast -> Either String EvidenceKind
compileV14EvidenceIndex (V14Atom "true") (V14Atom "approved") = Right EvidenceApproved
compileV14EvidenceIndex (V14Atom "false") (V14Atom "rejected") = Right EvidenceRejected
compileV14EvidenceIndex _ _ = Left "v14 dependent decision/evidence indices do not correspond"

validateV14HitDefinitions
  :: [V14Definition] -> Either String (String, String, String, String)
validateV14HitDefinitions = \case
  [ V14Definition typeName (V14Atom "u")
      (V14Node "interval-hit-type"
        [ V14Node "def" [V14Atom "1"], V14Node "def" [V14Atom "2"]
        , V14Node "def" [V14Atom "3"]])
    , V14Definition leftName (V14Node "def" [V14Atom "0"])
      (V14Atom "hit-left-con")
    , V14Definition rightName (V14Node "def" [V14Atom "0"])
      (V14Atom "hit-right-con")
    , V14Definition pathName
      (V14Node "path"
        [ V14Node "def" [V14Atom "0"], V14Node "def" [V14Atom "1"]
        , V14Node "def" [V14Atom "2"]])
      (V14Atom "hit-path-con")
    ] -> Right (typeName, leftName, rightName, pathName)
  _ -> Left "v14 interval HIT declaration closure is malformed"

parseV14HitBase :: V14Ast -> Either String HitBase
parseV14HitBase = \case
  V14Atom "hit-left" -> Right HitLeft
  V14Atom "hit-right" -> Right HitRight
  V14Node "iapply" [V14Atom "hit-path", V14Atom "i0"] -> Right HitPathZero
  V14Node "iapply" [V14Atom "hit-path", V14Atom "i1"] -> Right HitPathOne
  _ -> Left "v14 HIT term is outside the declared point/path grammar"

parseV14Orientation :: V14Ast -> Either String TubeOrientation
parseV14Orientation = \case
  V14Atom "forward" -> Right TubeForward
  V14Atom "reverse" -> Right TubeReverse
  _ -> Left "v14 active HIT tube orientation is malformed"

validateV14IdentityEquivalence :: [V14Definition] -> Either String ()
validateV14IdentityEquivalence = \case
  [V14Definition name (V14Atom "path-to-equiv")
    (V14Atom "builtin-path-to-equiv")]
      | name == "Agda.Builtin.Cubical.Equiv._.pathToEquiv" -> Right ()
  _ -> Left "v14 identity Glue equivalence declaration closure is malformed"

validateV14NegationDefinitions :: [V14Definition] -> Either String ()
validateV14NegationDefinitions definitions = case definitions of
  [ V14Definition _ (V14Node "equiv" [V14Atom "bool", V14Atom "bool"])
      (V14Node "negation-equiv" [V14Node "def" [V14Atom "1"]])
    , V14Definition _ (V14Node "pi" [V14Atom "bool", V14Atom "bool"])
      (V14Atom "bool-not")
    ] -> Right ()
  _ -> Left "v14 negation Glue definition closure is malformed"

parseBoundedCount :: String -> Either String Int
parseBoundedCount value
  | null value || any (not . isDigit) value =
      Left "definition-count is not a decimal integer"
  | otherwise = case reads value of
      [(count, "")]
        | count >= 1 && count <= 32 -> Right count
        | otherwise -> Left "definition-count is outside 1..32"
      _ -> Left "definition-count is malformed"

parseDefinition :: Map.Map String String -> Int -> Either String BoolExpression
parseDefinition fields index = do
  let prefix = "def" ++ show index
  validateQNameField fields (prefix ++ "-qname")
  requireField fields (prefix ++ "-type") "pi-bool-bool"
  lookupField fields (prefix ++ "-body") >>= parseBoolExpression

parseBoolExpression :: String -> Either String BoolExpression
parseBoolExpression value
  | value == "arg0" = Right ExprArgument
  | value == "false" = Right ExprFalse
  | value == "true" = Right ExprTrue
  | otherwise = case stripPrefix "apply-def" value of
      Just rest -> do
        let (digits, suffix) = span isDigit rest
        unless (not (null digits) && not (null suffix)
          && head suffix == '(' && last suffix == ')') $
          Left "Bool expression has malformed definition application"
        index <- case reads digits of
          [(parsed, "")] -> Right parsed
          _ -> Left "Bool expression has malformed definition index"
        argument <- parseBoolExpression (init (tail suffix))
        Right (ExprApply index argument)
      Nothing -> Left "Bool expression is outside the supported definition slice"

validateDefinitionReferences
  :: Int -> (Int, BoolExpression) -> Either String ()
validateDefinitionReferences count (index, expression) =
  validateExpressionReferences (min count index) True expression

validateExpressionReferences :: Int -> Bool -> BoolExpression -> Either String ()
validateExpressionReferences referenceLimit allowArgument = go 0
  where
    go depth _ | depth > 32 = Left "Bool expression exceeds depth 32"
    go _ ExprArgument = unless allowArgument $
      Left "top-level Bool expression contains an open argument"
    go _ ExprFalse = Right ()
    go _ ExprTrue = Right ()
    go depth (ExprApply index argument) = do
      unless (index >= 0 && index < referenceLimit) $
        Left "Bool expression references a missing or forward definition"
      go (depth + 1) argument

requireFieldSet :: Map.Map String String -> [String] -> Either String ()
requireFieldSet fields expected =
  unless (Map.keysSet fields == Set.fromList expected) $
    Left "runtime IR field set is incomplete or unknown"

validateQNameField :: Map.Map String String -> String -> Either String ()
validateQNameField fields key = do
  value <- lookupField fields key
  unless (not (null value) && length value <= 256
          && all validSourceCharacter value) $
    Left (key ++ " is empty or malformed")

parseBoolBase :: String -> Either String BoolBase
parseBoolBase value = case value of
  "false" -> Right BaseFalse
  "true" -> Right BaseTrue
  _ -> Left "Bool base is neither true nor false"

parseBoolFunction :: String -> Either String BoolFunction
parseBoolFunction value = case value of
  "arg0" -> Right BoolIdentity
  "false" -> Right BoolConstantFalse
  "true" -> Right BoolConstantTrue
  _ -> Left "Bool function body is outside the supported definition slice"

parseField :: ByteString.ByteString -> Either String (String, String)
parseField line = case ByteString.break (== '=') line of
  (key, separatorAndValue)
    | ByteString.null key || ByteString.null separatorAndValue
        || ByteString.null (ByteString.tail separatorAndValue) ->
        Left "runtime IR contains an empty key or value"
    | otherwise -> Right
        (ByteString.unpack key, ByteString.unpack (ByteString.tail separatorAndValue))

lookupField :: Map.Map String String -> String -> Either String String
lookupField fields key = maybe (Left ("runtime IR lacks " ++ key)) Right $
  Map.lookup key fields

requireField :: Map.Map String String -> String -> String -> Either String ()
requireField fields key expected = do
  actual <- lookupField fields key
  unless (actual == expected) $ Left (key ++ " identity mismatch")

validSourceCharacter :: Char -> Bool
validSourceCharacter character =
  isAlphaNum character || character `elem` ("._-" :: String)

withReflectedProgram
  :: FilePath
  -> BoolBase
  -> (FilePath -> IO a)
  -> IO a
withReflectedProgram temporaryDirectory base action =
  bracket
    (openTempFile temporaryDirectory "runtime-nbe-reflect.cctt")
    cleanup
    (\(path, handle) -> do
      hPutStr handle (renderProgram base)
      hClose handle
      action path)
  where
    cleanup (path, handle) = do
      _ <- try (hClose handle) :: IO (Either IOException ())
      _ <- try (removeFile path) :: IO (Either IOException ())
      pure ()

renderProgram :: BoolBase -> String
renderProgram base = unlines
  [ "inductive Bool := false | true;"
  , renderFunctions base
  , renderResult base
  ]
  where
    renderFunctions (BaseApply function _) =
      "sliceDef0 : Bool -> Bool := \\x. " ++ renderFunctionBody function ++ ";"
    renderFunctions (BaseProgram definitions _) = unlines $
      zipWith renderIndexedFunction [0 :: Int ..] definitions
    renderFunctions _ = ""
    renderIndexedFunction index expression =
      "sliceDef" ++ show index ++ " : Bool -> Bool := \\x. " ++
      renderExpression expression ++ ";"
    renderFunctionBody BoolIdentity = "x"
    renderFunctionBody BoolConstantFalse = "false"
    renderFunctionBody BoolConstantTrue = "true"
    renderBase BaseFalse = "false"
    renderBase BaseTrue = "true"
    renderBase (BaseApply _ argument) = "(sliceDef0 " ++ renderBase argument ++ ")"
    renderBase (BaseProgram _ expression) = renderExpression expression
    renderBase (BaseBoolPair _ _) = error "nested Bool pair is unsupported"
    renderBase (BaseTransp _) = error "nested transp is unsupported"
    renderBase (BaseActiveHComp _ _) = error "nested active hcomp is unsupported"
    renderBase (BaseGlue _) = error "nested Glue is unsupported"
    renderBase (BaseHit _) = error "nested HIT is unsupported"
    renderBase (BaseActiveHit _) = error "nested active HIT is unsupported"
    renderBase (BaseDependentEvidence _) = error "nested dependent evidence is unsupported"
    renderBase (BaseDependentCall _ _ _) = error "nested dependent call is unsupported"
    renderBase (BaseGlueTransp _) = error "nested Glue transport is unsupported"
    renderBase (BaseNegationGlueTransp _) =
      error "nested negation Glue transport is unsupported"
    renderExpression ExprArgument = "x"
    renderExpression ExprFalse = "false"
    renderExpression ExprTrue = "true"
    renderExpression (ExprApply index argument) =
      "(sliceDef" ++ show index ++ " " ++ renderExpression argument ++ ")"
    renderResult (BaseBoolPair first second) =
      "runtimeResult : Bool × Bool := hcom 0 1 (Bool × Bool) [] " ++
      "(" ++ renderBase first ++ ", " ++ renderBase second ++ ");"
    renderResult (BaseTransp baseValue) =
      "runtimeResult : Bool := coe 0 1 (i. Bool) " ++
      renderBase baseValue ++ ";"
    renderResult (BaseActiveHComp sideValue baseValue) = unlines
      [ "runtimeResult : Bool :="
      , "  let active (i : I) : Bool := hcom 0 1 Bool [i=0 _. " ++
          renderBase sideValue ++ "] " ++ renderBase baseValue ++ ";"
      , "  active 0;"
      ]
    renderResult (BaseGlue baseValue) = unlines
      [ "gluedRuntimeValue : Glue Bool [] := glue " ++ renderBase baseValue ++ " [];"
      , "runtimeResult : Bool := unglue gluedRuntimeValue;"
      ]
    renderResult (BaseHit baseKind) = unlines
      [ "higher inductive RuntimeHit :="
      , "    runtimeLeft"
      , "  | runtimeRight"
      , "  | runtimeSegment (i : I) [i=0. runtimeLeft; i=1. runtimeRight];"
      , "runtimeResult : RuntimeHit := hcom 0 1 RuntimeHit [] " ++
          renderHitBase baseKind ++ ";"
      ]
    renderResult (BaseActiveHit orientation) = unlines
      [ "higher inductive RuntimeHit :="
      , "    runtimeLeft"
      , "  | runtimeRight"
      , "  | runtimeSegment (i : I) [i=0. runtimeLeft; i=1. runtimeRight];"
      , "runtimeActive (face : I) : RuntimeHit :="
      , case orientation of
          TubeForward ->
            "  hcom 0 1 RuntimeHit [face=0 j. runtimeSegment j] runtimeLeft;"
          TubeReverse ->
            "  hcom 1 0 RuntimeHit [face=0 j. runtimeSegment j] runtimeRight;"
      , "runtimeResult : RuntimeHit := runtimeActive 0;"
      ]
    renderResult (BaseDependentEvidence evidenceKind) = unlines
      [ "inductive Evidence (b : Bool) :="
      , "    approved (b = true)"
      , "  | rejected (b = false);"
      , "inductive Sg (A : U) (B : A -> U) := pair (a : A) (b : B a);"
      , "runtimeResult : Sg Bool (λ b. Evidence b) :="
      , "  hcom 0 1 (Sg Bool (λ b. Evidence b)) [] " ++
          renderEvidence evidenceKind ++ ";"
      ]
    renderResult (BaseDependentCall approvedResult rejectedResult call) = unlines
      [ "inductive Evidence (b : Bool) :="
      , "    approved (b = true)"
      , "  | rejected (b = false);"
      , "sliceDecision (b : Bool) (e : Evidence b) : Bool := case e (_. Bool) ["
      , "  approved p. " ++ renderBase approvedResult ++ ";"
      , "  rejected p. " ++ renderBase rejectedResult ++ "];"
      , "runtimeResult : Bool := hcom 0 1 Bool [] " ++
          renderDecisionCall call ++ ";"
      ]
    renderResult (BaseGlueTransp baseValue) = unlines
      [ "isEquiv (A B : U) (f : A -> B) : U :="
      , "    (g : B -> A)"
      , "  × (linv : (x : A) -> g (f x) = x)"
      , "  × (rinv : (x : B) -> f (g x) = x)"
      , "  × (coh : (x : A) -> (rinv (f x)) ={i. f (linv x i) = f x} refl);"
      , "equiv (A B : U) : U := (f : A -> B) × isEquiv A B f;"
      , "idEquiv (A : U) : equiv A A :="
      , "  (λ x. x, λ x. x, λ x _. x, λ x _. x, λ x _ _. x);"
      , "runtimeFamily (i : I) : U := Glue Bool [i=1. Bool, idEquiv Bool];"
      , "gluedRuntimeValue : runtimeFamily 0 := glue " ++ renderBase baseValue ++ " [];"
      , "runtimeResult : Bool := coe 0 1 runtimeFamily gluedRuntimeValue;"
      ]
    renderResult (BaseNegationGlueTransp baseValue) = unlines
      [ "runtimeNot (x : Bool) : Bool := case x (_. Bool) [false. true; true. false];"
      , "runtimeNotNot (x : Bool) : runtimeNot (runtimeNot x) = x :="
      , "  case x (x. runtimeNot (runtimeNot x) = x) [false. refl; true. refl];"
      , "runtimeIsEquiv (A B : U) (f : A -> B) : U :="
      , "    (g : B -> A)"
      , "  × (linv : (x : A) -> g (f x) = x)"
      , "  × (rinv : (x : B) -> f (g x) = x)"
      , "  × (coh : (x : A) -> (rinv (f x)) ={i. f (linv x i) = f x} refl);"
      , "runtimeEquiv (A B : U) : U := (f : A -> B) × runtimeIsEquiv A B f;"
      , "runtimeIsIso (A B : U) (f : A -> B) : U :="
      , "    (g : B -> A)"
      , "  × (linv : (x : A) -> g (f x) = x)"
      , "  × (rinv : (x : B) -> f (g x) = x);"
      , "runtimeIso (A B : U) : U := (f : A -> B) × runtimeIsIso A B f;"
      , "runtimeIdEquiv (A : U) : runtimeEquiv A A :="
      , "  (λ x. x, λ x. x, λ x _. x, λ x _. x, λ x _ _. x);"
      , "runtimeFiber (A B : U) (f : A -> B) (b : B) : U := (x : A) × f x = b;"
      , "runtimeFiberRefl (A B : U) (f : A -> B) (a : A) :"
      , "  runtimeFiber A B f (f a) := (a, refl);"
      , "runtimeContractIsoFiber (A B : U) (is : runtimeIso A B) (a : A)"
      , "  (fib : runtimeFiber A B is.f (is.f a)) :"
      , "  fib = runtimeFiberRefl A B is.f a :="
      , "  let sq (j k : I) : A :="
      , "      hcom k j [k=0 j. is.g (fib.2 j); k=1 _. fib.1] (is.linv (fib.1) k);"
      , "  let sq2 (i k : I) : A :="
      , "      hcom 0 k [i=0. sq 1; i=1. is.linv a] (is.g (is.f a));"
      , "  λ i."
      , "  (sq2 i 1,"
      , "   λ j."
      , "   let aux : A :="
      , "     hcom j 0 [i=0. sq j; i=1. is.linv a; j=1. sq2 i]"
      , "       (is.linv (sq2 i 1) j);"
      , "   hcom 0 1"
      , "     [i=0. is.rinv (fib.2 j); i=1. is.rinv (is.f a);"
      , "      j=0. is.rinv (is.f (sq2 i 1)); j=1. is.rinv (is.f a)]"
      , "     (is.f aux));"
      , "runtimeIsoToEquiv (A B : U) (is : runtimeIso A B) : runtimeEquiv A B :="
      , "    is.f"
      , "  , is.g"
      , "  , λ a i. (runtimeContractIsoFiber A B is a"
      , "      (is.g (is.f a), is.rinv (is.f a)) i).1"
      , "  , is.rinv"
      , "  , λ a i. (runtimeContractIsoFiber A B is a"
      , "      (is.g (is.f a), is.rinv (is.f a)) i).2;"
      , "runtimeNotIso : runtimeIso Bool Bool :="
      , "  (runtimeNot, runtimeNot, runtimeNotNot, runtimeNotNot);"
      , "runtimeNotEquiv : runtimeEquiv Bool Bool :="
      , "  runtimeIsoToEquiv Bool Bool runtimeNotIso;"
      , "runtimeFamily (i : I) : U := Glue Bool"
      , "  [i=0. Bool, runtimeNotEquiv; i=1. Bool, runtimeIdEquiv Bool];"
      , "runtimeResult : Bool := coe 0 1 runtimeFamily " ++ renderBase baseValue ++ ";"
      ]
    renderResult other =
      "runtimeResult : Bool := hcom 0 1 Bool [] " ++ renderBase other ++ ";"
    renderHitBase HitLeft = "runtimeLeft"
    renderHitBase HitRight = "runtimeRight"
    renderHitBase HitPathZero = "(runtimeSegment 0)"
    renderHitBase HitPathOne = "(runtimeSegment 1)"
    renderEvidence EvidenceApproved = "(pair true (approved refl))"
    renderEvidence EvidenceRejected = "(pair false (rejected refl))"
    renderDecisionCall EvidenceApproved = "(sliceDecision true (approved refl))"
    renderDecisionCall EvidenceRejected = "(sliceDecision false (rejected refl))"
