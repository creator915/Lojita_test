{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}

-- | Test-only feasibility spike for the future in-process NbE adapter.
--
-- This module deliberately does not expose a production engine switch.  It
-- proves that checked Agda Internal syntax can be evaluated through an
-- environment/closure semantic domain and quoted back without routing term
-- normalization through Agda's reducer.  The supported fragment is small and
-- fail-closed: variables, lambdas/applications, literals, constructors, and
-- ordinary single-clause/multi-clause function definitions with variable,
-- constructor, literal, or dot patterns, plus independent Type/Sort/Level
-- evaluation and readback for the ordinary Pi/universe fragment.
module CubicalChez.Nbe.AdapterSpike
  ( SpikeOutcome (..)
  , SpikeReport (..)
  , normalizeRequestSpike
  , spikeFuelLimit
  , spikeProviderIdentity
  ) where

import Agda.Compiler.Backend
import Agda.Syntax.Common
  ( Arg (..)
  , ArgInfo
  , Named (..)
  , NamedArg
  , ProjOrigin (..)
  , defaultArg
  )
import Agda.Syntax.Common.Pretty (prettyShow)
import Agda.Syntax.Internal
  ( Abs (..)
  , Clause (..)
  , ConHead
  , ConInfo
  , DBPatVar (..)
  , DeBruijnPattern
  , Elim' (..)
  , Dom
  , Level
  , Sort
  , Term
  , Type
  , Univ
  , telToList
  )
import qualified Agda.Syntax.Internal as Internal
import Agda.Syntax.Literal (Literal (..))
import qualified Agda.TypeChecking.Monad.Builtin as Builtin
import Agda.TypeChecking.Free (freeIn)
import qualified Agda.TypeChecking.Free as Free
import Control.Monad (foldM, forM)
import Control.Monad.Except
  ( ExceptT
  , MonadError (catchError, throwError)
  , runExceptT
  )
import Control.Monad.State.Strict
  ( StateT
  , gets
  , modify'
  , runStateT
  )
import Control.Monad.Trans.Class (lift)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Map.Strict as Map
import Data.List (findIndex)
import qualified Data.Set as Set
import Data.Maybe (isJust)
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)

data SpikeOutcome
  = SpikeSucceeded SpikeReport
  | SpikeUnsupported String
  | SpikeFuelExhausted String
  | SpikeRecursiveCycle String

data SpikeReport = SpikeReport
  { spikeNormalTerm :: Term
  , spikeNormalType :: Type
  , spikeEvaluationNanoseconds :: Word64
  , spikeReadbackNanoseconds :: Word64
  , spikeDefinitionCacheHits :: Int
  , spikeDefinitionCacheMisses :: Int
  , spikeMaximumCallDepth :: Int
  , spikeTypeNodesEvaluated :: Int
  , spikeSortNodesEvaluated :: Int
  , spikeLevelNodesEvaluated :: Int
  , spikeRecordProjectionsEvaluated :: Int
  , spikeNeutralRecordTypeHeadsPreserved :: Int
  , spikeNeutralDataTypeHeadsPreserved :: Int
  , spikeDefinitionsReduced :: Int
  , spikeHitDefinitionPatternsMatched :: Int
  , spikeMaximumLevelAtomCount :: Int
  , spikePrimitiveRegistryHits :: Int
  , spikePrimitivesReduced :: Int
  , spikeIntervalOperationsEvaluated :: Int
  , spikeNeutralCofibrationSimplifications :: Int
  , spikePathApplicationsEvaluated :: Int
  , spikeCompsExpanded :: Int
  , spikeTransportsReduced :: Int
  , spikeConstantNatTransportsReduced :: Int
  , spikeConstantNatFunctionTransportsReduced :: Int
  , spikeUniverseTransportsReduced :: Int
  , spikeGlueTransportsReduced :: Int
  , spikeBackwardGlueTransportsReduced :: Int
  , spikeComposedGlueTransportsReduced :: Int
  , spikePiTransportsReduced :: Int
  , spikeVaryingPiCodomainTransportsReduced :: Int
  , spikeSemanticConstantPiCodomainTransportsReduced :: Int
  , spikeDependentSelfPathPiCodomainTransportsReduced :: Int
  , spikeDependentSingletonPiCodomainTransportsReduced :: Int
  , spikeDependentReversedSingletonPiCodomainTransportsReduced :: Int
  , spikeDependentNestedSingletonPiCodomainTransportsReduced :: Int
  , spikeDependentReversedNestedSingletonPiCodomainTransportsReduced :: Int
  , spikeDependentSigmaSpinePiCodomainTransportsReduced :: Int
  , spikeDependentReversedSigmaSpinePiCodomainTransportsReduced :: Int
  , spikeDependentSigmaSpineFieldsTransported :: Int
  , spikeDependentSigmaSpineStableFieldsPreserved :: Int
  , spikeDependentSigmaSpineIndexedPiFieldsTransported :: Int
  , spikeIndexedPiFieldApplicationsEvaluated :: Int
  , spikeIndexedPiGroundPayloadFieldsPreserved :: Int
  , spikeClosedStableFunctionValuesValidated :: Int
  , spikeClosedStablePiTypeViewsValidated :: Int
  , spikeRecordTransportsReduced :: Int
  , spikeDataTransportsReduced :: Int
  , spikeGlueUnglueCancellations :: Int
  , spikeHCompsReduced :: Int
  , spikeFuelConsumed :: Int
  }

data SpikeFailure
  = Unsupported String
  | ExhaustedFuel String
  | RecursiveCycle String

type Environment = [SemanticValue]
type Bindings = Map.Map Int SemanticValue
type SpikeM = StateT SpikeState (ExceptT SpikeFailure TCM)

data SpikeState = SpikeState
  { remainingFuel :: Int
  , definitionCache :: Map.Map QName Definition
  , definitionCacheHits :: Int
  , definitionCacheMisses :: Int
  , activeGroundCalls :: Set.Set CallKey
  , currentCallDepth :: Int
  , maximumCallDepth :: Int
  , typeNodesEvaluated :: Int
  , sortNodesEvaluated :: Int
  , levelNodesEvaluated :: Int
  , recordProjectionsEvaluated :: Int
  , neutralRecordTypeHeadsPreserved :: Int
  , neutralDataTypeHeadsPreserved :: Int
  , definitionsReduced :: Int
  , hitDefinitionPatternsMatched :: Int
  , maximumLevelAtomCount :: Int
  , primitiveRegistryHits :: Int
  , primitivesReduced :: Int
  , intervalOperationsEvaluated :: Int
  , neutralCofibrationSimplifications :: Int
  , pathApplicationsEvaluated :: Int
  , compsExpanded :: Int
  , transportsReduced :: Int
  , constantNatTransportsReduced :: Int
  , constantNatFunctionTransportsReduced :: Int
  , universeTransportsReduced :: Int
  , glueTransportsReduced :: Int
  , backwardGlueTransportsReduced :: Int
  , composedGlueTransportsReduced :: Int
  , piTransportsReduced :: Int
  , varyingPiCodomainTransportsReduced :: Int
  , semanticConstantPiCodomainTransportsReduced :: Int
  , dependentSelfPathPiCodomainTransportsReduced :: Int
  , dependentSingletonPiCodomainTransportsReduced :: Int
  , dependentReversedSingletonPiCodomainTransportsReduced :: Int
  , dependentNestedSingletonPiCodomainTransportsReduced :: Int
  , dependentReversedNestedSingletonPiCodomainTransportsReduced :: Int
  , dependentSigmaSpinePiCodomainTransportsReduced :: Int
  , dependentReversedSigmaSpinePiCodomainTransportsReduced :: Int
  , dependentSigmaSpineFieldsTransported :: Int
  , dependentSigmaSpineStableFieldsPreserved :: Int
  , dependentSigmaSpineIndexedPiFieldsTransported :: Int
  , indexedPiFieldApplicationsEvaluated :: Int
  , indexedPiGroundPayloadFieldsPreserved :: Int
  , closedStableFunctionValuesValidated :: Int
  , closedStablePiTypeViewsValidated :: Int
  , recordTransportsReduced :: Int
  , dataTransportsReduced :: Int
  , glueUnglueCancellations :: Int
  , hCompsReduced :: Int
  }

data CallKey = CallKey QName [ValueShape]
  deriving (Eq, Ord)

data ValueShape
  = ShapeNat Integer
  | ShapeLiteral String
  | ShapeConstructor QName [ValueShape]
  deriving (Eq, Ord)

data PrimitiveOperator
  = PrimitiveNatPlus
  | PrimitiveNatMinus
  | PrimitiveNatTimes
  | PrimitiveIMin
  | PrimitiveIMax
  | PrimitiveINeg
  | PrimitiveTransp
  | PrimitiveHComp
  | PrimitiveComp
  | PrimitiveGlueType
  | PrimitiveGlue
  | PrimitiveUnglue

data ConstantTransportKind
  = ConstantTransportNat
  | ConstantTransportNatFunction
  | ConstantTransportUniverse

data GlueFamilyView = GlueFamilyView
  { glueFamilyBaseType :: SemanticValue
  , glueFamilyFace :: SemanticValue
  , glueFamilyPartialType :: SemanticValue
  , glueFamilyEquivalence :: SemanticValue
  }

data HCompFamilyView = HCompFamilyView
  { hCompFamilyType :: SemanticValue
  , hCompFamilyFace :: SemanticValue
  , hCompFamilySides :: SemanticValue
  , hCompFamilyBase :: SemanticValue
  }

data CanonicalGluePath = CanonicalGluePath
  { canonicalGlueSourceType :: SemanticValue
  , canonicalGlueTargetType :: SemanticValue
  , canonicalGlueEquivalence :: SemanticValue
  , canonicalGlueForward :: SemanticValue
  }

-- | A checked canonical Glue segment together with the direction in which
-- transport traverses it.  Keeping the direction explicit prevents a
-- backward boundary from being accidentally evaluated by the forward map.
data CanonicalGlueStep
  = CanonicalGlueForwardStep CanonicalGluePath
  | CanonicalGlueBackwardStep CanonicalGluePath

data CanonicalPiCodomainTransport
  = StablePiCodomain
  | SemanticConstantPiCodomain
  | DependentSelfPathPiCodomain
  | DependentSingletonPiCodomain DependentSingletonDirection
  | DependentNestedSingletonPiCodomain
      DependentSingletonDirection [DependentSigmaFieldTransport]
  | DependentSigmaSpinePiCodomain
      Int DependentSingletonDirection [DependentSigmaFieldTransport]
  | CanonicalPiCodomainPath CanonicalGluePath

data DependentSingletonDirection
  = SingletonBinderToField
  | SingletonFieldToBinder

-- | A field-by-field transport plan checked jointly at the open probe and
-- both endpoints.  The outer Sigma field is always the canonical domain
-- point; inner fields may either follow that path or remain definitionally
-- stable and therefore be preserved by identity.
data DependentSigmaFieldTransport
  = SigmaFieldCanonicalPath
  | SigmaFieldStableIdentity Int
  | SigmaFieldOuterIndexedPi IndexedPiFieldTransport

-- | A deliberately narrow contravariant domain plan for an auxiliary
-- function field.  The domain must be a non-indexed data family whose only
-- open parameter is the outer Sigma point.  Runtime constructors may carry
-- only exact ground payloads (Nat, literals, or builtin Bool); those payloads
-- are preserved while the parameter slot is rewritten from the target point
-- to the source point before the original function is called.
data IndexedPiFieldTransport = IndexedPiFieldTransport
  { indexedPiFieldDataName :: QName
  , indexedPiFieldParameterCount :: Int
  , indexedPiFieldOuterTypeParameter :: Maybe Int
  , indexedPiFieldOuterParameter :: Int
  }

-- | The spike has a deterministic recursion/evaluation ceiling.  Production
-- timeout and allocation policy remains a separate acceptance item.
spikeProviderIdentity :: String
spikeProviderIdentity = "agda-specific-in-process-v1"

spikeFuelLimit :: Int
#if defined(CUBICAL_CHEZ_TEST_NBE_ADAPTER_LOW_FUEL)
spikeFuelLimit = 32
#else
spikeFuelLimit = 100000
#endif

-- cctt-inspired semantic domain: closures retain an environment, constructor
-- arguments are semantic values, and open readback uses level-based neutrals.
data SemanticValue
  = VClosure ArgInfo (Abs Term) Environment
  | VCompMaxClosure SemanticValue SemanticValue
  | VCompSidesClosure SemanticValue SemanticValue SemanticValue
  | VCompSideClosure
      SemanticValue SemanticValue SemanticValue SemanticValue
  | VCanonicalPiTransport
      CanonicalGluePath CanonicalPiCodomainTransport SemanticValue
  | VOuterIndexedPiFieldTransport
      IndexedPiFieldTransport CanonicalGluePath
      SemanticValue SemanticValue SemanticValue
  | VReflexivePath SemanticValue
  | VPi (Dom SemanticType) (Abs Type) Environment
  | VSort SemanticSort
  | VLevel SemanticLevel
  | VNat Integer
  | VLiteral Literal
  | VConstructor ConHead ConInfo [Arg SemanticValue]
  | VIntervalProbe
  | VNeutral Neutral

data Neutral
  = NLevel Int
  | NDefinition QName [Arg SemanticValue]
  | NApplication Neutral (Arg SemanticValue)
  | NProjection Neutral ProjOrigin QName
  | NPrimitive QName PrimitiveOperator [Arg SemanticValue]

data SemanticType = VEl SemanticSort SemanticValue

data SemanticSort
  = VUniverse Univ SemanticLevel
  | VInfiniteUniverse Univ Integer
  | VSizeUniverse
  | VLockUniverse
  | VLevelUniverse
  | VIntervalUniverse
  | VPiUniverse
      (Dom SemanticValue)
      SemanticSort
      (Abs Sort)
      Environment
  | VFunctionUniverse SemanticSort SemanticSort
  | VUniverseOf SemanticSort

data SemanticLevel = VMaximum Integer [SemanticPlusLevel]

data SemanticPlusLevel = VPlus Integer SemanticValue

normalizeRequestSpike :: Term -> Type -> TCM SpikeOutcome
normalizeRequestSpike term ty = do
  let requestType = injectPostulatedSort ty
  result <- runExceptT $ runStateT
    (do
      (evaluatedTerm, termEvaluationNanoseconds) <-
        measureSpikeStage $ evalTerm [] term
      (normalTerm, termReadbackNanoseconds) <-
        measureSpikeStage $ quoteValue 0 evaluatedTerm
      (evaluatedType, typeEvaluationNanoseconds) <-
        measureSpikeStage $ evalType [] requestType
      (normalType, typeReadbackNanoseconds) <-
        measureSpikeStage $ quoteType 0 evaluatedType
      pure
        ( normalTerm
        , normalType
        , termEvaluationNanoseconds + typeEvaluationNanoseconds
        , termReadbackNanoseconds + typeReadbackNanoseconds
        ))
    initialSpikeState
  pure $ case result of
    Right
      ( ( normalTerm
        , normalType
        , evaluationNanoseconds
        , readbackNanoseconds
        )
      , finalState
      ) -> SpikeSucceeded SpikeReport
      { spikeNormalTerm = normalTerm
      , spikeNormalType = normalType
      , spikeEvaluationNanoseconds = evaluationNanoseconds
      , spikeReadbackNanoseconds = readbackNanoseconds
      , spikeDefinitionCacheHits = definitionCacheHits finalState
      , spikeDefinitionCacheMisses = definitionCacheMisses finalState
      , spikeMaximumCallDepth = maximumCallDepth finalState
      , spikeTypeNodesEvaluated = typeNodesEvaluated finalState
      , spikeSortNodesEvaluated = sortNodesEvaluated finalState
      , spikeLevelNodesEvaluated = levelNodesEvaluated finalState
      , spikeRecordProjectionsEvaluated =
          recordProjectionsEvaluated finalState
      , spikeNeutralRecordTypeHeadsPreserved =
          neutralRecordTypeHeadsPreserved finalState
      , spikeNeutralDataTypeHeadsPreserved =
          neutralDataTypeHeadsPreserved finalState
      , spikeDefinitionsReduced = definitionsReduced finalState
      , spikeHitDefinitionPatternsMatched =
          hitDefinitionPatternsMatched finalState
      , spikeMaximumLevelAtomCount = maximumLevelAtomCount finalState
      , spikePrimitiveRegistryHits = primitiveRegistryHits finalState
      , spikePrimitivesReduced = primitivesReduced finalState
      , spikeIntervalOperationsEvaluated =
          intervalOperationsEvaluated finalState
      , spikeNeutralCofibrationSimplifications =
          neutralCofibrationSimplifications finalState
      , spikePathApplicationsEvaluated =
          pathApplicationsEvaluated finalState
      , spikeCompsExpanded = compsExpanded finalState
      , spikeTransportsReduced = transportsReduced finalState
      , spikeConstantNatTransportsReduced =
          constantNatTransportsReduced finalState
      , spikeConstantNatFunctionTransportsReduced =
          constantNatFunctionTransportsReduced finalState
      , spikeUniverseTransportsReduced =
          universeTransportsReduced finalState
      , spikeGlueTransportsReduced =
          glueTransportsReduced finalState
      , spikeBackwardGlueTransportsReduced =
          backwardGlueTransportsReduced finalState
      , spikeComposedGlueTransportsReduced =
          composedGlueTransportsReduced finalState
      , spikePiTransportsReduced = piTransportsReduced finalState
      , spikeVaryingPiCodomainTransportsReduced =
          varyingPiCodomainTransportsReduced finalState
      , spikeSemanticConstantPiCodomainTransportsReduced =
          semanticConstantPiCodomainTransportsReduced finalState
      , spikeDependentSelfPathPiCodomainTransportsReduced =
          dependentSelfPathPiCodomainTransportsReduced finalState
      , spikeDependentSingletonPiCodomainTransportsReduced =
          dependentSingletonPiCodomainTransportsReduced finalState
      , spikeDependentReversedSingletonPiCodomainTransportsReduced =
          dependentReversedSingletonPiCodomainTransportsReduced finalState
      , spikeDependentNestedSingletonPiCodomainTransportsReduced =
          dependentNestedSingletonPiCodomainTransportsReduced finalState
      , spikeDependentReversedNestedSingletonPiCodomainTransportsReduced =
          dependentReversedNestedSingletonPiCodomainTransportsReduced finalState
      , spikeDependentSigmaSpinePiCodomainTransportsReduced =
          dependentSigmaSpinePiCodomainTransportsReduced finalState
      , spikeDependentReversedSigmaSpinePiCodomainTransportsReduced =
          dependentReversedSigmaSpinePiCodomainTransportsReduced finalState
      , spikeDependentSigmaSpineFieldsTransported =
          dependentSigmaSpineFieldsTransported finalState
      , spikeDependentSigmaSpineStableFieldsPreserved =
          dependentSigmaSpineStableFieldsPreserved finalState
      , spikeDependentSigmaSpineIndexedPiFieldsTransported =
          dependentSigmaSpineIndexedPiFieldsTransported finalState
      , spikeIndexedPiFieldApplicationsEvaluated =
          indexedPiFieldApplicationsEvaluated finalState
      , spikeIndexedPiGroundPayloadFieldsPreserved =
          indexedPiGroundPayloadFieldsPreserved finalState
      , spikeClosedStableFunctionValuesValidated =
          closedStableFunctionValuesValidated finalState
      , spikeClosedStablePiTypeViewsValidated =
          closedStablePiTypeViewsValidated finalState
      , spikeRecordTransportsReduced = recordTransportsReduced finalState
      , spikeDataTransportsReduced = dataTransportsReduced finalState
      , spikeGlueUnglueCancellations =
          glueUnglueCancellations finalState
      , spikeHCompsReduced = hCompsReduced finalState
      , spikeFuelConsumed = spikeFuelLimit - remainingFuel finalState
      }
    Left (Unsupported problem) -> SpikeUnsupported problem
    Left (ExhaustedFuel problem) -> SpikeFuelExhausted problem
    Left (RecursiveCycle problem) -> SpikeRecursiveCycle problem

