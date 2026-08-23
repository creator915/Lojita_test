{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}

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
import Agda.Syntax.Internal (Term, Type, domInfo, unDom)
import Agda.Syntax.Internal.MetaVars (noMetas)
import Agda.Syntax.Position (noRange)
import Agda.Syntax.TopLevelModuleName (TopLevelModuleName)
import Agda.Syntax.Translation.ConcreteToAbstract (concreteToAbstract_)
import Agda.Syntax.Translation.InternalToAbstract (reify)
import Agda.TheTypeChecker (inferExpr)
import qualified Agda.TypeChecking.CheckInternal as CheckInternal
import Agda.TypeChecking.Conversion (compareType)
import Agda.TypeChecking.Free (closed)
import Agda.TypeChecking.Monad
  ( Comparison(CmpEq, CmpLeq), TCM, iFullHash, iTopLevelModuleName )
import Agda.TypeChecking.Records
  ( etaExpandRecord_, isEtaRecordType, isRecord, mkCon )
import Agda.TypeChecking.Reduce
  ( instantiateFull, normalise, reduce )
import qualified Agda.TypeChecking.Serialise as Serialise
import Agda.TypeChecking.Substitute (absApp, apply)
import Agda.TypeChecking.Telescope (shouldBePi)

import Agda.Utils.Impossible (__IMPOSSIBLE__)
import qualified Agda.Utils.Serialize as RawSerialise

data CubicalRuntimeOptions = CubicalRuntimeOptions
  { cubicalRuntimeExpression :: Maybe String
  , cubicalRuntimeExportExpression :: Maybe String
  , cubicalRuntimeImportConsumer :: Maybe String
  , cubicalRuntimeTermFile :: Maybe FilePath
  , cubicalRuntimeResultTermFile :: Maybe FilePath
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
      } -> runtimeEvaluate expression

    CubicalRuntimeOptions
      { cubicalRuntimeExpression = Nothing
      , cubicalRuntimeExportExpression = Just expression
      , cubicalRuntimeImportConsumer = Nothing
      , cubicalRuntimeTermFile = Just file
      , cubicalRuntimeResultTermFile = Nothing
      } -> runtimeExport file expression

    CubicalRuntimeOptions
      { cubicalRuntimeExpression = Nothing
      , cubicalRuntimeExportExpression = Nothing
      , cubicalRuntimeImportConsumer = Just consumer
      , cubicalRuntimeTermFile = Just file
      , cubicalRuntimeResultTermFile = resultFile
      } -> runtimeImport file resultFile consumer

    _ -> runtimeAbort $
      "select exactly one of --cubical-run, --cubical-export, or " ++
      "--cubical-import; result packets require import and both file options"

cubicalRuntimeEnabled :: CubicalRuntimeOptions -> Bool
cubicalRuntimeEnabled options = any isJust
  [ cubicalRuntimeExpression options
  , cubicalRuntimeExportExpression options
  , cubicalRuntimeImportConsumer options
  , cubicalRuntimeResultTermFile options
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
