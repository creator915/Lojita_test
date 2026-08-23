{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

-- | A small execution backend for full Cubical Agda.
--
-- The ordinary compiler backends erase types before generated code runs.  This
-- backend deliberately stays inside the type-checking process instead: after
-- the input module has been checked, it evaluates a user-supplied expression
-- while the current 'TCState' (and hence the signature and all internal types)
-- is still available.  Evaluation therefore goes through the ordinary Agda
-- reducer, including the implementations in
-- "Agda.TypeChecking.Primitive.Cubical".
--
-- Version 2 can also serialise closed Internal Terms and their types, then
-- recheck and consume them in a second Agda process whose complete interface
-- hash matches the producer.  It remains an interpreter-style backend and
-- does not interpret Agda's IO type.
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
    Internal.Def name [] -> do
      isBool <- isBuiltinName name Builtin.builtinBool
      isNat <- isBuiltinName name Builtin.builtinNat
      case () of
        _ | isBool -> pure Wire.TyBool
          | isNat -> pure Wire.TyNat
          | otherwise -> unsupportedBridge "type" $ prettyShow name
    Internal.Pi domain codomain -> do
      domainTy <- bridgeType $ Internal.unDom domain
      codomainTy <- bridgeType $ Internal.unAbs codomain
      pure $ Wire.TyPi domainTy codomainTy
    Internal.Sort{} -> pure Wire.TyUniverse
    other -> unsupportedBridge "type node" $ prettyShow other

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
    if isTransp
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
          let (typeDomains, resultType) = splitPiType wireType
          unless (domains == typeDomains) $
            unsupportedBridge "definition telescope" $ prettyShow name
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

splitPiType :: Wire.Ty -> ([Wire.Ty], Wire.Ty)
splitPiType ty = case ty of
  Wire.TyPi domain codomain ->
    let (domains, result) = splitPiType codomain
    in (domain : domains, result)
  _ -> ([], ty)

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
  Internal.Def name [] -> do
    isBool <- isBuiltinName name Builtin.builtinBool
    isNat <- isBuiltinName name Builtin.builtinNat
    case () of
      _ | isBool -> pure Wire.TyBool
        | isNat -> pure Wire.TyNat
        | otherwise -> unsupportedBridge "type term" $ prettyShow name
  Internal.Sort{} -> pure Wire.TyUniverse
  _ -> unsupportedBridge "type term" $ prettyShow term

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