measureSpikeStage :: SpikeM value -> SpikeM (value, Word64)
measureSpikeStage action = do
  started <- liftIO getMonotonicTimeNSec
  value <- action
  finished <- liftIO getMonotonicTimeNSec
  pure (value, finished - started)

injectPostulatedSort :: Type -> Type
#if defined(CUBICAL_CHEZ_TEST_NBE_POSTULATED_SORT)
injectPostulatedSort (Internal.El _ term@(Internal.Def definition eliminations)) =
  Internal.El (Internal.DefS definition eliminations) term
injectPostulatedSort ty = ty
#else
injectPostulatedSort = id
#endif

initialSpikeState :: SpikeState
initialSpikeState = SpikeState
  { remainingFuel = spikeFuelLimit
  , definitionCache = Map.empty
  , definitionCacheHits = 0
  , definitionCacheMisses = 0
  , activeGroundCalls = Set.empty
  , currentCallDepth = 0
  , maximumCallDepth = 0
  , typeNodesEvaluated = 0
  , sortNodesEvaluated = 0
  , levelNodesEvaluated = 0
  , recordProjectionsEvaluated = 0
  , neutralRecordTypeHeadsPreserved = 0
  , neutralDataTypeHeadsPreserved = 0
  , definitionsReduced = 0
  , hitDefinitionPatternsMatched = 0
  , maximumLevelAtomCount = 0
  , primitiveRegistryHits = 0
  , primitivesReduced = 0
  , intervalOperationsEvaluated = 0
  , neutralCofibrationSimplifications = 0
  , pathApplicationsEvaluated = 0
  , compsExpanded = 0
  , transportsReduced = 0
  , constantNatTransportsReduced = 0
  , constantNatFunctionTransportsReduced = 0
  , universeTransportsReduced = 0
  , glueTransportsReduced = 0
  , backwardGlueTransportsReduced = 0
  , composedGlueTransportsReduced = 0
  , piTransportsReduced = 0
  , varyingPiCodomainTransportsReduced = 0
  , semanticConstantPiCodomainTransportsReduced = 0
  , dependentSelfPathPiCodomainTransportsReduced = 0
  , dependentSingletonPiCodomainTransportsReduced = 0
  , dependentReversedSingletonPiCodomainTransportsReduced = 0
  , dependentNestedSingletonPiCodomainTransportsReduced = 0
  , dependentReversedNestedSingletonPiCodomainTransportsReduced = 0
  , dependentSigmaSpinePiCodomainTransportsReduced = 0
  , dependentReversedSigmaSpinePiCodomainTransportsReduced = 0
  , dependentSigmaSpineFieldsTransported = 0
  , dependentSigmaSpineStableFieldsPreserved = 0
  , dependentSigmaSpineIndexedPiFieldsTransported = 0
  , indexedPiFieldApplicationsEvaluated = 0
  , indexedPiGroundPayloadFieldsPreserved = 0
  , closedStableFunctionValuesValidated = 0
  , closedStablePiTypeViewsValidated = 0
  , recordTransportsReduced = 0
  , dataTransportsReduced = 0
  , glueUnglueCancellations = 0
  , hCompsReduced = 0
  }

consumeFuel :: String -> SpikeM ()
consumeFuel location = do
  remaining <- gets remainingFuel
  if remaining <= 0
    then throwError $ ExhaustedFuel $
      "fuel-exhausted: adapter spike exhausted its deterministic fuel while "
        ++ location
    else modify' $ \state -> state {remainingFuel = remaining - 1}

unsupported :: String -> SpikeM a
unsupported = throwError . Unsupported

evalTerm :: Environment -> Term -> SpikeM SemanticValue
evalTerm environment term = do
  consumeFuel "evaluating a term"
  case term of
    Internal.Var index eliminations -> do
      value <- case drop index environment of
        value' : _ -> pure value'
        [] -> unsupported $ "open variable escaped the adapter environment: "
          ++ show index
      evalEliminations environment value eliminations
    Internal.Lam argumentInfo abstraction ->
      pure $ VClosure argumentInfo abstraction environment
    Internal.Lit (LitNat natural) -> pure $ VNat natural
    Internal.Lit literal -> pure $ VLiteral literal
    Internal.Con constructor info eliminations -> do
      headValue <- makeConstructorHead constructor info
      evalEliminations environment headValue eliminations
    Internal.Def definition eliminations ->
      evalEliminations environment
        (VNeutral $ NDefinition definition []) eliminations
    Internal.DontCare ignored -> evalTerm environment ignored
    Internal.Pi domain codomain -> do
      evaluatedDomain <- traverse (evalType environment) domain
      pure $ VPi evaluatedDomain codomain environment
    Internal.Sort sort -> VSort <$> evalSort environment sort
    Internal.Level level -> VLevel <$> evalLevel environment level
    Internal.MetaV {} -> unsupported "metavariables are outside the spike fragment"
    Internal.Dummy {} -> unsupported "dummy terms are outside the spike fragment"

