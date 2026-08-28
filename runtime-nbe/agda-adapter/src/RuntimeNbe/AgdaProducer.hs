{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module RuntimeNbe.AgdaProducer
  ( ProducerOptions(..)
  , producerAbort
  , runtimeNbeBackendWith
  , runtimeNbeProducerBackend
  ) where

import Control.DeepSeq (NFData)
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Data.List (find)
import Data.Maybe (isJust)
import Data.Text (Text)
import GHC.Generics (Generic)
import System.Directory (doesFileExist, removeFile)

import Agda.Compiler.Backend
import Agda.Interaction.Options (lensOptCubical)
import Agda.Syntax.Common (Arg(unArg), Cubical(CFull))
import Agda.Syntax.Common.Pretty (prettyShow)
import Agda.Syntax.Internal
  ( Abs(Abs, NoAbs), Clause(clauseBody, clauseTel), Dom'(unDom), Elim'(Apply, IApply)
  , Term, Type, telToList
  )
import qualified Agda.Syntax.Internal as Internal
import Agda.Syntax.Internal.MetaVars (noMetas)
import qualified Agda.TypeChecking.Free as Free
import qualified Agda.TypeChecking.Monad.Builtin as Builtin
import Agda.Utils.GetOpt (ArgDescr(ReqArg), OptDescr(Option))


data ProducerOptions = ProducerOptions
  { producerEntry :: Maybe String
  , producerOutput :: Maybe FilePath
  }
  deriving (Generic)

instance NFData ProducerOptions

data HitInfo = HitInfo QName QName QName QName
data EvidenceInfo = EvidenceInfo QName QName QName

defaultProducerOptions :: ProducerOptions
defaultProducerOptions = ProducerOptions Nothing Nothing

runtimeNbeProducerBackend :: Backend
runtimeNbeProducerBackend = runtimeNbeBackendWith
  "RuntimeNbeProducer" "ir-v1" publishRuntimeIr

runtimeNbeBackendWith
  :: Text
  -> Text
  -> (ProducerOptions -> Definition -> Term -> String -> TCM ())
  -> Backend
runtimeNbeBackendWith name version publish = Backend $ Backend'
  { backendName = name
  , backendVersion = Just version
  , options = defaultProducerOptions
  , commandLineFlags = producerFlags
  , isEnabled = producerEnabled
  , preCompile = prepareOutput
  , postCompile = verifyOutput
  , preModule = \_ _ _ _ -> pure (Recompile ())
  , postModule = \_ _ _ _ _ -> pure ()
  , compileDef = compileDefinition publish
  , scopeCheckingSuffices = False
  , mayEraseType = const (pure False)
  , backendInteractTop = Nothing
  , backendInteractHole = Nothing
  }

producerFlags :: [OptDescr (Flag ProducerOptions)]
producerFlags =
  [ Option [] ["runtime-nbe-entry"]
      (ReqArg (\value opts -> pure opts { producerEntry = Just value }) "QNAME")
      "checked definition to lower for the runtime NbE path"
  , Option [] ["runtime-nbe-output"]
      (ReqArg (\value opts -> pure opts { producerOutput = Just value }) "FILE")
      "output file for the private runtime NbE IR"
  ]

producerEnabled :: ProducerOptions -> Bool
producerEnabled opts =
  isJust (producerEntry opts) || isJust (producerOutput opts)

prepareOutput :: ProducerOptions -> TCM ProducerOptions
prepareOutput opts = do
  case (producerEntry opts, producerOutput opts) of
    (Just _, Just path) -> liftIO $ do
      exists <- doesFileExist path
      when exists (removeFile path)
    _ -> producerAbort "both --runtime-nbe-entry and --runtime-nbe-output are required"
  pure opts

compileDefinition
  :: (ProducerOptions -> Definition -> Term -> String -> TCM ())
  -> ProducerOptions -> () -> IsMain -> Definition -> TCM ()
compileDefinition publish opts _ _ definition =
  case (producerEntry opts, producerOutput opts) of
    (Just requested, Just _)
      | prettyShow (defName definition) == requested ->
          locallyTCState
            (stPragmaOptions . lensOptCubical)
            (const $ Just CFull) $
              case theDef definition of
                Function { funClauses = [clause] }
                  | null (telToList (clauseTel clause))
                  , Just body <- clauseBody clause -> do
                      lowered <- lowerSupportedTerm definition body
                      case lowered of
                        Left reason -> producerAbort reason
                        Right runtimeIr -> publish opts definition body runtimeIr
                _ -> producerAbort
                  "selected entry is not a single-clause definition with a body"
    _ -> pure ()

publishRuntimeIr :: ProducerOptions -> Definition -> Term -> String -> TCM ()
publishRuntimeIr opts _ _ runtimeIr = case producerOutput opts of
  Just output -> liftIO $ writeFile output runtimeIr
  Nothing -> producerAbort "missing runtime NbE output path"

verifyOutput :: ProducerOptions -> IsMain -> modules -> TCM ()
verifyOutput opts _ _ = case producerOutput opts of
  Just output -> do
    exists <- liftIO $ doesFileExist output
    when (not exists) $ producerAbort "selected entry was not found"
  Nothing -> producerAbort "missing runtime NbE output path"

producerAbort :: String -> TCM a
producerAbort message = liftIO $ ioError $ userError $
  "CCNBE-AGDA-LOWER-REJECT: " ++ message

-- This is the first production-shaped slice migrated from the old adapter's
-- exact-builtin registry and fail-closed term inspection.  It deliberately
-- lowers no semantic values and never calls Agda's normalizer.
lowerSupportedTerm :: Definition -> Term -> TCM (Either String String)
lowerSupportedTerm definition term = do
  transName <- Builtin.getPrimitiveName' Builtin.builtinTrans
  unglueName <- Builtin.getPrimitiveName' Builtin.builtin_unglue
  case term of
    Internal.Def name _ | Just name == transName ->
      lowerConstantBoolTransp definition term
    Internal.Def name _ | Just name == unglueName ->
      lowerEmptyBoolGlue definition term
    _ -> lowerEmptyBoolHComp definition term

lowerEmptyBoolGlue :: Definition -> Term -> TCM (Either String String)
lowerEmptyBoolGlue definition term = do
  glueName <- Builtin.getPrimitiveName' Builtin.builtin_glue
  unglueName <- Builtin.getPrimitiveName' Builtin.builtin_unglue
  boolName <- Builtin.getBuiltinName' Builtin.builtinBool
  falseName <- Builtin.getBuiltinName' Builtin.builtinFalse
  trueName <- Builtin.getBuiltinName' Builtin.builtinTrue
  iZeroName <- Builtin.getBuiltinName' Builtin.builtinIZero
  emptyName <- Builtin.getBuiltinName' Builtin.builtinIsOneEmpty
  pure $ do
    glue <- requiredBuiltin "prim^glue" glueName
    unglue <- requiredBuiltin "prim^unglue" unglueName
    bool <- requiredBuiltin "Bool" boolName
    falseConstructor <- requiredBuiltin "false" falseName
    trueConstructor <- requiredBuiltin "true" trueName
    iZero <- requiredBuiltin "i0" iZeroName
    empty <- requiredBuiltin "isOneEmpty" emptyName
    unlessEither (isBoolType bool (defType definition))
      "prim^unglue result type is not exact builtin Bool"
    unlessEither (Free.closed term) "selected prim^unglue term is open"
    unlessEither (noMetas (term, defType definition))
      "selected prim^unglue term or type contains a metavariable"
    arguments <- case term of
      Internal.Def name eliminations
        | name == unglue -> appliedTerms eliminations
        | otherwise -> Left "selected term head is not exact builtin prim^unglue"
      _ -> Left "selected term is not a prim^unglue application"
    glued <- case arguments of
      [levelA, levelT, baseType, face, typeFamily, equivalence, candidate] -> do
        unlessEither (isZeroLevel levelA && isZeroLevel levelT)
          "empty Glue universe levels are not both lzero"
        unlessEither (isBoolTerm bool baseType)
          "empty Glue base type is not exact builtin Bool"
        unlessEither (isConstructor iZero face) "empty Glue face is not exact builtin i0"
        unlessEither (isConstantBoolFamily bool typeFamily)
          "empty Glue partial type is not constant builtin Bool"
        unlessEither (isEmptyPartial empty equivalence)
          "empty Glue equivalence system is not exact isOneEmpty"
        Right candidate
      _ -> Left "prim^unglue does not have the expected seven-argument spine"
    introduction <- case glued of
      Internal.Def name eliminations
        | name == glue -> appliedTerms eliminations
        | otherwise -> Left "prim^unglue argument head is not exact builtin prim^glue"
      _ -> Left "prim^unglue argument is not a prim^glue application"
    base <- case introduction of
      [levelA, levelT, baseType, face, typeFamily, equivalence, partialValue, value] -> do
        unlessEither (isZeroLevel levelA && isZeroLevel levelT)
          "empty prim^glue universe levels are not both lzero"
        unlessEither (isBoolTerm bool baseType)
          "empty prim^glue base type is not exact builtin Bool"
        unlessEither (isConstructor iZero face)
          "empty prim^glue face is not exact builtin i0"
        unlessEither (isConstantBoolFamily bool typeFamily)
          "empty prim^glue partial type is not constant builtin Bool"
        unlessEither (isEmptyPartial empty equivalence && isEmptyPartial empty partialValue)
          "empty prim^glue systems are not exact isOneEmpty"
        Right value
      _ -> Left "prim^glue does not have the expected eight-argument spine"
    baseValue <- classifyBoolBase falseConstructor trueConstructor base
    Right $ renderRuntimeIrV7 definition baseValue

lowerConstantBoolTransp :: Definition -> Term -> TCM (Either String String)
lowerConstantBoolTransp definition term = do
  transName <- Builtin.getPrimitiveName' Builtin.builtinTrans
  glueTypeName <- Builtin.getPrimitiveName' Builtin.builtinGlue
  glueIntroName <- Builtin.getPrimitiveName' Builtin.builtin_glue
  boolName <- Builtin.getBuiltinName' Builtin.builtinBool
  falseName <- Builtin.getBuiltinName' Builtin.builtinFalse
  trueName <- Builtin.getBuiltinName' Builtin.builtinTrue
  levelZeroName <- Builtin.getBuiltinName' Builtin.builtinLevelZero
  iZeroName <- Builtin.getBuiltinName' Builtin.builtinIZero
  iOneName <- Builtin.getBuiltinName' Builtin.builtinIOne
  iNegName <- Builtin.getPrimitiveName' Builtin.builtinINeg
  iMaxName <- Builtin.getPrimitiveName' Builtin.builtinIMax
  emptyName <- Builtin.getBuiltinName' Builtin.builtinIsOneEmpty
  familyDebug <- describeGlueFamilyDefinitions transName glueTypeName term
  nontrivial <- classifyNontrivialGlueFamily
    transName glueTypeName boolName falseName trueName iZeroName iOneName
    iNegName iMaxName term
  pure $ do
    trans <- requiredBuiltin "primTransp" transName
    bool <- requiredBuiltin "Bool" boolName
    falseConstructor <- requiredBuiltin "false" falseName
    trueConstructor <- requiredBuiltin "true" trueName
    levelZero <- requiredBuiltin "lzero" levelZeroName
    iZero <- requiredBuiltin "i0" iZeroName
    unlessEither (isBoolType bool (defType definition))
      "primTransp result type is not exact builtin Bool"
    unlessEither (Free.closed term) "selected primTransp term is open"
    unlessEither (noMetas (term, defType definition))
      "selected primTransp term or type contains a metavariable"
    arguments <- case term of
      Internal.Def name eliminations
        | name == trans -> appliedTerms eliminations
        | otherwise -> Left "selected term head is not exact builtin primTransp"
      _ -> Left "selected term is not a primTransp application"
    case arguments of
      [levelFamily, typeFamily, face, base] -> do
        unlessEither (isConstantZeroLevelFamily levelZero levelFamily)
          ("primTransp universe level family is not constant lzero: " ++
            take 512 (prettyShow levelFamily))
        unlessEither (isConstructor iZero face)
          "primTransp face is not exact builtin i0"
        if isConstantBoolFamily bool typeFamily then do
          baseValue <- classifyBoolBase falseConstructor trueConstructor base
          Right $ renderRuntimeIrV5 definition baseValue
        else do
          glueType <- requiredBuiltin "primGlue" glueTypeName
          case classifyIdentityGlueFamily familyDebug glueType bool typeFamily of
            Right equivalenceName -> do
              glueIntro <- requiredBuiltin "prim^glue" glueIntroName
              empty <- requiredBuiltin "isOneEmpty" emptyName
              baseValue <- classifyEmptyGlueBase glueIntro bool empty iZero
                falseConstructor trueConstructor base
              Right $ renderRuntimeIrV11 definition equivalenceName baseValue
            Left identityFailure -> case nontrivial of
              Nothing -> Left identityFailure
              Just (Left reason) -> Left reason
              Just (Right (equivalenceName, functionName)) -> do
                baseValue <- classifyBoolBase falseConstructor trueConstructor base
                Right $ renderRuntimeIrV13
                  definition equivalenceName functionName baseValue
      _ -> Left "primTransp does not have the expected four-argument spine"

classifyIdentityGlueFamily :: String -> QName -> QName -> Term -> Either String QName
classifyIdentityGlueFamily familyDebug glueType bool = \case
  Internal.Lam _ abstraction -> case abstractionBody abstraction of
    Internal.Def name eliminations | name == glueType -> do
      arguments <- appliedTerms eliminations
      case arguments of
        [levelA, levelT, baseType, face, partialType, equivalence] -> do
          unlessEither (isZeroLevel levelA && isZeroLevel levelT)
            "Glue transport family levels are not both lzero"
          unlessEither (isBoolTerm bool baseType)
            "Glue transport family base is not builtin Bool"
          unlessEither (face == Internal.Var 0 [])
            ("Glue transport family face is not its interval binder: face=" ++
              take 512 (prettyShow face) ++ "; partial-type=" ++
              take 1024 (prettyShow partialType) ++ "; equivalence=" ++
              take 2048 (prettyShow equivalence) ++ familyDebug)
          unlessEither (isConstantBoolFamily bool partialType)
            "Glue transport partial type is not constant Bool"
          classifyIdentityEquivalence bool equivalence
        _ -> Left "Glue transport family has an unexpected primGlue spine"
    _ -> Left "nonconstant transport family is not headed by primGlue"
  _ -> Left "nonconstant transport family is not an interval lambda"

describeGlueFamilyDefinitions :: Maybe QName -> Maybe QName -> Term -> TCM String
describeGlueFamilyDefinitions transName glueTypeName term = case (transName, glueTypeName, term) of
  (Just trans, Just glueType, Internal.Def name eliminations) | name == trans ->
    case appliedTerms eliminations of
      Right [_, Internal.Lam _ family, _, _] -> case abstractionBody family of
        Internal.Def glue eliminations' | glue == glueType ->
          case appliedTerms eliminations' of
            Right [_, _, _, _, partialType, equivalence] -> do
              partialDescription <- describeHead partialType
              equivalenceDescription <- describeHead equivalence
              pure $ "; partial-definition=" ++ partialDescription ++
                "; equivalence-definition=" ++ equivalenceDescription
            _ -> pure ""
        _ -> pure ""
      _ -> pure ""
  _ -> pure ""
  where
    describeHead candidate = case candidate of
      Internal.Def name _ -> prettyShow . theDef <$> getConstInfo name
      _ -> pure (take 1024 (prettyShow candidate))

classifyNontrivialGlueFamily
  :: Maybe QName -> Maybe QName -> Maybe QName -> Maybe QName -> Maybe QName
  -> Maybe QName -> Maybe QName -> Maybe QName -> Maybe QName
  -> Term -> TCM (Maybe (Either String (QName, QName)))
classifyNontrivialGlueFamily transName glueTypeName boolName falseName trueName
    iZeroName iOneName iNegName iMaxName term =
  case (transName, glueTypeName, boolName, falseName, trueName, iZeroName,
        iOneName, iNegName, iMaxName) of
    (Just trans, Just glueType, Just bool, Just falseConstructor,
      Just trueConstructor, Just iZero, Just iOne, Just iNeg, Just iMax) ->
      case extractFamily trans glueType iNeg iMax term of
        Nothing -> pure Nothing
        Just (Left reason) -> pure $ Just (Left reason)
        Just (Right (partialName, equivalenceName)) -> do
          partialResult <- validateBoolEndpointSystem
            partialName bool iZero iOne
          equivalenceResult <- validateEquivalenceEndpointSystem
            equivalenceName bool falseConstructor trueConstructor
            iZero iOne
          pure $ Just $ do
            partialResult
            (notEquivalence, notFunction) <- equivalenceResult
            Right (notEquivalence, notFunction)
    _ -> pure $ Just $ Left $
      "nontrivial Glue required builtin unavailable: " ++ show
        (map isJust [transName, glueTypeName, boolName, falseName, trueName,
          iZeroName, iOneName, iNegName, iMaxName])
  where
    extractFamily trans glueType iNeg iMax candidate = do
      arguments <- case candidate of
        Internal.Def name eliminations | name == trans -> either (const Nothing) Just $
          appliedTerms eliminations
        _ -> Nothing
      family <- case arguments of
        [_, value, _, _] -> Just value
        _ -> Nothing
      case family of
        Internal.Lam _ abstraction -> case abstractionBody abstraction of
          Internal.Def name eliminations | name == glueType ->
            case appliedTerms eliminations of
              Right [_, _, _, face, partialType, equivalence]
                | isCoveredIntervalFace iNeg iMax face -> Just $ do
                    partialName <- appliedVariableHead "partial-type" partialType
                    equivalenceName <- appliedVariableHead "equivalence" equivalence
                    Right (partialName, equivalenceName)
                | otherwise -> Just $ Left $
                    "nontrivial Glue covered face identity mismatch: " ++ show face ++
                    "; expected ineg=" ++ prettyShow iNeg ++
                    "; imax=" ++ prettyShow iMax
              Right _ -> Just $ Left "nontrivial Glue family has an unexpected primGlue spine"
              Left reason -> Just $ Left reason
          _ -> Nothing
        _ -> Nothing

isCoveredIntervalFace :: QName -> QName -> Term -> Bool
isCoveredIntervalFace iNeg iMax = \case
  Internal.Def name eliminations | name == iMax ->
    case appliedTerms eliminations of
      Right [negative, Internal.Var 0 []] -> case negative of
        Internal.Def neg eliminations' | neg == iNeg ->
          appliedTerms eliminations' == Right [Internal.Var 0 []]
        _ -> False
      _ -> False
  _ -> False

appliedVariableHead :: String -> Term -> Either String QName
appliedVariableHead label = \case
  Internal.Def name eliminations -> do
    values <- appliedTerms eliminations
    unlessEither (values == [Internal.Var 0 []]) $
      "nontrivial Glue " ++ label ++ " is not applied to its interval binder"
    Right name
  _ -> Left $ "nontrivial Glue " ++ label ++ " is not a named checked system"

validateBoolEndpointSystem
  :: QName -> QName -> QName -> QName -> TCM (Either String ())
validateBoolEndpointSystem systemName bool iZero iOne = do
  definition <- getConstInfo systemName
  pure $ case theDef definition of
    Function { funClauses = clauses } -> do
      zeroBody <- endpointClauseBody iZero clauses
      oneBody <- endpointClauseBody iOne clauses
      unlessEither (length (definedClauseBodies clauses) == 2 && isBoolTerm bool zeroBody
        && isBoolTerm bool oneBody)
        "nontrivial Glue partial type is not exact Bool at both endpoints"
    _ -> Left "nontrivial Glue partial type system is not a checked function"

validateEquivalenceEndpointSystem
  :: QName -> QName -> QName -> QName -> QName -> QName
  -> TCM (Either String (QName, QName))
validateEquivalenceEndpointSystem systemName bool falseConstructor trueConstructor
    iZero iOne = do
  definition <- getConstInfo systemName
  case theDef definition of
    Function { funClauses = clauses } -> case do
      zeroBody <- endpointClauseBody iZero clauses
      oneBody <- endpointClauseBody iOne clauses
      unlessEither (length (definedClauseBodies clauses) == 2)
        "nontrivial Glue equivalence system does not have two endpoint clauses"
      notEquivalence <- case zeroBody of
        Internal.Def name [] -> Right name
        _ -> Left "nontrivial Glue i0 equivalence is not a named checked definition"
      _ <- classifyPathToEquiv bool oneBody
      Right notEquivalence of
        Left reason -> pure (Left reason)
        Right notEquivalence -> do
          validated <- validateBoolNegationEquivalence
            notEquivalence bool falseConstructor trueConstructor
          pure $ fmap (\functionName -> (notEquivalence, functionName)) validated
    _ -> pure $ Left "nontrivial Glue equivalence system is not a checked function"

classifyPathToEquiv :: QName -> Term -> Either String QName
classifyPathToEquiv bool = \case
  Internal.Def name eliminations -> do
    unlessEither (prettyShow name == "Agda.Builtin.Cubical.Equiv._.pathToEquiv")
      "nontrivial Glue i1 equivalence is not locked pathToEquiv"
    arguments <- appliedTerms eliminations
    family <- maybe (Left "pathToEquiv application has no family") Right $
      case reverse arguments of
        candidate : _ -> Just candidate
        [] -> Nothing
    unlessEither (isConstantBoolFamily bool family)
      "nontrivial Glue i1 pathToEquiv family is not constant Bool"
    Right name
  _ -> Left "nontrivial Glue i1 equivalence is not pathToEquiv"

validateBoolNegationEquivalence
  :: QName -> QName -> QName -> QName -> TCM (Either String QName)
validateBoolNegationEquivalence equivalenceName _bool falseConstructor trueConstructor = do
  definition <- getConstInfo equivalenceName
  case theDef definition of
    Function { funClauses = [clause] } -> case clauseBody clause of
      Just (Internal.Con constructor _ eliminations)
        | prettyShow (Internal.conName constructor) == "Agda.Builtin.Sigma._,_" ->
          case appliedTerms eliminations of
            Right (Internal.Def functionName [] : _proof : []) -> do
              functionDefinition <- getConstInfo functionName
              pure $ case theDef functionDefinition of
                Function { funClauses = clauses } -> do
                  falseBody <- endpointClauseBody falseConstructor clauses
                  trueBody <- endpointClauseBody trueConstructor clauses
                  unlessEither (length clauses == 2
                    && isConstructor trueConstructor falseBody
                    && isConstructor falseConstructor trueBody)
                    "Glue equivalence function is not exact Bool negation"
                  Right functionName
                _ -> Left "Glue equivalence function is not a checked function"
            _ -> pure $ Left "Glue equivalence pair does not contain function and proof"
      _ -> pure $ Left "Glue i0 equivalence is not an exact Sigma pair"
    _ -> pure $ Left "Glue i0 equivalence is not a single checked definition"

endpointClauseBody :: QName -> [Clause] -> Either String Term
endpointClauseBody endpoint clauses = case
  [ body
  | clause <- clauses
  , any (patternIs endpoint . unArg) (Internal.clausePats clause)
  , Just body <- [clauseBody clause]
  ] of
    [body] -> Right body
    _ -> Left $ "endpoint system lacks one exact clause for " ++ prettyShow endpoint
  where
    patternIs expected = \case
      Internal.ConP constructor _ _ -> Internal.conName constructor == expected
      _ -> False

definedClauseBodies :: [Clause] -> [Term]
definedClauseBodies clauses = [body | clause <- clauses, Just body <- [clauseBody clause]]

classifyIdentityEquivalence :: QName -> Term -> Either String QName
classifyIdentityEquivalence bool = \case
  Internal.Lam _ abstraction -> case abstractionBody abstraction of
    Internal.Def name eliminations -> do
      arguments <- appliedTerms eliminations
      unlessEither (prettyShow name == "Agda.Builtin.Cubical.Equiv._.pathToEquiv")
        ("Glue transport equivalence is not locked pathToEquiv: " ++ prettyShow name)
      family <- maybe (Left "pathToEquiv application has no family") Right $
        case reverse arguments of
          candidate : _ -> Just candidate
          [] -> Nothing
      unlessEither (isConstantBoolFamily bool family)
        "pathToEquiv family is not constant builtin Bool"
      Right name
    _ -> Left "Glue transport equivalence system is not pathToEquiv"
  _ -> Left "Glue transport equivalence system is not a partial lambda"

classifyEmptyGlueBase
  :: QName -> QName -> QName -> QName -> QName -> QName -> Term
  -> Either String String
classifyEmptyGlueBase glueIntro bool empty iZero
    falseConstructor trueConstructor = \case
  Internal.Def name eliminations | name == glueIntro -> do
    arguments <- appliedTerms eliminations
    case arguments of
      [levelA, levelT, baseType, face, partialType, equivalence, partialValue, value] -> do
        unlessEither (isZeroLevel levelA && isZeroLevel levelT)
          "Glue transport base levels are not both lzero"
        unlessEither (isBoolTerm bool baseType && isConstructor iZero face)
          "Glue transport base type or face identity mismatch"
        unlessEither (isConstantBoolFamily bool partialType)
          "Glue transport base partial type is not constant Bool"
        _ <- classifyIdentityEquivalence bool equivalence
        unlessEither (isEmptyPartial empty partialValue)
          "Glue transport base partial value is not isOneEmpty"
        classifyBoolBase falseConstructor trueConstructor value
      _ -> Left "Glue transport base has an unexpected prim^glue spine"
  _ -> Left "Glue transport base is not exact prim^glue"

lowerEmptyBoolHComp :: Definition -> Term -> TCM (Either String String)
lowerEmptyBoolHComp definition term = do
  sigmaName <- Builtin.getBuiltinName' Builtin.builtinSigma
  boolName <- Builtin.getBuiltinName' Builtin.builtinBool
  case boolName of
    Just bool | isBoolType bool (defType definition) ->
      lowerEmptyBoolLiteralHComp definition term
    _ -> do
      hitInfo <- closedIntervalHitInfo (defType definition)
      evidenceInfo <- case (sigmaName, boolName) of
        (Just sigma, Just bool) -> dependentBoolEvidenceInfo sigma bool (defType definition)
        _ -> pure Nothing
      case (hitInfo, evidenceInfo, sigmaName, boolName) of
        (Just hit, _, _, _) -> lowerEmptyHitHComp definition term hit
        (_, Just evidence, Just sigma, Just bool) ->
          lowerEmptyDependentEvidenceHComp definition term sigma bool evidence
        (_, _, Just sigma, Just bool)
          | isBoolSigmaType sigma bool (defType definition) ->
              lowerEmptyBoolSigmaHComp definition term sigma bool
        _ -> lowerEmptyBoolLiteralHComp definition term

dependentBoolEvidenceInfo :: QName -> QName -> Type -> TCM (Maybe EvidenceInfo)
dependentBoolEvidenceInfo sigma bool (Internal.El _ typeTerm) =
  case typeTerm of
    Internal.Def name eliminations | name == sigma ->
      case appliedTerms eliminations of
        Right [levelA, levelB, domain, family]
          | isZeroLevel levelA && isZeroLevel levelB
          , isBoolTerm bool domain
          , Just evidenceName <- indexedFamilyName family -> do
              boolEvidenceInfoFromName evidenceName
        _ -> pure Nothing
    _ -> pure Nothing

boolEvidenceInfoFromName :: QName -> TCM (Maybe EvidenceInfo)
boolEvidenceInfoFromName evidenceName = do
  evidenceDefinition <- getConstInfo evidenceName
  case theDef evidenceDefinition of
    Datatype
      { dataPars = 0, dataIxs = 1
      , dataCons = [approvedName, rejectedName], dataPathCons = []
      } -> do
        approved <- getConstInfo approvedName
        rejected <- getConstInfo rejectedName
        falseName <- Builtin.getBuiltinName' Builtin.builtinFalse
        trueName <- Builtin.getBuiltinName' Builtin.builtinTrue
        pure $ do
          falseConstructor <- falseName
          trueConstructor <- trueName
          case (theDef approved, theDef rejected) of
            (Constructor { conArity = 0 }, Constructor { conArity = 0 })
              | constructorTargetsIndex evidenceName trueConstructor approved
              , constructorTargetsIndex evidenceName falseConstructor rejected ->
                  Just $ EvidenceInfo evidenceName approvedName rejectedName
            _ -> Nothing
    _ -> pure Nothing

indexedFamilyName :: Term -> Maybe QName
indexedFamilyName = \case
  Internal.Def name [] -> Just name
  Internal.Lam _ abstraction -> case abstractionBody abstraction of
    Internal.Def name [Apply argument]
      | unArg argument == Internal.Var 0 [] -> Just name
    _ -> Nothing
  _ -> Nothing

constructorTargetsIndex :: QName -> QName -> Definition -> Bool
constructorTargetsIndex familyName indexName definition =
  case defType definition of
    Internal.El _ (Internal.Def name eliminations)
      | name == familyName -> case appliedTerms eliminations of
          Right [index] -> isConstructor indexName index
          _ -> False
    _ -> False

lowerEmptyDependentEvidenceHComp
  :: Definition -> Term -> QName -> QName -> EvidenceInfo
  -> TCM (Either String String)
lowerEmptyDependentEvidenceHComp
    definition term sigma bool
    (EvidenceInfo evidenceName approvedName rejectedName) = do
  hcompName <- Builtin.getPrimitiveName' Builtin.builtinHComp
  falseName <- Builtin.getBuiltinName' Builtin.builtinFalse
  trueName <- Builtin.getBuiltinName' Builtin.builtinTrue
  sigmaDefinition <- getConstInfo sigma
  let sigmaConName = case theDef sigmaDefinition of
        Record { recConHead = constructor } -> Just (Internal.conName constructor)
        _ -> Nothing
  iZeroName <- Builtin.getBuiltinName' Builtin.builtinIZero
  emptyName <- Builtin.getBuiltinName' Builtin.builtinIsOneEmpty
  pure $ do
    hcomp <- requiredBuiltin "primHComp" hcompName
    falseConstructor <- requiredBuiltin "false" falseName
    trueConstructor <- requiredBuiltin "true" trueName
    sigmaConstructor <- requiredBuiltin "Sigma constructor" sigmaConName
    iZero <- requiredBuiltin "i0" iZeroName
    empty <- requiredBuiltin "isOneEmpty" emptyName
    unlessEither (Free.closed term) "selected dependent Sigma term is open"
    unlessEither (noMetas (term, defType definition))
      "selected dependent Sigma term or type contains a metavariable"
    arguments <- case term of
      Internal.Def name eliminations
        | name == hcomp -> appliedTerms eliminations
        | otherwise -> Left "dependent Sigma term head is not exact builtin primHComp"
      _ -> Left "dependent Sigma term is not a primHComp application"
    base <- case arguments of
      [level, valueType, face, sides, candidate] -> do
        unlessEither (isZeroLevel level) "dependent Sigma primHComp level is not lzero"
        unlessEither
          (isDependentEvidenceSigmaTerm sigma bool evidenceName valueType)
          "dependent Sigma value type identity mismatch"
        unlessEither (isConstructor iZero face)
          "dependent Sigma primHComp face is not exact builtin i0"
        unlessEither (isEmptySystem empty sides)
          "dependent Sigma primHComp system is not exact empty-face"
        Right candidate
      _ -> Left "dependent Sigma primHComp does not have the expected spine"
    components <- case base of
      Internal.Con constructor _ eliminations
        | Internal.conName constructor == sigmaConstructor -> appliedTerms eliminations
      _ -> Left "dependent Sigma base is not the exact pair constructor"
    case components of
      [decision, evidence]
        | isConstructor trueConstructor decision
        , isConstructor approvedName evidence ->
            Right $ renderRuntimeIrV9 definition evidenceName
              approvedName rejectedName "true" "approved"
        | isConstructor falseConstructor decision
        , isConstructor rejectedName evidence ->
            Right $ renderRuntimeIrV9 definition evidenceName
              approvedName rejectedName "false" "rejected"
        | otherwise -> Left "dependent Sigma decision/evidence indices do not correspond"
      _ -> Left "dependent Sigma pair does not contain exactly two fields"

closedIntervalHitInfo :: Type -> TCM (Maybe HitInfo)
closedIntervalHitInfo (Internal.El _ typeTerm) = case typeTerm of
  Internal.Def typeName [] -> do
    typeDefinition <- getConstInfo typeName
    case theDef typeDefinition of
      Datatype
        { dataPars = 0, dataIxs = 0, dataCons = [leftName, rightName, pathName]
        , dataPathCons = [declaredPath]
        }
          | pathName == declaredPath -> do
              leftDefinition <- getConstInfo leftName
              rightDefinition <- getConstInfo rightName
              pathDefinition <- getConstInfo pathName
              pure $ case
                  (theDef leftDefinition, theDef rightDefinition, theDef pathDefinition) of
                ( Constructor { conArity = 0 }, Constructor { conArity = 0 }
                  , Constructor { conArity = 1 }) ->
                    Just (HitInfo typeName leftName rightName pathName)
                _ -> Nothing
      _ -> pure Nothing
  _ -> pure Nothing

lowerEmptyHitHComp :: Definition -> Term -> HitInfo -> TCM (Either String String)
lowerEmptyHitHComp definition term (HitInfo typeName leftName rightName pathName) = do
  hcompName <- Builtin.getPrimitiveName' Builtin.builtinHComp
  iNegName <- Builtin.getPrimitiveName' Builtin.builtinINeg
  iZeroName <- Builtin.getBuiltinName' Builtin.builtinIZero
  iOneName <- Builtin.getBuiltinName' Builtin.builtinIOne
  emptyName <- Builtin.getBuiltinName' Builtin.builtinIsOneEmpty
  pure $ do
    hcomp <- requiredBuiltin "primHComp" hcompName
    iNeg <- requiredBuiltin "primINeg" iNegName
    iZero <- requiredBuiltin "i0" iZeroName
    iOne <- requiredBuiltin "i1" iOneName
    empty <- requiredBuiltin "isOneEmpty" emptyName
    unlessEither (Free.closed term) "selected HIT primHComp term is open"
    unlessEither (noMetas (term, defType definition))
      "selected HIT primHComp term or type contains a metavariable"
    arguments <- case term of
      Internal.Def name eliminations
        | name == hcomp -> appliedTerms eliminations
        | otherwise -> Left "selected HIT term head is not exact builtin primHComp"
      _ -> Left "selected HIT term is not a primHComp application"
    (faceKind, base) <- case arguments of
      [level, valueType, face, sides, candidate] -> do
        unlessEither (isZeroLevel level) "HIT primHComp level is not lzero"
        unlessEither (isNamedType typeName valueType)
          "HIT primHComp value type identity mismatch"
        if isConstructor iZero face then do
          unlessEither (isEmptySystem empty sides)
            "HIT primHComp system is not the exact empty-face system"
          Right (Nothing, candidate)
        else if isConstructor iOne face then do
          orientation <- classifyActiveHitSystem leftName rightName pathName iNeg sides
          Right (Just orientation, candidate)
        else Left "HIT primHComp face is neither exact builtin i0 nor i1"
      _ -> Left "HIT primHComp does not have the expected five-argument spine"
    baseKind <- classifyHitBase leftName rightName pathName iZero iOne base
    case faceKind of
      Nothing -> Right $ renderRuntimeIrV8
        definition typeName leftName rightName pathName baseKind
      Just orientation -> do
        unlessEither
          ((orientation == "forward" && baseKind == "left")
            || (orientation == "reverse" && baseKind == "right"))
          "active HIT tube does not agree with its composition-start base"
        Right $ renderRuntimeIrV12 definition typeName leftName rightName pathName orientation

classifyActiveHitSystem
  :: QName -> QName -> QName -> QName -> Term -> Either String String
classifyActiveHitSystem leftName rightName pathName iNeg = \case
  Internal.Lam _ outer -> case abstractionBody outer of
    Internal.Lam _ inner -> do
      let intervalVariable = case inner of
            NoAbs _ _ -> Internal.Var 0 []
            Abs _ _ -> Internal.Var 1 []
      endpoint <- case abstractionBody inner of
        Internal.Con constructor _ [IApply left right endpoint]
          | Internal.conName constructor == pathName
          , isConstructor leftName left
          , isConstructor rightName right -> Right endpoint
        _ -> Left "active HIT tube is not the declared left-to-right path constructor"
      if endpoint == intervalVariable then Right "forward"
      else case endpoint of
        Internal.Def name eliminations | name == iNeg -> do
          values <- appliedTerms eliminations
          unlessEither (values == [intervalVariable])
            "active HIT reverse tube negates a non-tube variable"
          Right "reverse"
        _ -> Left "active HIT path endpoint is neither tube variable nor its negation"
    _ -> Left "active HIT system is not a two-argument tube"
  _ -> Left "active HIT system is not a lambda tube"

classifyHitBase
  :: QName -> QName -> QName -> QName -> QName -> Term -> Either String String
classifyHitBase leftName rightName pathName iZero iOne = \case
  Internal.Con constructor _ eliminations
    | Internal.conName constructor == leftName -> do
        values <- appliedTerms eliminations
        unlessEither (null values) "HIT left point unexpectedly has arguments"
        Right "left"
    | Internal.conName constructor == rightName -> do
        values <- appliedTerms eliminations
        unlessEither (null values) "HIT right point unexpectedly has arguments"
        Right "right"
    | Internal.conName constructor == pathName -> do
        case eliminations of
          [IApply left right endpoint] -> do
            unlessEither (isConstructor leftName left && isConstructor rightName right)
              "HIT path constructor boundary is not left-to-right"
            if isConstructor iZero endpoint then Right "path-i0"
            else if isConstructor iOne endpoint then Right "path-i1"
            else Left "HIT path base is not applied to an interval endpoint"
          _ -> Left "HIT path base does not have one exact interval application"
  _ -> Left "HIT primHComp base is not a declared point/path constructor"

lowerEmptyBoolLiteralHComp :: Definition -> Term -> TCM (Either String String)
lowerEmptyBoolLiteralHComp definition term = do
  hcompName <- Builtin.getPrimitiveName' Builtin.builtinHComp
  boolName <- Builtin.getBuiltinName' Builtin.builtinBool
  falseName <- Builtin.getBuiltinName' Builtin.builtinFalse
  trueName <- Builtin.getBuiltinName' Builtin.builtinTrue
  iZeroName <- Builtin.getBuiltinName' Builtin.builtinIZero
  iOneName <- Builtin.getBuiltinName' Builtin.builtinIOne
  emptyName <- Builtin.getBuiltinName' Builtin.builtinIsOneEmpty
  case (do
    hcomp <- requiredBuiltin "primHComp" hcompName
    bool <- requiredBuiltin "Bool" boolName
    falseConstructor <- requiredBuiltin "false" falseName
    trueConstructor <- requiredBuiltin "true" trueName
    iZero <- requiredBuiltin "i0" iZeroName
    iOne <- requiredBuiltin "i1" iOneName
    empty <- requiredBuiltin "isOneEmpty" emptyName
    unlessEither (isBoolType bool (defType definition))
      "selected entry type is not exact builtin Bool"
    unlessEither (Free.closed term)
      "selected Internal term is open"
    unlessEither (noMetas (term, defType definition))
      "selected Internal term or type contains a metavariable"
    arguments <- case term of
      Internal.Def name eliminations
        | name == hcomp -> appliedTerms eliminations
        | otherwise -> Left "selected term head is not exact builtin primHComp"
      _ -> Left "selected term is not a primHComp application"
    loweredInput <- case arguments of
      [level, valueType, face, sides, base] -> do
        unlessEither (isZeroLevel level) "primHComp level is not lzero"
        unlessEither (isBoolTerm bool valueType) "primHComp value type is not exact builtin Bool"
        if isConstructor iZero face then do
          unlessEither (isEmptySystem empty sides)
            "primHComp system is not the exact empty-face system"
          pure (Nothing, base)
        else if isConstructor iOne face then do
          sideValue <- classifyActiveBoolSystem
            falseConstructor trueConstructor sides
          pure (Just sideValue, base)
        else Left "primHComp face is neither exact builtin i0 nor i1"
      _ -> Left "primHComp does not have the expected five-argument spine"
    pure (falseConstructor, trueConstructor, bool, loweredInput)
    ) of
      Left reason -> pure (Left reason)
      Right (falseConstructor, trueConstructor, bool, (Nothing, base)) ->
        lowerBoolBase definition bool falseConstructor trueConstructor base
      Right (falseConstructor, trueConstructor, _, (Just sideValue, base)) ->
        pure $ do
          baseValue <- classifyBoolBase falseConstructor trueConstructor base
          unlessEither (sideValue == baseValue)
            "active Bool primHComp side is not definitionally compatible with its base"
          Right $ renderRuntimeIrV6 definition sideValue baseValue

lowerEmptyBoolSigmaHComp
  :: Definition -> Term -> QName -> QName -> TCM (Either String String)
lowerEmptyBoolSigmaHComp definition term sigma bool = do
  hcompName <- Builtin.getPrimitiveName' Builtin.builtinHComp
  falseName <- Builtin.getBuiltinName' Builtin.builtinFalse
  trueName <- Builtin.getBuiltinName' Builtin.builtinTrue
  sigmaDefinition <- getConstInfo sigma
  let sigmaConName = case theDef sigmaDefinition of
        Record { recConHead = constructor } -> Just (Internal.conName constructor)
        _ -> Nothing
  iZeroName <- Builtin.getBuiltinName' Builtin.builtinIZero
  emptyName <- Builtin.getBuiltinName' Builtin.builtinIsOneEmpty
  pure $ do
    hcomp <- requiredBuiltin "primHComp" hcompName
    falseConstructor <- requiredBuiltin "false" falseName
    trueConstructor <- requiredBuiltin "true" trueName
    sigmaConstructor <- requiredBuiltin "Sigma constructor" sigmaConName
    iZero <- requiredBuiltin "i0" iZeroName
    empty <- requiredBuiltin "isOneEmpty" emptyName
    unlessEither (Free.closed term) "selected Internal Sigma term is open"
    unlessEither (noMetas (term, defType definition))
      "selected Internal Sigma term or type contains a metavariable"
    arguments <- case term of
      Internal.Def name eliminations
        | name == hcomp -> appliedTerms eliminations
        | otherwise -> Left "selected Sigma term head is not exact builtin primHComp"
      _ -> Left "selected Sigma term is not a primHComp application"
    base <- case arguments of
      [level, valueType, face, sides, candidate] -> do
        unlessEither (isZeroLevel level) "Sigma primHComp level is not lzero"
        unlessEither (isBoolSigmaTerm sigma bool valueType)
          ("Sigma primHComp value type is not exact Sigma Bool (const Bool): " ++
            take 512 (prettyShow valueType))
        unlessEither (isConstructor iZero face)
          "Sigma primHComp face is not exact builtin i0"
        unlessEither (isEmptySystem empty sides)
          "Sigma primHComp system is not the exact empty-face system"
        Right candidate
      _ -> Left "Sigma primHComp does not have the expected five-argument spine"
    components <- case base of
      Internal.Con constructor _ eliminations
        | Internal.conName constructor == sigmaConstructor -> appliedTerms eliminations
      _ -> Left "Sigma primHComp base is not the exact builtin pair constructor"
    case components of
      [first, second] -> do
        firstValue <- classifyBoolBase falseConstructor trueConstructor first
        secondValue <- classifyBoolBase falseConstructor trueConstructor second
        Right $ renderRuntimeIrV4 definition firstValue secondValue
      _ -> Left "Sigma pair does not contain exactly two runtime fields"

lowerBoolBase :: Definition -> QName -> QName -> QName -> Term -> TCM (Either String String)
lowerBoolBase selected bool falseConstructor trueConstructor base =
  case classifyBoolBase falseConstructor trueConstructor base of
    Right baseValue -> pure $ Right $ renderRuntimeIrV1 selected baseValue
    Left _ -> do
      dependent <- tryLowerDependentDecisionApplication
        selected bool falseConstructor trueConstructor base
      case dependent of
        Just result -> pure result
        Nothing -> do
          lowered <- lowerBoolExpression
            bool falseConstructor trueConstructor [] 0 False base
          pure $ do
            (definitions, expression) <- lowered
            unlessEither (not (null definitions))
              "primHComp base contains no supported definition application"
            unlessEither (length definitions <= maxDefinitionCount)
              "definition slice exceeds 32 definitions"
            pure $ renderRuntimeIrV3 selected definitions expression

tryLowerDependentDecisionApplication
  :: Definition -> QName -> QName -> QName -> Term
  -> TCM (Maybe (Either String String))
tryLowerDependentDecisionApplication
    selected bool falseConstructor trueConstructor base = case base of
  Internal.Def functionName eliminations -> case appliedTerms eliminations of
    Right [decision, evidence] -> do
      functionDefinition <- getConstInfo functionName
      case dependentDecisionEvidenceName bool (defType functionDefinition) of
        Nothing -> pure Nothing
        Just evidenceName -> do
          evidenceInfo <- boolEvidenceInfoFromName evidenceName
          pure $ Just $ do
            EvidenceInfo _ approvedName rejectedName <- maybe
              (Left "dependent decision function evidence family is unsupported")
              Right evidenceInfo
            (approvedResult, rejectedResult) <-
              dependentClauseResults falseConstructor trueConstructor
                approvedName rejectedName functionDefinition
            (decisionValue, evidenceKind) <-
              classifyDecisionEvidenceCall falseConstructor trueConstructor
                approvedName rejectedName decision evidence
            Right $ renderRuntimeIrV10 selected functionName evidenceName
              approvedName rejectedName approvedResult rejectedResult
              decisionValue evidenceKind
    _ -> pure Nothing
  _ -> pure Nothing

dependentDecisionEvidenceName :: QName -> Type -> Maybe QName
dependentDecisionEvidenceName bool (Internal.El _ term) = case term of
  Internal.Pi decisionDomain decisionCodomain
    | isBoolType bool (unDom decisionDomain) ->
        case abstractionBody decisionCodomain of
          Internal.El _ (Internal.Pi evidenceDomain resultCodomain)
            | isBoolType bool (abstractionBody resultCodomain) ->
                indexedEvidenceAtVariable (unDom evidenceDomain)
          _ -> Nothing
  _ -> Nothing

indexedEvidenceAtVariable :: Type -> Maybe QName
indexedEvidenceAtVariable (Internal.El _ term) = case term of
  Internal.Def name eliminations -> case appliedTerms eliminations of
    Right [Internal.Var 0 []] -> Just name
    _ -> Nothing
  _ -> Nothing

dependentClauseResults
  :: QName -> QName -> QName -> QName -> Definition -> Either String (String, String)
dependentClauseResults falseConstructor trueConstructor
    approvedName rejectedName definition = case theDef definition of
  Function { funClauses = [clause] }
    | [Internal.VarP _ _, Internal.VarP _ _] <- map unArg (Internal.clausePats clause)
    , Just (Internal.Var 1 []) <- clauseBody clause -> Right ("true", "false")
  Function { funClauses = clauses }
    | length clauses == 2 -> do
        classified <- traverse classify clauses
        approvedResult <- uniqueResult "approved" classified
        rejectedResult <- uniqueResult "rejected" classified
        Right (approvedResult, rejectedResult)
  _ -> Left "dependent decision function is not an exact two-clause definition"
  where
    classify clause = do
      body <- maybe (Left "dependent decision clause has no body") Right $
        clauseBody clause
      result <- classifyBoolBase falseConstructor trueConstructor body
      case map unArg (Internal.clausePats clause) of
        [ Internal.ConP decisionCon _ [], Internal.ConP evidenceCon _ [] ]
          | Internal.conName decisionCon == trueConstructor
          , Internal.conName evidenceCon == approvedName -> Right ("approved", result)
          | Internal.conName decisionCon == falseConstructor
          , Internal.conName evidenceCon == rejectedName -> Right ("rejected", result)
        _ -> Left "dependent decision clause patterns do not match indexed evidence"
    uniqueResult label values = case [result | (actual, result) <- values, actual == label] of
      [result] -> Right result
      _ -> Left ("dependent decision function lacks unique " ++ label ++ " clause")

classifyDecisionEvidenceCall
  :: QName -> QName -> QName -> QName -> Term -> Term -> Either String (String, String)
classifyDecisionEvidenceCall falseConstructor trueConstructor
    approvedName rejectedName decision evidence
  | isConstructor trueConstructor decision, isConstructor approvedName evidence =
      Right ("true", "approved")
  | isConstructor falseConstructor decision, isConstructor rejectedName evidence =
      Right ("false", "rejected")
  | otherwise = Left "dependent decision call has mismatched decision/evidence indices"

data BoolExpression
  = BoolArgument
  | BoolLiteralFalse
  | BoolLiteralTrue
  | BoolApply QName BoolExpression

data BoolDefinition = BoolDefinition QName BoolExpression

maxDefinitionDepth :: Int
maxDefinitionDepth = 16

maxDefinitionCount :: Int
maxDefinitionCount = 32

lowerBoolExpression
  :: QName -> QName -> QName -> [QName] -> Int -> Bool -> Term
  -> TCM (Either String ([BoolDefinition], BoolExpression))
lowerBoolExpression bool falseConstructor trueConstructor stack depth allowArgument term
  | depth > maxDefinitionDepth = pure $ Left "definition slice exceeds depth 16"
  | isConstructor falseConstructor term = pure $ Right ([], BoolLiteralFalse)
  | isConstructor trueConstructor term = pure $ Right ([], BoolLiteralTrue)
  | otherwise = case term of
      Internal.Var 0 []
        | allowArgument -> pure $ Right ([], BoolArgument)
      Internal.Def name eliminations
        | name `elem` stack -> pure $ Left "recursive Bool definition cycle is unsupported"
        | otherwise -> do
            referenced <- getConstInfo name
            case appliedTerms eliminations of
              Left reason -> pure (Left reason)
              Right [argumentTerm]
                | isBoolFunctionType bool (defType referenced) -> do
                    loweredArgument <- lowerBoolExpression
                      bool falseConstructor trueConstructor stack (depth + 1)
                      allowArgument argumentTerm
                    loweredBody <- case theDef referenced of
                      Function { funClauses = [clause] }
                        | length (telToList (clauseTel clause)) <= 1
                        , Just clauseTerm <- clauseBody clause ->
                            lowerBoolExpression bool falseConstructor trueConstructor
                              (name : stack) (depth + 1) True clauseTerm
                      _ -> pure $ Left
                        "referenced Bool policy is not a supported single-clause function"
                    pure $ do
                      (argumentDefinitions, argument) <- loweredArgument
                      (bodyDefinitions, body) <- loweredBody
                      let definitions = mergeDefinitions
                            (argumentDefinitions ++ bodyDefinitions ++ [BoolDefinition name body])
                      unlessEither (length definitions <= maxDefinitionCount)
                        "definition slice exceeds 32 definitions"
                      pure (definitions, BoolApply name argument)
              Right [_] -> pure $ Left
                "referenced policy definition is not exact Bool → Bool"
              Right _ -> pure $ Left
                "Bool policy definition is not applied to exactly one Bool argument"
      _ -> pure $ Left $ "Bool expression is not yet supported: "
        ++ take 512 (prettyShow term)

mergeDefinitions :: [BoolDefinition] -> [BoolDefinition]
mergeDefinitions = foldl insertDefinition []
  where
    insertDefinition accumulated definition@(BoolDefinition name _) =
      case find (sameName name) accumulated of
        Just _ -> accumulated
        Nothing -> accumulated ++ [definition]
    sameName expected (BoolDefinition actual _) = expected == actual

renderRuntimeIrV1 :: Definition -> String -> String
renderRuntimeIrV1 definition baseValue = unlines
  [ "schema=runtime-nbe-ir-v14"
  , "language=runtime-nbe-typed-ast-v1"
  , "context-size=0"
  , "type-ast=bool"
  , "term-ast=hcomp(i0,empty," ++ baseValue ++ ")"
  , "definition-count=0"
  , "source-qname=" ++ prettyShow (defName definition)
  , "agda-revision=3d04bacca842729f9c0869b9287256321b5f450f"
  , "provider-revision=ba16f3758a322e9be77ada1da2b93f45d500192e"
  ]

renderRuntimeIrV3 :: Definition -> [BoolDefinition] -> BoolExpression -> String
renderRuntimeIrV3 selected definitions expression = unlines $
  [ "schema=runtime-nbe-ir-v14"
  , "language=runtime-nbe-typed-ast-v1"
  , "context-size=0"
  , "type-ast=bool"
  , "term-ast=hcomp(i0,empty," ++
      renderTypedBoolExpression definitions expression ++ ")"
  , "definition-count=" ++ show (length definitions)
  ]
  ++ concatMap renderDefinition (zip [0 :: Int ..] definitions)
  ++ [ "source-qname=" ++ prettyShow (defName selected)
     , "agda-revision=3d04bacca842729f9c0869b9287256321b5f450f"
     , "provider-revision=ba16f3758a322e9be77ada1da2b93f45d500192e"
     ]
  where
    renderDefinition (index, BoolDefinition name body) =
      [ "def" ++ show index ++ "-qname=" ++ prettyShow name
      , "def" ++ show index ++ "-type-ast=pi(bool,bool)"
      , "def" ++ show index ++ "-body-ast=" ++
          renderTypedBoolExpression definitions body
      ]

renderTypedBoolExpression :: [BoolDefinition] -> BoolExpression -> String
renderTypedBoolExpression definitions = \case
  BoolArgument -> "var(0)"
  BoolLiteralFalse -> "false"
  BoolLiteralTrue -> "true"
  BoolApply name argument -> case definitionIndex name definitions of
    Just index -> "app(def(" ++ show index ++ ")," ++
      renderTypedBoolExpression definitions argument ++ ")"
    Nothing -> "invalid-missing-definition"

definitionIndex :: QName -> [BoolDefinition] -> Maybe Int
definitionIndex expected = go 0
  where
    go _ [] = Nothing
    go index (BoolDefinition actual _ : rest)
      | expected == actual = Just index
      | otherwise = go (index + 1) rest

renderRuntimeIrV4 :: Definition -> String -> String -> String
renderRuntimeIrV4 definition firstValue secondValue = renderRuntimeIrV14
  definition "sigma(bool,bool)"
  ("hcomp(i0,empty,pair(" ++ firstValue ++ "," ++ secondValue ++ "))") []

renderRuntimeIrV5 :: Definition -> String -> String
renderRuntimeIrV5 definition baseValue = renderRuntimeIrV14 definition "bool"
  ("transp(lambda-i(bool),i0," ++ baseValue ++ ")") []

renderRuntimeIrV6 :: Definition -> String -> String -> String
renderRuntimeIrV6 definition sideValue baseValue = renderRuntimeIrV14 definition "bool"
  ("hcomp(i1,constant-system(" ++ sideValue ++ ")," ++ baseValue ++ ")") []

renderRuntimeIrV7 :: Definition -> String -> String
renderRuntimeIrV7 definition baseValue = renderRuntimeIrV14 definition "bool"
  ("unglue(glue(bool,i0,empty," ++ baseValue ++ "))") []

renderRuntimeIrV8
  :: Definition -> QName -> QName -> QName -> QName -> String -> String
renderRuntimeIrV8 definition typeName leftName rightName pathName baseKind =
  renderRuntimeIrV14 definition "def(0)"
    ("hcomp(i0,empty," ++ hitBase baseKind ++ ")") hitDefinitions
  where
    hitDefinitions =
      [ (prettyShow typeName, "u", "interval-hit-type(def(1),def(2),def(3))")
      , (prettyShow leftName, "def(0)", "hit-left-con")
      , (prettyShow rightName, "def(0)", "hit-right-con")
      , (prettyShow pathName, "path(def(0),def(1),def(2))", "hit-path-con")
      ]
    hitBase "left" = "hit-left"
    hitBase "right" = "hit-right"
    hitBase "path-i0" = "iapply(hit-path,i0)"
    hitBase "path-i1" = "iapply(hit-path,i1)"
    hitBase _ = "invalid-hit-base"

renderRuntimeIrV9
  :: Definition -> QName -> QName -> QName -> String -> String -> String
renderRuntimeIrV9 definition evidenceName approvedName rejectedName
    decision evidenceKind = renderRuntimeIrV14 definition evidenceType
      ("hcomp(i0,empty,pair(" ++ decision ++ "," ++ evidenceKind ++ "))")
      evidenceDefinitions
  where
    evidenceType = "sigma(bool,app(def(0),var(0)))"
    evidenceDefinitions =
      [ (prettyShow evidenceName, "pi(bool,u)", "evidence-family(def(1),def(2))")
      , (prettyShow approvedName, "evidence-constructor(def(0),true)", "approved-con")
      , (prettyShow rejectedName, "evidence-constructor(def(0),false)", "rejected-con")
      ]

renderRuntimeIrV10
  :: Definition -> QName -> QName -> QName -> QName
  -> String -> String -> String -> String -> String
renderRuntimeIrV10 selected functionName evidenceName approvedName rejectedName
    approvedResult rejectedResult decision evidenceKind = renderRuntimeIrV14
      selected "bool" ("hcomp(i0,empty,app(app(def(3)," ++ decision ++ ")," ++
        evidenceKind ++ "))")
      [ (prettyShow evidenceName, "pi(bool,u)", "evidence-family(def(1),def(2))")
      , (prettyShow approvedName, "evidence-constructor(def(0),true)", "approved-con")
      , (prettyShow rejectedName, "evidence-constructor(def(0),false)", "rejected-con")
      , ( prettyShow functionName
        , "pi(bool,pi(app(def(0),var(0)),bool))"
        , "case-evidence(" ++ approvedResult ++ "," ++ rejectedResult ++ ")"
        )
      ]

renderRuntimeIrV11 :: Definition -> QName -> String -> String
renderRuntimeIrV11 definition equivalenceName baseValue = renderRuntimeIrV14
  definition "bool" ("transp(glue-family(identity,def(0)),i0," ++ baseValue ++ ")")
  [(prettyShow equivalenceName, "path-to-equiv", "builtin-path-to-equiv")]

renderRuntimeIrV12
  :: Definition -> QName -> QName -> QName -> QName -> String -> String
renderRuntimeIrV12 definition typeName leftName rightName pathName orientation =
  renderRuntimeIrV14 definition "def(0)"
    ("hcomp(i1,hit-path-system(" ++ orientation ++ ")," ++ base orientation ++ ")")
    hitDefinitions
  where
    hitDefinitions =
      [ (prettyShow typeName, "u", "interval-hit-type(def(1),def(2),def(3))")
      , (prettyShow leftName, "def(0)", "hit-left-con")
      , (prettyShow rightName, "def(0)", "hit-right-con")
      , (prettyShow pathName, "path(def(0),def(1),def(2))", "hit-path-con")
      ]
    base "forward" = "hit-left"
    base "reverse" = "hit-right"
    base _ = "invalid-hit-base"

renderRuntimeIrV13 :: Definition -> QName -> QName -> String -> String
renderRuntimeIrV13 definition equivalenceName functionName baseValue =
  renderRuntimeIrV14 definition "bool"
    ("transp(glue-family(negation,def(0),def(1)),i0," ++ baseValue ++ ")")
    [ (prettyShow equivalenceName, "equiv(bool,bool)", "negation-equiv(def(1))")
    , (prettyShow functionName, "pi(bool,bool)", "bool-not")
    ]

renderRuntimeIrV14
  :: Definition -> String -> String -> [(String, String, String)] -> String
renderRuntimeIrV14 selected typeAst termAst definitions = unlines $
  [ "schema=runtime-nbe-ir-v14"
  , "language=runtime-nbe-typed-ast-v1"
  , "context-size=0"
  , "type-ast=" ++ typeAst
  , "term-ast=" ++ termAst
  , "definition-count=" ++ show (length definitions)
  ] ++ concatMap renderDefinition (zip [0 :: Int ..] definitions) ++
  [ "source-qname=" ++ prettyShow (defName selected)
  , "agda-revision=3d04bacca842729f9c0869b9287256321b5f450f"
  , "provider-revision=ba16f3758a322e9be77ada1da2b93f45d500192e"
  ]
  where
    renderDefinition (index, (name, definitionType, body)) =
      [ "def" ++ show index ++ "-qname=" ++ name
      , "def" ++ show index ++ "-type-ast=" ++ definitionType
      , "def" ++ show index ++ "-body-ast=" ++ body
      ]


requiredBuiltin :: String -> Maybe a -> Either String a
requiredBuiltin label = maybe (Left ("required builtin is unavailable: " ++ label)) Right

unlessEither :: Bool -> String -> Either String ()
unlessEither condition message = unless condition (Left message)

appliedTerms :: [Internal.Elim] -> Either String [Term]
appliedTerms = traverse $ \elimination -> case elimination of
  Apply argument -> Right (unArg argument)
  _ -> Left "primHComp spine contains a non-application elimination"

isBoolType :: QName -> Type -> Bool
isBoolType bool (Internal.El _ term) = isBoolTerm bool term

isBoolFunctionType :: QName -> Type -> Bool
isBoolFunctionType bool (Internal.El _ term) = case term of
  Internal.Pi domain codomain ->
    isBoolType bool (unDom domain) && isBoolType bool (abstractionBody codomain)
  _ -> False

isBoolSigmaType :: QName -> QName -> Type -> Bool
isBoolSigmaType sigma bool (Internal.El _ term) =
  isBoolSigmaTerm sigma bool term

isBoolSigmaTerm :: QName -> QName -> Term -> Bool
isBoolSigmaTerm sigma bool = \case
  Internal.Def name eliminations
    | name == sigma -> case appliedTerms eliminations of
        Right [levelA, levelB, domain, family] ->
          isZeroLevel levelA && isZeroLevel levelB
          && isBoolTerm bool domain && isConstantBoolFamily bool family
        _ -> False
  _ -> False

isDependentEvidenceSigmaTerm :: QName -> QName -> QName -> Term -> Bool
isDependentEvidenceSigmaTerm sigma bool evidenceName = \case
  Internal.Def name eliminations
    | name == sigma -> case appliedTerms eliminations of
        Right [levelA, levelB, domain, family] ->
          isZeroLevel levelA && isZeroLevel levelB
          && isBoolTerm bool domain && indexedFamilyName family == Just evidenceName
        _ -> False
  _ -> False

isConstantBoolFamily :: QName -> Term -> Bool
isConstantBoolFamily bool = \case
  Internal.Lam _ abstraction -> isBoolTerm bool (abstractionBody abstraction)
  _ -> False

isConstantZeroLevelFamily :: QName -> Term -> Bool
isConstantZeroLevelFamily levelZero = \case
  Internal.Lam _ abstraction ->
    isZeroLevel (abstractionBody abstraction)
      || isNamedTerm levelZero (abstractionBody abstraction)
  _ -> False

isNamedTerm :: QName -> Term -> Bool
isNamedTerm expected = \case
  Internal.Def name [] -> name == expected
  _ -> False

isBoolTerm :: QName -> Term -> Bool
isBoolTerm bool = \case
  Internal.Def name [] -> name == bool
  _ -> False

isNamedType :: QName -> Term -> Bool
isNamedType expected = \case
  Internal.Def name [] -> name == expected
  _ -> False

isZeroLevel :: Term -> Bool
isZeroLevel = \case
  Internal.Level (Internal.Max 0 []) -> True
  _ -> False

isConstructor :: QName -> Term -> Bool
isConstructor expected = \case
  Internal.Con constructor _ [] -> Internal.conName constructor == expected
  _ -> False

isEmptySystem :: QName -> Term -> Bool
isEmptySystem empty = \case
  Internal.Lam _ abstraction -> case abstractionBody abstraction of
    Internal.Def name arguments -> name == empty && length arguments == 2
    _ -> False
  _ -> False

isEmptyPartial :: QName -> Term -> Bool
isEmptyPartial empty = \case
  Internal.Def name arguments -> name == empty && case appliedTerms arguments of
    Right values -> length values == 2
    Left _ -> False
  Internal.Lam _ abstraction -> isEmptyPartial empty (abstractionBody abstraction)
  _ -> False

classifyActiveBoolSystem :: QName -> QName -> Term -> Either String String
classifyActiveBoolSystem falseConstructor trueConstructor = \case
  Internal.Lam _ outer -> case abstractionBody outer of
    Internal.Lam _ inner ->
      classifyBoolBase falseConstructor trueConstructor (abstractionBody inner)
    _ -> Left "active Bool primHComp system is not a two-argument tube"
  _ -> Left "active Bool primHComp system is not a lambda tube"

abstractionBody :: Abs a -> a
abstractionBody abstraction = case abstraction of
  Abs _ body -> body
  NoAbs _ body -> body

classifyBoolBase :: QName -> QName -> Term -> Either String String
classifyBoolBase falseConstructor trueConstructor term
  | isConstructor falseConstructor term = Right "false"
  | isConstructor trueConstructor term = Right "true"
  | otherwise = Left $ "primHComp base is not yet supported: "
      ++ take 512 (prettyShow term)
