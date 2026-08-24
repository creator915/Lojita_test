{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

-- | Checked runtime bridges for full Cubical Agda.
--
-- The @cubical-run@ oracle deliberately stays inside the type-checking process
-- and uses Agda's ordinary reducer.  The distinct
-- @cubical-runtime-nbe-export@ path does not normalize the term: after checking
-- it, that path structurally translates the actual 'Term', 'Type', and required
-- definitions into the compiler-independent Goal 3 wire ABI.  The linked final
-- runtime performs evaluation and quotation outside the compiler process.
--
-- Version 2 can also serialise closed Internal Terms and their types, then
-- recheck and consume them in a second Agda process whose complete interface
-- hash matches the producer.  These three modes share checking infrastructure
-- but are separate execution boundaries.
module Agda.TypeChecking.Primitive.Cubical.Runtime
  ( cubicalRuntimeBackend
  ) where

import Control.DeepSeq (NFData)
import Control.Exception (ErrorCall, try)
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Maybe (MaybeT, runMaybeT)
import qualified Data.ByteString as ByteString
import Data.List (nubBy)
import Data.Maybe (fromMaybe, isJust)
import Data.Map (Map)
import Data.Word (Word64)
import GHC.Generics (Generic)
import System.Directory (doesFileExist, getFileSize)
import System.IO (hFlush, hSetBinaryMode, stdin, stdout)

import Agda.Compiler.Backend
  ( Backend, Backend_boot(..), Backend', Backend'_boot(..)
  , Definition, Recompile(..)
  )
import Agda.Compiler.Common (IsMain, curIF)
import Agda.Interaction.Base (ComputeMode(DefaultCompute))
import qualified Agda.Interaction.BasicOps as BasicOps
import Agda.Interaction.Options
  ( ArgDescr(ReqArg), Flag, OptDescr(..) )
import Agda.Syntax.Common (Arg(..))
import Agda.Syntax.Common.Pretty (prettyShow)
import Agda.Syntax.Abstract.Name (QName)
import Agda.Syntax.Internal (Term, Type, domInfo, unDom)
import qualified Agda.Syntax.Internal as Internal
import Agda.Syntax.Internal.MetaVars (noMetas)
import Agda.Syntax.Literal (Literal(..))
import Agda.Syntax.Position (noRange)
import Agda.Syntax.TopLevelModuleName (TopLevelModuleName)
import Agda.Syntax.Translation.ConcreteToAbstract (concreteToAbstract_)
import Agda.Syntax.Translation.InternalToAbstract (reify)
import Agda.TheTypeChecker (inferExpr)
import qualified Agda.TypeChecking.CheckInternal as CheckInternal
import Agda.TypeChecking.Conversion (compareType)
import Agda.TypeChecking.Free (closed)
import Agda.TypeChecking.Monad
  ( Comparison(CmpEq, CmpLeq), TCM, pattern Function, defType, funClauses
  , getConstInfo, iFullHash, iTopLevelModuleName, theDef
  )
import qualified Agda.TypeChecking.Monad.Builtin as Builtin
import Agda.TypeChecking.Records
  ( etaExpandRecord_, isEtaRecordType, isRecord, mkCon )
import Agda.TypeChecking.Reduce
  ( instantiateFull, normalise, reduce )
import qualified Agda.TypeChecking.Serialise as Serialise
import Agda.TypeChecking.Substitute (absApp, apply)
import Agda.TypeChecking.Telescope (shouldBePi)

import Agda.Utils.Impossible (__IMPOSSIBLE__)
import qualified Agda.Utils.Serialize as RawSerialise
import qualified Cubical.Runtime.Nbe.Wire as Wire

data CubicalRuntimeOptions = CubicalRuntimeOptions
  { cubicalRuntimeExpression :: Maybe String
  , cubicalRuntimeExportExpression :: Maybe String
  , cubicalRuntimeImportConsumer :: Maybe String
  , cubicalRuntimeTermFile :: Maybe FilePath
  , cubicalRuntimeResultTermFile :: Maybe FilePath
  , cubicalRuntimeNbeExportExpression :: Maybe String
  , cubicalRuntimeNbeFile :: Maybe FilePath
  }
  deriving (Generic)

instance NFData CubicalRuntimeOptions

defaultCubicalRuntimeOptions :: CubicalRuntimeOptions
defaultCubicalRuntimeOptions = CubicalRuntimeOptions
  { cubicalRuntimeExpression = Nothing
  , cubicalRuntimeExportExpression = Nothing
  , cubicalRuntimeImportConsumer = Nothing
  , cubicalRuntimeTermFile = Nothing
  , cubicalRuntimeResultTermFile = Nothing
  , cubicalRuntimeNbeExportExpression = Nothing
  , cubicalRuntimeNbeFile = Nothing
  }

cubicalRuntimeFlags :: [OptDescr (Flag CubicalRuntimeOptions)]
cubicalRuntimeFlags =
  [ Option [] ["cubical-run"]
      (ReqArg setExpression "EXPRESSION")
      "evaluate an expression with full Cubical Agda runtime reduction"
  , Option [] ["cubical-export"]
      (ReqArg setExportExpression "EXPRESSION")
      "normalise and serialise a closed internal Term"
  , Option [] ["cubical-import"]
      (ReqArg setImportConsumer "CONSUMER")
      "deserialise a Term, recheck it, and apply a unary consumer"
  , Option [] ["cubical-term-file"]
      (ReqArg setTermFile "FILE")
      "Term packet path; use - for stdout (export) or stdin (import)"
  , Option [] ["cubical-result-term-file"]
      (ReqArg setResultTermFile "FILE")
      "write an imported consumer result as a new typed Term packet"
  , Option [] ["cubical-runtime-nbe-export"]
      (ReqArg setNbeExportExpression "EXPRESSION")
      "translate a checked Agda Internal Term+Type to the runtime NbE wire ABI"
  , Option [] ["cubical-runtime-nbe-file"]
      (ReqArg setNbeFile "FILE")
      "runtime NbE wire packet path"
  ]
  where
  setExpression expression options =
    pure options { cubicalRuntimeExpression = Just expression }
  setExportExpression expression options =
    pure options { cubicalRuntimeExportExpression = Just expression }
  setImportConsumer expression options =
    pure options { cubicalRuntimeImportConsumer = Just expression }
  setTermFile file options =
    pure options { cubicalRuntimeTermFile = Just file }
  setResultTermFile file options =
    pure options { cubicalRuntimeResultTermFile = Just file }
  setNbeExportExpression expression options =
    pure options { cubicalRuntimeNbeExportExpression = Just expression }
  setNbeFile file options =
    pure options { cubicalRuntimeNbeFile = Just file }

-- | Backend exported to the small @agda-cubical-run@ executable.
cubicalRuntimeBackend :: Backend
cubicalRuntimeBackend = Backend cubicalRuntimeBackend'

cubicalRuntimeBackend'
  :: Backend' CubicalRuntimeOptions CubicalRuntimeOptions () () ()
cubicalRuntimeBackend' = Backend'
  { backendName           = "CubicalRun"
  , backendVersion        = Nothing
  , options               = defaultCubicalRuntimeOptions
  , commandLineFlags      = cubicalRuntimeFlags
  , isEnabled             = cubicalRuntimeEnabled
  , preCompile            = pure
  , postCompile           = cubicalRuntimePostCompile
  , preModule             = cubicalRuntimePreModule
  , postModule            = cubicalRuntimePostModule
  , compileDef            = cubicalRuntimeCompileDef
  , scopeCheckingSuffices = False
  , mayEraseType          = const $ pure False
  , backendInteractTop    = Nothing
  , backendInteractHole   = Nothing
  }

-- No treeless or target-language compilation is performed.  The checked
-- definitions remain in TCState and are consumed by the reducer in
-- 'cubicalRuntimePostCompile'.
cubicalRuntimePreModule
  :: CubicalRuntimeOptions
  -> IsMain
  -> TopLevelModuleName
  -> Maybe FilePath
  -> TCM (Recompile () ())
cubicalRuntimePreModule _ _ _ _ = pure $ Skip ()

cubicalRuntimeCompileDef
  :: CubicalRuntimeOptions -> () -> IsMain -> Definition -> TCM ()
cubicalRuntimeCompileDef _ _ _ _ = pure ()

cubicalRuntimePostModule
  :: CubicalRuntimeOptions
  -> ()
  -> IsMain
  -> TopLevelModuleName
  -> [()]
  -> TCM ()
cubicalRuntimePostModule _ _ _ _ _ = pure ()

cubicalRuntimePostCompile
  :: CubicalRuntimeOptions
  -> IsMain
  -> Map TopLevelModuleName ()
  -> TCM ()
cubicalRuntimePostCompile options _ _ = BasicOps.atTopLevel $
  case options of
    CubicalRuntimeOptions
      { cubicalRuntimeExpression = Just expression
      , cubicalRuntimeExportExpression = Nothing
      , cubicalRuntimeImportConsumer = Nothing
      , cubicalRuntimeTermFile = Nothing
      , cubicalRuntimeResultTermFile = Nothing
      , cubicalRuntimeNbeExportExpression = Nothing
      , cubicalRuntimeNbeFile = Nothing
      } -> runtimeEvaluate expression

    CubicalRuntimeOptions
      { cubicalRuntimeExpression = Nothing
      , cubicalRuntimeExportExpression = Just expression
      , cubicalRuntimeImportConsumer = Nothing
      , cubicalRuntimeTermFile = Just file
      , cubicalRuntimeResultTermFile = Nothing
      , cubicalRuntimeNbeExportExpression = Nothing
      , cubicalRuntimeNbeFile = Nothing
      } -> runtimeExport file expression

    CubicalRuntimeOptions
      { cubicalRuntimeExpression = Nothing
      , cubicalRuntimeExportExpression = Nothing
      , cubicalRuntimeImportConsumer = Just consumer
      , cubicalRuntimeTermFile = Just file
      , cubicalRuntimeResultTermFile = resultFile
      , cubicalRuntimeNbeExportExpression = Nothing
      , cubicalRuntimeNbeFile = Nothing
      } -> runtimeImport file resultFile consumer

    CubicalRuntimeOptions
      { cubicalRuntimeExpression = Nothing
      , cubicalRuntimeExportExpression = Nothing
      , cubicalRuntimeImportConsumer = Nothing
      , cubicalRuntimeTermFile = Nothing
      , cubicalRuntimeResultTermFile = Nothing
      , cubicalRuntimeNbeExportExpression = Just expression
      , cubicalRuntimeNbeFile = Just file
      } -> runtimeNbeExport file expression

    _ -> runtimeAbort $
      "select exactly one of --cubical-run, --cubical-export, --cubical-import, " ++
      "or --cubical-runtime-nbe-export; each packet mode requires its file option"

cubicalRuntimeEnabled :: CubicalRuntimeOptions -> Bool
cubicalRuntimeEnabled options = any isJust
  [ cubicalRuntimeExpression options
  , cubicalRuntimeExportExpression options
  , cubicalRuntimeImportConsumer options
  , cubicalRuntimeResultTermFile options
  , cubicalRuntimeNbeExportExpression options
  , cubicalRuntimeNbeFile options
  ]

runtimeInfer :: String -> TCM (Term, Type)
runtimeInfer expression = do
  concrete <- BasicOps.parseExpr noRange expression
  abstract <- concreteToAbstract_ concrete
  instantiateFull =<< inferExpr abstract

runtimeEvaluate :: String -> TCM ()
runtimeEvaluate expression = do
  (term, ty) <- runtimeInfer expression
  runtimeNormalise term ty >>= printRuntimeTerm

printRuntimeTerm :: Term -> TCM ()
printRuntimeTerm value = do
  rendered <- BasicOps.showComputed DefaultCompute =<< reify value
  liftIO $ putStrLn $ prettyShow rendered

-- The packet root deliberately includes the producer module's full interface
-- hash.  It covers the source hash and all imported-module hashes, so a
-- consumer can only reuse internal QNames against the exact same signature.
type RuntimePacket =
  ( String
  , ( Word64
    , ( Word64
      , ( String
        , (Term, Type)
        )
      )
    )
  )

runtimePacketMagic :: String
runtimePacketMagic = "agda-cubical-runtime-term"

runtimePacketVersion :: Word64
runtimePacketVersion = 2

-- Reject unexpectedly large inputs before decoding.  This is a protocol
-- limit, not a claim that all inputs below the limit are trustworthy.
maxRuntimePacketBytes :: Integer
maxRuntimePacketBytes = 64 * 1024 * 1024

runtimeExport :: FilePath -> String -> TCM ()
runtimeExport file expression = do
  (term0, ty0) <- runtimeInfer expression
  ty <- normalise ty0
  term <- runtimeNormalise term0 ty
  writeRuntimePacket file term ty

-- | Translate the checked Internal term directly to the compiler/runtime
-- narrow waist.  In particular, this path must not call 'normalise': runtime
-- work may not be discharged by the compiler and then misreported as NbE.
runtimeNbeExport :: FilePath -> String -> TCM ()
runtimeNbeExport file expression = do
  (term, ty) <- runtimeInfer expression
  ensurePortableTerm term ty
  CheckInternal.checkType ty
  CheckInternal.checkInternal term CmpLeq ty
  wireTy <- bridgeType ty
  (wireTerm, definitions0) <- bridgeTerm [] [] wireTy term
  let definitions = nubBy
        (\left right -> Wire.definitionName left == Wire.definitionName right)
        definitions0
  iface <- curIF
  let contextIdentity = "agda-internal-v1:" ++ show (iFullHash iface) ++ ":" ++
        prettyShow (iTopLevelModuleName iface)
      packet = Wire.Packet
        { Wire.packetAbi = Wire.abiVersion
        , Wire.packetProvider = Wire.providerIdentity
        , Wire.packetContext = contextIdentity
        , Wire.packetRequest = Wire.Request
            { Wire.requestTerm = wireTerm
            , Wire.requestType = wireTy
            , Wire.requestDefinitions = definitions
            }
        }
      encoded = Wire.encodePacket packet
  when (length encoded > 1024 * 1024) $
    runtimeAbort "runtime NbE packet exceeds the 1 MiB wire limit"
  if file == "-"
    then liftIO $ putStr encoded >> hFlush stdout
    else do
      exists <- liftIO $ doesFileExist file
      when exists $ runtimeAbort "runtime NbE packet already exists"
      liftIO $ writeFile file encoded

-- This first bridge slice is intentionally fail-closed.  It accepts the
-- ordinary closed fragment needed to prove that real Agda Internal syntax,
-- rather than a hand-authored packet, reaches the runtime.  Later Cubical
-- constructors extend these functions; unsupported Internal nodes never fall
-- back to pretty-printed names or compiler normalization.
bridgeType :: Type -> TCM Wire.Ty
bridgeType ty0 = do
  ty <- reduce ty0
  case Internal.unEl ty of
    Internal.Def name eliminations -> do
      isBool <- isBuiltinName name Builtin.builtinBool
      isNat <- isBuiltinName name Builtin.builtinNat
      isPathP <- isBuiltinName name Builtin.builtinPathP
      case () of
        _ | isBool && null eliminations -> pure Wire.TyBool
          | isNat && null eliminations -> pure Wire.TyNat
          | prettyShow name == "Cubical.Data.Int.Base.ℤ"
          , null eliminations -> pure Wire.TyInt
          | prettyShow name == "Cubical.HITs.S1.Base.S¹"
          , null eliminations -> pure Wire.TyS1
          | prettyShow name == "Agda.Builtin.Sigma.Σ" ->
              bridgeSigmaType eliminations
          | prettyShow name == "Cubical.Data.Sigma.Base._×_" ->
              bridgeProductType eliminations
          | prettyShow name == "Cubical.Data.Vec.Base.Vec"
          , Just [_level, element, size] <- mapM applyArgument eliminations ->
              Wire.TyVec <$> bridgeTypeTerm element <*> bridgeNatural size
          | isPathP -> bridgePathType eliminations
          | otherwise -> unsupportedBridge "type" $ prettyShow name
    Internal.Pi domain codomain -> do
      domainTy <- bridgeType $ Internal.unDom domain
      codomainTy <- bridgeType $ Internal.unAbs codomain
      pure $ Wire.TyPi domainTy codomainTy
    Internal.Sort{} -> pure Wire.TyUniverse
    other -> unsupportedBridge "type node" $ prettyShow other

bridgePathType :: Internal.Elims -> TCM Wire.Ty
bridgePathType eliminations = case mapM applyArgument eliminations of
  Just arguments
    | right : left : _family : _ <- reverse arguments -> do
        (pathTy, wireLeft) <- bridgePathEndpoint left
        (pathTy', wireRight) <- bridgePathEndpoint right
        unless (pathTy == pathTy') $
          unsupportedBridge "path endpoint types" $ show (pathTy, pathTy')
        pure (Wire.TyPath pathTy wireLeft wireRight)
  _ -> unsupportedBridge "PathP eliminations" $ prettyShow eliminations

bridgeSigmaType :: Internal.Elims -> TCM Wire.Ty
bridgeSigmaType eliminations = case mapM applyArgument eliminations of
  Just arguments
    | codomain : domain : _ <- reverse arguments ->
        Wire.TySigma <$> bridgeTypeTerm domain <*> bridgeConstantType codomain
  _ -> unsupportedBridge "Sigma eliminations" $ prettyShow eliminations

bridgeProductType :: Internal.Elims -> TCM Wire.Ty
bridgeProductType eliminations = case mapM applyArgument eliminations of
  Just arguments
    | second : first : _ <- reverse arguments ->
        Wire.TySigma <$> bridgeTypeTerm first <*> bridgeTypeTerm second
  _ -> unsupportedBridge "product eliminations" $ prettyShow eliminations

bridgeConstantType :: Term -> TCM Wire.Ty
bridgeConstantType term = case term of
  Internal.Lam _ abstraction -> bridgeTypeTerm $ Internal.unAbs abstraction
  _ -> unsupportedBridge "constant type abstraction" $ prettyShow term

bridgePathEndpoint :: Term -> TCM (Wire.Ty, Wire.Term)
bridgePathEndpoint term = case term of
  Internal.Con constructor _ []
    | prettyShow (Internal.conName constructor) ==
        "Cubical.HITs.S1.Base.S¹.base" -> pure (Wire.TyS1, Wire.S1Base)
  _ -> do
    ty <- bridgeTypeTerm term
    pure (Wire.TyUniverse, Wire.Type ty)

bridgeTerm
  :: [QName]
  -> [Wire.Ty]
  -> Wire.Ty
  -> Term
  -> TCM (Wire.Term, [Wire.Definition])
bridgeTerm active context expected term = case term of
  Internal.Var index eliminations -> do
    headTy <- case drop index context of
      ty : _ -> pure ty
      [] -> unsupportedBridge "variable" $ "out-of-scope index " ++ show index
    (wireTerm, actualTy, definitions) <- bridgeEliminations active context
      (Wire.Var index, headTy, []) eliminations
    unless (actualTy == expected) $
      unsupportedBridge "variable result type" $
        show actualTy ++ " /= " ++ show expected
    pure (wireTerm, definitions)
  Internal.Lam _ abstraction -> case expected of
    Wire.TyPi domain codomain -> do
      (body, definitions) <- bridgeTerm active (domain : context) codomain
        (Internal.unAbs abstraction)
      pure (Wire.Lam domain body, definitions)
    _ -> unsupportedBridge "lambda type" $ show expected
  Internal.Lit (LitNat natural)
    | expected == Wire.TyNat && natural >= 0 -> pure (Wire.NatLit natural, [])
  Internal.Con constructor _ []
    | expected == Wire.TyPath Wire.TyS1 Wire.S1Base Wire.S1Base
    , prettyShow (Internal.conName constructor) ==
        "Cubical.HITs.S1.Base.S¹.loop" -> pure (Wire.Loop, [])
  Internal.Con constructor _ eliminations
    | Wire.TyVec element size <- expected
    , prettyShow (Internal.conName constructor) ==
        "Cubical.Data.Vec.Base.Vec.[]"
    , null eliminations
    , size == 0 -> pure (Wire.VecLit element [], [])
  Internal.Con constructor _ eliminations
    | Wire.TyVec element size <- expected
    , prettyShow (Internal.conName constructor) ==
        "Cubical.Data.Vec.Base.Vec._∷_"
    , size > 0
    , Just arguments <- mapM applyArgument eliminations
    , tailTerm : headTerm : _ <- reverse arguments -> do
        (wireHead, headDefinitions) <- bridgeTerm active context element headTerm
        (wireTail, tailDefinitions) <- bridgeTerm active context
          (Wire.TyVec element (size - 1)) tailTerm
        case wireTail of
          Wire.VecLit actualElement elements
            | actualElement == element -> pure
                ( Wire.VecLit element (wireHead : elements)
                , headDefinitions ++ tailDefinitions
                )
          _ -> unsupportedBridge "Vec tail" $ show wireTail
  Internal.Con constructor _ eliminations
    | Wire.TySigma firstTy secondTy <- expected
    , prettyShow (Internal.conName constructor) == "Agda.Builtin.Sigma._,_"
    , Just arguments <- mapM applyArgument eliminations
    , second : first : _ <- reverse arguments -> do
        (wireFirst, firstDefinitions) <- bridgeTerm active context firstTy first
        (wireSecond, secondDefinitions) <- bridgeTerm active context secondTy second
        pure
          ( Wire.Pair wireFirst wireSecond
          , firstDefinitions ++ secondDefinitions
          )
  Internal.Con constructor _ eliminations
    | expected == Wire.TyInt
    , prettyShow (Internal.conName constructor) ==
        "Cubical.Data.Int.Base.ℤ.pos"
    , Just [natural] <- mapM applyArgument eliminations -> do
        value <- bridgeNatural natural
        pure (Wire.IntLit (fromIntegral value), [])
  Internal.Con constructor _ eliminations
    | expected == Wire.TyInt
    , prettyShow (Internal.conName constructor) ==
        "Cubical.Data.Int.Base.ℤ.negsuc"
    , Just [natural] <- mapM applyArgument eliminations -> do
        magnitude <- bridgeNatural natural
        pure (Wire.IntLit (negate (fromIntegral magnitude + 1)), [])
  Internal.Con constructor _ [] | expected == Wire.TyBool -> do
    let name = Internal.conName constructor
    isTrue <- isBuiltinName name Builtin.builtinTrue
    isFalse <- isBuiltinName name Builtin.builtinFalse
    case () of
      _ | isTrue -> pure (Wire.BoolLit True, [])
        | isFalse -> pure (Wire.BoolLit False, [])
        | otherwise -> unsupportedBridge "Bool constructor" $ prettyShow name
  Internal.Def name eliminations -> do
    isTransp <- isPrimitiveName name Builtin.builtinTrans
    isHComp <- isPrimitiveName name Builtin.builtinHComp
    if prettyShow name == "Cubical.HITs.S1.Base.S¹.loop"
      && null eliminations
      && expected == Wire.TyPath Wire.TyS1 Wire.S1Base Wire.S1Base
      then pure (Wire.Loop, [])
      else if prettyShow name == "Cubical.Foundations.Prelude.transport"
      then bridgeLibraryTransport active context expected eliminations
      else if prettyShow name == "Cubical.Foundations.Prelude.subst"
        then bridgeLibrarySubst active context expected eliminations
      else if prettyShow name == "Cubical.Foundations.Prelude._∙_"
        then bridgePathComposition active context expected eliminations
      else if prettyShow name == "Cubical.Foundations.Univalence.ua"
        then bridgeUaTerm expected (Internal.Def name eliminations)
      else if prettyShow name == "Cubical.HITs.S1.Base.winding"
        then bridgeWindingTerm expected eliminations
      else if isTransp
      then bridgeTransp active context expected eliminations
      else if isHComp
        then bridgeHComp active context expected eliminations
        else do
          when (name `elem` active) $
            unsupportedBridge "recursive definition" $ prettyShow name
          (definition, nestedDefinitions) <- bridgeDefinition (name : active) name
          (wireTerm, actualTy, argumentDefinitions) <- bridgeEliminations active context
            (Wire.Def (Wire.definitionName definition), Wire.definitionType definition, [])
            eliminations
          unless (actualTy == expected) $
            unsupportedBridge "definition result type" $
              show actualTy ++ " /= " ++ show expected
          pure (wireTerm, definition : nestedDefinitions ++ argumentDefinitions)
  Internal.DontCare value -> bridgeTerm active context expected value
  other -> unsupportedBridge "term node" $ prettyShow other

bridgeEliminations
  :: [QName]
  -> [Wire.Ty]
  -> (Wire.Term, Wire.Ty, [Wire.Definition])
  -> Internal.Elims
  -> TCM (Wire.Term, Wire.Ty, [Wire.Definition])
bridgeEliminations _ _ current [] = pure current
bridgeEliminations active context (headTerm, headTy, definitions) (elimination : rest) =
  case (headTy, elimination) of
    (Wire.TyPi domain codomain, Internal.Apply (Arg _ argument)) -> do
      (wireArgument, argumentDefinitions) <- bridgeTerm active context domain argument
      bridgeEliminations active context
        ( Wire.App headTerm wireArgument
        , codomain
        , definitions ++ argumentDefinitions
        ) rest
    _ -> unsupportedBridge "elimination" $ prettyShow elimination

bridgeDefinition
  :: [QName]
  -> QName
  -> TCM (Wire.Definition, [Wire.Definition])
bridgeDefinition active name = do
  definition <- getConstInfo name
  wireType <- bridgeType $ defType definition
  case theDef definition of
    Function {funClauses = [clause]}
      | Just body <- Internal.clauseBody clause
      , patterns <- Internal.clausePats clause
      , all isVariablePattern patterns -> do
          domains <- mapM (bridgeType . snd . Internal.unDom) $
            Internal.telToList $ Internal.clauseTel clause
          resultType <- case consumeDefinitionType domains wireType of
            Just result -> pure result
            Nothing -> unsupportedBridge "definition telescope" $
              prettyShow name ++ ": " ++ show domains ++ " not a prefix of " ++
              show wireType
          (wireBody, nestedDefinitions) <- bridgeTerm active
            (reverse domains) resultType body
          let wireBodyWithBinders = foldr Wire.Lam wireBody domains
          pure
            ( Wire.Definition (prettyShow name) wireType wireBodyWithBinders
            , nestedDefinitions
            )
    _ -> unsupportedBridge "definition" $
      prettyShow name ++ " (expected one variable-pattern function clause)"
  where
    isVariablePattern argument = case unArg argument of
      Internal.VarP{} -> True
      _ -> False

consumeDefinitionType :: [Wire.Ty] -> Wire.Ty -> Maybe Wire.Ty
consumeDefinitionType domains ty = case (domains, ty) of
  ([], result) -> Just result
  (domain : rest, Wire.TyPi actual codomain)
    | domain == actual -> consumeDefinitionType rest codomain
  _ -> Nothing

bridgeTransp
  :: [QName]
  -> [Wire.Ty]
  -> Wire.Ty
  -> Internal.Elims
  -> TCM (Wire.Term, [Wire.Definition])
bridgeTransp active context expected eliminations =
  case mapM applyArgument eliminations of
    Just [_level, family, face, base] -> do
      familyTy <- bridgeConstantTypeFamily family
      unless (familyTy == expected) $
        unsupportedBridge "transp family" $ prettyShow family
      faceValue <- bridgeFace face
      unless (faceValue == Wire.FaceZero) $
        unsupportedBridge "transp face" "only the canonical phi=i0 rule is supported"
      (wireBase, definitions) <- bridgeTerm active context expected base
      pure
        ( Wire.Transp (Wire.TypePath (Wire.FamilyConst expected)) wireBase
        , definitions
        )
    _ -> unsupportedBridge "transp eliminations" $ prettyShow eliminations

bridgeLibraryTransport
  :: [QName]
  -> [Wire.Ty]
  -> Wire.Ty
  -> Internal.Elims
  -> TCM (Wire.Term, [Wire.Definition])
bridgeLibraryTransport active context expected eliminations =
  case mapM applyArgument eliminations of
    Just [_level, source, target, pathTerm, base] -> case pathTerm of
      Internal.Lam{} -> do
        family <- bridgeTypeFamily pathTerm
        (sourceTy, targetTy) <- wireFamilyEndpoints family
        unless (targetTy == expected) $
          unsupportedBridge "library transport target" $
            show targetTy ++ " /= " ++ show expected
        (wireBase, definitions) <- bridgeTerm active context sourceTy base
        pure (Wire.Transp (Wire.TypePath family) wireBase, definitions)
      _ -> do
        sourceTy <- bridgeTypeTerm source
        targetTy <- bridgeTypeTerm target
        unless (targetTy == expected) $
          unsupportedBridge "library transport target" $
            show targetTy ++ " /= " ++ show expected
        let pathTy = Wire.TyPath Wire.TyUniverse
              (Wire.Type sourceTy) (Wire.Type targetTy)
        (wirePath, pathDefinitions) <- bridgeTerm active context pathTy pathTerm
        (wireBase, baseDefinitions) <- bridgeTerm active context sourceTy base
        pure
          ( Wire.Transp wirePath wireBase
          , pathDefinitions ++ baseDefinitions
          )
    _ -> unsupportedBridge "library transport eliminations" $ prettyShow eliminations

bridgeLibrarySubst
  :: [QName]
  -> [Wire.Ty]
  -> Wire.Ty
  -> Internal.Elims
  -> TCM (Wire.Term, [Wire.Definition])
bridgeLibrarySubst active context expected eliminations =
  case mapM applyArgument eliminations of
    Just arguments
      | base : _path : motive : _ <- reverse arguments -> do
          validateSubstMotive motive expected
          (wireBase, definitions) <- bridgeTerm active context expected base
          pure
            ( Wire.Transp
                (Wire.TypePath (Wire.FamilyConst expected))
                wireBase
            , definitions
            )
    _ -> unsupportedBridge "library subst eliminations" $ prettyShow eliminations

bridgePathComposition
  :: [QName]
  -> [Wire.Ty]
  -> Wire.Ty
  -> Internal.Elims
  -> TCM (Wire.Term, [Wire.Definition])
bridgePathComposition active context expected eliminations =
  case (expected, mapM applyArgument eliminations) of
    (Wire.TyPath pathTy left right, Just arguments)
      | rightPath : leftPath : _target : middle : _source : _ <-
          reverse arguments -> do
          wireMiddle <- bridgeEndpointAt pathTy middle
          (wireLeft, leftDefinitions) <- bridgeTerm active context
            (Wire.TyPath pathTy left wireMiddle) leftPath
          (wireRight, rightDefinitions) <- bridgeTerm active context
            (Wire.TyPath pathTy wireMiddle right) rightPath
          pure
            ( Wire.Concat wireLeft wireRight
            , leftDefinitions ++ rightDefinitions
            )
    _ -> unsupportedBridge "path composition eliminations" $ prettyShow eliminations

bridgeUaTerm :: Wire.Ty -> Term -> TCM (Wire.Term, [Wire.Definition])
bridgeUaTerm expected term = case expected of
  Wire.TyPath Wire.TyUniverse (Wire.Type source) (Wire.Type target) -> do
    family <- bridgeUniversePath term
    endpoints <- wireFamilyEndpoints family
    unless (endpoints == (source, target)) $
      unsupportedBridge "ua term endpoints" $ show (endpoints, (source, target))
    pure (Wire.TypePath family, [])
  _ -> unsupportedBridge "ua term type" $ show expected

bridgeWindingTerm
  :: Wire.Ty
  -> Internal.Elims
  -> TCM (Wire.Term, [Wire.Definition])
bridgeWindingTerm expected eliminations
  | null eliminations
  , pathTy <- Wire.TyPath Wire.TyS1 Wire.S1Base Wire.S1Base
  , expected == Wire.TyPi pathTy Wire.TyInt =
      pure (Wire.Lam pathTy (Wire.Winding (Wire.Var 0)), [])
  | otherwise = unsupportedBridge "winding use" $
      show expected ++ " / " ++ prettyShow eliminations

bridgeEndpointAt :: Wire.Ty -> Term -> TCM Wire.Term
bridgeEndpointAt pathTy term = case pathTy of
  Wire.TyUniverse -> Wire.Type <$> bridgeTypeTerm term
  Wire.TyS1
    | isS1BaseTerm term -> pure Wire.S1Base
  _ -> unsupportedBridge "path endpoint" $ prettyShow term

isS1BaseTerm :: Term -> Bool
isS1BaseTerm term = case term of
  Internal.Con constructor _ [] ->
    prettyShow (Internal.conName constructor) ==
      "Cubical.HITs.S1.Base.S¹.base"
  Internal.Def name [] ->
    prettyShow name == "Cubical.HITs.S1.Base.S¹.base"
  _ -> False

validateSubstMotive :: Term -> Wire.Ty -> TCM ()
validateSubstMotive motive expected = case (motive, expected) of
  (Internal.Def name eliminations, Wire.TyVec expectedElement _)
    | prettyShow name == "Cubical.Data.Vec.Base.Vec"
    , Just [_level, element] <- mapM applyArgument eliminations -> do
        actualElement <- bridgeTypeTerm element
        unless (actualElement == expectedElement) $
          unsupportedBridge "subst Vec element" $
            show (actualElement, expectedElement)
  _ -> unsupportedBridge "subst motive" $ prettyShow motive

bridgeTypeFamily :: Term -> TCM Wire.Family
bridgeTypeFamily term = case term of
  Internal.Lam _ abstraction -> bridgeTypeFamilyBody $ Internal.unAbs abstraction
  _ -> unsupportedBridge "type family" $ prettyShow term

bridgeTypeFamilyBody :: Term -> TCM Wire.Family
bridgeTypeFamilyBody term = case term of
  Internal.Pi domain codomain ->
    Wire.FamilyPi
      <$> bridgeTypeLine (Internal.unEl $ Internal.unDom domain)
      <*> bridgeTypeLine (Internal.unEl $ Internal.unAbs codomain)
  Internal.Def name eliminations
    | prettyShow name == "Cubical.Data.Vec.Base.Vec"
    , Just [_level, element, size] <- mapM applyArgument eliminations ->
        Wire.FamilyVec <$> bridgeTypeLine element <*> bridgeNatural size
    | prettyShow name == "Agda.Builtin.Sigma.Σ"
    , Just arguments <- mapM applyArgument eliminations
    , codomain : domain : _ <- reverse arguments ->
        Wire.FamilySigma
          <$> bridgeTypeLine domain
          <*> bridgeConstantTypeFamilyLine codomain
    | prettyShow name == "Cubical.Data.Sigma.Base._×_"
    , Just arguments <- mapM applyArgument eliminations
    , second : first : _ <- reverse arguments ->
        Wire.FamilySigma <$> bridgeTypeLine first <*> bridgeTypeLine second
  _ -> Wire.FamilyConst <$> bridgeTypeTerm term

bridgeConstantTypeFamilyLine :: Term -> TCM Wire.Family
bridgeConstantTypeFamilyLine term = case term of
  Internal.Lam _ abstraction -> bridgeTypeLine $ Internal.unAbs abstraction
  _ -> unsupportedBridge "constant family abstraction" $ prettyShow term

bridgeTypeLine :: Term -> TCM Wire.Family
bridgeTypeLine term = case term of
  Internal.Def name [_intervalApplication] -> do
    definition <- getConstInfo name
    case theDef definition of
      Function {funClauses = [clause]}
        | Just body <- Internal.clauseBody clause ->
            bridgeUniversePath body
      _ -> unsupportedBridge "type-line definition" $ prettyShow name
  _ -> Wire.FamilyConst <$> bridgeTypeTerm term

bridgeUniversePath :: Term -> TCM Wire.Family
bridgeUniversePath term = case term of
  Internal.Def name eliminations
    | prettyShow name == "Cubical.Foundations.Univalence.ua"
    , Just [_level, source, target, equivalence] <- mapM applyArgument eliminations -> do
        sourceTy <- bridgeTypeTerm source
        targetTy <- bridgeTypeTerm target
        wireEquivalence <- bridgeEquivalence equivalence
        unless (wireEquivalenceEndpoints wireEquivalence == (sourceTy, targetTy)) $
          unsupportedBridge "univalence equivalence endpoints" $
            show (wireEquivalenceEndpoints wireEquivalence, (sourceTy, targetTy))
        pure (Wire.FamilyGlue wireEquivalence)
  Internal.Def name [] -> do
    definition <- getConstInfo name
    case theDef definition of
      Function {funClauses = [clause]}
        | Just body <- Internal.clauseBody clause -> bridgeUniversePath body
      _ -> unsupportedBridge "universe-path definition" $ prettyShow name
  _ -> unsupportedBridge "universe path" $ prettyShow term

bridgeEquivalence :: Term -> TCM Wire.Equiv
bridgeEquivalence term = case term of
  Internal.Def name eliminations
    | prettyShow name == "Cubical.Foundations.Isomorphism.isoToEquiv"
    , Just arguments <- mapM applyArgument eliminations
    , isoTerm : _ <- reverse arguments -> bridgeIsoTerm isoTerm
  Internal.Def name [] -> do
    definition <- getConstInfo name
    case theDef definition of
      Function {funClauses = [clause]}
        | Just body <- Internal.clauseBody clause ->
            bridgeEquivalence body
      _ -> unsupportedBridge "equivalence definition" $ prettyShow name
  _ -> unsupportedBridge "equivalence" $ prettyShow term

bridgeIsoTerm :: Term -> TCM Wire.Equiv
bridgeIsoTerm term = case term of
  Internal.Con constructor _ eliminations
    | prettyShow (Internal.conName constructor) ==
        "Cubical.Foundations.Isomorphism.iso"
    , Just arguments <- mapM applyArgument eliminations
    , _proof2 : _proof1 : backward : forward : _ <- reverse arguments ->
        bridgeIsoEquivalence forward backward
  _ -> unsupportedBridge "iso term" $ prettyShow term

bridgeIsoEquivalence :: Term -> Term -> TCM Wire.Equiv
bridgeIsoEquivalence forward backward
  | prettyShow forward == "Cubical.Data.Bool.Base.not"
  , prettyShow backward == "Cubical.Data.Bool.Base.not" =
      pure Wire.EquivBoolNot
  | prettyShow forward == "Cubical.Data.Int.Base.sucℤ"
  , prettyShow backward == "Cubical.Data.Int.Base.predℤ" =
      pure Wire.EquivIntSucc
  | otherwise = unsupportedBridge "iso equivalence functions" $
      prettyShow forward ++ " / " ++ prettyShow backward

wireFamilyEndpoints :: Wire.Family -> TCM (Wire.Ty, Wire.Ty)
wireFamilyEndpoints family = case family of
  Wire.FamilyConst ty -> pure (ty, ty)
  Wire.FamilyGlue equivalence -> pure $ wireEquivalenceEndpoints equivalence
  Wire.FamilyVec element size -> do
    (source, target) <- wireFamilyEndpoints element
    pure (Wire.TyVec source size, Wire.TyVec target size)
  Wire.FamilyPi domain codomain -> do
    (domainSource, domainTarget) <- wireFamilyEndpoints domain
    (codomainSource, codomainTarget) <- wireFamilyEndpoints codomain
    pure
      ( Wire.TyPi domainSource codomainSource
      , Wire.TyPi domainTarget codomainTarget
      )
  Wire.FamilySigma first second -> do
    (firstSource, firstTarget) <- wireFamilyEndpoints first
    (secondSource, secondTarget) <- wireFamilyEndpoints second
    pure
      ( Wire.TySigma firstSource secondSource
      , Wire.TySigma firstTarget secondTarget
      )
  Wire.FamilyCompose first second -> do
    (source, middle) <- wireFamilyEndpoints first
    (middle', target) <- wireFamilyEndpoints second
    unless (middle == middle') $
      unsupportedBridge "composed family endpoints" $ show (middle, middle')
    pure (source, target)

wireEquivalenceEndpoints :: Wire.Equiv -> (Wire.Ty, Wire.Ty)
wireEquivalenceEndpoints equivalence = case equivalence of
  Wire.EquivIdentity ty -> (ty, ty)
  Wire.EquivBoolNot -> (Wire.TyBool, Wire.TyBool)
  Wire.EquivIntSucc -> (Wire.TyInt, Wire.TyInt)
  Wire.EquivCompose first second ->
    (fst (wireEquivalenceEndpoints first), snd (wireEquivalenceEndpoints second))
  Wire.EquivInverse inner ->
    let (source, target) = wireEquivalenceEndpoints inner in (target, source)

bridgeHComp
  :: [QName]
  -> [Wire.Ty]
  -> Wire.Ty
  -> Internal.Elims
  -> TCM (Wire.Term, [Wire.Definition])
bridgeHComp active context expected eliminations =
  case mapM applyArgument eliminations of
    Just [_level, tyTerm, face, system, base] -> do
      actualTy <- bridgeTypeTerm tyTerm
      unless (actualTy == expected) $
        unsupportedBridge "hcomp type" $ prettyShow tyTerm
      faceValue <- bridgeFace face
      (wireBase, baseDefinitions) <- bridgeTerm active context expected base
      case faceValue of
        Wire.FaceZero -> pure
          ( Wire.HComp expected Wire.FaceZero wireBase wireBase
          , baseDefinitions
          )
        Wire.FaceOne -> do
          systemBody <- case system of
            Internal.Lam _ intervalBody -> case Internal.unAbs intervalBody of
              Internal.Lam _ proofBody -> pure $ Internal.unAbs proofBody
              _ -> unsupportedBridge "hcomp system" $ prettyShow system
            _ -> unsupportedBridge "hcomp system" $ prettyShow system
          (wireSystem, systemDefinitions) <-
            bridgeTerm active context expected systemBody
          pure
            ( Wire.HComp expected Wire.FaceOne wireSystem wireBase
            , systemDefinitions ++ baseDefinitions
            )
    _ -> unsupportedBridge "hcomp eliminations" $ prettyShow eliminations

applyArgument :: Internal.Elim' Term -> Maybe Term
applyArgument elimination = case elimination of
  Internal.Apply (Arg _ argument) -> Just argument
  _ -> Nothing

bridgeConstantTypeFamily :: Term -> TCM Wire.Ty
bridgeConstantTypeFamily family = case family of
  Internal.Lam _ abstraction -> bridgeTypeTerm $ Internal.unAbs abstraction
  _ -> unsupportedBridge "constant type family" $ prettyShow family

bridgeTypeTerm :: Term -> TCM Wire.Ty
bridgeTypeTerm term = case term of
  Internal.Def name eliminations -> do
    isBool <- isBuiltinName name Builtin.builtinBool
    isNat <- isBuiltinName name Builtin.builtinNat
    case () of
      _ | isBool && null eliminations -> pure Wire.TyBool
        | isNat && null eliminations -> pure Wire.TyNat
        | prettyShow name == "Cubical.Data.Int.Base.ℤ"
        , null eliminations -> pure Wire.TyInt
        | prettyShow name == "Cubical.HITs.S1.Base.S¹"
        , null eliminations -> pure Wire.TyS1
        | prettyShow name == "Agda.Builtin.Sigma.Σ" ->
            bridgeSigmaType eliminations
        | prettyShow name == "Cubical.Data.Sigma.Base._×_" ->
            bridgeProductType eliminations
        | prettyShow name == "Cubical.Data.Vec.Base.Vec"
        , Just [_level, element, size] <- mapM applyArgument eliminations ->
            Wire.TyVec <$> bridgeTypeTerm element <*> bridgeNatural size
        | otherwise -> unsupportedBridge "type term" $ prettyShow name
  Internal.Sort{} -> pure Wire.TyUniverse
  _ -> unsupportedBridge "type term" $ prettyShow term

bridgeNatural :: Term -> TCM Int
bridgeNatural term = case term of
  Internal.Lit (LitNat natural)
    | natural >= 0
    , natural <= fromIntegral (maxBound :: Int) -> pure (fromIntegral natural)
  _ -> unsupportedBridge "natural index" $ prettyShow term

bridgeFace :: Term -> TCM Wire.Face
bridgeFace face = case face of
  Internal.Con constructor _ [] -> classify $ Internal.conName constructor
  Internal.Def name [] -> classify name
  _ -> unsupportedBridge "face" $ prettyShow face
  where
    classify name = do
      isZero <- isBuiltinName name Builtin.builtinIZero
      isOne <- isBuiltinName name Builtin.builtinIOne
      case () of
        _ | isZero -> pure Wire.FaceZero
          | isOne -> pure Wire.FaceOne
          | otherwise -> unsupportedBridge "face" $ prettyShow name

isBuiltinName :: QName -> Builtin.BuiltinId -> TCM Bool
isBuiltinName name builtinId = (== Just name) <$> Builtin.getBuiltinName' builtinId

isPrimitiveName :: QName -> Builtin.PrimitiveId -> TCM Bool
isPrimitiveName name primitiveId =
  (== Just name) <$> Builtin.getPrimitiveName' primitiveId

unsupportedBridge :: String -> String -> TCM a
unsupportedBridge node detail = runtimeAbort $
  "runtime NbE bridge does not support " ++ node ++ ": " ++ detail

writeRuntimePacket :: FilePath -> Term -> Type -> TCM ()
writeRuntimePacket file term ty = do
  ensurePortableTerm term ty

  iface <- curIF
  let packet :: RuntimePacket
      packet =
        ( runtimePacketMagic
        , ( runtimePacketVersion
          , ( iFullHash iface
            , ( prettyShow $ iTopLevelModuleName iface
              , (term, ty)
              )
            )
          )
        )

  encoded <- Serialise.encode packet
  bytes <- liftIO $ RawSerialise.serialize encoded
  writePacketBytes file bytes

runtimeImport :: FilePath -> Maybe FilePath -> String -> TCM ()
runtimeImport file resultFile consumerExpression = do
  bytes <- readPacketBytes file
  decodedEncoded <- liftIO
    (try (RawSerialise.deserialize bytes) ::
      IO (Either ErrorCall Serialise.Encoded))
  encoded <- either (const $ runtimeAbort "malformed or truncated Term packet") pure decodedEncoded
  decoded <- runMaybeT (Serialise.decode encoded :: MaybeT TCM RuntimePacket)
  packet <- maybe (runtimeAbort "malformed or incompatible Term packet") pure decoded

  let (magic, (version, (producerHash, (producerModule, (term, ty))))) = packet
  unless (magic == runtimePacketMagic) $
    runtimeAbort "Term packet has the wrong magic header"
  unless (version == runtimePacketVersion) $
    runtimeAbort "Term packet format version mismatch"

  iface <- curIF
  let consumerHash = iFullHash iface
      consumerModule = prettyShow $ iTopLevelModuleName iface
  unless (producerModule == consumerModule) $
    runtimeAbort "Term packet was produced from a different top-level module"
  unless (producerHash == consumerHash) $
    runtimeAbort "Term packet signature hash does not match the loaded module"

  ensurePortableTerm term ty
  CheckInternal.checkType ty
  CheckInternal.checkInternal term CmpLeq ty

  (consumer, consumerTy) <- runtimeInfer consumerExpression
  (domain, codomain) <- shouldBePi consumerTy
  compareType CmpEq ty (unDom domain)
  CheckInternal.checkInternal term CmpLeq (unDom domain)

  let result = consumer `apply` [Arg (domInfo domain) term]
      resultTy = codomain `absApp` term
  CheckInternal.checkInternal result CmpLeq resultTy
  normalisedResultTy <- normalise resultTy
  value <- runtimeNormalise result normalisedResultTy
  case resultFile of
    Nothing -> printRuntimeTerm value
    Just output -> do
      when (output /= "-") $ do
        exists <- liftIO $ doesFileExist output
        when exists $ runtimeAbort "result Term packet already exists"
      writeRuntimePacket output value normalisedResultTy

ensurePortableTerm :: Term -> Type -> TCM ()
ensurePortableTerm term ty = do
  unless (closed (term, ty)) $
    runtimeAbort "only closed Terms can cross the process boundary"
  unless (noMetas (term, ty)) $
    runtimeAbort "Term packet still contains process-local metavariables"

writePacketBytes :: FilePath -> ByteString.ByteString -> TCM ()
writePacketBytes "-" bytes = liftIO $ do
  hSetBinaryMode stdout True
  ByteString.hPut stdout bytes
  hFlush stdout
writePacketBytes file bytes = liftIO $ ByteString.writeFile file bytes

readPacketBytes :: FilePath -> TCM ByteString.ByteString
readPacketBytes "-" = do
  bytes <- liftIO $ do
    hSetBinaryMode stdin True
    ByteString.hGet stdin (fromInteger maxRuntimePacketBytes + 1)
  ensurePacketSize bytes
  pure bytes
readPacketBytes file = do
  fileSize <- liftIO $ getFileSize file
  when (fileSize > maxRuntimePacketBytes) $
    runtimeAbort "Term packet exceeds the 64 MiB size limit"
  bytes <- liftIO $ ByteString.readFile file
  ensurePacketSize bytes
  pure bytes

ensurePacketSize :: ByteString.ByteString -> TCM ()
ensurePacketSize bytes =
  when (toInteger (ByteString.length bytes) > maxRuntimePacketBytes) $
    runtimeAbort "Term packet exceeds the 64 MiB size limit"

runtimeAbort :: String -> TCM a
runtimeAbort message = liftIO $ ioError $ userError $ "Cubical runtime: " ++ message

-- | Normalise a runtime value in an eta-long form at top-level record types.
--
-- Agda intentionally suspends @transp@/@hcomp@ on eta records until a field
-- projection is present: the generated Kan operation is defined by
-- copatterns, and unfolding it eagerly would expose a large internal term.
-- Conversion still sees the value as a record because it eta-expands both
-- sides before comparing their fields.  A runtime read-back needs the same
-- type-directed step; otherwise a closed record such as @t09@ is printed as a
-- residual @transp@ even though every field computes.
runtimeNormalise :: Term -> Type -> TCM Term
runtimeNormalise term ty = do
  ty' <- reduce ty
  etaTerm <- isEtaRecordType ty' >>= \case
    Nothing -> pure term
    Just (recordName, parameters) -> do
      recordDef <- fromMaybe __IMPOSSIBLE__ <$> isRecord recordName
      etaExpandRecord_ recordName parameters recordDef term >>= \case
        Nothing                  -> pure term
        Just (_, con, info, args) -> pure $ mkCon con info args
  normalise etaTerm