evalEliminations
  :: Environment
  -> SemanticValue
  -> [Elim' Term]
  -> SpikeM SemanticValue
evalEliminations environment = foldM step
  where
    step value = \case
      Apply argument -> do
        evaluated <- traverse (evalTerm environment) argument
        applyValue value evaluated
      Proj origin projection -> projectValue origin projection value
      IApply _ _ interval -> do
        evaluatedInterval <- evalTerm environment interval
        case value of
          VClosure {} -> applyPathValue evaluatedInterval
          VCompMaxClosure {} -> applyPathValue evaluatedInterval
          VCompSidesClosure {} -> applyPathValue evaluatedInterval
          VCompSideClosure {} -> applyPathValue evaluatedInterval
          VReflexivePath {} -> applyPathValue evaluatedInterval
          VConstructor {} -> applyPathValue evaluatedInterval
          VNeutral (NDefinition _ _) -> applyPathValue evaluatedInterval
          VNeutral (NPrimitive _ _ _) -> applyPathValue evaluatedInterval
          _ -> unsupported $
            "path application requires a lambda closure or reducible "
              ++ "definition in the spike fragment; value="
              ++ semanticValueShape value
      where
        applyPathValue evaluatedInterval = do
            modify' $ \state -> state
              { pathApplicationsEvaluated =
                  pathApplicationsEvaluated state + 1 }
            applyValue value $ defaultArg evaluatedInterval

projectValue
  :: ProjOrigin
  -> QName
  -> SemanticValue
  -> SpikeM SemanticValue
projectValue origin projection originalReceiver = do
  consumeFuel $ "projecting " ++ prettyShow projection
  projectionDefinition <- getConstInfoCached projection
  projectionInfo <- case theDef projectionDefinition of
    Function {funProjection = Right info} -> pure info
    _ -> unsupported $
      "definition is not a record projection: " ++ prettyShow projection
  recordName <- case projProper projectionInfo of
    Just name -> pure name
    Nothing -> unsupported $
      "projection-like definition is not a proper record projection: "
        ++ prettyShow projection
  recordDefinition <- getConstInfoCached recordName
  fields <- case theDef recordDefinition of
    Record {recFields = recordFields} -> pure recordFields
    _ -> unsupported $
      "projection metadata names a non-record definition: "
        ++ prettyShow recordName
  let isSelectedField field =
        let fieldName = Internal.unDom field
        in fieldName == projection || fieldName == projOrig projectionInfo
  fieldIndex <- case findIndex isSelectedField fields of
    Just index -> pure index
    Nothing -> unsupported $
      "record metadata does not contain projection field "
        ++ prettyShow projection
        ++ " in "
        ++ prettyShow recordName
  modify' $ \state -> state
    { recordProjectionsEvaluated = recordProjectionsEvaluated state + 1 }
  let receiver = projectionReceiver originalReceiver
  case receiver of
    VConstructor constructor _ arguments -> do
      constructorDefinition <- getConstInfoCached $
        Internal.conName constructor
      (constructorRecord, parameterCount) <-
        case theDef constructorDefinition of
          Constructor {conData = dataName, conPars = parameters} ->
            pure (dataName, parameters)
          _ -> unsupported $
            "record projection receiver metadata is not a constructor: "
              ++ prettyShow (Internal.conName constructor)
      if constructorRecord /= recordName
        then unsupported $
          "record projection receiver constructor belongs to "
            ++ prettyShow constructorRecord
            ++ ", not "
            ++ prettyShow recordName
        else case recordFieldArguments
          parameterCount
          (length fields)
          arguments of
            Just fieldArguments
              | fieldIndex < length fieldArguments ->
                  pure $ unArg $ fieldArguments !! fieldIndex
            _ -> unsupported $
              "record projection receiver has an invalid field spine: "
                ++ prettyShow projection
    VNeutral neutral@(NDefinition definition arguments) -> do
      unfolded <- reduceDefinition definition arguments
      case unfolded of
        VNeutral (NDefinition definition' arguments')
          | definition' == definition
          , length arguments' == length arguments -> do
              copatternResult <- reduceDefinitionProjection
                definition
                arguments
                projection
              pure $ case copatternResult of
                Just result -> result
                Nothing -> VNeutral $ NProjection neutral origin projection
        _ -> projectValue origin projection unfolded
    VNeutral neutral -> pure $ VNeutral $
      NProjection neutral origin projection
    _ -> unsupported $
      "record projection receiver is neither a record constructor nor "
        ++ "a neutral value: "
        ++ prettyShow projection
projectionReceiver :: SemanticValue -> SemanticValue
#if defined(CUBICAL_CHEZ_TEST_NBE_BAD_PROJECTION_RECEIVER)
projectionReceiver _ = VNat 0
#else
projectionReceiver = id
#endif

recordFieldArguments
  :: Int
  -> Int
  -> [Arg SemanticValue]
  -> Maybe [Arg SemanticValue]
recordFieldArguments parameterCount fieldCount arguments
  | length arguments == fieldCount = Just arguments
  | length arguments == parameterCount + fieldCount =
      Just $ drop parameterCount arguments
  | otherwise = Nothing

reduceDefinitionProjection
  :: QName
  -> [Arg SemanticValue]
  -> QName
  -> SpikeM (Maybe SemanticValue)
reduceDefinitionProjection definition arguments projection = do
  definitionInfo <- getConstInfoCached definition
  case theDef definitionInfo of
    Function {funClauses = clauses} -> choose clauses
    _ -> pure Nothing
  where
    choose [] = pure Nothing
    choose (clause : rest) = case reverse $ namedClausePats clause of
      projectionPattern : reversedPatterns
        | Internal.ProjP _ expectedProjection <-
            namedThing $ unArg projectionPattern
        , expectedProjection == projection -> do
            let patterns = reverse reversedPatterns
            if length patterns /= length arguments
              then choose rest
              else do
                matched <- matchPatterns patterns arguments
                case (matched, clauseBody clause) of
                  (Just bindings, Just _) -> do
                    modify' $ \state -> state
                      { definitionsReduced = definitionsReduced state + 1 }
                    Just <$> evalClause definition clause bindings
                  _ -> choose rest
      _ -> choose rest

applyValue :: SemanticValue -> Arg SemanticValue -> SpikeM SemanticValue
applyValue value argument = do
  consumeFuel "applying a semantic value"
  case value of
    VClosure _ abstraction closureEnvironment -> case abstraction of
      Abs _ body -> evalTerm (unArg argument : closureEnvironment) body
      NoAbs _ body -> evalTerm closureEnvironment body
    VCompMaxClosure family fixedInterval -> do
      maximumInterval <- applyPrimitiveBuiltin
        Builtin.builtinIMax
        [argument, defaultArg fixedInterval]
      applyValue family $ maximumInterval <$ argument
    VCompSidesClosure levelFamily typeFamily sides ->
      pure $ VCompSideClosure
        levelFamily typeFamily sides (unArg argument)
    VCompSideClosure levelFamily typeFamily sides fillInterval -> do
      partialAtInterval <- applyValue sides $ defaultArg fillInterval
      element <- applyValue partialAtInterval argument
      applyCompForward
        levelFamily typeFamily fillInterval element
    VCanonicalPiTransport domainPath codomainTransport function -> do
      sourceArgument <- applyCanonicalGlueBackward
        domainPath
        (unArg argument)
      sourceResult <- applyValue function $ defaultArg sourceArgument
      case codomainTransport of
        StablePiCodomain -> pure sourceResult
        SemanticConstantPiCodomain -> do
          modify' $ \state -> state
            { semanticConstantPiCodomainTransportsReduced =
                semanticConstantPiCodomainTransportsReduced state + 1 }
          pure sourceResult
        DependentSelfPathPiCodomain -> do
          sourceIsReflexive <- isReflexivePathAt sourceArgument sourceResult
          if sourceIsReflexive
            then do
              modify' $ \state -> state
                { dependentSelfPathPiCodomainTransportsReduced =
                    dependentSelfPathPiCodomainTransportsReduced state + 1 }
              pure $ VReflexivePath $ unArg argument
            else unsupported $
              "dependent self-path Pi source function is not pointwise reflexive"
        DependentSingletonPiCodomain direction -> case sourceResult of
          VConstructor constructor info arguments -> do
            belongsToSigma <- constructorBelongsToBuiltin
              Builtin.builtinSigma constructor
            fields <- if belongsToSigma
              then recordConstructorFields sourceResult
              else pure []
            case fields of
              [sourceFirst, sourceSecond]
                | sameGroundValue sourceArgument $ unArg sourceFirst -> do
                    sourceIsReflexive <- isReflexivePathAt
                      sourceArgument
                      (unArg sourceSecond)
                    if sourceIsReflexive
                      then do
                        let targetPoint = unArg argument
                            targetFields =
                              [ targetPoint <$ sourceFirst
                              , VReflexivePath targetPoint <$ sourceSecond
                              ]
                            targetArguments = replaceTrailingArguments
                              2 arguments targetFields
                        modify' $ \state -> case direction of
                          SingletonBinderToField -> state
                            { dependentSingletonPiCodomainTransportsReduced =
                                dependentSingletonPiCodomainTransportsReduced state + 1 }
                          SingletonFieldToBinder -> state
                            { dependentReversedSingletonPiCodomainTransportsReduced =
                                dependentReversedSingletonPiCodomainTransportsReduced state + 1 }
                        pure $ VConstructor constructor info targetArguments
                      else unsupported $
                        "dependent singleton Pi source proof is not reflexive"
              _ -> unsupported $
                "dependent singleton Pi source function did not return its source point"
          _ -> unsupported $
            "dependent singleton Pi source function did not return a Sigma constructor"
        DependentNestedSingletonPiCodomain direction fieldPlan -> do
          targetResult <- transportCanonicalSigmaSpine
            domainPath fieldPlan 2
            sourceArgument (unArg argument) sourceResult
          modify' $ \state -> case direction of
            SingletonBinderToField -> state
              { dependentNestedSingletonPiCodomainTransportsReduced =
                  dependentNestedSingletonPiCodomainTransportsReduced state + 1 }
            SingletonFieldToBinder -> state
              { dependentReversedNestedSingletonPiCodomainTransportsReduced =
                  dependentReversedNestedSingletonPiCodomainTransportsReduced state + 1 }
          pure targetResult
        DependentSigmaSpinePiCodomain depth direction fieldPlan -> do
          targetResult <- transportCanonicalSigmaSpine
            domainPath fieldPlan depth
            sourceArgument (unArg argument) sourceResult
          modify' $ \state -> case direction of
            SingletonBinderToField -> state
              { dependentSigmaSpinePiCodomainTransportsReduced =
                  dependentSigmaSpinePiCodomainTransportsReduced state + 1 }
            SingletonFieldToBinder -> state
              { dependentReversedSigmaSpinePiCodomainTransportsReduced =
                  dependentReversedSigmaSpinePiCodomainTransportsReduced state + 1 }
          pure targetResult
        CanonicalPiCodomainPath codomainPath ->
          if not $ isGroundValue sourceResult
            then unsupported $
              "canonical varying Pi codomain requires a ground source result"
            else do
              targetResult <- applyValue
                (canonicalGlueForward codomainPath)
                (defaultArg sourceResult)
              if not $ isGroundValue targetResult
                then unsupported $
                  "canonical varying Pi codomain produced a non-ground target result"
                else do
                  modify' $ \state -> state
                    { varyingPiCodomainTransportsReduced =
                        varyingPiCodomainTransportsReduced state + 1 }
                  pure targetResult
    VOuterIndexedPiFieldTransport
        plan domainPath sourcePoint targetPoint function -> do
      sourceArgument <- remapOuterIndexedPiFieldArgument
        plan domainPath sourcePoint targetPoint (unArg argument)
      result <- applyValue function $ sourceArgument <$ argument
      modify' $ \state -> state
        { indexedPiFieldApplicationsEvaluated =
            indexedPiFieldApplicationsEvaluated state + 1
        }
      pure result
    VReflexivePath point -> pure point
    VPi {} -> unsupported "attempted to apply a Pi semantic value"
    VSort {} -> unsupported "attempted to apply a Sort semantic value"
    VLevel {} -> unsupported "attempted to apply a Level semantic value"
    VIntervalProbe -> unsupported "attempted to apply an interval probe"
    VConstructor constructor info arguments -> do
      isSuc <- isBuiltinConstructor Builtin.builtinSuc constructor
      case (isSuc, arguments, unArg argument) of
        (True, [], VNat natural) -> pure $ VNat (natural + 1)
        _ -> pure $ VConstructor constructor info (arguments ++ [argument])
    VNeutral (NDefinition definition arguments) ->
      reduceDefinition definition (arguments ++ [argument])
    VNeutral (NPrimitive definition operator arguments) ->
      applyPrimitive definition operator (arguments ++ [argument])
    VNeutral neutral -> pure $ VNeutral $ NApplication neutral argument
    VNat _ -> unsupported "attempted to apply a Nat value in the spike"
    VLiteral _ -> unsupported "attempted to apply a literal in the spike"

transportCanonicalSigmaSpine
  :: CanonicalGluePath
  -> [DependentSigmaFieldTransport]
  -> Int
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM SemanticValue
transportCanonicalSigmaSpine path fieldPlan depth sourcePoint targetPoint =
  rebuild True depth fieldPlan
  where
  rebuild isOuter remaining remainingPlan sourceValue
    | remaining <= 0 = unsupported $
        "dependent Sigma spine transport requires a positive depth"
    | otherwise = case remainingPlan of
      [] -> unsupported $
        "dependent Sigma spine transport plan ended before the value spine"
      fieldTransport : restPlan -> case sourceValue of
        VConstructor constructor info arguments -> do
          belongsToSigma <- constructorBelongsToBuiltin
            Builtin.builtinSigma constructor
          fields <- if belongsToSigma
            then recordConstructorFields sourceValue
            else pure []
          case fields of
            [sourceFirst, sourceRest] -> do
              targetFirst <- if isOuter
                then case fieldTransport of
                  SigmaFieldCanonicalPath
                    | sameGroundValue sourcePoint (unArg sourceFirst) ->
                        pure targetPoint
                    | otherwise -> unsupported $
                        "dependent Sigma spine outer point is not the source argument"
                  SigmaFieldStableIdentity _ -> unsupported $
                    "dependent Sigma spine outer field cannot use stable identity"
                  SigmaFieldOuterIndexedPi _ -> unsupported $
                    "dependent Sigma spine outer field cannot use indexed Pi transport"
                else transportAuxiliaryPoint
                  fieldTransport $ unArg sourceFirst
              targetRest <- if remaining == 1
                then if null restPlan
                then do
                  sourceIsReflexive <- isReflexivePathAt
                    sourcePoint (unArg sourceRest)
                  if sourceIsReflexive
                    then pure $ VReflexivePath targetPoint
                    else unsupported $
                      "dependent Sigma spine source proof is not reflexive"
                else unsupported $
                  "dependent Sigma spine transport plan exceeds the value spine"
                else rebuild False (remaining - 1) restPlan (unArg sourceRest)
              let targetFields =
                    [ targetFirst <$ sourceFirst
                    , targetRest <$ sourceRest
                    ]
                  targetArguments = replaceTrailingArguments
                    2 arguments targetFields
              pure $ VConstructor constructor info targetArguments
            _ -> unsupported $
              "dependent Sigma spine source value is not canonical"
        _ -> unsupported $
          "dependent Sigma spine source value is not a Sigma constructor"

  transportAuxiliaryPoint fieldTransport sourceField = case fieldTransport of
    SigmaFieldStableIdentity closedPiViewCount
      -> do
          sourceIsStable <- isStableIdentityFieldValue sourceField
          if not sourceIsStable
            then unsupported $
              "dependent Sigma spine stable auxiliary point is not a closed supported value"
            else do
              modify' $ \state -> state
                { dependentSigmaSpineStableFieldsPreserved =
                    dependentSigmaSpineStableFieldsPreserved state + 1
                , closedStablePiTypeViewsValidated =
                    closedStablePiTypeViewsValidated state
                      + closedPiViewCount
                }
              pure sourceField
    SigmaFieldOuterIndexedPi indexedPiPlan -> do
      sourceIsSupported <- isSupportedIndexedPiSourceFunction sourceField
      if not sourceIsSupported
        then unsupported $
          "dependent Sigma spine indexed Pi field is not a closed ordinary function: "
            ++ semanticValueShape sourceField
        else do
          modify' $ \state -> state
            { dependentSigmaSpineIndexedPiFieldsTransported =
                dependentSigmaSpineIndexedPiFieldsTransported state + 1
            }
          pure $ VOuterIndexedPiFieldTransport
            indexedPiPlan path sourcePoint targetPoint sourceField
    SigmaFieldCanonicalPath
      | sameGroundValue sourcePoint sourceField -> pure targetPoint
      | not $ isGroundValue sourceField -> unsupported $
          "dependent Sigma spine auxiliary source point is not ground"
      | otherwise -> do
        targetField <- applyValue
          (canonicalGlueForward path) (defaultArg sourceField)
        if not $ isGroundValue targetField
          then unsupported $
            "dependent Sigma spine auxiliary target point is not ground"
          else do
            roundTrip <- applyCanonicalGlueBackward path targetField
            if sameGroundValue sourceField roundTrip
              then do
                modify' $ \state -> state
                  { dependentSigmaSpineFieldsTransported =
                      dependentSigmaSpineFieldsTransported state + 1 }
                pure targetField
              else unsupported $
                "dependent Sigma spine auxiliary point failed round-trip"

  isSupportedIndexedPiSourceFunction = \case
    VClosure {} -> pure True
    value@(VNeutral (NDefinition definition _)) -> do
      definitionInfo <- getConstInfoCached definition
      case theDef definitionInfo of
        Function {funClauses = clauses}
          | not $ null clauses -> isClosedOrdinaryFunctionReadback value
        _ -> pure False
    _ -> pure False

  isClosedOrdinaryFunctionReadback value =
    (Free.closed <$> quoteValue 0 value)
      `catchError` \failure -> case failure of
        Unsupported _ -> pure False
        _ -> throwError failure

remapOuterIndexedPiFieldArgument
  :: IndexedPiFieldTransport
  -> CanonicalGluePath
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM SemanticValue
remapOuterIndexedPiFieldArgument
    plan domainPath sourcePoint targetPoint = \case
  VConstructor constructor info arguments -> do
    constructorDefinition <- getConstInfoCached $ Internal.conName constructor
    metadata <- case theDef constructorDefinition of
      Constructor
        { conData = dataName
        , conPars = parameterCount
        , conArity = payloadArity
        } -> pure (dataName, parameterCount, payloadArity)
      _ -> unsupported $
        "indexed Pi field argument metadata is not a constructor"
    let (constructorData, constructorParameters, constructorPayload) = metadata
        expectedParameters = indexedPiFieldParameterCount plan
        outerTypeParameter = indexedPiFieldOuterTypeParameter plan
        outerParameter = indexedPiFieldOuterParameter plan
        payloadTypesAreIndependent = constructorPayloadTypesAreIndependent
          constructorDefinition expectedParameters constructorPayload
    if constructorData /= indexedPiFieldDataName plan
      then unsupported $
        "indexed Pi field argument belongs to a different data family"
      else if constructorParameters /= expectedParameters
        then unsupported $
          "indexed Pi field argument constructor parameter count changed"
        else if not payloadTypesAreIndependent
          then unsupported $
            "indexed Pi field argument constructor payload types depend on prior binders"
        else if length arguments /= constructorPayload
            && length arguments /= expectedParameters + constructorPayload
          then unsupported $
            "indexed Pi field argument has a malformed constructor spine"
          else do
            let parametersAreExplicit =
                  length arguments == expectedParameters + constructorPayload
                (parameterArguments, payloadArguments) =
                  if parametersAreExplicit
                    then splitAt expectedParameters arguments
                    else ([], arguments)
            payloadIsSupported <- and <$> traverse
              (isIndexedPiGroundPayloadValue . unArg) payloadArguments
            if not payloadIsSupported
              then unsupported $
                "indexed Pi field argument has an unsupported constructor payload"
              else if null parameterArguments
                then preserveGroundPayloads payloadArguments $
                  VConstructor constructor info arguments
                else if outerParameter < 0
                    || outerParameter >= length parameterArguments
                    || maybe False
                      (\position -> position < 0
                        || position >= length parameterArguments
                        || position == outerParameter)
                      outerTypeParameter
                  then unsupported $
                    "indexed Pi field argument has a malformed explicit parameter spine"
                  else do
                    let targetParameter =
                          unArg $ parameterArguments !! outerParameter
                        targetTypeParameter =
                          (unArg . (parameterArguments !!)) <$> outerTypeParameter
                        remappedPositions =
                          outerParameter : maybe [] pure outerTypeParameter
                        otherParameters =
                          [ unArg parameter
                          | (index, parameter) <- zip [0 ..] parameterArguments
                          , index `notElem` remappedPositions
                          ]
                    otherParametersAreClosed <- and <$> traverse
                      isClosedStableTypeValue otherParameters
                    targetTypeMatches <- case targetTypeParameter of
                      Just targetType -> sameSemanticReadback
                        targetType (canonicalGlueTargetType domainPath)
                      Nothing -> pure True
                    if not (isGroundValue sourcePoint)
                        || not (sameGroundValue targetPoint targetParameter)
                        || not targetTypeMatches
                        || not otherParametersAreClosed
                      then unsupported $
                        "indexed Pi field argument parameters failed checked remapping"
                      else do
                        let replaceParameter position value parameters =
                              take position parameters
                                ++ [value <$ parameters !! position]
                                ++ drop (position + 1) parameters
                            pointRemapped = replaceParameter
                              outerParameter sourcePoint parameterArguments
                            remappedParameters = case outerTypeParameter of
                              Just typePosition -> replaceParameter
                                typePosition
                                (canonicalGlueSourceType domainPath)
                                pointRemapped
                              Nothing -> pointRemapped
                        preserveGroundPayloads payloadArguments $
                          VConstructor constructor info
                            (remappedParameters ++ payloadArguments)
  _ -> unsupported $
    "indexed Pi field transport requires a canonical constructor argument"
  where
  preserveGroundPayloads payloadArguments value = do
    modify' $ \state -> state
      { indexedPiGroundPayloadFieldsPreserved =
          indexedPiGroundPayloadFieldsPreserved state
            + length payloadArguments
      }
    pure value

isIndexedPiGroundPayloadValue :: SemanticValue -> SpikeM Bool
isIndexedPiGroundPayloadValue = \case
  VNat _ -> pure True
  VLiteral _ -> pure True
  VConstructor constructor _ [] -> do
    isTrue <- isBuiltinConstructor Builtin.builtinTrue constructor
    isFalse <- isBuiltinConstructor Builtin.builtinFalse constructor
    pure $ isTrue || isFalse
  _ -> pure False

-- | Payload values are preserved rather than transported, so their declared
-- constructor-field types must be independent of every preceding data
-- parameter and payload binder.  Inspecting the checked constructor type is
-- stricter than looking only at the endpoint value: a field of outer type @A@
-- can contain a Bool at both endpoints while still requiring transport along
-- the universe path.
constructorPayloadTypesAreIndependent :: Definition -> Int -> Int -> Bool
constructorPayloadTypesAreIndependent definition parameterCount payloadArity =
  case takePiDomains (parameterCount + payloadArity) $ defType definition of
    Just domains -> all
      (Free.closed . Internal.unDom)
      (take payloadArity $ drop parameterCount domains)
    Nothing -> False
  where
  takePiDomains remaining _ | remaining <= 0 = Just []
  takePiDomains remaining (Internal.El _ term) = case term of
    Internal.Pi domain codomain -> do
      rest <- takePiDomains (remaining - 1) $ case codomain of
        Abs _ body -> body
        NoAbs _ body -> body
      pure $ domain : rest
    _ -> Nothing

applyBuiltin
  :: Builtin.BuiltinId
  -> [Arg SemanticValue]
  -> SpikeM SemanticValue
applyBuiltin builtinId arguments = do
  builtinTerm <- lift $ lift $ Builtin.getBuiltin builtinId
  evalTerm [] builtinTerm >>= applyArguments arguments

applyPrimitiveBuiltin
  :: Builtin.PrimitiveId
  -> [Arg SemanticValue]
  -> SpikeM SemanticValue
applyPrimitiveBuiltin primitiveId arguments = do
  primitiveTerm <- lift $ lift $ Builtin.getPrimitiveTerm primitiveId
  evalTerm [] primitiveTerm >>= applyArguments arguments

applyCompForward
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM SemanticValue
applyCompForward levelFamily typeFamily face element =
  applyPrimitiveBuiltin Builtin.builtinTrans
    [ defaultArg $ VCompMaxClosure levelFamily face
    , defaultArg $ VCompMaxClosure typeFamily face
    , defaultArg face
    , defaultArg element
    ]

makeConstructorHead :: ConHead -> ConInfo -> SpikeM SemanticValue
makeConstructorHead constructor info = do
  isZero <- isBuiltinConstructor Builtin.builtinZero constructor
  pure $ if isZero
    then VNat 0
    else VConstructor constructor info []

isBuiltinConstructor :: Builtin.BuiltinId -> ConHead -> SpikeM Bool
isBuiltinConstructor builtinId constructor = do
  builtinName <- lift $ lift $ Builtin.getBuiltinName' builtinId
  pure $ builtinName == Just (Internal.conName constructor)

reduceDefinition :: QName -> [Arg SemanticValue] -> SpikeM SemanticValue
reduceDefinition definition arguments = do
  consumeFuel $ "unfolding " ++ prettyShow definition
  definitionInfo <- getConstInfoCached definition
  case theDef definitionInfo of
    Function {funClauses = clauses}
      | null clauses -> unsupported $
          "function has no clauses: " ++ prettyShow definition
      | otherwise -> case filter hasClauseBody clauses of
          [] -> unsupported $
            "function has only absurd clauses: " ++ prettyShow definition
          executableClauses
            | all ((> length arguments) . length . namedClausePats)
                executableClauses ->
                  pure $ VNeutral $ NDefinition definition arguments
            | otherwise ->
                withGroundCall definition arguments $
                  chooseClause clauses clauses
    Primitive {primName = primitiveName} ->
      case classifyPrimitive primitiveName of
        Just operator -> do
          modify' $ \state -> state
            { primitiveRegistryHits = primitiveRegistryHits state + 1 }
          applyPrimitive definition operator arguments
        Nothing -> unsupportedDefinitionNode
          "term-eval"
          ("Primitive(" ++ show primitiveName ++ ")")
          definition
          "primitive is absent from agda-primitive-id-v4"
    Axiom {} -> do
      isPathP <- isBuiltinQName Builtin.builtinPathP definition
      if isPathP
        then pure $ VNeutral $ NDefinition definition arguments
        else unsupportedDefinitionNode
          "term-eval"
          "Axiom"
          definition
          "postulated definitions cannot be reduced"
    Record {} -> do
      modify' $ \state -> state
        { neutralRecordTypeHeadsPreserved =
            neutralRecordTypeHeadsPreserved state + 1 }
      pure $ VNeutral $ NDefinition definition arguments
    Datatype {} -> do
      modify' $ \state -> state
        { neutralDataTypeHeadsPreserved =
            neutralDataTypeHeadsPreserved state + 1 }
      pure $ VNeutral $ NDefinition definition arguments
    _ -> unsupportedDefinitionNode
      "term-eval"
      "Definition"
      definition
      "definition is not an ordinary reducible function"
  where
    hasClauseBody clause = case clauseBody clause of
      Just _ -> True
      Nothing -> False

    chooseClause originalClauses [] = unsupported $
      "unsupported-node: stage=term-eval; node-kind=FunctionClauses; qname="
        ++ prettyShow definition
        ++ "; source-range="
        ++ prettyShow (nameBindingSite $ qnameName definition)
        ++ "; no clause matched a fully applied definition; clauses="
        ++ show (map clauseShape originalClauses)
        ++ "; arguments="
        ++ show (map (semanticValueShape . unArg) arguments)
    chooseClause originalClauses (clause : rest) = do
      let patterns = namedClausePats clause
          (consumed, extra) = splitAt (length patterns) arguments
      matched <- matchPatterns patterns consumed
      case matched of
        Nothing -> chooseClause originalClauses rest
        Just _ | clauseBody clause == Nothing ->
          chooseClause originalClauses rest
        Just bindings -> do
          modify' $ \state -> state
            { definitionsReduced = definitionsReduced state + 1 }
          evalClause definition clause bindings >>= applyArguments extra

    clauseShape clause =
      ( case clauseBody clause of
          Just _ -> "body"
          Nothing -> "absurd"
      , map (patternShape . namedThing . unArg) $ namedClausePats clause
      )

    patternShape = \case
      Internal.VarP {} -> "var"
      Internal.DotP {} -> "dot"
      Internal.LitP {} -> "lit"
      Internal.ConP constructor _ _ ->
        "con:" ++ prettyShow (Internal.conName constructor)
      Internal.IApplyP {} -> "iapply"
      Internal.ProjP {} -> "proj"
      Internal.DefP _ definition' _ -> "def:" ++ prettyShow definition'

classifyPrimitive :: PrimitiveId -> Maybe PrimitiveOperator
classifyPrimitive = \case
  PrimNatPlus -> Just PrimitiveNatPlus
  PrimNatMinus -> Just PrimitiveNatMinus
  PrimNatTimes -> Just PrimitiveNatTimes
  PrimIMin -> Just PrimitiveIMin
  PrimIMax -> Just PrimitiveIMax
  PrimINeg -> Just PrimitiveINeg
  PrimTrans -> Just PrimitiveTransp
  PrimHComp -> Just PrimitiveHComp
  PrimComp -> Just PrimitiveComp
  PrimGlue -> Just PrimitiveGlueType
  Prim_glue -> Just PrimitiveGlue
  Prim_unglue -> Just PrimitiveUnglue
  _ -> Nothing

applyPrimitive
  :: QName
  -> PrimitiveOperator
  -> [Arg SemanticValue]
  -> SpikeM SemanticValue
applyPrimitive definition operator arguments =
  case operator of
    PrimitiveNatPlus -> applyNatPrimitive (+)
    PrimitiveNatMinus -> applyNatPrimitive $ \left right ->
      max 0 (left - right)
    PrimitiveNatTimes -> applyNatPrimitive (*)
    PrimitiveIMin -> applyIntervalBinary True (&&)
    PrimitiveIMax -> applyIntervalBinary False (||)
    PrimitiveINeg -> applyIntervalNegation
    PrimitiveTransp -> applyTransp
    PrimitiveHComp -> applyHComp
    PrimitiveComp -> applyComp
    PrimitiveGlueType -> applyGlueType
    PrimitiveGlue -> applyGlue
    PrimitiveUnglue -> applyUnglue
  where
    neutral consumed = VNeutral $ NPrimitive definition operator consumed

    applyNatPrimitive operation = case splitAt 2 arguments of
      (_, []) | length arguments < 2 -> pure $ neutral arguments
      ([left, right], extra) -> do
        primitiveResult <- case (unArg left, unArg right) of
          (VNat leftNat, VNat rightNat) -> do
            recordPrimitiveReduction
            pure $ VNat $ operation leftNat rightNat
          _ -> pure $ neutral [left, right]
        applyArguments extra primitiveResult
      _ -> unsupported "Nat primitive argument splitting invariant failed"

    applyIntervalBinary isMinimum operation = case splitAt 2 arguments of
      (_, []) | length arguments < 2 -> pure $ neutral arguments
      ([left, right], extra) -> do
        leftEndpoint <- intervalEndpoint $ unArg left
        rightEndpoint <- intervalEndpoint $ unArg right
        primitiveResult <- case (leftEndpoint, rightEndpoint) of
          (Just leftValue, Just rightValue) -> do
            recordIntervalReduction
            let result = operation leftValue rightValue
            pure $ if result == leftValue then unArg left else unArg right
          (Just leftValue, Nothing) -> do
            recordNeutralCofibrationSimplification
            pure $ if leftValue == not isMinimum
              then unArg left
              else unArg right
          (Nothing, Just rightValue) -> do
            recordNeutralCofibrationSimplification
            pure $ if rightValue == not isMinimum
              then unArg right
              else unArg left
          (Nothing, Nothing) -> pure $ neutral [left, right]
        applyArguments extra primitiveResult
      _ -> unsupported "interval binary argument splitting invariant failed"

    applyIntervalNegation = case splitAt 1 arguments of
      (_, []) | null arguments -> pure $ neutral arguments
      ([argument], extra) -> do
        primitiveResult <- case unArg argument of
          VNeutral (NPrimitive _ PrimitiveINeg [inner]) -> do
            recordNeutralCofibrationSimplification
            pure $ unArg inner
          _ -> do
            endpoint <- intervalEndpoint $ unArg argument
            case endpoint of
              Just _ -> recordIntervalReduction
              Nothing -> pure ()
            pure $ neutral [argument]
        applyArguments extra primitiveResult
      _ -> unsupported "interval negation argument splitting invariant failed"

    applyTransp = case splitAt 4 arguments of
      (_, []) | length arguments < 4 -> pure $ neutral arguments
      ([level, family, face, base], extra) -> do
        endpoint <- intervalEndpoint $ unArg face
        constantFamily <- classifyConstantTransportFamily $ unArg family
        glueResult <- case (endpoint, constantFamily) of
          (Just False, Nothing) -> reduceCanonicalGlueTransport
            (unArg family)
            (unArg face)
            (unArg base)
          _ -> pure Nothing
        primitiveResult <- case (endpoint, constantFamily, glueResult) of
          (Just True, _, _) -> do
            recordPrimitiveReduction
            modify' $ \state -> state
              { transportsReduced = transportsReduced state + 1 }
            pure $ unArg base
          (_, Just ConstantTransportNat, _) -> do
            recordPrimitiveReduction
            modify' $ \state -> state
              { transportsReduced = transportsReduced state + 1
              , constantNatTransportsReduced =
                  constantNatTransportsReduced state + 1
              }
            pure $ unArg base
          (_, Just ConstantTransportNatFunction, _) -> do
            recordPrimitiveReduction
            modify' $ \state -> state
              { transportsReduced = transportsReduced state + 1
              , constantNatFunctionTransportsReduced =
                  constantNatFunctionTransportsReduced state + 1
              }
            pure $ unArg base
          (_, Just ConstantTransportUniverse, _) -> do
            recordPrimitiveReduction
            modify' $ \state -> state
              { transportsReduced = transportsReduced state + 1
              , universeTransportsReduced =
                  universeTransportsReduced state + 1
              }
            pure $ unArg base
          (_, _, Just result) -> do
            recordPrimitiveReduction
            modify' $ \state -> state
              { transportsReduced = transportsReduced state + 1
              , glueTransportsReduced = glueTransportsReduced state + 1
              }
            pure result
          _ -> pure $ neutral [level, family, face, base]
        applyArguments extra primitiveResult
      _ -> unsupported "transp argument splitting invariant failed"

    applyHComp = case splitAt 5 arguments of
      (_, []) | length arguments < 5 -> pure $ neutral arguments
      ([level, valueType, face, sides, base], extra) -> do
        endpoint <- intervalEndpoint $ unArg face
        natType <- isBuiltinDefinition Builtin.builtinNat $ unArg valueType
        primitiveResult <- case (endpoint, natType) of
          (Just True, _) -> do
            intervalOne <- applyBuiltin Builtin.builtinIOne []
            faceProof <- applyBuiltin Builtin.builtinItIsOne []
            sideAtOne <- applyValue
              (unArg sides)
              (defaultArg intervalOne)
            result <- applyValue sideAtOne $ defaultArg faceProof
            recordPrimitiveReduction
            modify' $ \state -> state
              { hCompsReduced = hCompsReduced state + 1 }
            pure result
          (Just False, True) -> do
            recordPrimitiveReduction
            modify' $ \state -> state
              { hCompsReduced = hCompsReduced state + 1 }
            pure $ unArg base
          _ -> pure $ neutral [level, valueType, face, sides, base]
        applyArguments extra primitiveResult
      _ -> unsupported "hcomp argument splitting invariant failed"

    -- This is the same CCHM expansion used by Agda's mkComp: transport each
    -- boundary value forward from its fill coordinate, then hcomp at i1.
    -- The auxiliary semantic closures are internal and may not escape
    -- readback; unsupported transport/hcomp shapes therefore still fail
    -- closed.
    applyComp = case splitAt 5 arguments of
      (_, []) | length arguments < 5 -> pure $ neutral arguments
      ([levelFamily, typeFamily, face, sides, base], extra) -> do
        intervalOne <- applyBuiltin Builtin.builtinIOne []
        intervalZero <- applyBuiltin Builtin.builtinIZero []
        endpoint <- intervalEndpoint $ unArg face
        primitiveResult <- case endpoint of
          Just True -> do
            sideAtOne <- applyValue
              (unArg sides)
              (defaultArg intervalOne)
            faceProof <- applyBuiltin Builtin.builtinItIsOne []
            applyValue sideAtOne $ defaultArg faceProof
          _ -> do
            levelAtOne <- applyValue
              (unArg levelFamily)
              (defaultArg intervalOne)
            typeAtOne <- applyValue
              (unArg typeFamily)
              (defaultArg intervalOne)
            baseAtOne <- applyCompForward
              (unArg levelFamily)
              (unArg typeFamily)
              intervalZero
              (unArg base)
            let transportedSides = VCompSidesClosure
                  (unArg levelFamily)
                  (unArg typeFamily)
                  (unArg sides)
            applyPrimitiveBuiltin Builtin.builtinHComp
              [ levelAtOne <$ levelFamily
              , typeAtOne <$ typeFamily
              , face
              , transportedSides <$ sides
              , baseAtOne <$ base
              ]
        recordPrimitiveReduction
        modify' $ \state -> state
          { compsExpanded = compsExpanded state + 1 }
        applyArguments extra primitiveResult
      _ -> unsupported "comp argument splitting invariant failed"

    applyGlueType = case splitAt 6 arguments of
      (_, []) | length arguments < 6 -> pure $ neutral arguments
      (consumed, extra) -> applyArguments extra $ neutral consumed

    applyGlue = case splitAt 8 arguments of
      (_, []) | length arguments < 8 -> pure $ neutral arguments
      (consumed, extra) -> applyArguments extra $ neutral consumed

    applyUnglue = case splitAt 7 arguments of
      (_, []) | length arguments < 7 -> pure $ neutral arguments
      ([levelA, levelT, valueType, face, partialType, equivalence, glued], extra) -> do
        primitiveResult <- case unArg glued of
          VNeutral (NPrimitive _ PrimitiveGlue glueArguments)
            | length glueArguments == 8 -> do
                recordPrimitiveReduction
                modify' $ \state -> state
                  { glueUnglueCancellations =
                      glueUnglueCancellations state + 1 }
                pure $ unArg $ glueArguments !! 7
          _ -> pure $ neutral
            [ levelA, levelT, valueType, face, partialType, equivalence, glued ]
        applyArguments extra primitiveResult
      _ -> unsupported "unglue argument splitting invariant failed"

recordPrimitiveReduction :: SpikeM ()
recordPrimitiveReduction = modify' $ \state -> state
  { primitivesReduced = primitivesReduced state + 1 }

recordIntervalReduction :: SpikeM ()
recordIntervalReduction = modify' $ \state -> state
  { primitivesReduced = primitivesReduced state + 1
  , intervalOperationsEvaluated = intervalOperationsEvaluated state + 1
  }

recordNeutralCofibrationSimplification :: SpikeM ()
recordNeutralCofibrationSimplification = modify' $ \state -> state
  { primitivesReduced = primitivesReduced state + 1
  , intervalOperationsEvaluated = intervalOperationsEvaluated state + 1
  , neutralCofibrationSimplifications =
      neutralCofibrationSimplifications state + 1
  }

intervalEndpoint :: SemanticValue -> SpikeM (Maybe Bool)
intervalEndpoint = \case
  VConstructor constructor _ [] -> do
    isZero <- isBuiltinConstructor Builtin.builtinIZero constructor
    isOne <- isBuiltinConstructor Builtin.builtinIOne constructor
    pure $ if isZero then Just False else if isOne then Just True else Nothing
  VNeutral (NPrimitive _ PrimitiveINeg [argument]) ->
    fmap not <$> intervalEndpoint (unArg argument)
  VNeutral (NPrimitive _ PrimitiveIMin [left, right]) -> do
    leftEndpoint <- intervalEndpoint $ unArg left
    rightEndpoint <- intervalEndpoint $ unArg right
    pure $ (&&) <$> leftEndpoint <*> rightEndpoint
  VNeutral (NPrimitive _ PrimitiveIMax [left, right]) -> do
    leftEndpoint <- intervalEndpoint $ unArg left
    rightEndpoint <- intervalEndpoint $ unArg right
    pure $ (||) <$> leftEndpoint <*> rightEndpoint
  _ -> pure Nothing

isBuiltinDefinition
  :: Builtin.BuiltinId
  -> SemanticValue
  -> SpikeM Bool
isBuiltinDefinition builtinId = \case
  VNeutral (NDefinition definition []) -> do
    isBuiltinQName builtinId definition
  _ -> pure False

isBuiltinQName :: Builtin.BuiltinId -> QName -> SpikeM Bool
isBuiltinQName builtinId definition = do
  builtinName <- lift $ lift $ Builtin.getBuiltinName' builtinId
  pure $ builtinName == Just definition

classifyConstantTransportFamily
  :: SemanticValue
  -> SpikeM (Maybe ConstantTransportKind)
classifyConstantTransportFamily family = case family of
  VClosure {} -> classifyAppliedFamily
  VCompMaxClosure {} -> classifyAppliedFamily
  _ -> pure Nothing
  where
    classifyAppliedFamily =
      applyValue family (defaultArg VIntervalProbe) >>=
        classifyConstantTransportType

classifyConstantTransportType
  :: SemanticValue
  -> SpikeM (Maybe ConstantTransportKind)
classifyConstantTransportType value = do
  isNat <- isBuiltinDefinition Builtin.builtinNat value
  if isNat
    then pure $ Just ConstantTransportNat
    else case value of
      VSort {} -> pure $ Just ConstantTransportUniverse
      VPi domain codomain closureEnvironment -> do
        domainIsNat <- isBuiltinNatSemanticType $ Internal.unDom domain
        codomainIsNat <- if domainIsNat
          then case codomain of
            NoAbs _ body ->
              evalType closureEnvironment body >>= isBuiltinNatSemanticType
            Abs _ body
              | not (freeIn 0 body) ->
                  evalType (VNat 0 : closureEnvironment) body >>=
                    isBuiltinNatSemanticType
            _ -> pure False
          else pure False
        pure $ if codomainIsNat
          then Just ConstantTransportNatFunction
          else Nothing
      _ -> pure Nothing

isBuiltinNatSemanticType :: SemanticType -> SpikeM Bool
isBuiltinNatSemanticType (VEl _ value) =
  isBuiltinDefinition Builtin.builtinNat value

-- | Recognise the canonical Glue family generated by univalence without
-- relying on the library QName for @ua@.  Direct canonical Glue paths and the
-- exact double-composition shell used by homogeneous path composition are
-- admitted.  The composed rule requires a constant left boundary, a canonical
-- Glue centre and right boundary, and matching intermediate closed types.
reduceCanonicalGlueTransport
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe SemanticValue)
reduceCanonicalGlueTransport family startInterval base
  | isApplicableFamily family = do
    probeFamily <- applyValue family $ defaultArg VIntervalProbe
    startFamily <- applyValue family $ defaultArg startInterval
    intervalOneTerm <- lift $ lift $ Builtin.getBuiltin Builtin.builtinIOne
    intervalOne <- evalTerm [] intervalOneTerm
    endFamily <- applyValue family $ defaultArg intervalOne
    proofTerm <- lift $ lift $ Builtin.getBuiltin Builtin.builtinItIsOne
    faceProof <- evalTerm [] proofTerm
    directPath <- classifyCanonicalGluePath
      faceProof probeFamily startFamily endFamily
    case directPath of
      Just path -> Just <$> applyValue
        (canonicalGlueForward path)
        (defaultArg base)
      Nothing -> do
        backwardPath <- classifyCanonicalBackwardGluePath
          faceProof probeFamily startFamily endFamily
        case backwardPath of
          Just path -> do
            result <- applyCanonicalGlueBackward path base
            modify' $ \state -> state
              { backwardGlueTransportsReduced =
                  backwardGlueTransportsReduced state + 1 }
            pure $ Just result
          Nothing -> do
            intervalZeroTerm <- lift $ lift $
              Builtin.getBuiltin Builtin.builtinIZero
            intervalZero <- evalTerm [] intervalZeroTerm
            probeHCompResult <- reduceCanonicalProbeHCompTransport
              faceProof
              intervalZero
              intervalOne
              probeFamily
              startFamily
              endFamily
              base
            case probeHCompResult of
              Just result -> do
                modify' $ \state -> state
                  { composedGlueTransportsReduced =
                      composedGlueTransportsReduced state + 1 }
                pure $ Just result
              Nothing -> do
                composedResult <- reduceCanonicalComposedGlueTransport
                  faceProof
                  intervalZero
                  intervalOne
                  probeFamily
                  startFamily
                  endFamily
                  base
                case composedResult of
                  Just result -> pure $ Just result
                  Nothing -> do
                    piResult <- reduceCanonicalPiTransport
                      faceProof probeFamily startFamily endFamily base
                    case piResult of
                      Just result -> pure $ Just result
                      Nothing -> do
                        structuredResult <- reduceCanonicalStructuredTransport
                          faceProof probeFamily startFamily endFamily base
                        case structuredResult of
                          Just result -> pure $ Just result
                          Nothing -> unsupported $
                            "canonical Glue transport family shape unavailable: probe="
                              ++ semanticFamilyShape probeFamily
                              ++ "; start=" ++ semanticFamilyShape startFamily
                              ++ "; end=" ++ semanticFamilyShape endFamily
  | otherwise = pure Nothing

