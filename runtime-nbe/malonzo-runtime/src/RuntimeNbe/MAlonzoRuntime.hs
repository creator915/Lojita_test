module RuntimeNbe.MAlonzoRuntime (normalizeCheckedRuntimePacket) where

import Control.Monad (unless)
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

import RuntimeNbe.CcttProvider (normalizeRuntimeIr)
import RuntimeNbe.PacketDigest (packetSha256Hex)


normalizeCheckedRuntimePacket :: Text.Text -> Text.Text -> IO Text.Text
normalizeCheckedRuntimePacket packet checked = do
  checkedBytes <- ByteString.readFile (Text.unpack checked)
  unless (ByteString.length checkedBytes <= 64 * 1024) $
    reject "checked result exceeds 64 KiB"
  checkedFields <- either reject pure (parseFields checkedBytes)
  packetBytes <- ByteString.readFile (Text.unpack packet)
  packetFields <- either reject pure (parseFields packetBytes)
  require checkedFields "schema" "runtime-nbe-result-v1"
  require checkedFields "provider" "cctt"
  require checkedFields "provider-revision"
    "ba16f3758a322e9be77ada1da2b93f45d500192e"
  let expectedType = expectedAgdaType packetFields
  require checkedFields "type-syntax" expectedType
  require checkedFields "recheck" "agda-check-internal"
  bindEqual packetFields "source-qname" checkedFields "source-qname"
  bindEqual packetFields "schema" checkedFields "runtime-input-schema"
  require checkedFields "runtime-input-sha256" (packetSha256Hex packetBytes)
  let packetCount = Map.findWithDefault "0" "definition-count" packetFields
  require checkedFields "definition-count" packetCount
  result <- normalizeRuntimeIr (Text.unpack packet)
  case result of
    Left failure -> reject (show failure)
    Right normalForm -> do
      canonical <- either reject pure $
        providerNormalFormToAgda packetFields normalForm
      require checkedFields "term-syntax" canonical
      pure (Text.pack normalForm)

parseFields :: ByteString.ByteString -> Either String (Map.Map String String)
parseFields bytes = do
  decoded <- either (Left . ("packet is not UTF-8: " ++) . show) Right $
    Text.decodeUtf8' bytes
  pairs <- traverse parseLine $ filter (not . Text.null) (Text.lines decoded)
  let fields = Map.fromList pairs
  unless (length pairs == Map.size fields) $ Left "packet contains duplicate fields"
  pure fields
  where
    parseLine line = case Text.breakOn (Text.pack "=") line of
      (key, value)
        | Text.null key || Text.null value
          || Text.null (Text.drop 1 value) ->
            Left "packet contains an empty key or value"
        | otherwise -> Right
            (Text.unpack key, Text.unpack (Text.drop 1 value))

require :: Map.Map String String -> String -> String -> IO ()
require fields key expected = unless (Map.lookup key fields == Just expected) $
  reject (key ++ " identity mismatch: expected " ++ show expected ++
    ", got " ++ show (Map.lookup key fields))

bindEqual
  :: Map.Map String String -> String -> Map.Map String String -> String -> IO ()
bindEqual left leftKey right rightKey =
  unless (Map.lookup leftKey left == Map.lookup rightKey right
    && Map.member leftKey left) $
      reject (leftKey ++ " does not match " ++ rightKey)

reject :: String -> IO a
reject reason = ioError $ userError $ "CCNBE-MALONZO-REJECT: " ++ reason

providerNormalFormToAgda
  :: Map.Map String String -> String -> Either String String
