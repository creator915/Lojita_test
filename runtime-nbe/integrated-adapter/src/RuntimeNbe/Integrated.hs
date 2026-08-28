{-# LANGUAGE OverloadedStrings #-}

module RuntimeNbe.Integrated (runtimeNbeIntegratedBackend) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Char8 as ByteString
import System.Directory (renameFile)

import Agda.Compiler.Backend (Backend, Definition(defName, defType))
import qualified Agda.Interaction.BasicOps as BasicOps
import Agda.Syntax.Abstract.Pretty (prettyA)
import Agda.Syntax.Common.Pretty (prettyShow, render)
import Agda.Syntax.Internal (Term)
import Agda.Syntax.Position (noRange)
import Agda.Syntax.Translation.ConcreteToAbstract (concreteToAbstract_)
import Agda.Syntax.Translation.InternalToAbstract (reify)
import qualified Agda.TypeChecking.CheckInternal as CheckInternal
import Agda.TypeChecking.Monad (Comparison(CmpLeq), TCM)
import Agda.TypeChecking.Reduce (instantiateFull)
import Agda.TypeChecking.Rules.Term (checkExpr)

import RuntimeNbe.AgdaProducer
  ( ProducerOptions(producerOutput), producerAbort, runtimeNbeBackendWith )
import RuntimeNbe.CcttProvider
  ( normalizeRuntimeIrBytes, providerName, providerRevision )
import RuntimeNbe.PacketDigest (packetSha256Hex)


runtimeNbeIntegratedBackend :: Backend
runtimeNbeIntegratedBackend = runtimeNbeBackendWith
  "RuntimeNbeIntegrated" "result-v1" evaluateReifyRecheck

evaluateReifyRecheck
  :: ProducerOptions -> Definition -> Term -> String -> TCM ()
evaluateReifyRecheck opts definition _ runtimeIr = do
  evaluated <- liftIO $ normalizeRuntimeIrBytes $ ByteString.pack runtimeIr
  normalForm <- case evaluated of
    Left failure -> integratedAbort $ "provider rejected checked input: " ++ show failure
    Right result -> pure result
  agdaSyntax <- either integratedAbort pure $
    providerNormalFormToAgda runtimeIr normalForm
  concrete <- BasicOps.parseExpr noRange agdaSyntax
  abstract <- concreteToAbstract_ concrete
  let resultType = defType definition
  checked <- instantiateFull =<< checkExpr abstract resultType
  checkedType <- instantiateFull resultType
  CheckInternal.checkType checkedType
  CheckInternal.checkInternal checked CmpLeq checkedType
  termSyntaxRaw <- render <$> (prettyA =<< reify checked)
  typeSyntaxRaw <- render <$> (prettyA =<< reify checkedType)
  let termSyntax = singleLine termSyntaxRaw
      typeSyntax = singleLine typeSyntaxRaw
  output <- maybe (producerAbort "missing runtime NbE output path") pure $
    producerOutput opts
  let temporary = output ++ ".rechecked"
      inputSchema = packetField "schema" runtimeIr
      definitionCount = packetField "definition-count" runtimeIr
      resultPacket = unlines
        [ "schema=runtime-nbe-result-v1"
        , "provider=" ++ providerName
        , "provider-revision=" ++ providerRevision
        , "source-qname=" ++ prettyShow (defName definition)
        , "runtime-input-schema=" ++ inputSchema
        , "runtime-input-sha256=" ++ packetSha256Hex (ByteString.pack runtimeIr)
        , "definition-count=" ++ definitionCount
        , "term-syntax=" ++ termSyntax
        , "type-syntax=" ++ typeSyntax
        , "recheck=agda-check-internal"
        ]
  liftIO $ writeFile temporary resultPacket
  liftIO $ renameFile temporary output

packetField :: String -> String -> String
packetField key input = case
  [ drop (length key + 1) line
  | line <- lines input
  , take (length key + 1) line == key ++ "="
  ] of
    [value] -> value
    [] | key == "definition-count" -> "0"
    _ -> "invalid"

providerNormalFormToAgda :: String -> String -> Either String String
providerNormalFormToAgda runtimeIr normalForm
  | packetField "schema" runtimeIr == "runtime-nbe-ir-v14"
  , packetField "type-ast" runtimeIr == "sigma(bool,bool)" =
      case break (== ',') normalForm of
        (first, ',' : ' ' : second)
          | first `elem` ["false", "true"]
          , second `elem` ["false", "true"] ->
              Right (first ++ " , " ++ second)
        _ -> Left "provider returned a malformed Sigma Bool normal form"
  | packetField "schema" runtimeIr == "runtime-nbe-ir-v14"
  , Just (typeName, leftName, rightName, _) <-
      intervalHitIdentities runtimeIr
  , take 9 (packetField "term-ast" runtimeIr) == "hcomp(i0," =
      case normalForm of
        "hcom 0 1 [] runtimeLeft" -> hitResult typeName leftName
        "hcom 0 1 [] runtimeRight" -> hitResult typeName rightName
        _ -> Left "provider returned a malformed interval HIT normal form"
  | packetField "schema" runtimeIr == "runtime-nbe-ir-v14"
  , Just (_, leftName, rightName, _) <-
      intervalHitIdentities runtimeIr
  , take 9 (packetField "term-ast" runtimeIr) == "hcomp(i1," =
      case normalForm of
        "runtimeLeft" -> Right $ shortQName leftName
        "runtimeRight" -> Right $ shortQName rightName
        _ -> Left "provider returned a malformed active interval HIT normal form"
  | packetField "schema" runtimeIr == "runtime-nbe-ir-v14"
  , Just (_, approvedName, rejectedName) <-
      evidenceIdentities runtimeIr =
      case normalForm of
        "pair true (approved (λ _. true))" ->
          Right $ "true , " ++ shortQName approvedName
        "pair false (rejected (λ _. false))" ->
          Right $ "false , " ++ shortQName rejectedName
        _ -> Left "provider returned a malformed dependent evidence normal form"
  | packetField "schema" runtimeIr == "runtime-nbe-ir-v4" =
      case break (== ',') normalForm of
        (first, ',' : ' ' : second)
          | first `elem` ["false", "true"]
          , second `elem` ["false", "true"] -> Right (first ++ " , " ++ second)
        _ -> Left "provider returned a malformed Sigma Bool normal form"
  | packetField "schema" runtimeIr == "runtime-nbe-ir-v8" =
      case normalForm of
        "hcom 0 1 [] runtimeLeft" -> legacyHitResult "left-qname"
        "hcom 0 1 [] runtimeRight" -> legacyHitResult "right-qname"
        _ -> Left "provider returned a malformed interval HIT normal form"
  | packetField "schema" runtimeIr == "runtime-nbe-ir-v12" =
      case normalForm of
        "runtimeLeft" -> Right $ shortQName $ packetField "left-qname" runtimeIr
        "runtimeRight" -> Right $ shortQName $ packetField "right-qname" runtimeIr
        _ -> Left "provider returned a malformed active interval HIT normal form"
  | packetField "schema" runtimeIr == "runtime-nbe-ir-v9" =
      case normalForm of
        "pair true (approved (λ _. true))" -> legacyEvidence "true" "approved-con-qname"
        "pair false (rejected (λ _. false))" -> legacyEvidence "false" "rejected-con-qname"
        _ -> Left "provider returned a malformed dependent evidence normal form"
  | otherwise = Right normalForm
  where
    hitResult typeName pointName = Right $
      "primHComp {A = " ++ shortQName typeName ++
      "} {φ = i0} (λ _ → isOneEmpty) " ++
      shortQName pointName
    legacyHitResult pointField = Right $
      "primHComp {A = " ++ shortQName (packetField "hit-type-qname" runtimeIr) ++
      "} {φ = i0} (λ _ → isOneEmpty) " ++
      shortQName (packetField pointField runtimeIr)
    legacyEvidence decision constructorField = Right $
      decision ++ " , " ++ shortQName (packetField constructorField runtimeIr)

intervalHitIdentities :: String -> Maybe (String, String, String, String)
intervalHitIdentities runtimeIr
  | packetField "type-ast" runtimeIr == "def(0)"
  , packetField "def0-body-ast" runtimeIr ==
      "interval-hit-type(def(1),def(2),def(3))" = Just
      ( packetField "def0-qname" runtimeIr
      , packetField "def1-qname" runtimeIr
      , packetField "def2-qname" runtimeIr
      , packetField "def3-qname" runtimeIr
      )
  | otherwise = Nothing

evidenceIdentities :: String -> Maybe (String, String, String)
evidenceIdentities runtimeIr
  | packetField "type-ast" runtimeIr == "sigma(bool,app(def(0),var(0)))"
  , packetField "def0-body-ast" runtimeIr ==
      "evidence-family(def(1),def(2))" = Just
      ( packetField "def0-qname" runtimeIr
      , packetField "def1-qname" runtimeIr
      , packetField "def2-qname" runtimeIr
      )
  | otherwise = Nothing

shortQName :: String -> String
shortQName value = reverse (takeWhile (/= '.') (reverse value))

singleLine :: String -> String
singleLine = unwords . words

integratedAbort :: String -> TCM a
integratedAbort message = producerAbort $ "CCNBE-INTEGRATED-REJECT: " ++ message