isApplicableFamily :: SemanticValue -> Bool
isApplicableFamily = \case
  VClosure {} -> True
  VCompMaxClosure {} -> True
  _ -> False

semanticFamilyShape :: SemanticValue -> String
semanticFamilyShape value = case viewHCompFamily value of
  Just hcomp -> semanticValueShape value
    ++ "{type=" ++ semanticValueShape (hCompFamilyType hcomp)
    ++ ",face=" ++ semanticCofibrationShape (hCompFamilyFace hcomp)
    ++ ",sides=" ++ semanticValueShape (hCompFamilySides hcomp)
    ++ ",base=" ++ semanticFamilyShape (hCompFamilyBase hcomp)
    ++ "}"
  Nothing -> case viewGlueFamily value of
    Just glue -> semanticValueShape value
      ++ "{base=" ++ semanticValueShape (glueFamilyBaseType glue)
      ++ ",face=" ++ semanticCofibrationShape (glueFamilyFace glue)
      ++ ",partial=" ++ semanticValueShape (glueFamilyPartialType glue)
      ++ ",equiv=" ++ semanticValueShape (glueFamilyEquivalence glue)
      ++ "}"
    Nothing -> semanticValueShape value

semanticCofibrationShape :: SemanticValue -> String
semanticCofibrationShape = \case
  VIntervalProbe -> "probe"
  VConstructor constructor _ [] ->
    "endpoint:" ++ prettyShow (Internal.conName constructor)
  VNeutral (NPrimitive _ operator arguments) ->
    showPrimitiveOperator operator
      ++ "(" ++ unwords
        (map (semanticCofibrationShape . unArg) arguments)
      ++ ")"
  value -> semanticValueShape value

reduceCanonicalPiTransport
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe SemanticValue)
reduceCanonicalPiTransport
    faceProof probeFamily startFamily endFamily base =
  case (viewPiFamily probeFamily, viewPiFamily startFamily, viewPiFamily endFamily) of
    ( Just (probeDomain, probeCodomain, probeEnvironment)
      , Just (startDomain, startCodomain, startEnvironment)
      , Just (endDomain, endCodomain, endEnvironment)
      ) -> do
        domainPath <- classifyCanonicalGluePath
          faceProof probeDomain startDomain endDomain
        probeCodomainCandidate <- evaluatePiCodomainCandidate
          probeCodomain probeEnvironment
        startCodomainCandidate <- evaluatePiCodomainCandidate
          startCodomain startEnvironment
        endCodomainCandidate <- evaluatePiCodomainCandidate
          endCodomain endEnvironment
        let probeCodomainValue = fst probeCodomainCandidate
            startCodomainValue = fst startCodomainCandidate
            endCodomainValue = fst endCodomainCandidate
            codomainMentionsBinder = or
              [ snd probeCodomainCandidate
              , snd startCodomainCandidate
              , snd endCodomainCandidate
              ]
        let codomainIsConstant = case
              (probeCodomainValue, startCodomainValue, endCodomainValue) of
                (Just probeValue, Just startValue, Just endValue) ->
                  sameClosedDefinition probeValue startValue
                    && sameClosedDefinition startValue endValue
                _ -> False
        codomainIsDependentSelfPath <- if codomainMentionsBinder
          then do
            probeMatches <- isDependentSelfPathPiCodomain
              probeDomain probeCodomainValue
            startMatches <- isDependentSelfPathPiCodomain
              startDomain startCodomainValue
            endMatches <- isDependentSelfPathPiCodomain
              endDomain endCodomainValue
            pure $ probeMatches && startMatches && endMatches
          else pure False
        codomainIsDependentSingleton <- if codomainMentionsBinder
          then do
            probeMatches <- isDependentSingletonPiCodomain
              faceProof SingletonBinderToField
              probeDomain probeCodomainValue
            startMatches <- isDependentSingletonPiCodomain
              faceProof SingletonBinderToField
              startDomain startCodomainValue
            endMatches <- isDependentSingletonPiCodomain
              faceProof SingletonBinderToField
              endDomain endCodomainValue
            pure $ probeMatches && startMatches && endMatches
          else pure False
        codomainIsDependentReversedSingleton <- if codomainMentionsBinder
          then do
            probeMatches <- isDependentSingletonPiCodomain
              faceProof SingletonFieldToBinder
              probeDomain probeCodomainValue
            startMatches <- isDependentSingletonPiCodomain
              faceProof SingletonFieldToBinder
              startDomain startCodomainValue
            endMatches <- isDependentSingletonPiCodomain
              faceProof SingletonFieldToBinder
              endDomain endCodomainValue
            pure $ probeMatches && startMatches && endMatches
          else pure False
        dependentNestedSingletonPlan <- if codomainMentionsBinder
          then classifyDependentSigmaSpinePiCodomain
            faceProof 2 SingletonBinderToField
            (probeDomain, probeCodomainValue)
            (startDomain, startCodomainValue)
            (endDomain, endCodomainValue)
          else pure Nothing
        dependentReversedNestedSingletonPlan <- if codomainMentionsBinder
          then classifyDependentSigmaSpinePiCodomain
            faceProof 2 SingletonFieldToBinder
            (probeDomain, probeCodomainValue)
            (startDomain, startCodomainValue)
            (endDomain, endCodomainValue)
          else pure Nothing
        dependentSigmaSpinePlan <- if codomainMentionsBinder
          then classifyDependentSigmaSpinePiCodomain
            faceProof piSigmaSpineDepthLimit SingletonBinderToField
            (probeDomain, probeCodomainValue)
            (startDomain, startCodomainValue)
            (endDomain, endCodomainValue)
          else pure Nothing
        dependentReversedSigmaSpinePlan <- if codomainMentionsBinder
          then classifyDependentSigmaSpinePiCodomain
            faceProof piSigmaSpineDepthLimit SingletonFieldToBinder
            (probeDomain, probeCodomainValue)
            (startDomain, startCodomainValue)
            (endDomain, endCodomainValue)
          else pure Nothing
        codomainTransport <- if codomainIsConstant
          then pure $ Just $ if codomainMentionsBinder
            then SemanticConstantPiCodomain
            else StablePiCodomain
          else if codomainIsDependentSelfPath
            then pure $ Just DependentSelfPathPiCodomain
            else if codomainIsDependentSingleton
              then pure $ Just $
                DependentSingletonPiCodomain SingletonBinderToField
            else if codomainIsDependentReversedSingleton
              then pure $ Just $
                DependentSingletonPiCodomain SingletonFieldToBinder
            else case dependentNestedSingletonPlan of
              Just fieldPlan -> pure $ Just $
                DependentNestedSingletonPiCodomain
                  SingletonBinderToField fieldPlan
              Nothing -> case dependentReversedNestedSingletonPlan of
                Just fieldPlan -> pure $ Just $
                  DependentNestedSingletonPiCodomain
                    SingletonFieldToBinder fieldPlan
                Nothing -> case dependentSigmaSpinePlan of
                  Just fieldPlan -> pure $ Just $
                    DependentSigmaSpinePiCodomain
                      piSigmaSpineDepthLimit
                      SingletonBinderToField
                      fieldPlan
                  Nothing -> case dependentReversedSigmaSpinePlan of
                    Just fieldPlan -> pure $ Just $
                      DependentSigmaSpinePiCodomain
                        piSigmaSpineDepthLimit
                        SingletonFieldToBinder
                        fieldPlan
                    Nothing -> if codomainMentionsBinder
                      then pure Nothing
                      else case
                        ( probeCodomainValue
                        , startCodomainValue
                        , endCodomainValue
                        ) of
                        (Just probeValue, Just startValue, Just endValue) ->
                          fmap CanonicalPiCodomainPath <$>
                            classifyCanonicalGluePath
                              faceProof probeValue startValue endValue
                        _ -> pure Nothing
        case (domainPath, codomainTransport, base) of
          (Just path, Just transport, VClosure {}) -> do
            modify' $ \state -> state
              { piTransportsReduced = piTransportsReduced state + 1 }
            pure $ Just $ VCanonicalPiTransport path transport base
          (Just _, Nothing, VClosure {}) -> unsupported $
            "dependent Pi codomain classifier unavailable: mentions-binder="
              ++ show codomainMentionsBinder
              ++ "; singleton=" ++ show codomainIsDependentSingleton
              ++ "; reversed-singleton="
              ++ show codomainIsDependentReversedSingleton
              ++ "; nested=" ++ show (isJust dependentNestedSingletonPlan)
              ++ "; reversed-nested="
              ++ show (isJust dependentReversedNestedSingletonPlan)
              ++ "; spine=" ++ show (isJust dependentSigmaSpinePlan)
              ++ "; reversed-spine="
              ++ show (isJust dependentReversedSigmaSpinePlan)
          _ -> pure Nothing
    _ -> pure Nothing