providerNormalFormToAgda fields normalForm
  | Map.lookup "schema" fields == Just "runtime-nbe-ir-v14"
  , Map.lookup "type-ast" fields == Just "sigma(bool,bool)" =
      case break (== ',') normalForm of
        (first, ',' : ' ' : second)
          | first `elem` ["false", "true"]
          , second `elem` ["false", "true"] ->
              Right (first ++ " , " ++ second)
        _ -> Left "provider returned a malformed Sigma Bool normal form"
  | Map.lookup "schema" fields == Just "runtime-nbe-ir-v14"
  , Just (typeName, leftName, rightName, _) <-
      intervalHitIdentities fields
  , maybe False ((== "hcomp(i0,") . take 9) (Map.lookup "term-ast" fields) =
      case normalForm of
        "hcom 0 1 [] runtimeLeft" -> hitResult typeName leftName
        "hcom 0 1 [] runtimeRight" -> hitResult typeName rightName
        _ -> Left "provider returned a malformed interval HIT normal form"
  | Map.lookup "schema" fields == Just "runtime-nbe-ir-v14"
  , Just (_, leftName, rightName, _) <-
      intervalHitIdentities fields
  , maybe False ((== "hcomp(i1,") . take 9) (Map.lookup "term-ast" fields) =
      case normalForm of
        "runtimeLeft" -> Right $ shortQName leftName
        "runtimeRight" -> Right $ shortQName rightName
        _ -> Left "provider returned a malformed active interval HIT normal form"
  | Map.lookup "schema" fields == Just "runtime-nbe-ir-v14"
  , Just (_, approvedName, rejectedName) <-
      evidenceIdentities fields =
      case normalForm of
        "pair true (approved (λ _. true))" ->
          Right $ "true , " ++ shortQName approvedName
        "pair false (rejected (λ _. false))" ->
          Right $ "false , " ++ shortQName rejectedName
        _ -> Left "provider returned a malformed dependent evidence normal form"
  | Map.lookup "schema" fields == Just "runtime-nbe-ir-v4" =
      case break (== ',') normalForm of
        (first, ',' : ' ' : second)
          | first `elem` ["false", "true"]
          , second `elem` ["false", "true"] -> Right (first ++ " , " ++ second)
        _ -> Left "provider returned a malformed Sigma Bool normal form"
  | Map.lookup "schema" fields == Just "runtime-nbe-ir-v8" =
      case normalForm of
        "hcom 0 1 [] runtimeLeft" -> legacyHitResult "left-qname"
        "hcom 0 1 [] runtimeRight" -> legacyHitResult "right-qname"
        _ -> Left "provider returned a malformed interval HIT normal form"
  | Map.lookup "schema" fields == Just "runtime-nbe-ir-v12" =
      case normalForm of
        "runtimeLeft" -> shortQName <$> lookupRequired fields "left-qname"
        "runtimeRight" -> shortQName <$> lookupRequired fields "right-qname"
        _ -> Left "provider returned a malformed active interval HIT normal form"
  | Map.lookup "schema" fields == Just "runtime-nbe-ir-v9" =
      case normalForm of
        "pair true (approved (λ _. true))" -> legacyEvidence "true" "approved-con-qname"
        "pair false (rejected (λ _. false))" -> legacyEvidence "false" "rejected-con-qname"
        _ -> Left "provider returned a malformed dependent evidence normal form"
  | otherwise = Right normalForm
  where
    hitResult _ pointName =
      Right $ "primHComp (λ _ → isOneEmpty) " ++ shortQName pointName
    legacyHitResult pointField = do
      point <- shortQName <$> lookupRequired fields pointField
      Right $ "primHComp (λ _ → isOneEmpty) " ++ point
    legacyEvidence decision constructorField = do
      constructor <- shortQName <$> lookupRequired fields constructorField
      Right $ decision ++ " , " ++ constructor

expectedAgdaType :: Map.Map String String -> String
expectedAgdaType fields = case Map.lookup "schema" fields of
  Just "runtime-nbe-ir-v14" -> case Map.lookup "type-ast" fields of
    Just "bool" -> "Bool"
    Just "sigma(bool,bool)" -> "Σ Bool (λ _ → Bool)"
    Just _
      | Just (typeName, _, _, _) <- intervalHitIdentities fields ->
          shortQName typeName
      | Just (evidenceName, _, _) <- evidenceIdentities fields ->
          "Σ Bool " ++ shortQName evidenceName
    _ -> "invalid-v14-type"
  Just "runtime-nbe-ir-v4" -> "Σ Bool (λ _ → Bool)"
  Just "runtime-nbe-ir-v8" -> shortQName $ requiredField fields "hit-type-qname"
  Just "runtime-nbe-ir-v12" -> shortQName $ requiredField fields "hit-type-qname"
  Just "runtime-nbe-ir-v9" -> "Σ Bool " ++
    shortQName (requiredField fields "evidence-type-qname")
  _ -> "Bool"

intervalHitIdentities
  :: Map.Map String String -> Maybe (String, String, String, String)
intervalHitIdentities fields
  | Map.lookup "type-ast" fields == Just "def(0)"
  , Map.lookup "def0-body-ast" fields ==
      Just "interval-hit-type(def(1),def(2),def(3))" = do
      typeName <- Map.lookup "def0-qname" fields
      leftName <- Map.lookup "def1-qname" fields
      rightName <- Map.lookup "def2-qname" fields
      pathName <- Map.lookup "def3-qname" fields
      Just (typeName, leftName, rightName, pathName)
  | otherwise = Nothing

evidenceIdentities :: Map.Map String String -> Maybe (String, String, String)
evidenceIdentities fields
  | Map.lookup "type-ast" fields ==
      Just "sigma(bool,app(def(0),var(0)))"
  , Map.lookup "def0-body-ast" fields ==
      Just "evidence-family(def(1),def(2))" = do
      evidenceName <- Map.lookup "def0-qname" fields
      approvedName <- Map.lookup "def1-qname" fields
      rejectedName <- Map.lookup "def2-qname" fields
      Just (evidenceName, approvedName, rejectedName)
  | otherwise = Nothing

requiredField :: Map.Map String String -> String -> String
requiredField fields key = Map.findWithDefault "invalid-missing-field" key fields

lookupRequired :: Map.Map String String -> String -> Either String String
lookupRequired fields key = maybe (Left ("packet lacks " ++ key)) Right $
  Map.lookup key fields

shortQName :: String -> String
shortQName value = reverse (takeWhile (/= '.') (reverse value))
