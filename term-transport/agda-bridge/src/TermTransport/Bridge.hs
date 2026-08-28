{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module TermTransport.Bridge (termTransportBackend) where

import Control.DeepSeq (NFData)
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as Lazy
import Data.Map (Map)
import Data.Maybe (isJust)
import Data.Word (Word64)
import GHC.Generics (Generic)
import System.Directory (doesFileExist, getFileSize)
import System.IO (hPutStrLn, stderr)

import Agda.Compiler.Backend
  ( Backend, Backend_boot(..), Backend', Backend'_boot(..)
  , Definition, Recompile(..)
  )
import Agda.Compiler.Common (IsMain, curIF)
import Agda.Interaction.Base (ComputeMode(DefaultCompute))
import qualified Agda.Interaction.BasicOps as BasicOps
import Agda.Interaction.Options
  ( ArgDescr(NoArg, ReqArg), Flag, OptDescr(..) )
import qualified Agda.Syntax.Abstract as A
import Agda.Syntax.Abstract.Pretty (prettyA)
import Agda.Syntax.Common.Pretty (prettyShow, render)
import Agda.Syntax.Internal (Term, Type)
import Agda.Syntax.Internal.MetaVars (noMetas)
import Agda.Syntax.Position (noRange)
import Agda.Syntax.TopLevelModuleName (TopLevelModuleName)
import Agda.Syntax.Translation.ConcreteToAbstract (concreteToAbstract_)
import Agda.Syntax.Translation.InternalToAbstract (reify)
import Agda.TheTypeChecker (inferExpr)
import qualified Agda.TypeChecking.CheckInternal as CheckInternal
import Agda.TypeChecking.Free (closed)
import Agda.TypeChecking.Monad
  ( Comparison(CmpLeq), TCM, iFullHash, iTopLevelModuleName )
import Agda.TypeChecking.Reduce (instantiateFull, normalise)
import Agda.TypeChecking.Rules.Term (checkExpr, isType_)
import qualified Agda.Utils.Hash as Hash


data BridgeOptions = BridgeOptions
  { bridgeExportExpression :: Maybe String
  , bridgeImportEnabled :: Bool
  , bridgePacketFile :: Maybe FilePath
  }
  deriving (Generic)

instance NFData BridgeOptions

defaultBridgeOptions :: BridgeOptions
defaultBridgeOptions = BridgeOptions Nothing False Nothing

data WireTerm = WireSyntax String
  deriving (Generic)

instance Binary.Binary WireTerm

data WireType = WireTypeSyntax String
  deriving (Generic)

instance Binary.Binary WireType

data BridgePayload = BridgePayload
  { packetMagic :: String
  , packetVersion :: Word64
  , packetProviderRevision :: String
  , packetInterfaceHash :: Word64
  , packetModule :: String
  , packetTerm :: WireTerm
  , packetType :: WireType
  }
  deriving (Generic)

instance Binary.Binary BridgePayload

data BridgePacket = BridgePacket
  { packetPayload :: BridgePayload
  , packetIntegrityHash :: Word64
  }
  deriving (Generic)

instance Binary.Binary BridgePacket

bridgeMagic :: String
bridgeMagic = "agda-internal-term-bridge"

bridgeVersion :: Word64
bridgeVersion = 2

bridgeProviderRevision :: String
bridgeProviderRevision = "3d04bacca842729f9c0869b9287256321b5f450f"

maxPacketBytes :: Integer
maxPacketBytes = 1024 * 1024

maxSyntaxCharacters :: Int
maxSyntaxCharacters = 256 * 1024

bridgeFlags :: [OptDescr (Flag BridgeOptions)]
bridgeFlags =
  [ Option [] ["term-export"]
      (ReqArg setExport "EXPRESSION")
      "export a checked closed Internal Term+Type packet"
  , Option [] ["term-import"]
      (NoArg setImport)
      "import, reconstruct and recheck an Internal Term+Type packet"
  , Option [] ["term-packet"]
      (ReqArg setPacket "FILE")
      "packet file used by --term-export or --term-import"
  ]
  where
    setExport expression opts =
      pure opts { bridgeExportExpression = Just expression }
    setImport opts = pure opts { bridgeImportEnabled = True }
    setPacket file opts = pure opts { bridgePacketFile = Just file }

termTransportBackend :: Backend
termTransportBackend = Backend termTransportBackend'

termTransportBackend'
  :: Backend' BridgeOptions BridgeOptions () () ()
termTransportBackend' = Backend'
  { backendName = "TermTransport"
  , backendVersion = Nothing
  , options = defaultBridgeOptions
  , commandLineFlags = bridgeFlags
  , isEnabled = bridgeEnabled
  , preCompile = pure
  , postCompile = bridgePostCompile
  , preModule = bridgePreModule
  , postModule = bridgePostModule
  , compileDef = bridgeCompileDef
  , scopeCheckingSuffices = False
  , mayEraseType = const $ pure False
  , backendInteractTop = Nothing
  , backendInteractHole = Nothing
  }

bridgeEnabled :: BridgeOptions -> Bool
bridgeEnabled opts =
  isJust (bridgeExportExpression opts)
    || bridgeImportEnabled opts
    || isJust (bridgePacketFile opts)

bridgePreModule
  :: BridgeOptions
  -> IsMain
  -> TopLevelModuleName
  -> Maybe FilePath
  -> TCM (Recompile () ())
bridgePreModule _ _ _ _ = pure $ Skip ()

bridgeCompileDef :: BridgeOptions -> () -> IsMain -> Definition -> TCM ()
bridgeCompileDef _ _ _ _ = pure ()

bridgePostModule
  :: BridgeOptions -> () -> IsMain -> TopLevelModuleName -> [()] -> TCM ()
bridgePostModule _ _ _ _ _ = pure ()

bridgePostCompile
  :: BridgeOptions -> IsMain -> Map TopLevelModuleName () -> TCM ()
bridgePostCompile opts _ _ = BasicOps.atTopLevel $
  case opts of
    BridgeOptions (Just expression) False (Just file) -> exportTerm file expression
    BridgeOptions Nothing True (Just file) -> importTerm file
    _ -> bridgeAbort "select exactly one of --term-export or --term-import and one --term-packet"

inferInternal :: String -> TCM (Term, Type)
inferInternal expression = do
  concrete <- BasicOps.parseExpr noRange expression
  abstract <- concreteToAbstract_ concrete
  instantiateFull =<< inferExpr abstract

parseAbstract :: String -> TCM A.Expr
parseAbstract expression = do
  concrete <- BasicOps.parseExpr noRange expression
  concreteToAbstract_ concrete

toWire :: Term -> Type -> TCM (WireTerm, WireType)
toWire term ty = do
  termSyntax <- render <$> (prettyA =<< reify term)
  typeSyntax <- render <$> (prettyA =<< reify ty)
  when (length termSyntax > maxSyntaxCharacters) $
    bridgeAbort "reified term exceeds syntax limit"
  when (length typeSyntax > maxSyntaxCharacters) $
    bridgeAbort "reified type exceeds syntax limit"
  pure (WireSyntax termSyntax, WireTypeSyntax typeSyntax)

fromWire :: WireTerm -> WireType -> TCM (Term, Type)
fromWire (WireSyntax termSyntax) (WireTypeSyntax typeSyntax) = do
  when (length termSyntax > maxSyntaxCharacters) $
    bridgeAbort "term syntax exceeds limit"
  when (length typeSyntax > maxSyntaxCharacters) $
    bridgeAbort "type syntax exceeds limit"
  ty <- isType_ =<< parseAbstract typeSyntax
  abstractTerm <- parseAbstract termSyntax
  term <- checkExpr abstractTerm ty
  instantiateFull (term, ty)

ensurePortable :: Term -> Type -> TCM ()
ensurePortable term ty = do
  unless (closed (term, ty)) $ bridgeAbort "only closed Internal Terms can cross processes"
  unless (noMetas (term, ty)) $ bridgeAbort "Internal Term contains process-local metas"

exportTerm :: FilePath -> String -> TCM ()
exportTerm file expression = do
  exists <- liftIO $ doesFileExist file
  when exists $ bridgeAbort "packet output already exists"
  (term0, ty0) <- inferInternal expression
  term <- normalise term0
  ty <- normalise ty0
  ensurePortable term ty
  (wireTerm, wireType) <- toWire term ty
  iface <- curIF
  let payload = BridgePayload
        { packetMagic = bridgeMagic
        , packetVersion = bridgeVersion
        , packetProviderRevision = bridgeProviderRevision
        , packetInterfaceHash = iFullHash iface
        , packetModule = prettyShow $ iTopLevelModuleName iface
        , packetTerm = wireTerm
        , packetType = wireType
        }
      packet = BridgePacket payload $ payloadHash payload
  liftIO $ Lazy.writeFile file $ Binary.encode packet
  liftIO $ hPutStrLn stderr "term-bridge: EXPORTED real Agda Internal Term+Type"

decodePacket :: Lazy.ByteString -> Either String BridgePacket
decodePacket bytes = case Binary.decodeOrFail bytes of
  Left (_, _, message) -> Left message
  Right (rest, _, packet)
    | Lazy.null rest -> Right packet
    | otherwise -> Left "trailing bytes"

payloadHash :: BridgePayload -> Word64
payloadHash = Hash.hashByteString . Lazy.toStrict . Binary.encode

importTerm :: FilePath -> TCM ()
importTerm file = do
  size <- liftIO $ getFileSize file
  when (size > maxPacketBytes) $ bridgeAbort "packet exceeds byte limit"
  bytes <- liftIO $ Lazy.readFile file
  packet <- either (bridgeAbort . ("malformed packet: " ++)) pure $ decodePacket bytes
  let payload = packetPayload packet
  unless (packetIntegrityHash packet == payloadHash payload) $
    bridgeAbort "packet content integrity mismatch"
  unless (packetMagic payload == bridgeMagic) $ bridgeAbort "packet magic mismatch"
  unless (packetVersion payload == bridgeVersion) $ bridgeAbort "packet version mismatch"
  unless (packetProviderRevision payload == bridgeProviderRevision) $
    bridgeAbort "packet provider revision mismatch"
  iface <- curIF
  unless (packetModule payload == prettyShow (iTopLevelModuleName iface)) $
    bridgeAbort "packet top-level module mismatch"
  unless (packetInterfaceHash payload == iFullHash iface) $
    bridgeAbort "packet interface hash mismatch"
  (term, ty) <- fromWire (packetTerm payload) (packetType payload)
  ensurePortable term ty
  CheckInternal.checkType ty
  CheckInternal.checkInternal term CmpLeq ty
  rendered <- BasicOps.showComputed DefaultCompute =<< reify term
  liftIO $ putStrLn $ prettyShow rendered
  liftIO $ hPutStrLn stderr "term-bridge: RECHECKED real Agda Internal Term+Type"

bridgeAbort :: String -> TCM a
bridgeAbort message = liftIO $ ioError $ userError $ "Term bridge: " ++ message