viewPiFamily
  :: SemanticValue
  -> Maybe (SemanticValue, Abs Type, Environment)
viewPiFamily = \case
  VPi domain codomain environment -> case Internal.unDom domain of
    VEl _ domainValue -> Just (domainValue, codomain, environment)
  _ -> Nothing

evaluatePiCodomainCandidate
  :: Abs Type
  -> Environment
  -> SpikeM (Maybe SemanticValue, Bool)
evaluatePiCodomainCandidate codomain environment = case codomain of
  NoAbs _ body -> do
    value <- semanticTypeValue <$> evalType environment body
    pure (Just value, False)
  Abs _ body -> do
    value <- semanticTypeValue <$>
      evalType (VNeutral (NLevel piCodomainBinderLevel) : environment) body
    pure (Just value, freeIn 0 body)

piCodomainBinderLevel :: Int
piCodomainBinderLevel = -4

piPathFamilyProbeLevel :: Int
piPathFamilyProbeLevel = -5

piSingletonFieldLevel :: Int
piSingletonFieldLevel = -7

piSigmaSpineDepthLimit :: Int
piSigmaSpineDepthLimit = 3

isDependentSelfPathPiCodomain
  :: SemanticValue
  -> Maybe SemanticValue
  -> SpikeM Bool
isDependentSelfPathPiCodomain domain = \case
  Just candidate -> dependentPathMatchesDomain
    domain
    isPiCodomainBinder
    isPiCodomainBinder
    candidate
  _ -> pure False

isDependentSingletonPiCodomain
  :: SemanticValue
  -> DependentSingletonDirection
  -> SemanticValue
  -> Maybe SemanticValue
  -> SpikeM Bool
isDependentSingletonPiCodomain faceProof direction domain = \case
  Just candidate ->
    (do
      sigmaArguments <- builtinApplicationArguments
        Builtin.builtinSigma candidate
      case lastTwoArguments =<< sigmaArguments of
        Just (firstType, secondFamily) -> do
          firstMatches <- semanticValuesMatchAsOuterPath
            faceProof firstType domain
          singletonPath <- applyValue secondFamily $ defaultArg $
            VNeutral $ NLevel piSingletonFieldLevel
          let (leftMatches, rightMatches) = case direction of
                SingletonBinderToField ->
                  (isPiCodomainBinder, isPiSingletonField)
                SingletonFieldToBinder ->
                  (isPiSingletonField, isPiCodomainBinder)
          pathMatches <- dependentPathMatchesDomain
            domain leftMatches rightMatches singletonPath
          pure $ firstMatches && pathMatches
        Nothing -> pure False)
    `catchError` \failure -> case failure of
      Unsupported _ -> pure False
      _ -> throwError failure
  Nothing -> pure False

classifyDependentSigmaSpinePiCodomain
  :: SemanticValue
  -> Int
  -> DependentSingletonDirection
  -> (SemanticValue, Maybe SemanticValue)
  -> (SemanticValue, Maybe SemanticValue)
  -> (SemanticValue, Maybe SemanticValue)
  -> SpikeM (Maybe [DependentSigmaFieldTransport])
classifyDependentSigmaSpinePiCodomain
    faceProof depth direction
    (probeDomain, probeCandidate)
    (startDomain, startCandidate)
    (endDomain, endCandidate) = case
      (probeCandidate, startCandidate, endCandidate) of
  (Just probe, Just start, Just end)
    | depth > 0 -> do
        plan <- classify depth piSingletonFieldLevel
          (probeDomain, probe) (startDomain, start) (endDomain, end)
          `catchError` \failure -> case failure of
            Unsupported _ -> pure Nothing
            _ -> throwError failure
        pure $ case plan of
          Just (SigmaFieldCanonicalPath : _) -> plan
          _ -> Nothing
  _ -> pure Nothing
  where
    classify remaining fieldLevel
        (currentProbeDomain, currentProbe)
        (currentStartDomain, currentStart)
        (currentEndDomain, currentEnd) = do
      probeArguments <- builtinApplicationArguments
        Builtin.builtinSigma currentProbe
      startArguments <- builtinApplicationArguments
        Builtin.builtinSigma currentStart
      endArguments <- builtinApplicationArguments
        Builtin.builtinSigma currentEnd
      case ( lastTwoArguments =<< probeArguments
           , lastTwoArguments =<< startArguments
           , lastTwoArguments =<< endArguments
           ) of
        ( Just (probeFirst, probeSecond)
          , Just (startFirst, startSecond)
          , Just (endFirst, endSecond)
          ) -> do
            fieldTransport <- classifyDependentSigmaFieldTransport
              faceProof
              (currentProbeDomain, probeFirst)
              (currentStartDomain, startFirst)
              (currentEndDomain, endFirst)
            let fieldProbe = defaultArg $
                  VNeutral $ NLevel fieldLevel
            probeRest <- applyValue probeSecond fieldProbe
            startRest <- applyValue startSecond fieldProbe
            endRest <- applyValue endSecond fieldProbe
            restPlan <- if remaining == 1
              then do
                let (leftMatches, rightMatches) = case direction of
                      SingletonBinderToField ->
                        (isPiCodomainBinder, isPiSingletonField)
                      SingletonFieldToBinder ->
                        (isPiSingletonField, isPiCodomainBinder)
                probeMatches <- dependentPathMatchesDomain
                  currentProbeDomain leftMatches rightMatches probeRest
                startMatches <- dependentPathMatchesDomain
                  currentStartDomain leftMatches rightMatches startRest
                endMatches <- dependentPathMatchesDomain
                  currentEndDomain leftMatches rightMatches endRest
                pure $ if probeMatches && startMatches && endMatches
                  then Just []
                  else Nothing
              else classify (remaining - 1) (fieldLevel - 1)
                (currentProbeDomain, probeRest)
                (currentStartDomain, startRest)
                (currentEndDomain, endRest)
            pure $ (:) <$> fieldTransport <*> restPlan
        _ -> pure Nothing

classifyDependentSigmaFieldTransport
  :: SemanticValue
  -> (SemanticValue, SemanticValue)
  -> (SemanticValue, SemanticValue)
  -> (SemanticValue, SemanticValue)
  -> SpikeM (Maybe DependentSigmaFieldTransport)
classifyDependentSigmaFieldTransport
    faceProof
    (probeDomain, probeField)
    (startDomain, startField)
    (endDomain, endField) = do
  probeMatches <- semanticValuesMatchAsOuterPath
    faceProof probeField probeDomain
  startMatches <- semanticValuesMatchAsOuterPath
    faceProof startField startDomain
  endMatches <- semanticValuesMatchAsOuterPath
    faceProof endField endDomain
  if probeMatches && startMatches && endMatches
    then pure $ Just SigmaFieldCanonicalPath
    else do
      probeStartMatches <- sameSemanticReadback probeField startField
      startEndMatches <- sameSemanticReadback startField endField
      fieldsAreClosed <- and <$> traverse isClosedStableTypeValue
        [probeField, startField, endField]
      if fieldsAreClosed && probeStartMatches && startEndMatches
        then do
          let closedPiViewCount = length
                [ ()
                | VPi {} <- [probeField, startField, endField]
                ]
          pure $ Just $ SigmaFieldStableIdentity closedPiViewCount
        else fmap SigmaFieldOuterIndexedPi <$>
          classifyOuterIndexedPiFieldTransport faceProof
            [ (probeDomain, probeField)
            , (startDomain, startField)
            , (endDomain, endField)
            ]

classifyOuterIndexedPiFieldTransport
  :: SemanticValue
  -> [(SemanticValue, SemanticValue)]
  -> SpikeM (Maybe IndexedPiFieldTransport)
classifyOuterIndexedPiFieldTransport faceProof domainFields = do
  let outerDomains = map fst domainFields
      fields = map snd domainFields
  exposedFields <- traverse exposePiFieldType fields
  views <- traverse viewFieldPi exposedFields
  case (outerDomains, sequence views) of
    ( [probeOuterDomain, startOuterDomain, endOuterDomain]
      , Just
        [ (probeDomain, probeCodomain)
        , (startDomain, startCodomain)
        , (endDomain, endCodomain)
        ]
      ) -> do
        domainPlan <- classifyOuterParameterizedDataDomains
          faceProof
          [probeOuterDomain, startOuterDomain, endOuterDomain]
          [probeDomain, startDomain, endDomain]
        codomainsMatch <- (&&)
          <$> sameSemanticReadback probeCodomain startCodomain
          <*> sameSemanticReadback startCodomain endCodomain
        codomainsAreClosed <- and <$> traverse isClosedStableTypeValue
          [probeCodomain, startCodomain, endCodomain]
        pure $ if codomainsMatch && codomainsAreClosed
          then domainPlan
          else Nothing
    _ -> pure Nothing
  where
    exposePiFieldType value = case value of
      VNeutral (NDefinition definition arguments) ->
        reduceDefinition definition arguments
          `catchError` \failure -> case failure of
            Unsupported _ -> pure value
            _ -> throwError failure
      _ -> pure value

    viewFieldPi value = case viewPiFamily value of
      Just (domain, codomain, environment) -> do
        (codomainValue, codomainMentionsBinder) <-
          evaluatePiCodomainCandidate codomain environment
        pure $ case (codomainValue, codomainMentionsBinder) of
          (Just resultType, False) -> Just (domain, resultType)
          _ -> Nothing
      _ -> pure Nothing

classifyOuterParameterizedDataDomains
  :: SemanticValue
  -> [SemanticValue]
  -> [SemanticValue]
  -> SpikeM (Maybe IndexedPiFieldTransport)
classifyOuterParameterizedDataDomains faceProof outerDomains domains = do
  views <- traverse viewDataDomain domains
  case (outerDomains, sequence views) of
    ( [probeOuter, startOuter, endOuter]
      , Just
        [ (probeData, probeParameterCount, probeArguments)
        , (startData, startParameterCount, startArguments)
        , (endData, endParameterCount, endArguments)
        ]
      )
      | probeData == startData
      , startData == endData
      , probeParameterCount == startParameterCount
      , startParameterCount == endParameterCount
      , length probeArguments == probeParameterCount
      , length startArguments == probeParameterCount
      , length endArguments == probeParameterCount
      -> do
          let argumentColumns = zip3
                (map unArg probeArguments)
                (map unArg startArguments)
                (map unArg endArguments)
              outerValueParameters =
                [ position
                | (position, (probe, start, end)) <- zip [0 ..] argumentColumns
                , all isOuterSigmaFieldNeutral [probe, start, end]
                ]
          classifications <- forM
            (zip [0 ..] argumentColumns) $ \(position, arguments) ->
              if position `elem` outerValueParameters
                then pure (position, False, False)
                else do
                  let (probe, start, end) = arguments
                  closed <- (&&)
                    <$> (and <$> traverse isClosedStableTypeValue
                      [probe, start, end])
                    <*> ((&&)
                      <$> sameSemanticReadback probe start
                      <*> sameSemanticReadback start end)
                  followsOuterPath <- and <$> sequence
                    [ semanticValuesMatchAsOuterPath
                        faceProof probe probeOuter
                    , semanticValuesMatchAsOuterPath
                        faceProof start startOuter
                    , semanticValuesMatchAsOuterPath
                        faceProof end endOuter
                    ]
                  pure (position, closed, followsOuterPath)
          let outerTypeParameters =
                [ position
                | (position, _, followsOuterPath) <- classifications
                , followsOuterPath
                ]
              allOtherParametersChecked = and
                [ closed || followsOuterPath
                | (position, closed, followsOuterPath) <- classifications
                , position `notElem` outerValueParameters
                ]
          case (outerValueParameters, outerTypeParameters) of
            ([outerParameter], [])
              | allOtherParametersChecked -> pure $ Just $ IndexedPiFieldTransport
                  probeData probeParameterCount Nothing outerParameter
            ([outerParameter], [outerTypeParameter])
              | allOtherParametersChecked -> pure $ Just $ IndexedPiFieldTransport
                  probeData probeParameterCount
                  (Just outerTypeParameter) outerParameter
            _ -> pure Nothing
    _ -> pure Nothing
  where
    viewDataDomain = \case
      VNeutral (NDefinition definition arguments) -> do
        definitionInfo <- getConstInfoCached definition
        pure $ case theDef definitionInfo of
          Datatype {dataPars = parameterCount, dataIxs = 0} ->
            Just (definition, parameterCount, arguments)
          _ -> Nothing
      _ -> pure Nothing

isOuterSigmaFieldNeutral :: SemanticValue -> Bool
isOuterSigmaFieldNeutral = \case
  VNeutral (NLevel level) -> level == piSingletonFieldLevel
  _ -> False

dependentPathMatchesDomain
  :: SemanticValue
  -> (SemanticValue -> Bool)
  -> (SemanticValue -> Bool)
  -> SemanticValue
  -> SpikeM Bool
dependentPathMatchesDomain domain leftMatches rightMatches = \case
  VNeutral (NDefinition definition arguments) -> do
    isPathP <- isBuiltinQName Builtin.builtinPathP definition
    case (isPathP, reverse arguments) of
      (True, [right, left, family, _level])
        | leftMatches $ unArg left
        , rightMatches $ unArg right
        , isSyntacticallyConstantPathFamily $ unArg family -> do
            intervalZero <- applyBuiltin Builtin.builtinIZero []
            intervalOne <- applyBuiltin Builtin.builtinIOne []
            zeroMatches <- constantPathFamilyMatchesDomain
              intervalZero (unArg family) domain
            oneMatches <- constantPathFamilyMatchesDomain
              intervalOne (unArg family) domain
            pure $ zeroMatches && oneMatches
      _ -> pure False
  _ -> pure False

isPiCodomainBinder :: SemanticValue -> Bool
isPiCodomainBinder = \case
  VNeutral (NLevel level) -> level == piCodomainBinderLevel
  _ -> False

isPiSingletonField :: SemanticValue -> Bool
isPiSingletonField = \case
  VNeutral (NLevel level) -> level == piSingletonFieldLevel
  _ -> False

semanticValuesMatchAsOuterPath
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM Bool
semanticValuesMatchAsOuterPath _faceProof left right =
  (do
    intervalZero <- applyBuiltin Builtin.builtinIZero []
    intervalOne <- applyBuiltin Builtin.builtinIOne []
    leftAtZero <- specialiseIntervalProbe intervalZero left
    rightAtZero <- specialiseIntervalProbe intervalZero right
    leftAtOne <- specialiseIntervalProbe intervalOne left
    rightAtOne <- specialiseIntervalProbe intervalOne right
    zeroMatches <- sameSemanticReadback leftAtZero rightAtZero
    oneMatches <- sameSemanticReadback leftAtOne rightAtOne
    probeMatches <- case (viewGlueFamily left, viewGlueFamily right) of
      (Just leftGlue, Just rightGlue) -> do
        baseMatches <- sameSemanticReadback
          (glueFamilyBaseType leftGlue)
          (glueFamilyBaseType rightGlue)
        pure $ baseMatches
          && semanticCofibrationShape (glueFamilyFace leftGlue)
            == semanticCofibrationShape (glueFamilyFace rightGlue)
      (Nothing, Nothing) -> sameSemanticReadback left right
      _ -> pure False
    pure $ probeMatches && zeroMatches && oneMatches)
  `catchError` \failure -> case failure of
    Unsupported _ -> pure False
    _ -> throwError failure

isSyntacticallyConstantPathFamily :: SemanticValue -> Bool
isSyntacticallyConstantPathFamily = \case
  VClosure _ abstraction _ -> case abstraction of
    NoAbs {} -> True
    Abs _ body -> not $ freeIn 0 body
  _ -> False

constantPathFamilyMatchesDomain
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM Bool
constantPathFamilyMatchesDomain outerInterval family domain =
  (do
    specialisedFamily <- specialiseIntervalProbe outerInterval family
    specialisedDomain <- specialiseIntervalProbe outerInterval domain
    intervalZero <- applyBuiltin Builtin.builtinIZero []
    intervalOne <- applyBuiltin Builtin.builtinIOne []
    atZero <- applyValue specialisedFamily $ defaultArg intervalZero
    atProbe <- applyValue specialisedFamily $ defaultArg $
      VNeutral $ NLevel piPathFamilyProbeLevel
    atOne <- applyValue specialisedFamily $ defaultArg intervalOne
    zeroMatches <- sameSemanticReadback atZero specialisedDomain
    probeMatches <- sameSemanticReadback atProbe specialisedDomain
    oneMatches <- sameSemanticReadback atOne specialisedDomain
    pure $ zeroMatches && probeMatches && oneMatches)
  `catchError` \failure -> case failure of
    Unsupported _ -> pure False
    _ -> throwError failure

semanticTypeValue :: SemanticType -> SemanticValue
semanticTypeValue (VEl _ value) = value

reduceCanonicalStructuredTransport
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe SemanticValue)
reduceCanonicalStructuredTransport
    faceProof probeFamily startFamily endFamily base = do
  sigmaResult <- reduceCanonicalSigmaTransport
    faceProof probeFamily startFamily endFamily base
  case sigmaResult of
    Just result -> pure $ Just result
    Nothing -> reduceCanonicalListTransport
      faceProof probeFamily startFamily endFamily base

reduceCanonicalSigmaTransport
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe SemanticValue)
reduceCanonicalSigmaTransport
    faceProof probeFamily startFamily endFamily base = do
  probeArguments <- builtinApplicationArguments Builtin.builtinSigma probeFamily
  startArguments <- builtinApplicationArguments Builtin.builtinSigma startFamily
  endArguments <- builtinApplicationArguments Builtin.builtinSigma endFamily
  case (probeArguments, startArguments, endArguments) of
    (Just probe, Just start, Just end)
      | Just (probeFirst, probeSecond) <- lastTwoArguments probe
      , Just (startFirst, startSecond) <- lastTwoArguments start
      , Just (endFirst, endSecond) <- lastTwoArguments end -> do
          firstPath <- classifyCanonicalGluePath
            faceProof probeFirst startFirst endFirst
          secondIsStable <- stableNonDependentSigmaSecond
            probeSecond startSecond endSecond
          case (firstPath, secondIsStable, base) of
            ( Just path
              , True
              , VConstructor constructor info arguments
              ) -> do
                belongsToSigma <- constructorBelongsToBuiltin
                  Builtin.builtinSigma constructor
                fields <- if belongsToSigma
                  then recordConstructorFields base
                  else pure []
                case fields of
                  [firstField, secondField]
                    | isGroundValue $ unArg firstField
                    , isGroundValue $ unArg secondField -> do
                        transportedFirst <- applyValue
                          (canonicalGlueForward path)
                          firstField
                        if not $ isGroundValue transportedFirst
                          then unsupported $
                            "canonical Sigma transport produced a non-ground first field"
                          else do
                            let transportedFields =
                                  [ transportedFirst <$ firstField
                                  , secondField
                                  ]
                                transportedArguments = replaceTrailingArguments
                                  2 arguments transportedFields
                            modify' $ \state -> state
                              { recordTransportsReduced =
                                  recordTransportsReduced state + 1 }
                            pure $ Just $ VConstructor
                              constructor info transportedArguments
                  _ -> pure Nothing
            _ -> pure Nothing
    _ -> pure Nothing

reduceCanonicalListTransport
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe SemanticValue)
reduceCanonicalListTransport
    faceProof probeFamily startFamily endFamily base = do
  probeArguments <- builtinApplicationArguments Builtin.builtinList probeFamily
  startArguments <- builtinApplicationArguments Builtin.builtinList startFamily
  endArguments <- builtinApplicationArguments Builtin.builtinList endFamily
  case ( lastArgument =<< probeArguments
       , lastArgument =<< startArguments
       , lastArgument =<< endArguments
       ) of
    (Just probeElement, Just startElement, Just endElement) -> do
      elementPath <- classifyCanonicalGluePath
        faceProof probeElement startElement endElement
      case elementPath of
        Just path -> do
          result <- mapCanonicalBuiltinList path base
          modify' $ \state -> state
            { dataTransportsReduced = dataTransportsReduced state + 1 }
          pure $ Just result
        Nothing -> pure Nothing
    _ -> pure Nothing

builtinApplicationArguments
  :: Builtin.BuiltinId
  -> SemanticValue
  -> SpikeM (Maybe [Arg SemanticValue])
builtinApplicationArguments builtinId = \case
  VNeutral (NDefinition definition arguments) -> do
    matches <- isBuiltinQName builtinId definition
    pure $ if matches then Just arguments else Nothing
  _ -> pure Nothing

lastTwoArguments
  :: [Arg SemanticValue]
  -> Maybe (SemanticValue, SemanticValue)
lastTwoArguments arguments = case reverse arguments of
  second : first : _ -> Just (unArg first, unArg second)
  _ -> Nothing

lastArgument :: [Arg SemanticValue] -> Maybe SemanticValue
lastArgument arguments = case reverse arguments of
  argument : _ -> Just $ unArg argument
  [] -> Nothing

stableNonDependentSigmaSecond
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM Bool
stableNonDependentSigmaSecond probeSecond startSecond endSecond = do
  let fieldProbe = defaultArg $ VNeutral $ NLevel (-6)
  probeValue <- applyValue probeSecond fieldProbe
  startValue <- applyValue startSecond fieldProbe
  endValue <- applyValue endSecond fieldProbe
  pure $
    sameClosedDefinition probeValue startValue
      && sameClosedDefinition startValue endValue

constructorBelongsToBuiltin
  :: Builtin.BuiltinId
  -> ConHead
  -> SpikeM Bool
constructorBelongsToBuiltin builtinId constructor = do
  constructorDefinition <- getConstInfoCached $ Internal.conName constructor
  case theDef constructorDefinition of
    Constructor {conData = dataName} -> isBuiltinQName builtinId dataName
    _ -> pure False

replaceTrailingArguments
  :: Int
  -> [Arg SemanticValue]
  -> [Arg SemanticValue]
  -> [Arg SemanticValue]
replaceTrailingArguments fieldCount arguments fields =
  take (length arguments - fieldCount) arguments ++ fields

isGroundValue :: SemanticValue -> Bool
isGroundValue value = case valueShape value of
  Just _ -> True
  Nothing -> False

-- | Stable identity is still intentionally narrower than arbitrary readback.
-- Besides the original ground values, admit constructor spines only after
-- checked constructor metadata separates closed parameters from the exact
-- payload arity.  Every payload must recursively satisfy the same predicate.
-- Ordinary function closures are admitted only when full semantic readback
-- produces an Agda-closed term; internal composition/transport closures and
-- all open neutrals therefore remain unsupported.
isStableIdentityFieldValue :: SemanticValue -> SpikeM Bool
isStableIdentityFieldValue value
  | isGroundValue value = pure True
  | otherwise = case value of
      VClosure {} -> isClosedStableFunctionValue value
      _ -> isClosedStableConstructorValue value

isClosedStableFunctionValue :: SemanticValue -> SpikeM Bool
isClosedStableFunctionValue value =
  (do
    quoted <- quoteValue 0 value
    let quotedIsClosed = Free.closed quoted
    if quotedIsClosed
      then modify' $ \state -> state
        { closedStableFunctionValuesValidated =
            closedStableFunctionValuesValidated state + 1 }
      else pure ()
    pure quotedIsClosed)
  `catchError` \failure -> case failure of
    Unsupported _ -> pure False
    _ -> throwError failure

isClosedStableConstructorValue :: SemanticValue -> SpikeM Bool
isClosedStableConstructorValue = \case
  VConstructor constructor _ arguments -> do
    constructorDefinition <- getConstInfoCached $ Internal.conName constructor
    metadata <- case theDef constructorDefinition of
      Constructor {conPars = parameters, conArity = arity} ->
        pure $ Just (parameters, arity)
      _ -> pure Nothing
    case metadata of
      Just (parameterCount, payloadArity)
        | length arguments == payloadArity ->
            and <$> traverse
              (isStableIdentityFieldValue . unArg) arguments
        | length arguments == parameterCount + payloadArity -> do
            let (parameters, payload) = splitAt parameterCount arguments
            parametersAreClosed <- and <$> traverse
              (isClosedStableTypeValue . unArg) parameters
            payloadIsClosed <- and <$> traverse
              (isStableIdentityFieldValue . unArg) payload
            pure $ parametersAreClosed && payloadIsClosed
      _ -> pure False
  _ -> pure False

-- | Conservative binder-free type shape used by the stable-field classifier.
-- Definition applications may retain closed level/type/index arguments, but
-- closures, interval probes, applications, projections, primitives and every
-- level neutral are rejected.  The final equality check is semantic readback
-- across probe/i0/i1; this predicate prevents that equality from being caused
-- merely by reusing the same opaque binder neutral in all three observations.
isClosedStableTypeValue :: SemanticValue -> SpikeM Bool
isClosedStableTypeValue = \case
  VNeutral (NDefinition _ arguments) -> and <$> traverse
    (isClosedStableTypeValue . unArg) arguments
  value@VPi {} -> isClosedStablePiTypeValue value
  VLevel level -> isClosedStableLevel level
  VSort sort -> isClosedStableSort sort
  VNat {} -> pure True
  VLiteral {} -> pure True
  value@VConstructor {} -> pure $ isGroundValue value
  _ -> pure False

isClosedStablePiTypeValue :: SemanticValue -> SpikeM Bool
isClosedStablePiTypeValue value =
  (do
    quoted <- quoteValue 0 value
    pure $ Free.closed quoted)
  `catchError` \failure -> case failure of
    Unsupported _ -> pure False
    _ -> throwError failure

isClosedStableLevel :: SemanticLevel -> SpikeM Bool
isClosedStableLevel (VMaximum _ plusLevels) =
  and <$> traverse isClosedPlus plusLevels
  where
    isClosedPlus (VPlus _ value) = isClosedStableTypeValue value

isClosedStableSort :: SemanticSort -> SpikeM Bool
isClosedStableSort = \case
  VUniverse _ level -> isClosedStableLevel level
  VInfiniteUniverse {} -> pure True
  VSizeUniverse -> pure True
  VLockUniverse -> pure True
  VLevelUniverse -> pure True
  VIntervalUniverse -> pure True
  VFunctionUniverse domain codomain -> (&&)
    <$> isClosedStableSort domain
    <*> isClosedStableSort codomain
  VUniverseOf sort -> isClosedStableSort sort
  VPiUniverse {} -> pure False

mapCanonicalBuiltinList
  :: CanonicalGluePath
  -> SemanticValue
  -> SpikeM SemanticValue
mapCanonicalBuiltinList path value = do
  consumeFuel "mapping a canonical builtin List transport"
  case value of
    VConstructor constructor info arguments -> do
      isNil <- isBuiltinConstructor Builtin.builtinNil constructor
      isCons <- isBuiltinConstructor Builtin.builtinCons constructor
      constructorDefinition <- getConstInfoCached $ Internal.conName constructor
      parameterCount <- case theDef constructorDefinition of
        Constructor {conPars = parameters} -> pure parameters
        _ -> unsupported "builtin List value has non-constructor metadata"
      if isNil && (null arguments || length arguments == parameterCount)
        then pure value
        else if isCons
          && (length arguments == 2 || length arguments == parameterCount + 2)
          then case reverse arguments of
            tailField : headField : reversedParameters -> do
              if not $ isGroundValue $ unArg headField
                then unsupported "canonical List transport requires ground elements"
                else do
                  transportedHead <- applyValue
                    (canonicalGlueForward path)
                    headField
                  transportedTail <- mapCanonicalBuiltinList path $ unArg tailField
                  if not $ isGroundValue transportedHead
                    then unsupported $
                      "canonical List transport produced a non-ground element"
                    else pure $ VConstructor constructor info $
                      reverse reversedParameters
                        ++ [ transportedHead <$ headField
                           , transportedTail <$ tailField
                           ]
            _ -> unsupported "builtin List cons field spine is malformed"
          else unsupported "canonical List transport received a non-List spine"
    _ -> unsupported "canonical List transport requires a constructor spine"

classifyCanonicalGluePath
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe CanonicalGluePath)
classifyCanonicalGluePath faceProof probeFamily startFamily endFamily =
  case ( viewGlueFamily probeFamily
       , viewGlueFamily startFamily
       , viewGlueFamily endFamily
       ) of
    (Just probeView, Just startView, Just endView) -> do
      startFace <- intervalEndpoint $ glueFamilyFace startView
      endFace <- intervalEndpoint $ glueFamilyFace endView
      startPartialType <- applyValue
        (glueFamilyPartialType startView)
        (defaultArg faceProof)
      endPartialType <- applyValue
        (glueFamilyPartialType endView)
        (defaultArg faceProof)
      startEquivalence <- applyValue
        (glueFamilyEquivalence startView)
        (defaultArg faceProof)
      endEquivalence <- applyValue
        (glueFamilyEquivalence endView)
        (defaultArg faceProof)
      startFunction <- sigmaFirstField startEquivalence
      endFunction <- sigmaFirstField endEquivalence
      let sameBase = sameClosedDefinition
            (glueFamilyBaseType startView)
            (glueFamilyBaseType endView)
          endPartialIsBase = sameClosedDefinition
            endPartialType
            (glueFamilyBaseType endView)
          exactShape =
            startFace == Just True
              && endFace == Just True
              && isProbeComplementFace (glueFamilyFace probeView)
              && sameBase
              && endPartialIsBase
      case (exactShape, startFunction, endFunction) of
        (True, Just forward, Just final) -> do
          finalIsIdentity <- isCheckedIdentityCandidate final
          pure $ if finalIsIdentity
            then Just CanonicalGluePath
              { canonicalGlueSourceType = startPartialType
              , canonicalGlueTargetType = glueFamilyBaseType endView
              , canonicalGlueEquivalence = startEquivalence
              , canonicalGlueForward = forward
              }
            else Nothing
        _ -> pure Nothing
    _ -> pure Nothing

-- | Recognise the same canonical univalence geometry traversed from its
-- identity endpoint back to the source.  This is deliberately separate from
-- the forward classifier: the identity check belongs to the start
-- equivalence, while the end equivalence supplies the checked inverse.
classifyCanonicalBackwardGluePath
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe CanonicalGluePath)
classifyCanonicalBackwardGluePath
    faceProof probeFamily startFamily endFamily =
  case ( viewGlueFamily probeFamily
       , viewGlueFamily startFamily
       , viewGlueFamily endFamily
       ) of
    (Just probeView, Just startView, Just endView) -> do
      startFace <- intervalEndpoint $ glueFamilyFace startView
      endFace <- intervalEndpoint $ glueFamilyFace endView
      startPartialType <- applyValue
        (glueFamilyPartialType startView)
        (defaultArg faceProof)
      endPartialType <- applyValue
        (glueFamilyPartialType endView)
        (defaultArg faceProof)
      startEquivalence <- applyValue
        (glueFamilyEquivalence startView)
        (defaultArg faceProof)
      endEquivalence <- applyValue
        (glueFamilyEquivalence endView)
        (defaultArg faceProof)
      startFunction <- sigmaFirstField startEquivalence
      endFunction <- sigmaFirstField endEquivalence
      let sameBase = sameClosedDefinition
            (glueFamilyBaseType startView)
            (glueFamilyBaseType endView)
          startPartialIsBase = sameClosedDefinition
            startPartialType
            (glueFamilyBaseType startView)
          exactShape =
            startFace == Just True
              && endFace == Just True
              && isProbeComplementFace (glueFamilyFace probeView)
              && sameBase
              && startPartialIsBase
      case (exactShape, startFunction, endFunction) of
        (True, Just initial, Just forward) -> do
          initialIsIdentity <- isCheckedIdentityCandidate initial
          pure $ if initialIsIdentity
            then Just CanonicalGluePath
              { canonicalGlueSourceType = endPartialType
              , canonicalGlueTargetType = glueFamilyBaseType startView
              , canonicalGlueEquivalence = endEquivalence
              , canonicalGlueForward = forward
              }
            else Nothing
        _ -> pure Nothing
    _ -> pure Nothing

reduceCanonicalComposedGlueTransport
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe SemanticValue)
reduceCanonicalComposedGlueTransport
    faceProof intervalZero intervalOne
    probeFamily startFamily endFamily base =
  case ( viewHCompFamily probeFamily
       , viewHCompFamily startFamily
       , viewHCompFamily endFamily
       ) of
    (Just probeHComp, Just startHComp, Just endHComp) -> do
      startFace <- intervalEndpoint $ hCompFamilyFace startHComp
      endFace <- intervalEndpoint $ hCompFamilyFace endHComp
      let exactShell =
            isUniverseValue (hCompFamilyType probeHComp)
              && isUniverseValue (hCompFamilyType startHComp)
              && isUniverseValue (hCompFamilyType endHComp)
              && isProbeComplementFace (hCompFamilyFace probeHComp)
              && startFace == Just True
              && endFace == Just True
              && sameDefinitionApplicationHead
                (hCompFamilySides probeHComp)
                (hCompFamilySides startHComp)
                (hCompFamilySides endHComp)
      if not exactShell
        then pure Nothing
        else do
          centrePath <- classifyCanonicalGluePath
            faceProof
            (hCompFamilyBase probeHComp)
            (hCompFamilyBase startHComp)
            (hCompFamilyBase endHComp)
          leftAtZero <- applyHCompSide
            (hCompFamilySides startHComp) intervalZero faceProof
          leftAtProbe <- applyHCompSide
            (hCompFamilySides startHComp) VIntervalProbe faceProof
          leftAtOne <- applyHCompSide
            (hCompFamilySides startHComp) intervalOne faceProof
          rightAtZero <- applyHCompSide
            (hCompFamilySides endHComp) intervalZero faceProof
          rightAtProbe <- applyHCompSide
            (hCompFamilySides endHComp) VIntervalProbe faceProof
          rightAtOne <- applyHCompSide
            (hCompFamilySides endHComp) intervalOne faceProof
          rightPath <- classifyCanonicalGluePath
            faceProof rightAtProbe rightAtZero rightAtOne
          case (centrePath, rightPath) of
            (Just centre, Just right) -> do
              let leftIsConstant =
                    sameClosedDefinition leftAtZero leftAtProbe
                      && sameClosedDefinition leftAtProbe leftAtOne
                      && sameClosedDefinition
                        leftAtProbe
                        (canonicalGlueSourceType centre)
                  middleMatches = sameClosedDefinition
                    (canonicalGlueTargetType centre)
                    (canonicalGlueSourceType right)
              if leftIsConstant && middleMatches
                then do
                  centreResult <- applyValue
                    (canonicalGlueForward centre)
                    (defaultArg base)
                  result <- applyValue
                    (canonicalGlueForward right)
                    (defaultArg centreResult)
                  modify' $ \state -> state
                    { composedGlueTransportsReduced =
                        composedGlueTransportsReduced state + 1 }
                  pure $ Just result
                else pure Nothing
            _ -> pure Nothing
    _ -> pure Nothing

viewGlueFamily :: SemanticValue -> Maybe GlueFamilyView
viewGlueFamily = \case
  VNeutral (NPrimitive _ PrimitiveGlueType arguments)
    | [_, _, baseType, face, partialType, equivalence] <- arguments ->
        Just GlueFamilyView
          { glueFamilyBaseType = unArg baseType
          , glueFamilyFace = unArg face
          , glueFamilyPartialType = unArg partialType
          , glueFamilyEquivalence = unArg equivalence
          }
  _ -> Nothing

viewHCompFamily :: SemanticValue -> Maybe HCompFamilyView
viewHCompFamily = \case
  VNeutral (NPrimitive _ PrimitiveHComp arguments)
    | [_, valueType, face, sides, base] <- arguments ->
        Just HCompFamilyView
          { hCompFamilyType = unArg valueType
          , hCompFamilyFace = unArg face
          , hCompFamilySides = unArg sides
          , hCompFamilyBase = unArg base
          }
  _ -> Nothing

applyHCompSide
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM SemanticValue
applyHCompSide sides fillInterval faceProof = do
  sideAtInterval <- applyValue sides $ defaultArg fillInterval
  applyValue sideAtInterval $ defaultArg faceProof

-- | Recognise the HCompU shell produced when a HIT eliminator maps path
-- composition into the universe.  Agda simplifies that shell away at i0/i1,
-- so the probe can be an HComp while the observed endpoints are a closed type
-- and a canonical Glue type.  Endpoint specialisation and readback equality
-- keep this rule tied to that exact representation.
reduceCanonicalProbeHCompTransport
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe SemanticValue)
reduceCanonicalProbeHCompTransport
    faceProof intervalZero intervalOne
    probeFamily startFamily endFamily base = case viewHCompFamily probeFamily of
  Just hcomp
    | isUniverseValue $ hCompFamilyType hcomp
    , isProbeComplementFace $ hCompFamilyFace hcomp -> do
        specialisedStart <- specialiseIntervalProbe intervalZero probeFamily
        specialisedEnd <- specialiseIntervalProbe intervalOne probeFamily
        startMatches <- sameSemanticReadback specialisedStart startFamily
        endMatches <- sameSemanticReadback specialisedEnd endFamily
        if not (startMatches && endMatches)
          then unsupported $
            "probe-hcomp endpoint specialisation mismatch: start="
              ++ show startMatches
              ++ " (specialised=" ++ semanticFamilyShape specialisedStart
              ++ "; actual=" ++ semanticFamilyShape startFamily ++ ")"
              ++ "; end=" ++ show endMatches
              ++ " (specialised=" ++ semanticFamilyShape specialisedEnd
              ++ "; actual=" ++ semanticFamilyShape endFamily ++ ")"
          else do
            result <- transportCanonicalTriple
              faceProof intervalZero intervalOne
              probeFamily startFamily endFamily base
            case result of
              Just (transported, _, _) -> pure $ Just transported
              Nothing -> unsupported $
                "probe-hcomp recursive transport shape mismatch"
  _ -> pure Nothing

transportCanonicalTriple
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM
      (Maybe (SemanticValue, SemanticValue, SemanticValue))
transportCanonicalTriple
    faceProof intervalZero intervalOne
    probeFamily startFamily endFamily base = do
  probeIsStart <- sameSemanticReadback probeFamily startFamily
  startIsEnd <- sameSemanticReadback startFamily endFamily
  if probeIsStart && startIsEnd
    then pure $ Just (base, startFamily, endFamily)
    else do
      directStep <- classifyCanonicalGlueStep
        faceProof probeFamily startFamily endFamily
      case directStep of
        Just step -> do
          transported <- applyCanonicalGlueStep step base
          pure $ Just
            ( transported
            , canonicalGlueStepSourceType step
            , canonicalGlueStepTargetType step
            )
        Nothing -> case viewHCompFamily probeFamily of
          Just hcomp
            | isUniverseValue $ hCompFamilyType hcomp
            , isProbeComplementFace $ hCompFamilyFace hcomp -> do
                specialisedStart <- specialiseIntervalProbe
                  intervalZero probeFamily
                specialisedEnd <- specialiseIntervalProbe
                  intervalOne probeFamily
                startMatches <- sameSemanticReadback
                  specialisedStart startFamily
                endMatches <- sameSemanticReadback specialisedEnd endFamily
                if not (startMatches && endMatches)
                  then unsupported $
                    "nested probe-hcomp endpoint mismatch: start="
                      ++ show startMatches ++ "; end=" ++ show endMatches
                  else do
                    baseStart <- specialiseIntervalProbe
                      intervalZero $ hCompFamilyBase hcomp
                    baseEnd <- specialiseIntervalProbe
                      intervalOne $ hCompFamilyBase hcomp
                    centreResult <- transportCanonicalTriple
                      faceProof intervalZero intervalOne
                      (hCompFamilyBase hcomp)
                      baseStart
                      baseEnd
                      base
                    case centreResult of
                      Nothing -> unsupported $
                        "nested probe-hcomp centre path mismatch: probe="
                          ++ semanticFamilyShape (hCompFamilyBase hcomp)
                          ++ "; start=" ++ semanticFamilyShape baseStart
                          ++ "; end=" ++ semanticFamilyShape baseEnd
                      Just
                          ( transportedCentre
                          , centreSource
                          , centreTarget
                          ) -> do
                        startSides <- specialiseIntervalProbe
                          intervalZero $ hCompFamilySides hcomp
                        endSides <- specialiseIntervalProbe
                          intervalOne $ hCompFamilySides hcomp
                        leftAtZero <- applyHCompSide
                          startSides intervalZero faceProof
                        leftAtProbe <- applyHCompSide
                          startSides VIntervalProbe faceProof
                        leftAtOne <- applyHCompSide
                          startSides intervalOne faceProof
                        rightAtZero <- applyHCompSide
                          endSides intervalZero faceProof
                        rightAtProbe <- applyHCompSide
                          endSides VIntervalProbe faceProof
                        rightAtOne <- applyHCompSide
                          endSides intervalOne faceProof
                        leftZeroIsProbe <- sameSemanticReadback
                          leftAtZero leftAtProbe
                        leftProbeIsOne <- sameSemanticReadback
                          leftAtProbe leftAtOne
                        leftMatchesCentre <- sameSemanticReadback
                          leftAtProbe centreSource
                        rightResult <- transportCanonicalTriple
                          faceProof intervalZero intervalOne
                          rightAtProbe rightAtZero rightAtOne
                          transportedCentre
                        case rightResult of
                          Just (transported, rightSource, rightTarget) -> do
                            middleMatches <- sameSemanticReadback
                              centreTarget rightSource
                            if leftZeroIsProbe
                                && leftProbeIsOne
                                && leftMatchesCentre
                                && middleMatches
                              then do
                                pure $ Just
                                  ( transported
                                  , centreSource
                                  , rightTarget
                                  )
                              else unsupported $
                                "probe-hcomp boundary mismatch: left-0-probe="
                                  ++ show leftZeroIsProbe
                                  ++ "; left-probe-1=" ++ show leftProbeIsOne
                                  ++ "; left-centre=" ++ show leftMatchesCentre
                                  ++ "; middle=" ++ show middleMatches
                                  ++ " (centre-target="
                                  ++ semanticFamilyShape centreTarget
                                  ++ "; right-source="
                                  ++ semanticFamilyShape rightSource
                                  ++ ")"
                          Nothing -> unsupported $
                            "probe-hcomp right boundary is not a canonical recursive Glue composition: probe="
                              ++ semanticFamilyShape rightAtProbe
                              ++ "; start=" ++ semanticFamilyShape rightAtZero
                              ++ "; end=" ++ semanticFamilyShape rightAtOne
          _ -> pure Nothing

classifyCanonicalGlueStep
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> SpikeM (Maybe CanonicalGlueStep)
classifyCanonicalGlueStep faceProof probeFamily startFamily endFamily = do
  forwardPath <- classifyCanonicalGluePath
    faceProof probeFamily startFamily endFamily
  case forwardPath of
    Just path -> pure $ Just $ CanonicalGlueForwardStep path
    Nothing -> fmap CanonicalGlueBackwardStep <$>
      classifyCanonicalBackwardGluePath
        faceProof probeFamily startFamily endFamily

canonicalGlueStepSourceType :: CanonicalGlueStep -> SemanticValue
canonicalGlueStepSourceType = \case
  CanonicalGlueForwardStep path -> canonicalGlueSourceType path
  CanonicalGlueBackwardStep path -> canonicalGlueTargetType path

canonicalGlueStepTargetType :: CanonicalGlueStep -> SemanticValue
canonicalGlueStepTargetType = \case
  CanonicalGlueForwardStep path -> canonicalGlueTargetType path
  CanonicalGlueBackwardStep path -> canonicalGlueSourceType path

applyCanonicalGlueStep
  :: CanonicalGlueStep
  -> SemanticValue
  -> SpikeM SemanticValue
applyCanonicalGlueStep step value = case step of
  CanonicalGlueForwardStep path -> applyValue
    (canonicalGlueForward path)
    (defaultArg value)
  CanonicalGlueBackwardStep path -> do
    result <- applyCanonicalGlueBackward path value
    modify' $ \state -> state
      { backwardGlueTransportsReduced =
          backwardGlueTransportsReduced state + 1 }
    pure result

sameSemanticReadback :: SemanticValue -> SemanticValue -> SpikeM Bool
sameSemanticReadback left right =
  (do
    quotedLeft <- quoteValue 0 left
    quotedRight <- quoteValue 0 right
    pure $ quotedLeft == quotedRight)
  `catchError` \failure -> case failure of
    Unsupported _ -> pure False
    _ -> throwError failure

specialiseIntervalProbe
  :: SemanticValue
  -> SemanticValue
  -> SpikeM SemanticValue
specialiseIntervalProbe replacement = \case
  VIntervalProbe -> pure replacement
  VClosure argumentInfo abstraction environment ->
    VClosure argumentInfo abstraction <$>
      traverse (specialiseIntervalProbe replacement) environment
  VCompMaxClosure family fixedInterval -> VCompMaxClosure
    <$> specialiseIntervalProbe replacement family
    <*> specialiseIntervalProbe replacement fixedInterval
  VCompSidesClosure levelFamily typeFamily sides -> VCompSidesClosure
    <$> specialiseIntervalProbe replacement levelFamily
    <*> specialiseIntervalProbe replacement typeFamily
    <*> specialiseIntervalProbe replacement sides
  VCompSideClosure levelFamily typeFamily sides fillInterval ->
    VCompSideClosure
      <$> specialiseIntervalProbe replacement levelFamily
      <*> specialiseIntervalProbe replacement typeFamily
      <*> specialiseIntervalProbe replacement sides
      <*> specialiseIntervalProbe replacement fillInterval
  VCanonicalPiTransport domainPath codomainTransport function -> do
    specialisedDomainPath <- specialiseCanonicalGluePath
      replacement domainPath
    specialisedCodomainTransport <- case codomainTransport of
      StablePiCodomain -> pure StablePiCodomain
      SemanticConstantPiCodomain -> pure SemanticConstantPiCodomain
      DependentSelfPathPiCodomain -> pure DependentSelfPathPiCodomain
      DependentSingletonPiCodomain direction -> pure $
        DependentSingletonPiCodomain direction
      DependentNestedSingletonPiCodomain direction fieldPlan -> pure $
        DependentNestedSingletonPiCodomain direction fieldPlan
      DependentSigmaSpinePiCodomain depth direction fieldPlan -> pure $
        DependentSigmaSpinePiCodomain depth direction fieldPlan
      CanonicalPiCodomainPath path -> CanonicalPiCodomainPath <$>
        specialiseCanonicalGluePath replacement path
    specialisedFunction <- specialiseIntervalProbe replacement function
    pure $ VCanonicalPiTransport
      specialisedDomainPath specialisedCodomainTransport specialisedFunction
  VOuterIndexedPiFieldTransport
      plan domainPath sourcePoint targetPoint function -> do
    specialisedDomainPath <- specialiseCanonicalGluePath
      replacement domainPath
    VOuterIndexedPiFieldTransport plan specialisedDomainPath
      <$> specialiseIntervalProbe replacement sourcePoint
      <*> specialiseIntervalProbe replacement targetPoint
      <*> specialiseIntervalProbe replacement function
  VReflexivePath point -> VReflexivePath <$>
    specialiseIntervalProbe replacement point
  VPi domain codomain environment -> VPi
    <$> traverse (specialiseSemanticType replacement) domain
    <*> pure codomain
    <*> traverse (specialiseIntervalProbe replacement) environment
  VSort sort -> VSort <$> specialiseSemanticSort replacement sort
  VLevel level -> VLevel <$> specialiseSemanticLevel replacement level
  VNat natural -> pure $ VNat natural
  VLiteral literal -> pure $ VLiteral literal
  VConstructor constructor info arguments -> VConstructor constructor info
    <$> traverse (traverse $ specialiseIntervalProbe replacement) arguments
  VNeutral neutral -> specialiseNeutral replacement neutral

specialiseCanonicalGluePath
  :: SemanticValue
  -> CanonicalGluePath
  -> SpikeM CanonicalGluePath
specialiseCanonicalGluePath replacement path = do
  sourceType <- specialiseIntervalProbe replacement $
    canonicalGlueSourceType path
  targetType <- specialiseIntervalProbe replacement $
    canonicalGlueTargetType path
  equivalence <- specialiseIntervalProbe replacement $
    canonicalGlueEquivalence path
  forward <- specialiseIntervalProbe replacement $
    canonicalGlueForward path
  pure CanonicalGluePath
    { canonicalGlueSourceType = sourceType
    , canonicalGlueTargetType = targetType
    , canonicalGlueEquivalence = equivalence
    , canonicalGlueForward = forward
    }

specialiseSemanticType
  :: SemanticValue
  -> SemanticType
  -> SpikeM SemanticType
specialiseSemanticType replacement (VEl sort value) = VEl
  <$> specialiseSemanticSort replacement sort
  <*> specialiseIntervalProbe replacement value

specialiseSemanticSort
  :: SemanticValue
  -> SemanticSort
  -> SpikeM SemanticSort
specialiseSemanticSort replacement = \case
  VUniverse universe level ->
    VUniverse universe <$> specialiseSemanticLevel replacement level
  VInfiniteUniverse universe index ->
    pure $ VInfiniteUniverse universe index
  VSizeUniverse -> pure VSizeUniverse
  VLockUniverse -> pure VLockUniverse
  VLevelUniverse -> pure VLevelUniverse
  VIntervalUniverse -> pure VIntervalUniverse
  VPiUniverse domain domainSort codomain environment -> VPiUniverse
    <$> traverse (specialiseIntervalProbe replacement) domain
    <*> specialiseSemanticSort replacement domainSort
    <*> pure codomain
    <*> traverse (specialiseIntervalProbe replacement) environment
  VFunctionUniverse domainSort codomainSort -> VFunctionUniverse
    <$> specialiseSemanticSort replacement domainSort
    <*> specialiseSemanticSort replacement codomainSort
  VUniverseOf sort ->
    VUniverseOf <$> specialiseSemanticSort replacement sort

specialiseSemanticLevel
  :: SemanticValue
  -> SemanticLevel
  -> SpikeM SemanticLevel
specialiseSemanticLevel replacement (VMaximum closed plusLevels) =
  VMaximum closed <$> forM plusLevels (\case
    VPlus offset value ->
      VPlus offset <$> specialiseIntervalProbe replacement value)

specialiseNeutral
  :: SemanticValue
  -> Neutral
  -> SpikeM SemanticValue
specialiseNeutral replacement = \case
  NLevel level -> pure $ VNeutral $ NLevel level
  NDefinition definition arguments -> do
    specialised <- traverse
      (traverse $ specialiseIntervalProbe replacement)
      arguments
    pure $ VNeutral $ NDefinition definition specialised
  NApplication neutral argument -> do
    specialisedHead <- specialiseNeutral replacement neutral
    specialisedArgument <- traverse
      (specialiseIntervalProbe replacement)
      argument
    applyValue specialisedHead specialisedArgument
  NProjection neutral origin projection -> do
    specialisedHead <- specialiseNeutral replacement neutral
    projectValue origin projection specialisedHead
  NPrimitive definition operator arguments -> do
    specialised <- traverse
      (traverse $ specialiseIntervalProbe replacement)
      arguments
    applyPrimitive definition operator specialised

isUniverseValue :: SemanticValue -> Bool
isUniverseValue VSort {} = True
isUniverseValue _ = False

sameDefinitionApplicationHead
  :: SemanticValue
  -> SemanticValue
  -> SemanticValue
  -> Bool
sameDefinitionApplicationHead
    (VNeutral (NDefinition probeDefinition probeArguments))
    (VNeutral (NDefinition startDefinition startArguments))
    (VNeutral (NDefinition endDefinition endArguments)) =
  probeDefinition == startDefinition
    && startDefinition == endDefinition
    && length probeArguments == length startArguments
    && length startArguments == length endArguments
sameDefinitionApplicationHead _ _ _ = False

isProbeComplementFace :: SemanticValue -> Bool
isProbeComplementFace = \case
  VNeutral (NPrimitive _ PrimitiveIMax [left, right]) ->
    (isIntervalProbe (unArg left) && isNegatedIntervalProbe (unArg right))
      || (isNegatedIntervalProbe (unArg left) && isIntervalProbe (unArg right))
  _ -> False

isIntervalProbe :: SemanticValue -> Bool
isIntervalProbe VIntervalProbe = True
isIntervalProbe _ = False

isNegatedIntervalProbe :: SemanticValue -> Bool
isNegatedIntervalProbe = \case
  VNeutral (NPrimitive _ PrimitiveINeg [argument]) ->
    isIntervalProbe $ unArg argument
  _ -> False

sameClosedDefinition :: SemanticValue -> SemanticValue -> Bool
sameClosedDefinition
  (VNeutral (NDefinition left []))
  (VNeutral (NDefinition right [])) = left == right
sameClosedDefinition _ _ = False

isIdentityProbe :: SemanticValue -> Bool
isIdentityProbe (VNeutral (NLevel index)) = index == -1
isIdentityProbe _ = False

isCheckedIdentityCandidate :: SemanticValue -> SpikeM Bool
isCheckedIdentityCandidate function =
  (do
    let identityProbe = VNeutral $ NLevel (-1)
    identityResult <- applyValue function $ defaultArg identityProbe
    pure $ isIdentityProbe identityResult)
  `catchError` \failure -> case failure of
    Unsupported _ -> pure False
    _ -> throwError failure

semanticValueShape :: SemanticValue -> String
semanticValueShape = \case
  VClosure {} -> "closure"
  VCompMaxClosure {} -> "comp-max-closure"
  VCompSidesClosure {} -> "comp-sides-closure"
  VCompSideClosure {} -> "comp-side-closure"
  VCanonicalPiTransport {} -> "canonical-pi-transport"
  VOuterIndexedPiFieldTransport {} -> "outer-indexed-pi-field-transport"
  VReflexivePath {} -> "reflexive-path"
  VPi {} -> "pi"
  VSort {} -> "sort"
  VLevel {} -> "level"
  VNat {} -> "nat"
  VLiteral {} -> "literal"
  VConstructor constructor _ arguments ->
    "constructor:" ++ prettyShow (Internal.conName constructor)
      ++ "/" ++ show (length arguments)
  VIntervalProbe -> "interval-probe"
  VNeutral neutral -> case neutral of
    NLevel index -> "level-neutral:" ++ show index
    NDefinition definition arguments ->
      "definition:" ++ prettyShow definition ++ "/" ++ show (length arguments)
    NApplication {} -> "application-neutral"
    NProjection _ _ projection ->
      "projection:" ++ prettyShow projection
    NPrimitive definition operator arguments ->
      "primitive:" ++ prettyShow definition
        ++ "/" ++ showPrimitiveOperator operator
        ++ "/" ++ show (length arguments)

showPrimitiveOperator :: PrimitiveOperator -> String
showPrimitiveOperator = \case
  PrimitiveNatPlus -> "nat-plus"
  PrimitiveNatMinus -> "nat-minus"
  PrimitiveNatTimes -> "nat-times"
  PrimitiveIMin -> "imin"
  PrimitiveIMax -> "imax"
  PrimitiveINeg -> "ineg"
  PrimitiveTransp -> "transp"
  PrimitiveHComp -> "hcomp"
  PrimitiveComp -> "comp"
  PrimitiveGlueType -> "Glue"
  PrimitiveGlue -> "glue"
  PrimitiveUnglue -> "unglue"

applyCanonicalGlueBackward
  :: CanonicalGluePath
  -> SemanticValue
  -> SpikeM SemanticValue
applyCanonicalGlueBackward path targetValue = do
  equivalenceProof <- sigmaSecondField $ canonicalGlueEquivalence path
  (isoForward, isoInverse) <- case equivalenceProof of
    Just proof -> do
      recordArgument <- case proof of
        VNeutral (NDefinition _ arguments) ->
          pure $ findRecordConstructorArgument $ reverse arguments
        _ -> pure Nothing
      case recordArgument of
        Just recordValue -> do
          fields <- recordConstructorFields recordValue
          case fields of
            forward : inverse : _ : _ : [] ->
              pure (unArg forward, unArg inverse)
            _ -> unsupported $
              "canonical Glue inverse proof record does not have four fields"
        Nothing -> unsupported $
          "canonical Glue inverse requires an isomorphism-backed proof"
    Nothing -> unsupported $
      "canonical Glue equivalence proof projection is unavailable"
  sourceValue <- applyValue isoInverse $ defaultArg targetValue
  isoRoundTrip <- applyValue isoForward $ defaultArg sourceValue
  canonicalRoundTrip <- applyValue
    (canonicalGlueForward path)
    (defaultArg sourceValue)
  if sameGroundValue targetValue isoRoundTrip
      && sameGroundValue targetValue canonicalRoundTrip
    then pure sourceValue
    else unsupported $
      "canonical Glue inverse failed the checked pointwise round trip"

findRecordConstructorArgument
  :: [Arg SemanticValue]
  -> Maybe SemanticValue
findRecordConstructorArgument = \case
  [] -> Nothing
  argument : rest -> case unArg argument of
    value@VConstructor {} -> Just value
    _ -> findRecordConstructorArgument rest

recordConstructorFields
  :: SemanticValue
  -> SpikeM [Arg SemanticValue]
recordConstructorFields = \case
  VConstructor constructor _ arguments -> do
    constructorDefinition <- getConstInfoCached $ Internal.conName constructor
    (recordName, parameterCount) <- case theDef constructorDefinition of
      Constructor {conData = dataName, conPars = parameters} ->
        pure (dataName, parameters)
      _ -> unsupported "inverse proof value is not a record constructor"
    recordDefinition <- getConstInfoCached recordName
    fields <- case theDef recordDefinition of
      Record {recFields = recordFields} -> pure recordFields
      _ -> unsupported "inverse proof constructor does not belong to a record"
    case recordFieldArguments parameterCount (length fields) arguments of
      Just fieldArguments -> pure fieldArguments
      Nothing -> unsupported "inverse proof record field spine is malformed"
  _ -> unsupported "inverse proof value is not a constructor"

sameGroundValue :: SemanticValue -> SemanticValue -> Bool
sameGroundValue left right = case (valueShape left, valueShape right) of
  (Just leftShape, Just rightShape) -> leftShape == rightShape
  _ -> False

isReflexivePathAt :: SemanticValue -> SemanticValue -> SpikeM Bool
isReflexivePathAt point proof = do
  intervalZero <- applyBuiltin Builtin.builtinIZero []
  intervalOne <- applyBuiltin Builtin.builtinIOne []
  atZero <- applyValue proof $ defaultArg intervalZero
  atProbe <- applyValue proof $ defaultArg VIntervalProbe
  atOne <- applyValue proof $ defaultArg intervalOne
  pure $ all (sameGroundValue point) [atZero, atProbe, atOne]

sigmaFirstField :: SemanticValue -> SpikeM (Maybe SemanticValue)
sigmaFirstField value = do
  sigmaName <- lift $ lift $ Builtin.getBuiltinName' Builtin.builtinSigma
  case sigmaName of
    Nothing -> pure Nothing
    Just sigma -> do
      sigmaDefinition <- getConstInfoCached sigma
      case theDef sigmaDefinition of
        Record {recFields = firstField : _} ->
          Just <$> projectValue ProjSystem (Internal.unDom firstField) value
        _ -> pure Nothing

sigmaSecondField :: SemanticValue -> SpikeM (Maybe SemanticValue)
sigmaSecondField value = do
  sigmaName <- lift $ lift $ Builtin.getBuiltinName' Builtin.builtinSigma
  case sigmaName of
    Nothing -> pure Nothing
    Just sigma -> do
      sigmaDefinition <- getConstInfoCached sigma
      case theDef sigmaDefinition of
        Record {recFields = _ : secondField : _} ->
          Just <$> projectValue ProjSystem (Internal.unDom secondField) value
        _ -> pure Nothing

unsupportedDefinitionNode
  :: String
  -> String
  -> QName
  -> String
  -> SpikeM a
unsupportedDefinitionNode stage nodeKind definition reason = unsupported $
  "unsupported-node: stage="
    ++ stage
    ++ "; node-kind="
    ++ nodeKind
    ++ "; qname="
    ++ prettyShow definition
    ++ "; source-range="
    ++ prettyShow (nameBindingSite $ qnameName definition)
    ++ "; "
    ++ reason

getConstInfoCached :: QName -> SpikeM Definition
getConstInfoCached definition = do
  cached <- gets $ Map.lookup definition . definitionCache
  case cached of
    Just definitionInfo -> do
      modify' $ \state -> state
        { definitionCacheHits = definitionCacheHits state + 1 }
      pure definitionInfo
    Nothing -> do
      definitionInfo <- lift $ lift $ getConstInfo definition
      modify' $ \state -> state
        { definitionCache = Map.insert definition definitionInfo
            (definitionCache state)
        , definitionCacheMisses = definitionCacheMisses state + 1
        }
      pure definitionInfo

withGroundCall
  :: QName
  -> [Arg SemanticValue]
  -> SpikeM SemanticValue
  -> SpikeM SemanticValue
withGroundCall definition arguments action =
  case traverse (valueShape . unArg) arguments of
    Nothing -> action
    Just shapes -> do
      let groundCallKey = CallKey definition shapes
      active <- gets activeGroundCalls
      if Set.member groundCallKey active
        then throwError $ RecursiveCycle $
          "recursive-cycle: repeated ground call to " ++ prettyShow definition
        else do
          modify' $ \state ->
            let depth = currentCallDepth state + 1
            in state
              { activeGroundCalls = Set.insert groundCallKey
                  (activeGroundCalls state)
              , currentCallDepth = depth
              , maximumCallDepth = max depth (maximumCallDepth state)
              }
          result <- action
          modify' $ \state -> state
            { activeGroundCalls = Set.delete groundCallKey
                (activeGroundCalls state)
            , currentCallDepth = currentCallDepth state - 1
            }
          pure result

valueShape :: SemanticValue -> Maybe ValueShape
valueShape = \case
  VNat natural -> Just $ ShapeNat natural
  VLiteral literal -> Just $ ShapeLiteral $ prettyShow literal
  VConstructor constructor _ arguments -> ShapeConstructor
    (Internal.conName constructor) <$> traverse (valueShape . unArg) arguments
  VClosure {} -> Nothing
  VCompMaxClosure {} -> Nothing
  VCompSidesClosure {} -> Nothing
  VCompSideClosure {} -> Nothing
  VCanonicalPiTransport {} -> Nothing
  VOuterIndexedPiFieldTransport {} -> Nothing
  VReflexivePath {} -> Nothing
  VPi {} -> Nothing
  VSort {} -> Nothing
  VLevel {} -> Nothing
  VIntervalProbe -> Nothing
  VNeutral {} -> Nothing

evalType :: Environment -> Type -> SpikeM SemanticType
evalType environment (Internal.El sort term) = do
  consumeFuel "evaluating a type"
  modify' $ \state -> state
    { typeNodesEvaluated = typeNodesEvaluated state + 1 }
  evaluatedSort <- evalSort environment sort
  evaluatedTerm <- evalTerm environment term
  pure $ VEl evaluatedSort evaluatedTerm

evalSort :: Environment -> Sort -> SpikeM SemanticSort
evalSort environment sort = do
  consumeFuel "evaluating a sort"
  modify' $ \state -> state
    { sortNodesEvaluated = sortNodesEvaluated state + 1 }
  case sort of
    Internal.Univ universe level ->
      VUniverse universe <$> evalLevel environment level
    Internal.Inf universe index -> pure $ VInfiniteUniverse universe index
    Internal.SizeUniv -> pure VSizeUniverse
    Internal.LockUniv -> pure VLockUniverse
    Internal.LevelUniv -> pure VLevelUniverse
    Internal.IntervalUniv -> pure VIntervalUniverse
    Internal.PiSort domain domainSort codomain -> do
      evaluatedDomain <- traverse (evalTerm environment) domain
      evaluatedDomainSort <- evalSort environment domainSort
      pure $ VPiUniverse
        evaluatedDomain
        evaluatedDomainSort
        codomain
        environment
    Internal.FunSort domainSort codomainSort ->
      VFunctionUniverse
        <$> evalSort environment domainSort
        <*> evalSort environment codomainSort
    Internal.UnivSort inner -> VUniverseOf <$> evalSort environment inner
    Internal.MetaS {} -> unsupported "sort metavariables are outside the spike fragment"
    Internal.DefS definition _ -> unsupported $
      "postulated-sort-policy=reject-v1: postulated sorts are outside "
        ++ "the spike fragment: "
        ++ prettyShow definition
    Internal.DummyS _ -> unsupported "dummy sorts are outside the spike fragment"

evalLevel :: Environment -> Level -> SpikeM SemanticLevel
evalLevel environment (Internal.Max closed plusLevels) = do
  consumeFuel "evaluating a level"
  modify' $ \state -> state
    { levelNodesEvaluated = levelNodesEvaluated state + 1
    , maximumLevelAtomCount = max
        (length plusLevels)
        (maximumLevelAtomCount state)
    }
  evaluated <- forM plusLevels $ \case
    Internal.Plus offset atom ->
      VPlus offset <$> evalTerm environment atom
  pure $ VMaximum closed evaluated

applyArguments :: [Arg SemanticValue] -> SemanticValue -> SpikeM SemanticValue
applyArguments arguments value = foldM applyValue value arguments

evalClause :: QName -> Clause -> Bindings -> SpikeM SemanticValue
evalClause definition clause bindings = case clauseBody clause of
  Nothing -> unsupported $
    "absurd clauses are outside the spike fragment: "
      ++ prettyShow definition
      ++ "; patterns="
      ++ show (namedClausePats clause)
  Just body -> do
    let environmentSize = length $ telToList $ clauseTel clause
    environment <- forM [0 .. environmentSize - 1] $ \index ->
      case Map.lookup index bindings of
        Just value -> pure value
        Nothing
          -- Forced constructor indices can remain in the clause telescope
          -- without a VarP.  They need no semantic reconstruction when the
          -- checked body does not refer to them; a level neutral is therefore
          -- an unreachable environment placeholder, not an inferred value.
          | not $ freeIn index body ->
              pure $ VNeutral $ NLevel (-1000000 - index)
          | otherwise -> unsupported $
              "referenced clause telescope binding was not produced by its patterns: "
                ++ show index
    evalTerm environment body

matchPatterns
  :: [NamedArg DeBruijnPattern]
  -> [Arg SemanticValue]
  -> SpikeM (Maybe Bindings)
matchPatterns patterns arguments
  | length patterns /= length arguments = pure Nothing
  | otherwise = go Map.empty $ zip patterns arguments
  where
    go bindings [] = pure $ Just bindings
    go bindings ((patternArgument, valueArgument) : rest) = do
      matched <- matchPattern
        (namedThing $ unArg patternArgument)
        (unArg valueArgument)
        bindings
      case matched of
        Nothing -> pure Nothing
        Just bindings' -> go bindings' rest

matchPattern
  :: DeBruijnPattern
  -> SemanticValue
  -> Bindings
  -> SpikeM (Maybe Bindings)
matchPattern pattern' value bindings = do
  consumeFuel "matching a clause pattern"
  case pattern' of
    Internal.VarP _ variable ->
      if Map.member (dbPatVarIndex variable) bindings
        then unsupported "duplicate de Bruijn pattern binding in one clause"
        else pure $ Just $ Map.insert (dbPatVarIndex variable) value bindings
    Internal.DotP {} -> pure $ Just bindings
    Internal.LitP _ expected -> pure $ case value of
      VNat actual | expected == LitNat actual -> Just bindings
      VLiteral actual | actual == expected -> Just bindings
      _ -> Nothing
    Internal.ConP expected _ subpatterns -> do
      isZero <- isBuiltinConstructor Builtin.builtinZero expected
      isSuc <- isBuiltinConstructor Builtin.builtinSuc expected
      isIntervalZero <- isBuiltinConstructor Builtin.builtinIZero expected
      isIntervalOne <- isBuiltinConstructor Builtin.builtinIOne expected
      endpoint <- if isIntervalZero || isIntervalOne
        then intervalEndpoint value
        else pure Nothing
      case value of
        VNat natural
          | isZero && natural == 0 ->
              matchSubpatterns subpatterns [] bindings
          | isSuc && natural > 0 ->
              matchSubpatterns
                subpatterns
                (map (VNat (natural - 1) <$) subpatterns)
                bindings
        VConstructor actual _ arguments
          | Internal.conName actual == Internal.conName expected ->
              matchSubpatterns subpatterns arguments bindings
        _ | isIntervalZero && endpoint == Just False ->
              matchSubpatterns subpatterns [] bindings
          | isIntervalOne && endpoint == Just True ->
              matchSubpatterns subpatterns [] bindings
        _ -> pure Nothing
    Internal.IApplyP _ _ _ variable ->
      if Map.member (dbPatVarIndex variable) bindings
        then unsupported "duplicate de Bruijn IApply pattern binding in one clause"
        else pure $ Just $ Map.insert (dbPatVarIndex variable) value bindings
    Internal.ProjP {} ->
      unsupported "copattern clauses are outside the spike fragment"
    Internal.DefP _ expected subpatterns ->
      let matchDefinitionHead actual arguments
            | actual /= expected = pure Nothing
            | otherwise = do
                matched <- matchSubpatterns subpatterns arguments bindings
                case matched of
                  Just _ -> modify' $ \state -> state
                    { hitDefinitionPatternsMatched =
                        hitDefinitionPatternsMatched state + 1 }
                  Nothing -> pure ()
                pure matched
      in case value of
        VNeutral (NDefinition actual arguments) ->
          matchDefinitionHead actual arguments
        VNeutral (NPrimitive actual _ arguments) ->
          matchDefinitionHead actual arguments
        _ -> pure Nothing

matchSubpatterns
  :: [NamedArg DeBruijnPattern]
  -> [Arg SemanticValue]
  -> Bindings
  -> SpikeM (Maybe Bindings)
matchSubpatterns patterns arguments bindings
  | length patterns /= length arguments = pure Nothing
  | otherwise = go bindings $ zip patterns arguments
  where
    go bindings' [] = pure $ Just bindings'
    go bindings' ((patternArgument, valueArgument) : rest) = do
      matched <- matchPattern
        (namedThing $ unArg patternArgument)
        (unArg valueArgument)
        bindings'
      case matched of
        Nothing -> pure Nothing
        Just next -> go next rest

quoteValue :: Int -> SemanticValue -> SpikeM Term
quoteValue depth value = do
  consumeFuel "quoting a semantic value"
  case value of
    VNat natural -> pure $ Internal.Lit $ LitNat natural
    VLiteral literal -> pure $ Internal.Lit literal
    VConstructor constructor info arguments -> do
      quoted <- traverse (traverse $ quoteValue depth) arguments
      pure $ Internal.Con constructor info $ map Apply quoted
    VPi domain codomain environment -> do
      quotedDomain <- traverse (quoteType depth) domain
      quotedCodomain <- case codomain of
        Abs name body -> do
          bodyValue <- evalType
            (VNeutral (NLevel depth) : environment)
            body
          Abs name <$> quoteType (depth + 1) bodyValue
        NoAbs name body -> do
          bodyValue <- evalType environment body
          NoAbs name <$> quoteType depth bodyValue
      pure $ Internal.Pi quotedDomain quotedCodomain
    VSort sort -> Internal.Sort <$> quoteSort depth sort
    VLevel level -> Internal.Level <$> quoteLevel depth level
    VIntervalProbe ->
      unsupported "internal interval probe escaped constant-family checking"
    VClosure argumentInfo abstraction environment -> case abstraction of
      Abs name body -> do
        bodyValue <- evalTerm (VNeutral (NLevel depth) : environment) body
        quotedBody <- quoteValue (depth + 1) bodyValue
        pure $ Internal.Lam argumentInfo $ Abs name quotedBody
      NoAbs name body -> do
        bodyValue <- evalTerm environment body
        quotedBody <- quoteValue depth bodyValue
        pure $ Internal.Lam argumentInfo $ NoAbs name quotedBody
    VCompMaxClosure {} -> unsupported $
      "internal comp maximum closure escaped exact composition reduction"
    VCompSidesClosure {} -> unsupported $
      "internal comp sides closure escaped exact composition reduction"
    VCompSideClosure {} -> unsupported $
      "internal comp side closure escaped exact composition reduction"
    VCanonicalPiTransport {} -> unsupported $
      "unapplied canonical Pi transport escaped the exact application slice"
    VOuterIndexedPiFieldTransport {} -> unsupported $
      "unapplied indexed Pi field transport escaped the exact application slice"
    VReflexivePath {} -> unsupported $
      "unapplied reflexive path escaped the exact endpoint-observation slice"
    VNeutral neutral -> quoteNeutral depth neutral

quoteType :: Int -> SemanticType -> SpikeM Type
quoteType depth (VEl sort term) =
  Internal.El <$> quoteSort depth sort <*> quoteValue depth term

quoteSort :: Int -> SemanticSort -> SpikeM Sort
quoteSort depth = \case
  VUniverse universe level ->
    Internal.Univ universe <$> quoteLevel depth level
  VInfiniteUniverse universe index -> pure $ Internal.Inf universe index
  VSizeUniverse -> pure Internal.SizeUniv
  VLockUniverse -> pure Internal.LockUniv
  VLevelUniverse -> pure Internal.LevelUniv
  VIntervalUniverse -> pure Internal.IntervalUniv
  VPiUniverse domain domainSort codomain environment -> do
    quotedDomain <- traverse (quoteValue depth) domain
    quotedDomainSort <- quoteSort depth domainSort
    quotedCodomain <- case codomain of
      Abs name body -> do
        bodyValue <- evalSort
          (VNeutral (NLevel depth) : environment)
          body
        Abs name <$> quoteSort (depth + 1) bodyValue
      NoAbs name body -> do
        bodyValue <- evalSort environment body
        NoAbs name <$> quoteSort depth bodyValue
    pure $ Internal.PiSort quotedDomain quotedDomainSort quotedCodomain
  VFunctionUniverse domainSort codomainSort ->
    Internal.FunSort
      <$> quoteSort depth domainSort
      <*> quoteSort depth codomainSort
  VUniverseOf inner -> Internal.UnivSort <$> quoteSort depth inner

quoteLevel :: Int -> SemanticLevel -> SpikeM Level
quoteLevel depth (VMaximum closed plusLevels) = do
  quoted <- forM plusLevels $ \case
    VPlus offset atom -> Internal.Plus offset <$> quoteValue depth atom
  pure $ Internal.Max closed quoted

quoteNeutral :: Int -> Neutral -> SpikeM Term
quoteNeutral depth = \case
  NLevel level
    | level < depth -> pure $ Internal.Var (depth - level - 1) []
    | otherwise -> unsupported "invalid neutral level during readback"
  NDefinition definition arguments -> do
    quoted <- traverse (traverse $ quoteValue depth) arguments
    pure $ Internal.Def definition $ map Apply quoted
  NApplication neutral argument -> do
    headTerm <- quoteNeutral depth neutral
    quotedArgument <- traverse (quoteValue depth) argument
    appendApplication headTerm quotedArgument
  NProjection neutral origin projection -> do
    headTerm <- quoteNeutral depth neutral
    appendProjection headTerm origin projection
  NPrimitive definition _ arguments -> do
    quoted <- traverse (traverse $ quoteValue depth) arguments
    pure $ Internal.Def definition $ map Apply quoted

appendApplication :: Term -> Arg Term -> SpikeM Term
appendApplication term argument = case term of
  Internal.Var index eliminations ->
    pure $ Internal.Var index $ eliminations ++ [Apply argument]
  Internal.Def definition eliminations ->
    pure $ Internal.Def definition $ eliminations ++ [Apply argument]
  Internal.Con constructor info eliminations ->
    pure $ Internal.Con constructor info $ eliminations ++ [Apply argument]
  _ -> unsupported "neutral readback produced an invalid application head"

appendProjection :: Term -> ProjOrigin -> QName -> SpikeM Term
appendProjection term origin projection = case term of
  Internal.Var index eliminations ->
    pure $ Internal.Var index $ eliminations ++ [Proj origin projection]
  Internal.Def definition eliminations ->
    pure $ Internal.Def definition $ eliminations ++ [Proj origin projection]
  Internal.Con constructor info eliminations ->
    pure $ Internal.Con constructor info $
      eliminations ++ [Proj origin projection]
  _ -> unsupported "neutral readback produced an invalid projection head"
