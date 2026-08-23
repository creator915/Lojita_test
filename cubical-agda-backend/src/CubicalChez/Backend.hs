{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module CubicalChez.Backend (chezBackend) where

import Agda.Compiler.Backend
#if defined(CUBICAL_CHEZ_AGDA_29)
import Agda.Compiler.Common (curIF)
#endif
#if defined(CUBICAL_CHEZ_AGDA_29)
import Agda.Compiler.ToTreeless (closedTermToTreeless, mkDefaultCCConfig)
#else
import Agda.Compiler.ToTreeless (CCSubst (EraseUnused), closedTermToTreeless)
#endif
import Agda.Syntax.Common.Pretty (prettyShow)
import Agda.Syntax.Common (Hiding (NotHidden), getHiding)
#if defined(CUBICAL_CHEZ_TEST_UNRESOLVED_META) || defined(CUBICAL_CHEZ_TEST_ENGINE_UNRESOLVED_META)
import Agda.Syntax.Common (MetaId (MetaId), noModuleNameHash)
#endif
import Agda.Syntax.Internal
  ( Clause (..)
  , ConHead
  , ConInfo
  , Term
  , Type
  , telToList
  )
import qualified Agda.Syntax.Internal as Internal
import Agda.Syntax.Internal.Names (NamesIn, namesIn)
import Agda.Syntax.Literal (Literal (..))
import Agda.Syntax.Internal.MetaVars (noMetas)
import Agda.TypeChecking.Records
  ( etaExpandRecord_
  , isEtaRecordType
  , isRecord
  , mkCon
  )
import Agda.TypeChecking.Reduce (normalise, reduce)
import Agda.TypeChecking.Free (closed)
import Agda.TypeChecking.Substitute (teleLam, telePi)
import qualified Agda.TypeChecking.CheckInternal as CheckInternal
import qualified Agda.TypeChecking.Monad.Builtin as Builtin
#if defined(CUBICAL_CHEZ_AGDA_29)
import qualified Agda.TypeChecking.Serialise as Serialise
#endif
import Agda.Utils.GetOpt
  ( ArgDescr (NoArg, ReqArg)
  , OptDescr (Option)
  )
import Agda.Utils.Impossible (__IMPOSSIBLE__)
#if defined(CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE) || defined(CUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE)
import qualified CubicalChez.Nbe.AdapterSpike as NbeSpike
#endif
#if defined(CUBICAL_CHEZ_AGDA_29)
import qualified Agda.Utils.Serialize as RawSerialise
#endif
import Control.DeepSeq (NFData)
import Control.Monad (forM, forM_, unless, when)
import Control.Monad.Except (catchError, throwError)
import Control.Monad.IO.Class (liftIO)
#if defined(CUBICAL_CHEZ_AGDA_29)
import Control.Monad.Trans.Maybe (MaybeT, runMaybeT)
#endif
import qualified Data.ByteString as ByteString
import Data.Char (isAlphaNum, ord)
import Data.List (intercalate, isInfixOf, isPrefixOf, isSuffixOf)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe)
import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Word (Word64)
import GHC.Generics (Generic)
import GHC.Clock (getMonotonicTimeNSec)
import Numeric (showHex)
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  , removeFile
  )
import System.FilePath ((</>))
import System.IO (hFlush, hSetBinaryMode, stdout)

data ChezOptions = ChezOptions
  { chezEnabled :: Bool
  , chezEngine :: String
  , chezNbeFallback :: String
  , chezResidualPolicy :: String
  , chezPacketFile :: Maybe FilePath
  , chezOutputDirectory :: FilePath
  , chezEntry :: String
  }
  deriving (Generic)

instance NFData ChezOptions

data CompiledDef = CompiledDef
  { compiledName :: QName
  , compiledTerm :: TTerm
  , compiledFromMainModule :: Bool
  , compiledIsEntry :: Bool
  , compiledInternalTermBlockers :: [QName]
  , compiledInternalTypeBlockers :: [QName]
  , compiledInternalTermCatalogBlockers :: [QName]
  , compiledInternalTypeCatalogBlockers :: [QName]
  , compiledInternalTermSemanticSources :: [(QName, String)]
  , compiledInternalTypeSemanticSources :: [(QName, String)]
  , compiledInternalTermSemanticCatalogDisagreements :: [QName]
  , compiledInternalTypeSemanticCatalogDisagreements :: [QName]
  , compiledTreelessBlockers :: [QName]
  , compiledInternalTermUnknownCubical :: [QName]
  , compiledInternalTypeUnknownCubical :: [QName]
  , compiledTreelessUnknownCubical :: [QName]
  , compiledBindingTime :: BindingTimeClass
  , compiledBindingReason :: BindingTimeReason
  , compiledRequestedEngine :: String
  , compiledEffectiveEngine :: String
  , compiledNbeFallbackPolicy :: String
  , compiledNbeFallbackUsed :: Bool
  , compiledNbeFallbackReason :: String
  , compiledEngineEvidence :: [String]
  , compiledTypedResidual :: Maybe TypedResidual
  , compiledEngineTotalNanoseconds :: Word64
  , compiledNbeEvaluationNanoseconds :: Maybe Word64
  , compiledNbeReadbackNanoseconds :: Maybe Word64
  , compiledResultAdmissionNanoseconds :: Word64
  , compiledInternalAuditNanoseconds :: Word64
  , compiledTreelessNanoseconds :: Word64
  }

data BindingTimeClass
  = BindingStatic
  | BindingDynamic
  | BindingMixed
  | BindingUnsupported
  deriving (Eq)

data BindingTimeReason
  = NoRuntimeBlockers
  | WholeEntryRuntimeHead
  | StaticContextAroundRuntimeBlocker
  | InternalSemanticCatalogDisagreement
  | InternalTreelessAuditDisagreement
  | UnknownCubicalPrimitive
  deriving (Eq)

-- | The primary binding-time evidence for one checked Internal value. The
-- semantic side is derived from Agda's registered Cubical builtin/primitive
-- identities (plus checked Kan-operation metadata), while the catalog side is
-- the pinned 2.8/2.9 compatibility allowlist. Publication requires both sides
-- to agree; the allowlist is no longer itself the Internal classifier.
data InternalSemanticAudit = InternalSemanticAudit
  { internalSemanticBlockers :: [QName]
  , internalCatalogBlockers :: [QName]
  , internalSemanticSources :: [(QName, String)]
  , internalSemanticCatalogDisagreements :: [QName]
  , internalUnknownCubicalPrimitives :: [QName]
  }

-- | Stable machine-readable failure taxonomy. Human explanations may grow,
-- but automation should key only on these codes.
data BackendFailureClass
  = InvalidConfiguration
  | EntryRejected
  | NbeUnavailable
  | NbeUnsupportedFeature
  | EngineTimeout
  | NbeExecutionFailed
  | EngineResultInvalid
  | UnsupportedProgram
  | ResidualRequired
  | ResidualizationFailed
  | SchemeLoweringFailed

-- | Evidence retained when the candidate Treeless term still needs typed
-- Cubical semantics.  Both the diagnostic manifest and the Agda 2.9 packet
-- bridge consume this original Internal Term and Type; no typed information
-- is reconstructed from erased Treeless syntax.
data TypedResidual = TypedResidual
  { residualTerm :: Term
  , residualType :: Type
  , residualDirectDependencies :: [QName]
  }

-- | A checked dependency graph for the current whole-entry residual. Every
-- QName in the transitive closure was resolved from Agda's current signature.
-- Agda builtins/primitives are retained as non-expanded signature leaves;
-- ordinary definitions are traversed through their checked Definition value.
data ResidualClosure = ResidualClosure
  { residualClosurePayload :: TypedResidual
  , residualClosureResolvedDependencies :: [QName]
  , residualClosureExpandedDefinitions :: [QName]
  , residualClosureSignatureLeaves :: [QName]
  , residualClosureExcludedPresentationDependencies :: [QName]
  }

data DependencyGraph = DependencyGraph
  { dependencyGraphResolved :: [QName]
  , dependencyGraphExpanded :: [QName]
  , dependencyGraphLeaves :: [QName]
  , dependencyGraphExcludedPresentation :: [QName]
  }

-- | A deterministic plan for carving maximal blocker-headed Treeless subtrees
-- out of a mixed entry. Treeless provides identity only: each selected subtree
-- must match exactly one subterm discovered by Agda's Internal rechecker,
-- which supplies the authoritative Term, Type, and local telescope. Open
-- sources are lambda-lifted before they become packet payloads.
data ResidualSlicePlan
  = ResidualSliceNotApplicable String
  | ResidualSlicePlanned [ResidualHolePlan]

data ResidualHolePlan = ResidualHolePlan
  { residualHoleId :: String
  , residualHolePath :: String
  , residualHoleBlockers :: [QName]
  , residualHoleClosure :: ResidualClosure
  , residualHoleCallableAbi :: ResidualHoleCallableAbi
  , residualHoleSourceClosed :: Bool
  , residualHoleEnvironmentArity :: Int
  }

-- | Deliberately narrow capabilities derived from the checked hole type.
-- Closed/single-slot holes accept one visible builtin Bool/Nat/Word64/Char/Int argument;
-- an open multi-slot hole may instead carry an ordered non-dependent
-- Bool/Nat/Word64/Char/Int
-- environment vector. Application and result consumption stay inside Agda;
-- only the final Bool/Nat observation crosses back to Chez.
data ResidualHoleCallableAbi
  = ResidualHoleObservationOnly
  | ResidualHoleUnaryGroundElimination ResidualGroundCodec
  | ResidualHoleOrderedGroundEnvironmentElimination [ResidualGroundCodec]
  | ResidualHoleDependentGroundEnvironmentElimination
  deriving (Eq)

data ResidualGroundCodec
  = ResidualGroundBool
  | ResidualGroundNat
  | ResidualGroundWord64
  | ResidualGroundChar
  | ResidualGroundInt
  deriving (Eq)

data ResidualGroundCodecDescriptor = ResidualGroundCodecDescriptor
  { groundCodecDescriptorCodec :: ResidualGroundCodec
  , groundCodecDescriptorName :: String
  , groundCodecDescriptorArgumentValidator :: String
  , groundCodecDescriptorArgumentReifier :: String
  , groundCodecDescriptorEntryParser :: String
  , groundCodecDescriptorValueReifier :: String
  }

residualGroundCodecDescriptors :: [ResidualGroundCodecDescriptor]
residualGroundCodecDescriptors =
  [ ResidualGroundCodecDescriptor
      ResidualGroundBool
      "bool"
      "cubical-chez-valid-bool-argument?"
      "(lambda (literal) (string-append \"Agda.Builtin.Bool.\" literal))"
      "(lambda (literal) (cubical-chez-agda-bool-value literal))"
      ( "(lambda (value) (string-append \"Agda.Builtin.Bool.\""
          ++ " (cubical-chez-agda-bool-literal value)))"
      )
  , ResidualGroundCodecDescriptor
      ResidualGroundNat
      "nat"
      "cubical-chez-valid-nat-argument?"
      "(lambda (literal) literal)"
      "(lambda (literal) (cubical-chez-agda-nat-value literal))"
      ( "(lambda (value)"
          ++ " (unless (and (integer? value) (exact? value)"
          ++ " (>= value 0) (<= value 4294967295))"
          ++ " (cubical-chez-bridge-fail \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
          ++ " \"expected bounded Chez Agda Nat\"))"
          ++ " (number->string value))"
      )
  , ResidualGroundCodecDescriptor
      ResidualGroundWord64
      "word64"
      "cubical-chez-valid-word64-argument?"
      ( "(lambda (literal)"
          ++ " (string-append \"(Agda.Builtin.Word.primWord64FromNat \""
          ++ " literal \" )\"))"
      )
      "(lambda (literal) (cubical-chez-agda-word64-value literal))"
      ( "(lambda (value)"
          ++ " (unless (and (integer? value) (exact? value)"
          ++ " (>= value 0) (<= value 18446744073709551615))"
          ++ " (cubical-chez-bridge-fail \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
          ++ " \"expected bounded Chez Agda Word64\"))"
          ++ " (string-append \"(Agda.Builtin.Word.primWord64FromNat \""
          ++ " (number->string value) \" )\"))"
      )
  , ResidualGroundCodecDescriptor
      ResidualGroundChar
      "char"
      "cubical-chez-valid-char-argument?"
      ( "(lambda (literal)"
          ++ " (string-append \"(Agda.Builtin.Char.primNatToChar \""
          ++ " literal \" )\"))"
      )
      "(lambda (literal) (cubical-chez-agda-char-value literal))"
      ( "(lambda (value)"
          ++ " (unless (char? value)"
          ++ " (cubical-chez-bridge-fail \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
          ++ " \"expected Chez Agda Char\"))"
          ++ " (string-append \"(Agda.Builtin.Char.primNatToChar \""
          ++ " (number->string (char->integer value)) \" )\"))"
      )
  , ResidualGroundCodecDescriptor
      ResidualGroundInt
      "int"
      "cubical-chez-valid-int-argument?"
      "(lambda (literal) (cubical-chez-int-term (string->number literal)))"
      "(lambda (literal) (cubical-chez-agda-int-value literal))"
      ( "(lambda (value) (cubical-chez-int-term"
          ++ " (cubical-chez-agda-int->integer value)))"
      )
  ]

residualGroundCodecDescriptor
  :: ResidualGroundCodec
  -> ResidualGroundCodecDescriptor
residualGroundCodecDescriptor codec =
  case
    [ descriptor
    | descriptor <- residualGroundCodecDescriptors
    , groundCodecDescriptorCodec descriptor == codec
    ] of
    descriptor : _ -> descriptor
    [] -> __IMPOSSIBLE__

-- | The single source of truth for ground values allowed to cross the erased
-- Chez boundary. Builtin identity lookup, callable ABI publication, manifest
-- evidence, and the generated Scheme registry all enumerate this value.
allResidualGroundCodecs :: [ResidualGroundCodec]
allResidualGroundCodecs =
  map groundCodecDescriptorCodec residualGroundCodecDescriptors

residualGroundCodecBuiltinName
  :: ResidualGroundCodec
  -> TCM (Maybe QName)
residualGroundCodecBuiltinName = \case
  ResidualGroundBool -> Builtin.getBuiltinName' Builtin.builtinBool
  ResidualGroundNat -> Builtin.getBuiltinName' Builtin.builtinNat
  ResidualGroundWord64 -> Builtin.getBuiltinName' Builtin.builtinWord64
  ResidualGroundChar -> Builtin.getBuiltinName' Builtin.builtinChar
  ResidualGroundInt -> Builtin.getBuiltinName' Builtin.builtinInteger

residualGroundCodecRegistry
  :: TCM [(ResidualGroundCodec, Maybe QName)]
residualGroundCodecRegistry = forM allResidualGroundCodecs $ \codec -> do
  builtinName <- residualGroundCodecBuiltinName codec
  pure (codec, builtinName)

lookupResidualGroundCodec
  :: [(ResidualGroundCodec, Maybe QName)]
  -> QName
  -> Maybe ResidualGroundCodec
lookupResidualGroundCodec registry actual =
  case
    [ codec
    | (codec, Just registered) <- registry
    , actual == registered
    ] of
    codec : _ -> Just codec
    [] -> Nothing

data ResidualHoleSeed = ResidualHoleSeed
  { residualHoleSeedId :: String
  , residualHoleSeedPath :: String
  , residualHoleSeedBlockers :: [QName]
  , residualHoleSeedTreeless :: TTerm
  }

data ResidualHoleCandidate = ResidualHoleCandidate
  { residualHoleCandidateTerm :: Term
  , residualHoleCandidateType :: Type
  , residualHoleCandidateTreeless :: TTerm
  , residualHoleCandidateSourceClosed :: Bool
  , residualHoleCandidateEnvironmentArity :: Int
  }

-- | Capability produced only after the complete reachable Treeless closure
-- has no unresolved definitions and every definition lowers to Scheme.  The
-- static publication path consumes this value, so blocker classification
-- alone can never authorize type erasure.
data StaticClosure = StaticClosure
  { staticClosureDefinitions :: [CompiledDef]
  , staticClosureProgram :: String
  }

data StaticClosureFailure = StaticClosureFailure
  { staticClosureFailureDefinitions :: [CompiledDef]
  , staticClosureFailureUnresolved :: [QName]
  , staticClosureFailureBlockers :: [QName]
  , staticClosureFailureUnknownCubical :: [QName]
  , staticClosureFailureReason :: String
  , staticClosureFailureLowering :: String
  , staticClosureFailureProblem :: String
  }

data StaticClosureReport
  = StaticClosureNotApplicable
  | StaticClosureComplete Int
  | StaticClosureIncomplete Int [QName] [QName] [QName] String String

-- | Versioned contract shared by the ordinary static program and the mixed
-- residual static shell.  Treeless does not distinguish record constructors
-- from data constructors, so both deliberately use the same tagged-vector
-- representation.  The declared value is kept separate from the lowering
-- implementation so a producer cannot silently publish a new ABI under the
-- old version label.
data ChezCoreAbi = ChezCoreAbi
  { chezCoreAbiVersion :: String
  , chezCoreAbiQName :: String
  , chezCoreAbiFunction :: String
  , chezCoreAbiDataConstructor :: String
  , chezCoreAbiRecord :: String
  , chezCoreAbiConstructorTagIndex :: Int
  , chezCoreAbiConstructorFieldBaseIndex :: Int
  , chezCoreAbiPrimitiveApplication :: String
  , chezCoreAbiPrimitiveFirstClass :: String
  }
  deriving (Eq)

data ChezPrimitiveForm
  = ChezPrimitiveBinary String
  | ChezPrimitiveIf
  | ChezPrimitiveBegin
  | ChezPrimitiveIdentity

chezPrimitiveApplicationTable :: [(TPrim, Int, ChezPrimitiveForm)]
chezPrimitiveApplicationTable =
#if defined(CUBICAL_CHEZ_TEST_CORE_ABI_PRIMITIVE_DRIFT)
  [ (PAdd, 2, ChezPrimitiveBinary "-")
#else
  [ (PAdd, 2, ChezPrimitiveBinary "+")
#endif
  , (PAdd64, 2, ChezPrimitiveBinary "+")
  , (PSub, 2, ChezPrimitiveBinary "-")
  , (PSub64, 2, ChezPrimitiveBinary "-")
  , (PMul, 2, ChezPrimitiveBinary "*")
  , (PMul64, 2, ChezPrimitiveBinary "*")
  , (PQuot, 2, ChezPrimitiveBinary "quotient")
  , (PQuot64, 2, ChezPrimitiveBinary "quotient")
  , (PRem, 2, ChezPrimitiveBinary "remainder")
  , (PRem64, 2, ChezPrimitiveBinary "remainder")
  , (PGeq, 2, ChezPrimitiveBinary ">=")
  , (PLt, 2, ChezPrimitiveBinary "<")
  , (PLt64, 2, ChezPrimitiveBinary "<")
  , (PEqI, 2, ChezPrimitiveBinary "=")
  , (PEq64, 2, ChezPrimitiveBinary "=")
  , (PEqF, 2, ChezPrimitiveBinary "=")
  , (PEqS, 2, ChezPrimitiveBinary "string=?")
  , (PEqC, 2, ChezPrimitiveBinary "char=?")
  , (PIf, 3, ChezPrimitiveIf)
  , (PSeq, 2, ChezPrimitiveBegin)
  , (PITo64, 1, ChezPrimitiveIdentity)
  , (P64ToI, 1, ChezPrimitiveIdentity)
  ]

chezPrimitiveFirstClassTable :: [(TPrim, String)]
chezPrimitiveFirstClassTable =
  [ (PAdd, "+")
  , (PSub, "-")
  , (PMul, "*")
  ]

renderChezPrimitiveFormAbi :: ChezPrimitiveForm -> String
renderChezPrimitiveFormAbi = \case
  ChezPrimitiveBinary operator -> operator
  ChezPrimitiveIf -> "if"
  ChezPrimitiveBegin -> "begin"
  ChezPrimitiveIdentity -> "identity"

renderChezPrimitiveApplicationMap :: String
renderChezPrimitiveApplicationMap = intercalate "," $
  [ show primitive ++ "/" ++ show arity ++ "="
      ++ renderChezPrimitiveFormAbi form
  | (primitive, arity, form) <- chezPrimitiveApplicationTable
  ]

renderChezPrimitiveFirstClassMap :: String
renderChezPrimitiveFirstClassMap = intercalate "," $
  [ show primitive ++ "=curried:" ++ operator
  | (primitive, operator) <- chezPrimitiveFirstClassTable
  ]

expectedChezPrimitiveApplicationMap :: String
expectedChezPrimitiveApplicationMap =
  "PAdd/2=+,PAdd64/2=+,PSub/2=-,PSub64/2=-,PMul/2=*,PMul64/2=*"
    ++ ",PQuot/2=quotient,PQuot64/2=quotient,PRem/2=remainder"
    ++ ",PRem64/2=remainder,PGeq/2=>=,PLt/2=<,PLt64/2=<,PEqI/2=="
    ++ ",PEq64/2==,PEqF/2==,PEqS/2=string=?,PEqC/2=char=?"
    ++ ",PIf/3=if,PSeq/2=begin,PITo64/1=identity,P64ToI/1=identity"

expectedChezPrimitiveFirstClassMap :: String
expectedChezPrimitiveFirstClassMap =
  "PAdd=curried:+,PSub=curried:-,PMul=curried:*"

implementedChezCoreAbi :: ChezCoreAbi
implementedChezCoreAbi = ChezCoreAbi
  { chezCoreAbiVersion = "chez-core-abi-v1"
  , chezCoreAbiQName = "agda-prefix+non-alphanumeric-codepoint-hex-v1"
  , chezCoreAbiFunction = "unary-curried-closure-v1"
  , chezCoreAbiDataConstructor = "tagged-vector-v1"
  , chezCoreAbiRecord = "tagged-vector-v1"
  , chezCoreAbiConstructorTagIndex = 0
  , chezCoreAbiConstructorFieldBaseIndex = 1
  , chezCoreAbiPrimitiveApplication = "exact-arity-whitelist-v1"
  , chezCoreAbiPrimitiveFirstClass = "curried-add-sub-mul-v1"
  }

declaredChezCoreAbi :: ChezCoreAbi
#if defined(CUBICAL_CHEZ_TEST_CORE_ABI_MISMATCH)
declaredChezCoreAbi = implementedChezCoreAbi
  { chezCoreAbiFunction = "uncurried-closure-v0"
  }
#else
declaredChezCoreAbi = implementedChezCoreAbi
#endif

validateChezCoreAbi :: Either String ()
validateChezCoreAbi
  | declaredChezCoreAbi /= implementedChezCoreAbi = Left $
      "declared Chez core ABI does not match the lowering implementation"
  | renderChezPrimitiveApplicationMap /=
      expectedChezPrimitiveApplicationMap = Left $
      "Chez core ABI v1 primitive application map changed without a version bump"
  | renderChezPrimitiveFirstClassMap /=
      expectedChezPrimitiveFirstClassMap = Left $
      "Chez core ABI v1 first-class primitive map changed without a version bump"
  | otherwise = Right ()

renderChezCoreAbiManifest :: [String]
renderChezCoreAbiManifest =
  [ "chez-core-abi: " ++ chezCoreAbiVersion declaredChezCoreAbi
  , "chez-qname-abi: " ++ chezCoreAbiQName declaredChezCoreAbi
  , "chez-function-abi: " ++ chezCoreAbiFunction declaredChezCoreAbi
  , "chez-data-constructor-abi: "
      ++ chezCoreAbiDataConstructor declaredChezCoreAbi
  , "chez-record-abi: " ++ chezCoreAbiRecord declaredChezCoreAbi
  , "chez-constructor-tag-index: "
      ++ show (chezCoreAbiConstructorTagIndex declaredChezCoreAbi)
  , "chez-constructor-field-base-index: "
      ++ show (chezCoreAbiConstructorFieldBaseIndex declaredChezCoreAbi)
  , "chez-primitive-application-abi: "
      ++ chezCoreAbiPrimitiveApplication declaredChezCoreAbi
  , "chez-primitive-application-map: "
      ++ renderChezPrimitiveApplicationMap
  , "chez-primitive-first-class-abi: "
      ++ chezCoreAbiPrimitiveFirstClass declaredChezCoreAbi
  , "chez-primitive-first-class-map: "
      ++ renderChezPrimitiveFirstClassMap
  ]

data StaticEngine
  = AgdaBaseline
  | MatureNbe
  | NbeAdapterSpike

data EngineRequest = EngineRequest
  { requestTerm :: Term
  , requestType :: Type
  }

data EngineResult = EngineResult
  { resultNormalTerm :: Term
  , resultNormalType :: Type
  }

data EngineAttempt
  = EngineSucceeded StaticEngine [String] EngineStageBreakdown EngineResult
  | EngineUnsupported StaticEngine [String] EngineStageBreakdown String

data EngineStageBreakdown = EngineStageBreakdown
  { engineEvaluationNanoseconds :: Maybe Word64
  , engineReadbackNanoseconds :: Maybe Word64
  }

data EngineExecution = EngineExecution
  { executionResult :: EngineResult
  , executionRequestedEngine :: String
  , executionEffectiveEngine :: String
  , executionFallbackPolicy :: String
  , executionFallbackUsed :: Bool
  , executionFallbackReason :: String
  , executionEngineEvidence :: [String]
  , executionEngineTotalNanoseconds :: Word64
  , executionNbeEvaluationNanoseconds :: Maybe Word64
  , executionNbeReadbackNanoseconds :: Maybe Word64
  , executionResultAdmissionNanoseconds :: Word64
  }

#if defined(CUBICAL_CHEZ_AGDA_29)
-- This is intentionally byte-compatible with the v2 runtime archive.
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
#endif

expectedRuntimePacketMagic :: String
expectedRuntimePacketMagic = "agda-cubical-runtime-term"

expectedRuntimePacketVersion :: Word64
expectedRuntimePacketVersion = 2

-- Test-only variants deliberately encode a bad header.  The verifier builds
-- them as separate executables and proves that the producer self-check fails
-- before publishing a packet.
runtimePacketMagic :: String
#if defined(CUBICAL_CHEZ_TEST_BAD_MAGIC)
runtimePacketMagic = "invalid-cubical-runtime-term"
#else
runtimePacketMagic = expectedRuntimePacketMagic
#endif

runtimePacketVersion :: Word64
#if defined(CUBICAL_CHEZ_TEST_BAD_VERSION)
runtimePacketVersion = expectedRuntimePacketVersion + 1
#else
runtimePacketVersion = expectedRuntimePacketVersion
#endif

packetCodecName :: String
#if defined(CUBICAL_CHEZ_AGDA_29)
packetCodecName = "agda-utils-serialize"
#else
packetCodecName = "unavailable-agda-2.8-development-build"
#endif

type ChezModule = [CompiledDef]

chezBackend :: Backend
chezBackend = Backend chezBackend'

chezBackend' :: Backend' ChezOptions ChezOptions () ChezModule (Maybe CompiledDef)
chezBackend' = Backend'
  { backendName = "CubicalChez"
  , backendVersion = Just "0.1.0-dev"
  , options = ChezOptions
      { chezEnabled = False
      , chezEngine = "agda-baseline"
      , chezNbeFallback = "reject"
      , chezResidualPolicy = "reject"
      , chezPacketFile = Nothing
      , chezOutputDirectory = "build" </> "formal-generated"
      , chezEntry = "main"
      }
  , commandLineFlags =
      [ Option [] ["cubical-chez"] (NoArg enable)
          "compile with the staged Cubical Chez backend"
      , Option [] ["cubical-chez-engine"] (ReqArg setEngine "ENGINE")
          "static engine: agda-baseline or nbe"
      , Option [] ["cubical-chez-nbe-fallback"] (ReqArg setNbeFallback "POLICY")
          "on NbE unsupported feature: reject or agda-baseline"
      , Option [] ["cubical-chez-residual"] (ReqArg setResidualPolicy "POLICY")
          "typed residual policy: reject, manifest, or packet"
      , Option [] ["cubical-chez-packet-file"] (ReqArg setPacketFile "FILE")
          "packet destination override; use - for stdout"
      , Option [] ["cubical-chez-output"] (ReqArg setOutputDirectory "DIRECTORY")
          "output directory for Scheme, staging reports, and diagnostics"
      , Option [] ["cubical-chez-entry"] (ReqArg setEntry "NAME")
          "entry definition: unqualified name or fully qualified QName"
      ]
  , isEnabled = chezEnabled
  , preCompile = validateOptions
  , postCompile = writeProgram
  , preModule = \_ _ _ _ -> pure (Recompile ())
  , postModule = \_ _ _ _ defs -> pure (catMaybes defs)
  , compileDef = compileDefinition
  , scopeCheckingSuffices = False
  , mayEraseType = const (pure True)
  , backendInteractTop = Nothing
  , backendInteractHole = Nothing
  }
  where
    enable opts = pure opts {chezEnabled = True}
    setEngine engine opts = pure opts {chezEngine = engine}
    setNbeFallback policy opts = pure opts {chezNbeFallback = policy}
    setResidualPolicy policy opts = pure opts {chezResidualPolicy = policy}
    setPacketFile file opts = pure opts {chezPacketFile = Just file}
    setOutputDirectory directory opts = pure opts {chezOutputDirectory = directory}
    setEntry entry opts = pure opts {chezEntry = entry}

validateOptions :: ChezOptions -> TCM ChezOptions
validateOptions opts = do
  -- A rejected invocation must not leave a stale successful publication that
  -- can be mistaken for its output.  An empty output path has no safe cleanup
  -- target, so that invalid case is rejected below without deleting anything.
  when (not $ null $ chezOutputDirectory opts) $
    liftIO $ clearPublishedArtifacts opts
  validateOptionsAfterCleanup opts

validateOptionsAfterCleanup :: ChezOptions -> TCM ChezOptions
validateOptionsAfterCleanup opts
  | chezEngine opts `notElem` ["agda-baseline", "nbe"] =
      backendAbortWith InvalidConfiguration $
        "unknown static engine " ++ show (chezEngine opts)
  | chezResidualPolicy opts `notElem` ["reject", "manifest", "packet"] =
      backendAbortWith InvalidConfiguration $
        "unknown typed residual policy " ++ show (chezResidualPolicy opts)
  | chezNbeFallback opts `notElem` ["reject", "agda-baseline", "typed-residual"] =
      backendAbortWith InvalidConfiguration $
        "unknown NbE fallback policy " ++ show (chezNbeFallback opts)
  | chezEngine opts /= "nbe"
  , chezNbeFallback opts /= "reject" =
      backendAbortWith InvalidConfiguration
        "a non-reject NbE fallback requires --cubical-chez-engine=nbe"
  | Just packetFile <- chezPacketFile opts
  , null packetFile = backendAbortWith InvalidConfiguration
      "packet destination must not be empty"
  | Just _ <- chezPacketFile opts
  , chezResidualPolicy opts /= "packet" =
      backendAbortWith InvalidConfiguration
        "--cubical-chez-packet-file requires --cubical-chez-residual=packet"
  | null (chezOutputDirectory opts) =
      backendAbortWith InvalidConfiguration "output directory must not be empty"
  | null (chezEntry opts) =
      backendAbortWith InvalidConfiguration "entry definition must not be empty"
  | otherwise = pure opts

compileDefinition :: ChezOptions -> () -> IsMain -> Definition -> TCM (Maybe CompiledDef)
compileDefinition opts _ isMain def = case theDef def of
  Function {funClauses = [clause]}
    | isMain == IsMain
    , isRequestedEntryName (chezEntry opts) (defName def)
    , null (telToList (clauseTel clause))
    , Just body <- clauseBody clause -> do
        engineExecution <- normalizeEntry opts $ EngineRequest
          { requestTerm = body
          , requestType = defType def
          }
        let engineResult = executionResult engineExecution
            normalized = resultNormalTerm engineResult
            normalizedType = resultNormalType engineResult
        ((internalTermAudit, internalTypeAudit), internalAuditNanoseconds) <-
          measureTcmStage $ do
            termAudit <- auditTypedInternal normalized
            typeAudit <- auditTypedInternal normalizedType
            pure (termAudit, typeAudit)
        let internalTermBlockers = internalSemanticBlockers internalTermAudit
            internalTypeBlockers = internalSemanticBlockers internalTypeAudit
            internalTermUnknownCubical =
              internalUnknownCubicalPrimitives internalTermAudit
            internalTypeUnknownCubical =
              internalUnknownCubicalPrimitives internalTypeAudit
        (compiled, treelessNanoseconds) <- measureTcmStage $
          compileClosedTerm normalized

        let treelessBlockers = testTreelessBlockers (typedTreelessBlockers compiled)
            treelessUnknownCubical = typedTreelessUnknownCubical compiled
            blockers = mergeBlockers internalTermBlockers treelessBlockers
            unknownCubical = mergeBlockers
              internalTermUnknownCubical
              treelessUnknownCubical
            typedResidualPassthrough =
              "nbe-unsupported-disposition: typed-residual-passthrough-v1"
                `elem` executionEngineEvidence engineExecution
            (bindingTime, bindingReason)
              | typedResidualPassthrough =
                  (BindingDynamic, WholeEntryRuntimeHead)
              | otherwise = classifyBindingTime
                  internalTermBlockers
                  treelessBlockers
                  internalTermUnknownCubical
                  treelessUnknownCubical
                  (internalSemanticCatalogDisagreements internalTermAudit)
                  compiled
            typedResidual
              | null blockers && null unknownCubical
              , not typedResidualPassthrough = Nothing
              | otherwise = Just TypedResidual
                  { residualTerm = normalized
                  , residualType = normalizedType
                  , residualDirectDependencies = residualDependencyNames
                      normalized
                      normalizedType
                  }
        pure $ Just CompiledDef
          { compiledName = defName def
          , compiledTerm = compiled
          , compiledFromMainModule = True
          , compiledIsEntry = True
          , compiledInternalTermBlockers = internalTermBlockers
          , compiledInternalTypeBlockers = internalTypeBlockers
          , compiledInternalTermCatalogBlockers =
              internalCatalogBlockers internalTermAudit
          , compiledInternalTypeCatalogBlockers =
              internalCatalogBlockers internalTypeAudit
          , compiledInternalTermSemanticSources =
              internalSemanticSources internalTermAudit
          , compiledInternalTypeSemanticSources =
              internalSemanticSources internalTypeAudit
          , compiledInternalTermSemanticCatalogDisagreements =
              internalSemanticCatalogDisagreements internalTermAudit
          , compiledInternalTypeSemanticCatalogDisagreements =
              internalSemanticCatalogDisagreements internalTypeAudit
          , compiledTreelessBlockers = treelessBlockers
          , compiledInternalTermUnknownCubical = internalTermUnknownCubical
          , compiledInternalTypeUnknownCubical = internalTypeUnknownCubical
          , compiledTreelessUnknownCubical = treelessUnknownCubical
          , compiledBindingTime = bindingTime
          , compiledBindingReason = bindingReason
          , compiledRequestedEngine = executionRequestedEngine engineExecution
          , compiledEffectiveEngine = executionEffectiveEngine engineExecution
          , compiledNbeFallbackPolicy = executionFallbackPolicy engineExecution
          , compiledNbeFallbackUsed = executionFallbackUsed engineExecution
          , compiledNbeFallbackReason = executionFallbackReason engineExecution
          , compiledEngineEvidence = executionEngineEvidence engineExecution
          , compiledTypedResidual = typedResidual
          , compiledEngineTotalNanoseconds =
              executionEngineTotalNanoseconds engineExecution
          , compiledNbeEvaluationNanoseconds =
              executionNbeEvaluationNanoseconds engineExecution
          , compiledNbeReadbackNanoseconds =
              executionNbeReadbackNanoseconds engineExecution
          , compiledResultAdmissionNanoseconds =
              executionResultAdmissionNanoseconds engineExecution
          , compiledInternalAuditNanoseconds = internalAuditNanoseconds
          , compiledTreelessNanoseconds = treelessNanoseconds
          }
  FunctionDefn {}
    | isMain == IsMain
    , isRequestedEntryName (chezEntry opts) (defName def) ->
        backendAbortWith EntryRejected $
          "entry definition must have one closed, argument-free clause: "
          ++ prettyShow (defName def)
  -- A non-default entry is an explicit closed-entry acceptance request.  Its
  -- normalized body must therefore be self-contained.  Avoid converting the
  -- complete imported signature to Treeless; if a definition reference does
  -- survive normalization, the existing unresolved-closure gate rejects it.
  FunctionDefn {}
    | chezEntry opts /= "main" -> pure Nothing
  FunctionDefn {} -> do
    term <- toTreeless EagerEvaluation (defName def)
    pure $ fmap (\compiled -> CompiledDef
      { compiledName = defName def
      , compiledTerm = compiled
      , compiledFromMainModule = isMain == IsMain
      , compiledIsEntry = False
      , compiledInternalTermBlockers = []
      , compiledInternalTypeBlockers = []
      , compiledInternalTermCatalogBlockers = []
      , compiledInternalTypeCatalogBlockers = []
      , compiledInternalTermSemanticSources = []
      , compiledInternalTypeSemanticSources = []
      , compiledInternalTermSemanticCatalogDisagreements = []
      , compiledInternalTypeSemanticCatalogDisagreements = []
      , compiledTreelessBlockers = []
      , compiledInternalTermUnknownCubical = []
      , compiledInternalTypeUnknownCubical = []
      , compiledTreelessUnknownCubical = []
      , compiledBindingTime = BindingStatic
      , compiledBindingReason = NoRuntimeBlockers
      , compiledRequestedEngine = chezEngine opts
      , compiledEffectiveEngine = chezEngine opts
      , compiledNbeFallbackPolicy = chezNbeFallback opts
      , compiledNbeFallbackUsed = False
      , compiledNbeFallbackReason = "none"
      , compiledEngineEvidence = []
      , compiledTypedResidual = Nothing
      , compiledEngineTotalNanoseconds = 0
      , compiledNbeEvaluationNanoseconds = Nothing
      , compiledNbeReadbackNanoseconds = Nothing
      , compiledResultAdmissionNanoseconds = 0
      , compiledInternalAuditNanoseconds = 0
      , compiledTreelessNanoseconds = 0
      }) term
  _ -> pure Nothing

compileClosedTerm :: Term -> TCM TTerm
compileClosedTerm = closedTermToTreeless
#if defined(CUBICAL_CHEZ_AGDA_29)
  (mkDefaultCCConfig EagerEvaluation)
#else
  (EagerEvaluation, EraseUnused)
#endif

measureTcmStage :: TCM value -> TCM (value, Word64)
measureTcmStage action = do
  started <- liftIO getMonotonicTimeNSec
  value <- action
  finished <- liftIO getMonotonicTimeNSec
  pure (value, finished - started)

-- | Typed engine request/result boundary.  The baseline and the future NbE
-- adapter must both return a normal form paired with its normalized type.
normalizeEntry :: ChezOptions -> EngineRequest -> TCM EngineExecution
normalizeEntry opts request = case parseStaticEngine (chezEngine opts) of
  Left problem -> backendAbortWith InvalidConfiguration problem
  Right engine -> do
    (attempt, requestedEngineNanoseconds) <-
      measureTcmStage $ runStaticEngine engine request
    case attempt of
      EngineSucceeded effective evidence breakdown result -> do
        (preserveTypedResult, resultTypeAuditNanoseconds) <-
          measureTcmStage $
            requiresTypedResidualResultType evidence result
        if preserveTypedResult
          then finish
            effective
            True
            "nbe-result-type-typed-residual"
            ( evidence ++
              [ "nbe-unsupported-disposition: typed-residual-passthrough-v1"
              , "nbe-typed-residual-trigger: result-type-runtime-blocker-v1"
              ]
            )
            breakdown
            requestedEngineNanoseconds
            resultTypeAuditNanoseconds
            EngineResult
              { resultNormalTerm = requestTerm request
              , resultNormalType = requestType request
              }
          else finish effective False "none" evidence breakdown
            requestedEngineNanoseconds resultTypeAuditNanoseconds result
      EngineUnsupported unsupportedEngine evidence breakdown problem -> case chezNbeFallback opts of
        "reject" -> backendAbortWith NbeUnsupportedFeature problem
        "agda-baseline" -> do
          (result, fallbackEngineNanoseconds) <-
            measureTcmStage $ runAgdaBaseline request
          finish AgdaBaseline True "nbe-unsupported-feature" []
            emptyEngineStageBreakdown fallbackEngineNanoseconds 0 result
        "typed-residual"
          | "nbe-adapter-implementation: agda-specific-in-process-v1"
              `elem` evidence ->
              finish
                unsupportedEngine
                True
                "nbe-unsupported-typed-residual"
                ( evidence ++
                  [ "nbe-unsupported-disposition: typed-residual-passthrough-v1"
                  ]
                )
                (unsupportedStageBreakdown
                  unsupportedEngine breakdown requestedEngineNanoseconds)
                requestedEngineNanoseconds
                0
                EngineResult
                  { resultNormalTerm = requestTerm request
                  , resultNormalType = requestType request
                  }
          | otherwise -> backendAbortWith NbeUnavailable $
              "typed-residual preservation requires a linked NbE adapter"
        policy -> backendAbortWith InvalidConfiguration $
          "unknown NbE fallback policy " ++ show policy
  where
    requiresTypedResidualResultType evidence result
      | chezNbeFallback opts /= "typed-residual" = pure False
      | "nbe-adapter-implementation: agda-specific-in-process-v1"
          `notElem` evidence = pure False
      | otherwise = do
          resultTypeAudit <- auditTypedInternal (resultNormalType result)
          pure $
            not (null (internalSemanticBlockers resultTypeAudit)) ||
            not (null (internalUnknownCubicalPrimitives resultTypeAudit)) ||
            not
              (null
                (internalSemanticCatalogDisagreements resultTypeAudit))
    finish effectiveEngine fallbackUsed fallbackReason evidence breakdown
      engineNanoseconds preliminaryAdmissionNanoseconds result = do
      (checked, validationNanoseconds) <- measureTcmStage $
        validateEngineResult (testEngineResult result)
      pure EngineExecution
        { executionResult = checked
        , executionRequestedEngine = chezEngine opts
        , executionEffectiveEngine = renderStaticEngine effectiveEngine
        , executionFallbackPolicy = chezNbeFallback opts
        , executionFallbackUsed = fallbackUsed
        , executionFallbackReason = fallbackReason
        , executionEngineEvidence = evidence
        , executionEngineTotalNanoseconds = engineNanoseconds
        , executionNbeEvaluationNanoseconds =
            engineEvaluationNanoseconds breakdown
        , executionNbeReadbackNanoseconds =
            engineReadbackNanoseconds breakdown
        , executionResultAdmissionNanoseconds =
            preliminaryAdmissionNanoseconds + validationNanoseconds
        }

emptyEngineStageBreakdown :: EngineStageBreakdown
emptyEngineStageBreakdown = EngineStageBreakdown
  { engineEvaluationNanoseconds = Nothing
  , engineReadbackNanoseconds = Nothing
  }

unsupportedStageBreakdown
  :: StaticEngine
  -> EngineStageBreakdown
  -> Word64
  -> EngineStageBreakdown
unsupportedStageBreakdown MatureNbe breakdown totalNanoseconds
  | Nothing <- engineEvaluationNanoseconds breakdown
  , Nothing <- engineReadbackNanoseconds breakdown = EngineStageBreakdown
      { engineEvaluationNanoseconds = Just totalNanoseconds
      , engineReadbackNanoseconds = Nothing
      }
unsupportedStageBreakdown _ breakdown _ = breakdown

parseStaticEngine :: String -> Either String StaticEngine
parseStaticEngine = \case
  "agda-baseline" -> Right AgdaBaseline
  "nbe" -> Right MatureNbe
  engine -> Left $ "unknown static engine " ++ show engine

renderStaticEngine :: StaticEngine -> String
renderStaticEngine = \case
  AgdaBaseline -> "agda-baseline"
  MatureNbe -> "nbe"
  NbeAdapterSpike -> "nbe-spike-test-only"

runStaticEngine :: StaticEngine -> EngineRequest -> TCM EngineAttempt
runStaticEngine = \case
  AgdaBaseline ->
    fmap (EngineSucceeded AgdaBaseline [] emptyEngineStageBreakdown) .
      runAgdaBaseline
  MatureNbe -> \request -> request `seq`
#if defined(CUBICAL_CHEZ_TEST_ENGINE_TIMEOUT)
    backendAbortWith EngineTimeout
      "the NbE engine exceeded its configured evaluation deadline"
#elif defined(CUBICAL_CHEZ_TEST_NBE_FAILURE)
    backendAbortWith NbeExecutionFailed
      "the NbE engine failed while evaluating the checked request"
#elif defined(CUBICAL_CHEZ_TEST_NBE_UNSUPPORTED)
    pure $ EngineUnsupported MatureNbe [] emptyEngineStageBreakdown
      "the NbE adapter reported an unsupported feature in the checked request"
#elif defined(CUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE) && !defined(CUBICAL_CHEZ_NBE_PROVIDER_SELECTED) && !defined(CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE)
    backendAbortWith NbeUnavailable $ unlines
      [ "the in-process NbE production candidate is linked but not selected"
      , "Linked adapter identity: " ++ NbeSpike.spikeProviderIdentity
      , "Validate a selected provider lock before supplying the production selection build key."
      ]
#elif defined(CUBICAL_CHEZ_NBE_PROVIDER_SELECTED) && !defined(CUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE) && !defined(CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE)
    backendAbortWith NbeUnavailable $ unlines
      [ "the NbE provider selection build key is present but no adapter is linked"
      , "The two-key gate requires the in-process adapter candidate in the same build."
      ]
#elif defined(CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE) || (defined(CUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE) && defined(CUBICAL_CHEZ_NBE_PROVIDER_SELECTED))
    NbeSpike.normalizeRequestSpike
      (requestTerm request)
      (requestType request) >>= \case
      NbeSpike.SpikeSucceeded report -> do
        pure $ EngineSucceeded
#if defined(CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE)
          NbeAdapterSpike
#else
          MatureNbe
#endif
          [ "nbe-adapter-implementation: " ++ NbeSpike.spikeProviderIdentity
#if defined(CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE)
          , "nbe-adapter-linkage: test-only"
          , "nbe-provider-lock-status: not-applicable-test-only"
#else
          , "nbe-adapter-linkage: production-candidate"
          , "nbe-provider-lock-status: selected-build-key"
#endif
          , "nbe-definition-cache: per-request-qname-v1"
          , "nbe-definition-cache-hits: "
              ++ show (NbeSpike.spikeDefinitionCacheHits report)
          , "nbe-definition-cache-misses: "
              ++ show (NbeSpike.spikeDefinitionCacheMisses report)
          , "nbe-recursion-cycle-policy: ground-call-shape-v1"
          , "nbe-maximum-call-depth: "
              ++ show (NbeSpike.spikeMaximumCallDepth report)
          , "nbe-type-nodes-evaluated: "
              ++ show (NbeSpike.spikeTypeNodesEvaluated report)
          , "nbe-sort-nodes-evaluated: "
              ++ show (NbeSpike.spikeSortNodesEvaluated report)
          , "nbe-level-nodes-evaluated: "
              ++ show (NbeSpike.spikeLevelNodesEvaluated report)
          , "nbe-record-projections-evaluated: "
              ++ show (NbeSpike.spikeRecordProjectionsEvaluated report)
          , "nbe-neutral-record-type-heads-preserved: "
              ++ show
                (NbeSpike.spikeNeutralRecordTypeHeadsPreserved report)
          , "nbe-neutral-data-type-heads-preserved: "
              ++ show
                (NbeSpike.spikeNeutralDataTypeHeadsPreserved report)
          , "nbe-definitions-reduced: "
              ++ show (NbeSpike.spikeDefinitionsReduced report)
          , "nbe-hit-definition-patterns-matched: "
              ++ show (NbeSpike.spikeHitDefinitionPatternsMatched report)
          , "nbe-maximum-level-atom-count: "
              ++ show (NbeSpike.spikeMaximumLevelAtomCount report)
          , "nbe-primitive-registry-hits: "
              ++ show (NbeSpike.spikePrimitiveRegistryHits report)
          , "nbe-primitives-reduced: "
              ++ show (NbeSpike.spikePrimitivesReduced report)
          , "nbe-interval-operations-evaluated: "
              ++ show (NbeSpike.spikeIntervalOperationsEvaluated report)
          , "nbe-neutral-cofibration-simplifications: "
              ++ show
                (NbeSpike.spikeNeutralCofibrationSimplifications report)
          , "nbe-path-applications-evaluated: "
              ++ show (NbeSpike.spikePathApplicationsEvaluated report)
          , "nbe-comps-expanded: "
              ++ show (NbeSpike.spikeCompsExpanded report)
          , "nbe-transports-reduced: "
              ++ show (NbeSpike.spikeTransportsReduced report)
          , "nbe-constant-nat-transports-reduced: "
              ++ show
                (NbeSpike.spikeConstantNatTransportsReduced report)
          , "nbe-constant-nat-function-transports-reduced: "
              ++ show
                (NbeSpike.spikeConstantNatFunctionTransportsReduced report)
          , "nbe-universe-transports-reduced: "
              ++ show (NbeSpike.spikeUniverseTransportsReduced report)
          , "nbe-glue-transports-reduced: "
              ++ show (NbeSpike.spikeGlueTransportsReduced report)
          , "nbe-backward-glue-transports-reduced: "
              ++ show (NbeSpike.spikeBackwardGlueTransportsReduced report)
          , "nbe-composed-glue-transports-reduced: "
              ++ show
                (NbeSpike.spikeComposedGlueTransportsReduced report)
          , "nbe-pi-transports-reduced: "
              ++ show (NbeSpike.spikePiTransportsReduced report)
          , "nbe-varying-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeVaryingPiCodomainTransportsReduced report)
          , "nbe-semantic-constant-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeSemanticConstantPiCodomainTransportsReduced report)
          , "nbe-dependent-self-path-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeDependentSelfPathPiCodomainTransportsReduced report)
          , "nbe-dependent-singleton-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeDependentSingletonPiCodomainTransportsReduced report)
          , "nbe-dependent-reversed-singleton-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeDependentReversedSingletonPiCodomainTransportsReduced report)
          , "nbe-dependent-nested-singleton-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeDependentNestedSingletonPiCodomainTransportsReduced report)
          , "nbe-dependent-reversed-nested-singleton-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeDependentReversedNestedSingletonPiCodomainTransportsReduced report)
          , "nbe-dependent-sigma-spine-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeDependentSigmaSpinePiCodomainTransportsReduced report)
          , "nbe-dependent-reversed-sigma-spine-pi-codomain-transports-reduced: "
              ++ show
                (NbeSpike.spikeDependentReversedSigmaSpinePiCodomainTransportsReduced report)
          , "nbe-dependent-sigma-spine-fields-transported: "
              ++ show
                (NbeSpike.spikeDependentSigmaSpineFieldsTransported report)
          , "nbe-dependent-sigma-spine-stable-fields-preserved: "
              ++ show
                (NbeSpike.spikeDependentSigmaSpineStableFieldsPreserved report)
          , "nbe-dependent-sigma-spine-indexed-pi-fields-transported: "
              ++ show
                (NbeSpike.spikeDependentSigmaSpineIndexedPiFieldsTransported report)
          , "nbe-indexed-pi-field-applications-evaluated: "
              ++ show
                (NbeSpike.spikeIndexedPiFieldApplicationsEvaluated report)
          , "nbe-indexed-pi-ground-payload-fields-preserved: "
              ++ show
                (NbeSpike.spikeIndexedPiGroundPayloadFieldsPreserved report)
          , "nbe-closed-stable-function-values-validated: "
              ++ show
                (NbeSpike.spikeClosedStableFunctionValuesValidated report)
          , "nbe-closed-stable-pi-type-views-validated: "
              ++ show
                (NbeSpike.spikeClosedStablePiTypeViewsValidated report)
          , "nbe-record-transports-reduced: "
              ++ show (NbeSpike.spikeRecordTransportsReduced report)
          , "nbe-data-transports-reduced: "
              ++ show (NbeSpike.spikeDataTransportsReduced report)
          , "nbe-glue-unglue-cancellations: "
              ++ show (NbeSpike.spikeGlueUnglueCancellations report)
          , "nbe-hcomps-reduced: "
              ++ show (NbeSpike.spikeHCompsReduced report)
          , "nbe-fuel-limit: " ++ show NbeSpike.spikeFuelLimit
          , "nbe-fuel-consumed: "
              ++ show (NbeSpike.spikeFuelConsumed report)
          ] EngineStageBreakdown
          { engineEvaluationNanoseconds =
              Just (NbeSpike.spikeEvaluationNanoseconds report)
          , engineReadbackNanoseconds =
              Just (NbeSpike.spikeReadbackNanoseconds report)
          } EngineResult
          { resultNormalTerm = NbeSpike.spikeNormalTerm report
          , resultNormalType = NbeSpike.spikeNormalType report
          }
      NbeSpike.SpikeUnsupported problem -> pure $ EngineUnsupported
#if defined(CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE)
        NbeAdapterSpike
        [ "nbe-adapter-implementation: " ++ NbeSpike.spikeProviderIdentity
        , "nbe-adapter-linkage: test-only"
        , "nbe-provider-lock-status: not-applicable-test-only"
        ]
#else
        MatureNbe
        [ "nbe-adapter-implementation: " ++ NbeSpike.spikeProviderIdentity
        , "nbe-adapter-linkage: production-candidate"
        , "nbe-provider-lock-status: selected-build-key"
        ]
#endif
        emptyEngineStageBreakdown
        problem
      NbeSpike.SpikeFuelExhausted problem ->
        backendAbortWith EngineTimeout problem
      NbeSpike.SpikeRecursiveCycle problem ->
        backendAbortWith NbeExecutionFailed problem
#else
    backendAbortWith NbeUnavailable $ unlines
    [ "the NbE adapter has not been configured"
    , "The two-key gate requires both a selected config/nbe-adapter.lock.tsv"
    , "and adapter code linked against engine-request-v1."
    , "Validate provider identity with make verify-nbe-adapter-contract."
    , "Select --cubical-chez-engine=agda-baseline only for baseline verification."
    ]
#endif
  NbeAdapterSpike -> \_ ->
    backendAbortWith InvalidConfiguration
      "the test-only NbE adapter spike cannot be selected through the CLI"

runAgdaBaseline :: EngineRequest -> TCM EngineResult
runAgdaBaseline request = do
  normalizedType <- normalise (requestType request)
  normalizedTerm <- baselineNormalise (requestTerm request) normalizedType
  pure EngineResult
    { resultNormalTerm = normalizedTerm
    , resultNormalType = normalizedType
    }

-- | No static evaluator is trusted to manufacture well-scoped Internal
-- syntax.  This gate is deliberately before Treeless conversion and type
-- erasure, so the future NbE adapter must return a closed, meta-free term/type
-- pair which Agda itself accepts in the current signature.
validateEngineResult :: EngineResult -> TCM EngineResult
validateEngineResult result = do
  let term = resultNormalTerm result
      ty = resultNormalType result
  unless (closed (term, ty)) $
    backendAbortWith EngineResultInvalid
      "static engine returned an open Term or Type"
  unless (noMetas (term, ty)) $
    backendAbortWith EngineResultInvalid
      "static engine returned unresolved metavariables"
  (do
      CheckInternal.checkType ty
      CheckInternal.checkInternal term CmpLeq ty
      pure result
    ) `catchError` \_ ->
      backendAbortWith EngineResultInvalid
        "static engine returned a Term/Type pair rejected by Agda"

-- Compile-time-only faults prove each engine-result gate.  They are built as
-- isolated verifier binaries and cannot be selected through the production
-- CLI.
testEngineResult :: EngineResult -> EngineResult
#if defined(CUBICAL_CHEZ_TEST_ENGINE_OPEN_TERM)
testEngineResult result = result
  { resultNormalTerm = Internal.Var 0 []
  }
#elif defined(CUBICAL_CHEZ_TEST_ENGINE_UNRESOLVED_META)
testEngineResult result = result
  { resultNormalTerm = Internal.MetaV (MetaId 0 noModuleNameHash) []
  }
#elif defined(CUBICAL_CHEZ_TEST_ENGINE_TYPE_MISMATCH)
testEngineResult result = result
  { resultNormalTerm = Internal.Lit (LitString "invalid engine result")
  }
#else
testEngineResult = id
#endif

-- | Type-directed top-level eta expansion from the v2 runtime, followed by
-- Agda's reducer.  This is the oracle/baseline against which the NbE adapter
-- will be checked.
baselineNormalise :: Term -> Type -> TCM Term
baselineNormalise term ty = do
  ty' <- reduce ty
  etaTerm <- isEtaRecordType ty' >>= \case
    Nothing -> pure term
    Just (recordName, parameters) -> do
      recordDef <- fromMaybe __IMPOSSIBLE__ <$> isRecord recordName
      expansion <- etaExpandRecord_ recordName parameters recordDef term
      pure $ etaExpansionTerm term expansion
  normalise etaTerm

-- Agda 2.8 returned the eta expansion directly, while Agda 2.9 wraps failure
-- in Maybe.  Keeping this tiny compatibility layer lets the standalone
-- vertical slice compile against 2.8 and the pinned delivery tree use 2.9.
class EtaExpansionResult result where
  etaExpansionTerm :: Term -> result -> Term

instance EtaExpansionResult (telescope, ConHead, ConInfo, Internal.Args) where
  etaExpansionTerm _ (_, con, info, args) = mkCon con info args

instance EtaExpansionResult (Maybe (telescope, ConHead, ConInfo, Internal.Args)) where
  etaExpansionTerm fallback = \case
    Nothing -> fallback
    Just (_, con, info, args) -> mkCon con info args

writeProgram :: ChezOptions -> IsMain -> Map.Map TopLevelModuleName ChezModule -> TCM ()
writeProgram opts _ modules = do
  let defs = concat (Map.elems modules)
      outputDirectory = chezOutputDirectory opts
      schemePath = outputDirectory </> "program.ss"
      dumpPath = outputDirectory </> "treeless.txt"
      stagingPath = outputDirectory </> "staging.txt"
      residualPath = outputDirectory </> "typed-residual.txt"
      defaultPacketPath = outputDirectory </> "typed-residual.bin"
      stageTimingsPath = outputDirectory </> stageTimingsName
      staticShellPath = outputDirectory </> residualStaticShellName
      groundBridgePath = outputDirectory </> typedHoleGroundBridgeName
      packetPath = fromMaybe defaultPacketPath (chezPacketFile opts)
  liftIO $ do
    createDirectoryIfMissing True outputDirectory
    removeIfExists schemePath
    removeIfExists residualPath
    removeIfExists defaultPacketPath
    removeIfExists stageTimingsPath
    removeIfExists staticShellPath
    removeIfExists groundBridgePath
    removePacketIfExists packetPath
    clearResidualHolePackets outputDirectory
  entry <- either (backendAbortWith EntryRejected) pure (findEntry opts defs)
  case compiledTypedResidual entry of
    Just residual -> do
      liftIO $ writeFile stagingPath
        (renderStaging opts entry StaticClosureNotApplicable)
      runTimedPublication stageTimingsPath entry "residualization" $
        handleTypedResidual opts residualPath packetPath entry residual
    Nothing -> runTimedPublication
      stageTimingsPath entry "scheme-codegen-publication" $
        case proveStaticClosure defs entry of
          Left failure -> do
            liftIO $ do
              writeFile dumpPath $ renderDump
                (staticClosureFailureDefinitions failure)
                (staticClosureFailureUnresolved failure)
              writeFile stagingPath $ renderStaging opts entry $
                StaticClosureIncomplete
                  (length $ staticClosureFailureDefinitions failure)
                  (staticClosureFailureUnresolved failure)
                  (staticClosureFailureBlockers failure)
                  (staticClosureFailureUnknownCubical failure)
                  (staticClosureFailureReason failure)
                  (staticClosureFailureLowering failure)
            backendAbortWith (staticClosureFailureClass failure)
              (staticClosureFailureProblem failure)
          Right closure -> liftIO $ do
            writeFile dumpPath
              (renderDump (staticClosureDefinitions closure) [])
            writeFile stagingPath $ renderStaging opts entry $
              StaticClosureComplete (length $ staticClosureDefinitions closure)
            writeFile schemePath (staticClosureProgram closure)

runTimedPublication
  :: FilePath
  -> CompiledDef
  -> String
  -> TCM ()
  -> TCM ()
runTimedPublication stageTimingsPath entry publicationStage action = do
  (outcome, publicationNanoseconds) <- measureTcmStage $
    (Right <$> action) `catchError` (pure . Left)
  liftIO $ writeFile stageTimingsPath $
    renderStageTimings entry publicationStage publicationNanoseconds
  either throwError pure outcome

renderStageTimings :: CompiledDef -> String -> Word64 -> String
renderStageTimings entry publicationStage publicationNanoseconds = unlines $
  [ "stage\telapsed_nanoseconds\tstatus"
  , numeric "engine-total" $ compiledEngineTotalNanoseconds entry
  , optional "nbe-evaluation" $ compiledNbeEvaluationNanoseconds entry
  , optional "nbe-readback" $ compiledNbeReadbackNanoseconds entry
  , numeric "engine-result-admission" $
      compiledResultAdmissionNanoseconds entry
  , numeric "internal-semantic-audit" $
      compiledInternalAuditNanoseconds entry
  , numeric "treeless-conversion" $ compiledTreelessNanoseconds entry
  , publication "residualization"
  , publication "scheme-codegen-publication"
  ]
  where
    numeric stage nanoseconds =
      stage ++ "\t" ++ show nanoseconds ++ "\tmeasured"
    optional stage = \case
      Just nanoseconds -> numeric stage nanoseconds
      Nothing -> stage ++ "\t-\tnot-applicable"
    publication stage
      | stage == publicationStage = numeric stage publicationNanoseconds
      | otherwise = stage ++ "\t-\tnot-applicable"

-- | Prove every condition required before the type-erased Chez path can be
-- published.  The result is deliberately a capability rather than a Boolean:
-- only a successful proof carries rendered Scheme to the writer.
proveStaticClosure
  :: [CompiledDef]
  -> CompiledDef
  -> Either StaticClosureFailure StaticClosure
proveStaticClosure defs entry
  | compiledBindingTime entry /= BindingStatic =
      failure [] "binding-time-not-static" "not-run"
        "static closure requested for a non-static entry"
  | Just _ <- compiledTypedResidual entry =
      failure [] "typed-residual-present" "not-run"
        "static closure requested for a typed residual"
  | not (null closureRuntimeBlockers) =
      failure [] "reachable-runtime-blockers" "not-run"
        "static closure contains reachable runtime blockers"
  | not (null closureUnknownCubical) =
      failure [] "reachable-unknown-cubical-primitive" "not-run"
        "static closure contains unknown Cubical primitives"
  | missing : _ <- unresolved =
      failure unresolved "unresolved-definitions" "not-run" $
        "unsupported unresolved definition " ++ prettyShow missing
  | Left problem <- renderedProgram =
      failure [] "scheme-lowering-rejected" "rejected" problem
  | Right scheme <- renderedProgram =
      Right StaticClosure
        { staticClosureDefinitions = reachable
        , staticClosureProgram = scheme
        }
  where
    (reachable, unresolved) = reachableDefinitions defs entry
    renderedProgram = renderProgram entry reachable
    closureRuntimeBlockers = Set.toList $ Set.fromList $
      compiledRuntimeBlockers entry
        ++ concatMap (typedTreelessBlockers . compiledTerm) reachable
    closureUnknownCubical = Set.toList $ Set.fromList $
      compiledUnknownCubicalPrimitives entry
        ++ concatMap (typedTreelessUnknownCubical . compiledTerm) reachable
    failure missing reason lowering problem = Left StaticClosureFailure
      { staticClosureFailureDefinitions = reachable
      , staticClosureFailureUnresolved = missing
      , staticClosureFailureBlockers = closureRuntimeBlockers
      , staticClosureFailureUnknownCubical = closureUnknownCubical
      , staticClosureFailureReason = reason
      , staticClosureFailureLowering = lowering
      , staticClosureFailureProblem = problem
      }

staticClosureFailureClass :: StaticClosureFailure -> BackendFailureClass
staticClosureFailureClass failure
  | staticClosureFailureReason failure == "scheme-lowering-rejected" =
      SchemeLoweringFailed
  | otherwise = UnsupportedProgram

handleTypedResidual
  :: ChezOptions
  -> FilePath
  -> FilePath
  -> CompiledDef
  -> TypedResidual
  -> TCM ()
handleTypedResidual opts manifestPath packetPath entry residual = do
  let problem =
        "typed residual required for "
          ++ prettyShow (compiledName entry)
          ++ "; blockers: "
          ++ renderBlockers (compiledRuntimeBlockers entry)
  when (compiledBindingTime entry == BindingUnsupported) $ do
    when (chezResidualPolicy opts == "manifest") $ do
      checkedClosure <- validateTypedResidualContract
        (testResidualContract residual)
      slicePlan <- buildResidualSlicePlan entry $
        residualClosurePayload checkedClosure
      liftIO $ writeFile manifestPath
        (renderTypedResidual
          "unsupported-diagnostic" entry checkedClosure slicePlan)
    backendAbortWith UnsupportedProgram $ case compiledBindingReason entry of
      UnknownCubicalPrimitive ->
        "unsupported unknown Cubical primitive for "
          ++ prettyShow (compiledName entry)
          ++ "; primitives: "
          ++ renderBlockers (compiledUnknownCubicalPrimitives entry)
      _ ->
        "unsupported binding-time classification for "
          ++ prettyShow (compiledName entry)
          ++ "; Internal and Treeless blocker audits disagree"
  case chezResidualPolicy opts of
    "reject" -> backendAbortWith ResidualRequired problem
    "manifest" -> do
      checkedResidual <- validateTypedResidualContract
        (testResidualContract residual)
      slicePlan <- buildResidualSlicePlan entry $
        residualClosurePayload checkedResidual
      _ <- buildResidualStaticShell entry slicePlan
      liftIO $ writeFile manifestPath
        (renderTypedResidual "manifest-only" entry checkedResidual slicePlan)
      backendAbortWith ResidualRequired problem
    "packet" -> do
      checkedResidual <- validateTypedResidualContract $
        testPacketResidual (testResidualContract residual)
      slicePlan <- buildResidualSlicePlan entry $
        residualClosurePayload checkedResidual
      staticShell <- buildResidualStaticShell entry slicePlan
      bytes <- encodeRuntimePacket checkedResidual
      verifyRuntimePacket checkedResidual bytes
      holePackets <- encodeResidualHolePackets opts slicePlan
      liftIO $ do
        writeFile manifestPath
          (renderTypedResidual "packet-v2" entry checkedResidual slicePlan)
        forM_ holePackets $ \(path, holeBytes) ->
          ByteString.writeFile path holeBytes
        forM_ staticShell $ \shell ->
          do
            writeFile
              (chezOutputDirectory opts </> residualStaticShellName)
              shell
            writeFile
              (chezOutputDirectory opts </> typedHoleGroundBridgeName)
              typedHoleGroundBridgeScript
        writePacketBytes packetPath bytes
    policy -> backendAbortWith InvalidConfiguration $
      "unknown typed residual policy " ++ show policy

ensurePortableTerm :: Term -> Type -> TCM ()
ensurePortableTerm term ty = do
  unless (closed (term, ty)) $
    backendAbortWith ResidualizationFailed
      "only closed Terms can cross the process boundary"
  unless (noMetas (term, ty)) $
    backendAbortWith ResidualizationFailed
      "typed residual still contains process-local metavariables"

-- | The v2 packet carries only the checked Internal payload. QName definitions
-- stay in the consumer's already-loaded signature, whose top-level module and
-- full interface hash are part of the packet envelope. Keeping a derived
-- direct-dependency inventory makes this boundary observable and prevents a
-- future producer from publishing a payload whose declared requirements drift
-- from the serialized Term/Type pair.
validateTypedResidualContract :: TypedResidual -> TCM ResidualClosure
validateTypedResidualContract residual = do
  let term = residualTerm residual
      ty = residualType residual
      derivedDependencies = residualDependencyNames term ty
  unless (residualDirectDependencies residual == derivedDependencies) $
    backendAbortWith ResidualizationFailed
      "typed residual dependency inventory does not match its Term/Type payload"
  ensurePortableTerm term ty
  (do
      CheckInternal.checkType ty
      CheckInternal.checkInternal term CmpLeq ty
      pure ()
    ) `catchError` \_ ->
      backendAbortWith ResidualizationFailed
        "typed residual Term/Type pair was rejected by Agda before publication"
  resolveResidualClosure residual

residualClosureLimit :: Int
residualClosureLimit = 10000

resolveResidualClosure :: TypedResidual -> TCM ResidualClosure
resolveResidualClosure residual = do
  graph <- resolveDependencyGraph (residualDirectDependencies residual)
  pure ResidualClosure
    { residualClosurePayload = residual
    , residualClosureResolvedDependencies = dependencyGraphResolved graph
    , residualClosureExpandedDefinitions = dependencyGraphExpanded graph
    , residualClosureSignatureLeaves = dependencyGraphLeaves graph
    , residualClosureExcludedPresentationDependencies =
        dependencyGraphExcludedPresentation graph
    }

resolveDependencyGraph :: [QName] -> TCM DependencyGraph
resolveDependencyGraph = go Set.empty [] [] Set.empty
  where
    go seen expanded leaves excludedPresentation pending = case pending of
      [] -> pure DependencyGraph
        { dependencyGraphResolved = Set.toList seen
        , dependencyGraphExpanded = reverse expanded
        , dependencyGraphLeaves = reverse leaves
        , dependencyGraphExcludedPresentation = Set.toList $
            Set.difference excludedPresentation seen
        }
      name : rest
        | name `Set.member` seen ->
            go seen expanded leaves excludedPresentation rest
        | Set.size seen >= residualClosureLimit ->
            backendAbortWith ResidualizationFailed $
              "typed residual dependency closure exceeds "
              ++ show residualClosureLimit
              ++ " resolved QNames"
        | otherwise -> do
            definitionResult <- lookupResidualDefinition name
            definition <- case definitionResult of
              Left _ -> backendAbortWith ResidualizationFailed $
                "typed residual dependency is unavailable in the current signature: "
                ++ prettyShow name
              Right checkedDefinition -> pure checkedDefinition
            let seen' = Set.insert name seen
            if isResidualSignatureLeaf name
              then go seen' expanded (name : leaves) excludedPresentation rest
              else do
                let exactDependencies =
                      residualDefinitionDependencyNames definition
                    discovered = testResidualDefinitionDependencies
                      definition exactDependencies
                    allDefinitionNames =
                      namesIn definition :: Set.Set QName
                    presentationOnly = Set.delete name $
                      Set.difference allDefinitionNames exactDependencies
                unless (discovered == exactDependencies) $
                  backendAbortWith ResidualizationFailed
                    "typed residual definition dependency slice does not match its checked type/body"
                go seen' (name : expanded) leaves
                  (Set.union excludedPresentation presentationOnly)
                  (Set.toList discovered ++ rest)

buildResidualSlicePlan :: CompiledDef -> TypedResidual -> TCM ResidualSlicePlan
buildResidualSlicePlan entry residual = case compiledBindingTime entry of
  BindingMixed -> do
    let seeds = testResidualHoleSeeds $
          collectResidualHoleSeeds [] (compiledTerm entry)
        plannedBlockers = Set.fromList $
          concatMap residualHoleSeedBlockers seeds
        expectedBlockers = Set.fromList (compiledTreelessBlockers entry)
    when (null seeds) $
      backendAbortWith ResidualizationFailed
        "mixed residual slice plan found no blocker-headed typed hole"
    unless (plannedBlockers == expectedBlockers) $
      backendAbortWith ResidualizationFailed
        "mixed residual slice plan does not cover every Treeless blocker"
    candidates <- testResidualHoleCandidates <$>
      collectResidualHoleCandidates residual
    ResidualSlicePlanned <$> traverse (materializeHole candidates) seeds
  BindingDynamic -> pure $ ResidualSliceNotApplicable "whole-entry-dynamic"
  BindingStatic -> pure $ ResidualSliceNotApplicable "static-entry"
  BindingUnsupported -> pure $ ResidualSliceNotApplicable "unsupported-entry"
  where
    materializeHole candidates seed = case matchingCandidates of
      [candidate] -> do
        let term = residualHoleCandidateTerm candidate
            ty = residualHoleCandidateType candidate
            sourceClosed = residualHoleCandidateSourceClosed candidate
            environmentArity =
              residualHoleCandidateEnvironmentArity candidate
            typedResidual = TypedResidual
              { residualTerm = term
              , residualType = ty
              , residualDirectDependencies = residualDependencyNames term ty
              }
        unless
          ( (sourceClosed && environmentArity == 0)
            || ( not sourceClosed
                 && environmentArity > 0
                 && environmentArity <= residualHoleEnvironmentLimit
               )
          ) $
          backendAbortWith ResidualizationFailed $
            "mixed residual hole environment arity is outside 1.."
              ++ show residualHoleEnvironmentLimit
        closure <- validateTypedResidualContract typedResidual
        callableAbi <- classifyResidualHoleCallableAbi environmentArity ty
        pure ResidualHolePlan
          { residualHoleId = residualHoleSeedId seed
          , residualHolePath = residualHoleSeedPath seed
          , residualHoleBlockers = residualHoleSeedBlockers seed
          , residualHoleClosure = closure
          , residualHoleCallableAbi = callableAbi
          , residualHoleSourceClosed =
              residualHoleCandidateSourceClosed candidate
          , residualHoleEnvironmentArity =
              residualHoleCandidateEnvironmentArity candidate
          }
      [] -> backendAbortWith ResidualizationFailed $
        "mixed residual hole "
          ++ residualHoleSeedId seed
          ++ " has no unique checked Internal Term/Type match"
      _ -> backendAbortWith ResidualizationFailed $
        "mixed residual hole "
          ++ residualHoleSeedId seed
          ++ " has multiple checked Internal Term/Type matches"
      where
        matchingCandidates = filter matches candidates
        matches candidate =
          residualHoleCandidateTreeless candidate
            == residualHoleSeedTreeless seed
          && Set.fromList (residualHoleSeedBlockers seed)
            `Set.isSubsetOf` Set.fromList
              (typedInternalBlockers $ residualHoleCandidateTerm candidate)

classifyResidualHoleCallableAbi
  :: Int
  -> Type
  -> TCM ResidualHoleCallableAbi
classifyResidualHoleCallableAbi environmentArity ty
  | environmentArity > 1 = do
      codecs <- classifyOrderedGroundEnvironment environmentArity ty
      case codecs of
        Just orderedCodecs -> pure $
          ResidualHoleOrderedGroundEnvironmentElimination orderedCodecs
        Nothing -> do
          dependent <-
            classifyDependentGroundEnvironment environmentArity ty
          pure $ if dependent
            then ResidualHoleDependentGroundEnvironmentElimination
            else ResidualHoleObservationOnly
  | otherwise = classifyUnary ty
  where
    classifyUnary unaryType = do
      reducedType <- reduce unaryType
      registry <- residualGroundCodecRegistry
      case Internal.unEl reducedType of
        Internal.Pi domain _
          | getHiding domain == NotHidden -> do
              reducedDomain <- reduce (Internal.unDom domain)
              pure $ case Internal.unEl reducedDomain of
                Internal.Def actual [] ->
                  maybe
                    ResidualHoleObservationOnly
                    ResidualHoleUnaryGroundElimination
                    (lookupResidualGroundCodec registry actual)
                _ -> ResidualHoleObservationOnly
        _ -> pure ResidualHoleObservationOnly

classifyOrderedGroundEnvironment
  :: Int
  -> Type
  -> TCM (Maybe [ResidualGroundCodec])
classifyOrderedGroundEnvironment arity ty = do
  registry <- residualGroundCodecRegistry
  go registry arity ty
  where
    go _ 0 _ = pure $ Just []
    go registry remaining currentType = do
      reducedType <- reduce currentType
      case Internal.unEl reducedType of
        Internal.Pi domain codomain
          | getHiding domain == NotHidden -> do
              reducedDomain <- reduce (Internal.unDom domain)
              let codec = case Internal.unEl reducedDomain of
                    Internal.Def actual [] ->
                      lookupResidualGroundCodec registry actual
                    _ -> Nothing
              if not (closed reducedDomain)
                then pure Nothing
                else case codec of
                  Nothing -> pure Nothing
                  Just groundCodec -> underAbstraction domain codomain $ \body -> do
                    rest <- go registry (remaining - 1) body
                    pure $ (groundCodec :) <$> rest
        _ -> pure Nothing

-- | A visible telescope with at least two slots and at least one domain that
-- depends on an earlier slot. Closed domains must be builtin
-- Bool/Nat/Word64/Char/Int; open
-- domains are admitted only as dependent candidates. At runtime every actual
-- value must still be representable as Bool/Nat/Word64/Char/Int, and Agda checks the complete
-- dependent application after all literals have been supplied.
classifyDependentGroundEnvironment :: Int -> Type -> TCM Bool
classifyDependentGroundEnvironment arity ty = do
  registry <- residualGroundCodecRegistry
  if arity < 2
    then pure False
    else go registry arity False ty
  where
    go _ 0 sawDependent _ = pure sawDependent
    go registry remaining sawDependent currentType = do
      reducedType <- reduce currentType
      case Internal.unEl reducedType of
        Internal.Pi domain codomain
          | getHiding domain == NotHidden -> do
              reducedDomain <- reduce (Internal.unDom domain)
              let domainClosed = closed reducedDomain
                  closedGround = case Internal.unEl reducedDomain of
                    Internal.Def actual [] ->
                      case lookupResidualGroundCodec registry actual of
                        Just _ -> True
                        Nothing -> False
                    _ -> False
              if domainClosed && not closedGround
                then pure False
                else underAbstraction domain codomain $ \body ->
                  go registry (remaining - 1)
                    (sawDependent || not domainClosed) body
        _ -> pure False

-- | Re-run Agda's Internal checker with an observation-only action. The
-- checker, not Treeless, supplies the expected Type and current telescope for
-- each subterm. Closed candidates stay unchanged. An open/meta-free candidate
-- is lambda-lifted over that telescope, producing a closed Term/Type packet;
-- the explicit environment arguments remain typed and are never reconstructed
-- from erased Treeless syntax.
collectResidualHoleCandidates
  :: TypedResidual
  -> TCM [ResidualHoleCandidate]
collectResidualHoleCandidates residual = do
  observed <- liftIO $ newIORef []
  let term = residualTerm residual
      ty = residualType residual
      capture subtermType subterm = do
        let sourceClosed = closed (subterm, subtermType)
        when
          ( not (null $ typedInternalBlockers subterm)
            && noMetas (subterm, subtermType)
          ) $ do
          context <- getContextTelescope
          let environmentArity =
                if sourceClosed then 0 else length (telToList context)
              candidateTerm =
                if sourceClosed then subterm else teleLam context subterm
              candidateType =
                if sourceClosed then subtermType else telePi context subtermType
          when (closed (candidateTerm, candidateType)) $
            liftIO $ modifyIORef' observed
              (( candidateTerm
               , candidateType
               , sourceClosed
               , environmentArity
               ) :)
        pure subterm
      action = CheckInternal.defaultAction
        { CheckInternal.postAction = capture
        }
  (do
      _ <- CheckInternal.checkInternal' action term CmpLeq ty
      pure ()
    ) `catchError` \_ ->
      backendAbortWith ResidualizationFailed
        "mixed residual Internal subterm discovery was rejected by Agda"
  pairs <- liftIO $ readIORef observed
  let uniquePairs = Map.elems $ Map.fromList
        [ ( ( prettyShow candidateTerm
            , prettyShow candidateType
            , sourceClosed
            , environmentArity
            )
          , ( candidateTerm
            , candidateType
            , sourceClosed
            , environmentArity
            )
          )
        | (candidateTerm, candidateType, sourceClosed, environmentArity) <- pairs
        ]
  forM uniquePairs $
      \(candidateTerm, candidateType, sourceClosed, environmentArity) -> do
    liftedTreeless <- compileClosedTerm candidateTerm
    candidateTreeless <- case stripTreelessEnvironment
      environmentArity liftedTreeless of
        Just body -> pure body
        Nothing -> backendAbortWith ResidualizationFailed
          "lambda-lifted mixed hole did not preserve its environment arity"
    pure ResidualHoleCandidate
      { residualHoleCandidateTerm = candidateTerm
      , residualHoleCandidateType = candidateType
      , residualHoleCandidateTreeless = candidateTreeless
      , residualHoleCandidateSourceClosed = sourceClosed
      , residualHoleCandidateEnvironmentArity = environmentArity
      }

stripTreelessEnvironment :: Int -> TTerm -> Maybe TTerm
stripTreelessEnvironment arity term
  | arity <= 0 = Just term
stripTreelessEnvironment arity (TLam body) =
  stripTreelessEnvironment (arity - 1) body
stripTreelessEnvironment _ _ = Nothing

residualHoleEnvironmentLimit :: Int
residualHoleEnvironmentLimit = 64

collectResidualHoleSeeds :: [String] -> TTerm -> [ResidualHoleSeed]
collectResidualHoleSeeds path term
  | runtimeBlockerAtHead term =
      [ ResidualHoleSeed
          { residualHoleSeedId = "typed-hole@" ++ renderResidualHolePath path
          , residualHoleSeedPath = renderResidualHolePath path
          , residualHoleSeedBlockers = typedTreelessBlockers term
          , residualHoleSeedTreeless = term
          }
      ]
  | otherwise = case term of
      TVar _ -> []
      TPrim _ -> []
      TDef _ -> []
      TApp function arguments ->
        collectResidualHoleSeeds (path ++ ["app-function"]) function
          ++ concat
            [ collectResidualHoleSeeds
                (path ++ ["app-argument-" ++ show index])
                argument
            | (index, argument) <- zip [(0 :: Int) ..] arguments
            ]
      TLam body -> collectResidualHoleSeeds (path ++ ["lambda-body"]) body
      TLit _ -> []
      TCon _ -> []
      TLet value body ->
        collectResidualHoleSeeds (path ++ ["let-value"]) value
          ++ collectResidualHoleSeeds (path ++ ["let-body"]) body
      TCase _ _ fallback alternatives ->
        collectResidualHoleSeeds (path ++ ["case-fallback"]) fallback
          ++ concat
            [ collectResidualAlternativeSeeds
                (path ++ ["case-alternative-" ++ show index])
                alternative
            | (index, alternative) <- zip [(0 :: Int) ..] alternatives
            ]
      TUnit -> []
      TSort -> []
      TErased -> []
      TCoerce coerced ->
        collectResidualHoleSeeds (path ++ ["coerce-body"]) coerced
      TError _ -> []

collectResidualAlternativeSeeds :: [String] -> TAlt -> [ResidualHoleSeed]
collectResidualAlternativeSeeds path = \case
  TACon _ _ body ->
    collectResidualHoleSeeds (path ++ ["constructor-body"]) body
  TAGuard guard body ->
    collectResidualHoleSeeds (path ++ ["guard-test"]) guard
      ++ collectResidualHoleSeeds (path ++ ["guard-body"]) body
  TALit _ body -> collectResidualHoleSeeds (path ++ ["literal-body"]) body

renderResidualHolePath :: [String] -> String
renderResidualHolePath = \case
  [] -> "root"
  segments -> joinWithDot segments
  where
    joinWithDot = foldr1 (\left right -> left ++ "." ++ right)

testResidualHoleSeeds :: [ResidualHoleSeed] -> [ResidualHoleSeed]
#if defined(CUBICAL_CHEZ_TEST_RESIDUAL_SLICE_NO_HOLES)
testResidualHoleSeeds _ = []
#else
testResidualHoleSeeds = id
#endif

testResidualHoleCandidates
  :: [ResidualHoleCandidate]
  -> [ResidualHoleCandidate]
#if defined(CUBICAL_CHEZ_TEST_RESIDUAL_SLICE_NO_TYPED_MATCH)
testResidualHoleCandidates _ = []
#else
testResidualHoleCandidates = id
#endif

lookupResidualDefinition :: QName -> TCM (Either SigError Definition)
lookupResidualDefinition name =
#if defined(CUBICAL_CHEZ_TEST_RESIDUAL_UNRESOLVED_DEPENDENCY)
  if isResidualSignatureLeaf name
    then getConstInfo' name
    else backendAbortWith ResidualizationFailed $
      "typed residual dependency is unavailable in the current signature: "
      ++ prettyShow name
#else
  getConstInfo' name
#endif

isResidualSignatureLeaf :: QName -> Bool
isResidualSignatureLeaf name =
  "Agda.Builtin." `isPrefixOf` rendered
    || "Agda.Primitive." `isPrefixOf` rendered
  where
    rendered = prettyShow name

residualDependencyNames :: Term -> Type -> [QName]
residualDependencyNames term ty = Set.toList $ Set.union
  (namesIn term :: Set.Set QName)
  (namesIn ty :: Set.Set QName)

-- | Only checked type and definition-body names can affect checking or
-- normalization of the residual payload. Definition display forms are
-- presentation metadata: record them for audit, but never let them enlarge
-- the executable signature slice.
residualDefinitionDependencyNames :: Definition -> Set.Set QName
residualDefinitionDependencyNames definition = Set.union
  (namesIn (defType definition) :: Set.Set QName)
  (namesIn (theDef definition) :: Set.Set QName)

-- Compile-time-only regression fault. It restores the former broad
-- @NamesIn Definition@ traversal so the gate proves presentation metadata
-- cannot silently become an executable dependency again.
testResidualDefinitionDependencies
  :: Definition
  -> Set.Set QName
  -> Set.Set QName
#if defined(CUBICAL_CHEZ_TEST_RESIDUAL_PRESENTATION_DEPENDENCY_LEAK)
testResidualDefinitionDependencies definition _ =
  namesIn definition :: Set.Set QName
#else
testResidualDefinitionDependencies _ = id
#endif

-- Compile-time-only inventory fault. It proves that dependency evidence is a
-- checked producer contract, not decorative manifest text.
testResidualContract :: TypedResidual -> TypedResidual
#if defined(CUBICAL_CHEZ_TEST_RESIDUAL_DEPENDENCY_MISMATCH)
testResidualContract residual = residual {residualDirectDependencies = []}
#else
testResidualContract = id
#endif

-- Test-only producer faults exercise the portability gates before bytes are
-- published.  Production and ordinary verification builds use the checked
-- residual unchanged.
testPacketResidual :: TypedResidual -> TypedResidual
#if defined(CUBICAL_CHEZ_TEST_OPEN_TERM)
testPacketResidual residual = residual
  { residualTerm = Internal.Var 0 []
  , residualDirectDependencies = residualDependencyNames
      (Internal.Var 0 [])
      (residualType residual)
  }
#elif defined(CUBICAL_CHEZ_TEST_UNRESOLVED_META)
testPacketResidual residual = residual
  { residualTerm = Internal.MetaV (MetaId 0 noModuleNameHash) []
  , residualDirectDependencies = residualDependencyNames
      (Internal.MetaV (MetaId 0 noModuleNameHash) [])
      (residualType residual)
  }
#else
testPacketResidual = id
#endif

encodeRuntimePacket :: ResidualClosure -> TCM ByteString.ByteString
#if defined(CUBICAL_CHEZ_AGDA_29)
encodeRuntimePacket closure = do
  iface <- curIF
  let residual = residualClosurePayload closure
  let term = residualTerm residual
      ty = residualType residual
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
  liftIO $ RawSerialise.serialize encoded
#else
encodeRuntimePacket _ = backendAbortWith ResidualizationFailed $
  "packet output requires an Agda 2.9 build with CUBICAL_CHEZ_AGDA_29 enabled"
#endif

-- | Decode and recheck the exact bytes before publishing them.  This does not
-- replace the consumer's independent checks; it prevents producing a corrupt
-- packet in the first place.
verifyRuntimePacket :: ResidualClosure -> ByteString.ByteString -> TCM ()
#if defined(CUBICAL_CHEZ_AGDA_29)
verifyRuntimePacket expectedClosure bytes = do
  encoded <- liftIO $ deserializeEncoded bytes
  decoded <- runMaybeT (Serialise.decode encoded :: MaybeT TCM RuntimePacket)
  packet <- maybe
    (backendAbortWith ResidualizationFailed
      "packet self-check could not decode its own bytes")
    pure
    decoded
  let (magic, (version, (_, (_, (term, ty))))) = packet
  unless (magic == expectedRuntimePacketMagic) $
    backendAbortWith ResidualizationFailed
      "packet self-check found the wrong magic header"
  unless (version == expectedRuntimePacketVersion) $
    backendAbortWith ResidualizationFailed
      "packet self-check found the wrong format version"
  unless
    ( residualDependencyNames term ty
        == residualDirectDependencies
          (residualClosurePayload expectedClosure)
    ) $
    backendAbortWith ResidualizationFailed
      "packet self-check found a changed residual dependency inventory"
  ensurePortableTerm term ty
  CheckInternal.checkType ty
  CheckInternal.checkInternal term CmpLeq ty
#else
verifyRuntimePacket _ _ = backendAbortWith ResidualizationFailed $
  "packet verification requires an Agda 2.9 build with CUBICAL_CHEZ_AGDA_29 enabled"
#endif

encodeResidualHolePackets
  :: ChezOptions
  -> ResidualSlicePlan
  -> TCM [(FilePath, ByteString.ByteString)]
encodeResidualHolePackets opts = \case
  ResidualSliceNotApplicable _ -> pure []
  ResidualSlicePlanned holes -> forM
    (zip [(1 :: Int) ..] holes) $ \(index, hole) -> do
      let closure = residualHoleClosure hole
          path = chezOutputDirectory opts </> residualHolePacketName index
      bytes <- encodeRuntimePacket closure
      verifyRuntimePacket closure bytes
      pure (path, bytes)

#if defined(CUBICAL_CHEZ_AGDA_29)
deserializeEncoded :: ByteString.ByteString -> IO Serialise.Encoded
deserializeEncoded = RawSerialise.deserialize
#endif

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
  exists <- doesFileExist path
  if exists then removeFile path else pure ()

clearPublishedArtifacts :: ChezOptions -> IO ()
clearPublishedArtifacts opts = do
  let outputDirectory = chezOutputDirectory opts
  removeIfExists (outputDirectory </> "program.ss")
  removeIfExists (outputDirectory </> "treeless.txt")
  removeIfExists (outputDirectory </> "staging.txt")
  removeIfExists (outputDirectory </> stageTimingsName)
  removeIfExists (outputDirectory </> "typed-residual.txt")
  removeIfExists (outputDirectory </> "typed-residual.bin")
  removeIfExists (outputDirectory </> residualStaticShellName)
  clearResidualHolePackets outputDirectory
  maybe (pure ()) removePacketIfExists (chezPacketFile opts)

clearResidualHolePackets :: FilePath -> IO ()
clearResidualHolePackets outputDirectory = do
  exists <- doesDirectoryExist outputDirectory
  when exists $ do
    names <- listDirectory outputDirectory
    forM_ names $ \name ->
      when
        ( "typed-residual-hole-" `isPrefixOf` name
          && ".bin" `isSuffixOf` name
        ) $
        removeIfExists (outputDirectory </> name)

removePacketIfExists :: FilePath -> IO ()
removePacketIfExists "-" = pure ()
removePacketIfExists path = removeIfExists path

writePacketBytes :: FilePath -> ByteString.ByteString -> IO ()
writePacketBytes "-" bytes = do
  hSetBinaryMode stdout True
  ByteString.hPut stdout bytes
  hFlush stdout
writePacketBytes path bytes = ByteString.writeFile path bytes

renderStaging :: ChezOptions -> CompiledDef -> StaticClosureReport -> String
renderStaging opts entry closureReport = unlines $
  [ "backend: CubicalChez 0.1.0-dev"
  , "engine: " ++ compiledEffectiveEngine entry
  , "engine-requested: " ++ compiledRequestedEngine entry
  , "engine-effective: " ++ compiledEffectiveEngine entry
  , "nbe-fallback-policy: " ++ compiledNbeFallbackPolicy entry
  , "nbe-fallback-used: " ++ renderBoolean (compiledNbeFallbackUsed entry)
  , "nbe-fallback-reason: " ++ compiledNbeFallbackReason entry
  , "requested-entry: " ++ chezEntry opts
  , "entry: " ++ prettyShow (compiledName entry)
  ]
  ++ renderNbeSpikeEvidence entry
  ++ renderChezCoreAbiManifest
  ++
  [ "engine-result-closed: true"
  , "engine-result-meta-free: true"
  , "engine-result-agda-checked: true"
  , "packet-destination: " ++ case chezPacketFile opts of
      Nothing -> "default"
      Just "-" -> "stdout"
      Just path -> path
  , "internal-term-blockers: " ++ renderBlockers (compiledInternalTermBlockers entry)
  , "internal-type-blockers: " ++ renderBlockers (compiledInternalTypeBlockers entry)
  , "internal-term-catalog-blockers: "
      ++ renderBlockers (compiledInternalTermCatalogBlockers entry)
  , "internal-type-catalog-blockers: "
      ++ renderBlockers (compiledInternalTypeCatalogBlockers entry)
  , "internal-term-semantic-sources: "
      ++ renderSemanticSources (compiledInternalTermSemanticSources entry)
  , "internal-type-semantic-sources: "
      ++ renderSemanticSources (compiledInternalTypeSemanticSources entry)
  , "internal-term-semantic-catalog-disagreements: "
      ++ renderBlockers
        (compiledInternalTermSemanticCatalogDisagreements entry)
  , "internal-type-semantic-catalog-disagreements: "
      ++ renderBlockers
        (compiledInternalTypeSemanticCatalogDisagreements entry)
  , "internal-term-semantic-catalog-status: "
      ++ semanticCatalogStatus
        (compiledInternalTermSemanticCatalogDisagreements entry)
  , "internal-type-semantic-catalog-status: "
      ++ semanticCatalogStatus
        (compiledInternalTypeSemanticCatalogDisagreements entry)
  , "treeless-blockers: " ++ renderBlockers (compiledTreelessBlockers entry)
  , "internal-term-unknown-cubical-primitives: "
      ++ renderBlockers (compiledInternalTermUnknownCubical entry)
  , "internal-type-unknown-cubical-primitives: "
      ++ renderBlockers (compiledInternalTypeUnknownCubical entry)
  , "treeless-unknown-cubical-primitives: "
      ++ renderBlockers (compiledTreelessUnknownCubical entry)
  , "binding-time: " ++ renderBindingTime (compiledBindingTime entry)
  , "binding-time-scope: whole-entry"
  , "binding-time-reason: " ++ bindingTimeReason (compiledBindingReason entry)
  , "binding-time-action: " ++ bindingTimeAction (compiledBindingTime entry)
  , "static-closure: " ++ staticClosureState closureReport
  , "static-closure-reason: " ++ staticClosureReportReason closureReport
  , "static-closure-reachable-definitions: "
      ++ staticClosureReachableCount closureReport
  , "static-closure-unresolved-definitions: "
      ++ staticClosureUnresolvedDefinitions closureReport
  , "static-closure-runtime-blockers: "
      ++ staticClosureRuntimeBlockers closureReport
  , "static-closure-unknown-cubical-primitives: "
      ++ staticClosureUnknownCubicalPrimitives closureReport
  , "static-closure-scheme-lowering: "
      ++ staticClosureLoweringStatus closureReport
  , "type-erasure-authorized: " ++ typeErasureAuthorized closureReport
  , "decision: " ++ stagingDecision entry closureReport
  ]

renderNbeSpikeEvidence :: CompiledDef -> [String]
renderNbeSpikeEvidence entry
  | "nbe-adapter-implementation: agda-specific-in-process-v1"
      `elem` compiledEngineEvidence entry =
      [ "nbe-adapter-status: " ++
          if compiledEffectiveEngine entry == "nbe"
            then "production-candidate-selected"
            else "experimental-test-only"
      , "nbe-adapter-production-readiness: candidate-not-accepted"
      , "nbe-adapter-profile: ordinary-closures-data-record-universe-primitive-cubical-glue-ua-hit-v36"
      , "nbe-term-normalizer: environment-closure-data-record+primitive+neutral-cubical-glue-ua-hit-eval-readback-v35"
      , "nbe-type-normalizer: semantic-type+sort+level+alias-eval-readback-v1"
      , "nbe-postulated-sort-policy: reject-v1"
      , "nbe-primitive-registry: agda-primitive-id-v4"
      , "nbe-cofibration-normalizer: endpoint+neutral-identities-v1"
      , "nbe-constant-family-transport: exact-builtin-nat+nat-to-nat+universe-v3"
      , "nbe-path-application-policy: closure+constructor+definition+primitive+comp-beta-v3"
      , "nbe-glue-normalizer: introduction-elimination-cancellation+canonical-ua-bidirectional+double-composition+probe-hcomp-v6"
      , "nbe-pi-transport-normalizer: canonical-domain+stable+semantic-constant+canonical+self-path+bidirectional-singleton+bidirectional-nested-singleton+probe-shell-identity+dependent-alias+per-layer-stable-identity+parameterized-stable-identity+metadata-constructor-stable-identity+closed-function-readback+closed-pi-type-readback+outer-parameter-indexed-pi-field+ground-payload-indexed-pi-field+fieldwise-bidirectional-bounded-sigma-spine-codomain+opaque-binder+isomorphism-proof-roundtrip-v19"
      , "nbe-structured-transport-normalizer: builtin-sigma-stable-second+list-parameter-map-v1"
      , "nbe-hit-pattern-policy: exact-definition-or-primitive-head+checked-subpatterns-v2"
      ]
      ++ compiledEngineEvidence entry
  | otherwise = []

renderBoolean :: Bool -> String
renderBoolean True = "true"
renderBoolean False = "false"

staticClosureState :: StaticClosureReport -> String
staticClosureState = \case
  StaticClosureNotApplicable -> "not-applicable"
  StaticClosureComplete _ -> "complete"
  StaticClosureIncomplete {} -> "incomplete"

staticClosureReportReason :: StaticClosureReport -> String
staticClosureReportReason = \case
  StaticClosureNotApplicable -> "typed-residual-or-unsupported"
  StaticClosureComplete _ -> "reachable-closure-and-lowering-verified"
  StaticClosureIncomplete _ _ _ _ reason _ -> reason

staticClosureReachableCount :: StaticClosureReport -> String
staticClosureReachableCount = \case
  StaticClosureNotApplicable -> "not-applicable"
  StaticClosureComplete count -> show count
  StaticClosureIncomplete count _ _ _ _ _ -> show count

staticClosureUnresolvedDefinitions :: StaticClosureReport -> String
staticClosureUnresolvedDefinitions = \case
  StaticClosureNotApplicable -> "not-applicable"
  StaticClosureComplete _ -> "none"
  StaticClosureIncomplete _ unresolved _ _ _ _ -> renderBlockers unresolved

staticClosureRuntimeBlockers :: StaticClosureReport -> String
staticClosureRuntimeBlockers = \case
  StaticClosureNotApplicable -> "not-applicable"
  StaticClosureComplete _ -> "none"
  StaticClosureIncomplete _ _ blockers _ _ _ -> renderBlockers blockers

staticClosureUnknownCubicalPrimitives :: StaticClosureReport -> String
staticClosureUnknownCubicalPrimitives = \case
  StaticClosureNotApplicable -> "not-applicable"
  StaticClosureComplete _ -> "none"
  StaticClosureIncomplete _ _ _ unknown _ _ -> renderBlockers unknown

staticClosureLoweringStatus :: StaticClosureReport -> String
staticClosureLoweringStatus = \case
  StaticClosureNotApplicable -> "not-run"
  StaticClosureComplete _ -> "checked"
  StaticClosureIncomplete _ _ _ _ _ lowering -> lowering

typeErasureAuthorized :: StaticClosureReport -> String
typeErasureAuthorized = \case
  StaticClosureComplete _ -> "true"
  _ -> "false"

stagingDecision :: CompiledDef -> StaticClosureReport -> String
stagingDecision entry = \case
  StaticClosureIncomplete {} -> "unsupported"
  _ -> bindingTimeDecision (compiledBindingTime entry)

renderTypedResidual
  :: String
  -> CompiledDef
  -> ResidualClosure
  -> ResidualSlicePlan
  -> String
renderTypedResidual artifact entry closure slicePlan = unlines $
  [ "entry: " ++ prettyShow (compiledName entry)
  , "artifact: " ++ artifact
  ]
  ++ renderChezCoreAbiManifest
  ++
  [ "residual-contract: whole-entry-same-interface-v1"
  , "residual-scope: whole-entry"
  , "residual-payload: internal-term+type"
  , "residual-signature-identity: top-level-module+full-interface-hash"
  , "residual-dependency-closure: exact-consumer-interface"
  , "residual-dependency-slice: checked-type+definition-body-v1"
  , "residual-presentation-metadata: excluded-from-executable-slice"
  , "residual-direct-dependency-count: "
      ++ show (length $ residualDirectDependencies residual)
  , "residual-direct-dependencies: "
      ++ renderBlockers (residualDirectDependencies residual)
  , "residual-closure-complete: true"
  , "residual-resolved-dependency-count: "
      ++ show (length $ residualClosureResolvedDependencies closure)
  , "residual-resolved-dependencies: "
      ++ renderBlockers (residualClosureResolvedDependencies closure)
  , "residual-expanded-definition-count: "
      ++ show (length $ residualClosureExpandedDefinitions closure)
  , "residual-expanded-definitions: "
      ++ renderBlockers (residualClosureExpandedDefinitions closure)
  , "residual-signature-leaf-count: "
      ++ show (length $ residualClosureSignatureLeaves closure)
  , "residual-signature-leaves: "
      ++ renderBlockers (residualClosureSignatureLeaves closure)
  , "residual-excluded-presentation-dependency-count: "
      ++ show
        (length $ residualClosureExcludedPresentationDependencies closure)
  , "residual-excluded-presentation-dependencies: "
      ++ renderBlockers
        (residualClosureExcludedPresentationDependencies closure)
  , "residual-unresolved-dependencies: none"
  , "residual-embedded-definitions: none"
  , "residual-whole-signature-embedded: false"
  , "residual-slice-plan: " ++ residualSlicePlanState slicePlan
  , "residual-slice-static-shell: "
      ++ residualSliceStaticShell artifact slicePlan
  , "residual-slice-static-shell-artifact: "
      ++ residualSliceStaticShellArtifact artifact slicePlan
  , "residual-slice-static-shell-bridge-artifact: "
      ++ residualSliceStaticShellBridgeArtifact artifact slicePlan
  , "residual-slice-static-shell-import-contract: "
      ++ residualSliceStaticShellImportContract slicePlan
  , "residual-slice-static-shell-hole-forcing: "
      ++ residualSliceStaticShellHoleForcing slicePlan
  , "residual-slice-static-shell-callable-elimination: "
      ++ residualSliceStaticShellCallableElimination slicePlan
  , "residual-slice-static-shell-typed-value-proxy: "
      ++ residualSliceStaticShellTypedValueProxy slicePlan
  , "residual-slice-static-shell-proxy-composition: "
      ++ residualSliceStaticShellProxyComposition slicePlan
  , "residual-slice-static-shell-typed-value-carrier: "
      ++ residualSliceStaticShellTypedValueCarrier slicePlan
  , "residual-slice-static-shell-proxy-mapping: "
      ++ residualSliceStaticShellProxyMapping slicePlan
  , "residual-slice-static-shell-proxy-store-quota: "
      ++ residualSliceStaticShellProxyStoreQuota slicePlan
  , "residual-slice-static-shell-proxy-publication-lock: "
      ++ residualSliceStaticShellProxyPublicationLock slicePlan
  , "residual-slice-static-shell-proxy-state-transactions: "
      ++ residualSliceStaticShellProxyStateTransactions slicePlan
  , "residual-slice-open-hole-closure-conversion: "
      ++ residualSliceOpenHoleClosureConversion slicePlan
  , "residual-slice-static-shell-environment-binding: "
      ++ residualSliceStaticShellEnvironmentBinding slicePlan
  , "residual-slice-open-hole-environment-arity-limit: "
      ++ show residualHoleEnvironmentLimit
  , "residual-slice-typed-source: " ++ residualSliceTypedSource slicePlan
  , "residual-slice-hole-count: " ++ show (residualSliceHoleCount slicePlan)
  , "residual-slice-hole-ids: " ++ residualSliceHoleIds slicePlan
  , "residual-slice-independent-artifacts: "
      ++ residualSliceIndependentArtifacts artifact slicePlan
  , "residual-slice-execution: "
      ++ residualSliceExecution artifact slicePlan
  , "packet-format: " ++ runtimePacketMagic ++ "/v" ++ show runtimePacketVersion
  , "packet-codec: " ++ packetCodecName
  , "ground-codec-registry-version: ground-codec-registry-v1"
  , "ground-codec-registry: " ++ renderResidualGroundCodecRegistry
  , "ground-codec-descriptor-version: ground-codec-descriptor-v1"
  , "ground-codec-descriptor-fields: codec,unary-abi,cli-prefix,validator,argument-reifier,entry-parser,value-reifier"
  , "blockers: " ++ renderBlockers (compiledRuntimeBlockers entry)
  , "internal-term-blockers: " ++ renderBlockers (compiledInternalTermBlockers entry)
  , "internal-type-blockers: " ++ renderBlockers (compiledInternalTypeBlockers entry)
  , "internal-term-catalog-blockers: "
      ++ renderBlockers (compiledInternalTermCatalogBlockers entry)
  , "internal-type-catalog-blockers: "
      ++ renderBlockers (compiledInternalTypeCatalogBlockers entry)
  , "internal-term-semantic-sources: "
      ++ renderSemanticSources (compiledInternalTermSemanticSources entry)
  , "internal-type-semantic-sources: "
      ++ renderSemanticSources (compiledInternalTypeSemanticSources entry)
  , "internal-term-semantic-catalog-disagreements: "
      ++ renderBlockers
        (compiledInternalTermSemanticCatalogDisagreements entry)
  , "internal-type-semantic-catalog-disagreements: "
      ++ renderBlockers
        (compiledInternalTypeSemanticCatalogDisagreements entry)
  , "internal-term-semantic-catalog-status: "
      ++ semanticCatalogStatus
        (compiledInternalTermSemanticCatalogDisagreements entry)
  , "internal-type-semantic-catalog-status: "
      ++ semanticCatalogStatus
        (compiledInternalTypeSemanticCatalogDisagreements entry)
  , "treeless-blockers: " ++ renderBlockers (compiledTreelessBlockers entry)
  , "internal-term-unknown-cubical-primitives: "
      ++ renderBlockers (compiledInternalTermUnknownCubical entry)
  , "internal-type-unknown-cubical-primitives: "
      ++ renderBlockers (compiledInternalTypeUnknownCubical entry)
  , "treeless-unknown-cubical-primitives: "
      ++ renderBlockers (compiledTreelessUnknownCubical entry)
  , "binding-time: " ++ renderBindingTime (compiledBindingTime entry)
  , "binding-time-scope: whole-entry"
  , "binding-time-reason: " ++ bindingTimeReason (compiledBindingReason entry)
  , "binding-time-action: " ++ bindingTimeAction (compiledBindingTime entry)
  , "type:"
  , "  " ++ prettyShow (residualType residual)
  , "term:"
  , "  " ++ prettyShow (residualTerm residual)
  ] ++ renderResidualHoles artifact slicePlan
  where
    residual = residualClosurePayload closure

residualSlicePlanState :: ResidualSlicePlan -> String
residualSlicePlanState = \case
  ResidualSliceNotApplicable reason -> "not-applicable-" ++ reason
  ResidualSlicePlanned _ -> "materialized-checked-internal"

residualSliceStaticShell :: String -> ResidualSlicePlan -> String
residualSliceStaticShell artifact = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned _
    | artifact == "packet-v2" -> "emitted-ground-call-chez"
    | otherwise -> "validated-not-published"

residualSliceStaticShellArtifact :: String -> ResidualSlicePlan -> String
residualSliceStaticShellArtifact artifact = \case
  ResidualSlicePlanned _
    | artifact == "packet-v2" -> residualStaticShellName
  _ -> "none"

residualSliceStaticShellBridgeArtifact :: String -> ResidualSlicePlan -> String
residualSliceStaticShellBridgeArtifact artifact = \case
  ResidualSlicePlanned _
    | artifact == "packet-v2" -> typedHoleGroundBridgeName
  _ -> "none"

residualSliceStaticShellImportContract :: ResidualSlicePlan -> String
residualSliceStaticShellImportContract = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any (not . residualHoleSourceClosed) holes ->
        "opaque-lambda-lifted-import-v1"
    | otherwise -> "opaque-import-v1"

residualSliceStaticShellHoleForcing :: ResidualSlicePlan -> String
residualSliceStaticShellHoleForcing = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any (not . residualHoleSourceClosed) holes ->
        "lambda-lifted-explicit-environment-observation-by-id-v1"
    | otherwise -> "closed-hole-ground-observation-by-id-v1"

residualSliceStaticShellCallableElimination :: ResidualSlicePlan -> String
residualSliceStaticShellCallableElimination = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsAutomaticDependentGroundEnvironment holes ->
        "lambda-lifted-explicit+lexical-dependent-ground-elimination-v1"
    | any residualHoleSupportsAutomaticOrderedGroundEnvironment holes ->
        "lambda-lifted-explicit+lexical-ordered-ground-elimination-v1"
    | any (not . residualHoleSourceClosed) holes
    , any ((/= ResidualHoleObservationOnly) . residualHoleCallableAbi) holes ->
        "lambda-lifted-explicit-environment-ground-unary-elimination-v1"
    | any ((/= ResidualHoleObservationOnly) . residualHoleCallableAbi) holes ->
        "closed-ground-unary-elimination-v1"
    | otherwise -> "none"

residualSliceStaticShellTypedValueProxy :: ResidualSlicePlan -> String
residualSliceStaticShellTypedValueProxy = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsPersistentTypedValueProxy holes ->
        "persistent-typed-packet-v1"
    | otherwise -> "none"

residualSliceStaticShellProxyComposition :: ResidualSlicePlan -> String
residualSliceStaticShellProxyComposition = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsPersistentTypedValueProxy holes ->
        "parent-retained-recursive-gc-v1"
    | otherwise -> "none"

residualSliceStaticShellTypedValueCarrier :: ResidualSlicePlan -> String
residualSliceStaticShellTypedValueCarrier = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsPersistentTypedValueProxy holes ->
        "checked-packet-reference-v1"
    | otherwise -> "none"

residualSliceStaticShellProxyMapping :: ResidualSlicePlan -> String
residualSliceStaticShellProxyMapping = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsPersistentTypedValueProxy holes ->
        "named-checked-function-v1"
    | otherwise -> "none"

residualSliceStaticShellProxyStoreQuota :: ResidualSlicePlan -> String
residualSliceStaticShellProxyStoreQuota = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsPersistentTypedValueProxy holes ->
        "count-256+bytes-67108864-v1"
    | otherwise -> "none"

residualSliceStaticShellProxyPublicationLock :: ResidualSlicePlan -> String
residualSliceStaticShellProxyPublicationLock = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsPersistentTypedValueProxy holes ->
        "atomic-mkdir-v1"
    | otherwise -> "none"

residualSliceStaticShellProxyStateTransactions :: ResidualSlicePlan -> String
residualSliceStaticShellProxyStateTransactions = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsPersistentTypedValueProxy holes ->
        "store-lock+atomic-state-v1"
    | otherwise -> "none"

residualSliceOpenHoleClosureConversion :: ResidualSlicePlan -> String
residualSliceOpenHoleClosureConversion = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any (not . residualHoleSourceClosed) holes ->
        "lambda-lifted-explicit-environment-v1"
    | otherwise -> "none"

residualSliceStaticShellEnvironmentBinding :: ResidualSlicePlan -> String
residualSliceStaticShellEnvironmentBinding = \case
  ResidualSliceNotApplicable _ -> "not-applicable"
  ResidualSlicePlanned holes
    | any residualHoleSupportsAutomaticDependentGroundEnvironment holes ->
        "dependent-ground-chez-lexical-binding-v1"
    | any residualHoleSupportsAutomaticOrderedGroundEnvironment holes ->
        "ordered-ground-chez-lexical-binding-v1"
    | not (null singleCodecs) ->
        "single-"
          ++ intercalate "+" singleCodecs
          ++ "-chez-lexical-binding-v1"
    | otherwise -> "none"
    where
      singleCodecs =
        [ renderResidualGroundCodec codec
        | codec <- allResidualGroundCodecs
        , any ((== Just codec) . residualHoleAutomaticSingleGroundCodec) holes
        ]

residualSliceTypedSource :: ResidualSlicePlan -> String
residualSliceTypedSource = \case
  ResidualSliceNotApplicable _ -> "whole-entry-internal-term+type"
  ResidualSlicePlanned holes
    | any (not . residualHoleSourceClosed) holes ->
        "checked-internal-subterm+telescope+type"
    | otherwise -> "checked-internal-subterm+type"

residualSliceHoleCount :: ResidualSlicePlan -> Int
residualSliceHoleCount = \case
  ResidualSliceNotApplicable _ -> 0
  ResidualSlicePlanned holes -> length holes

residualSliceHoleIds :: ResidualSlicePlan -> String
residualSliceHoleIds = \case
  ResidualSliceNotApplicable _ -> "none"
  ResidualSlicePlanned holes -> commaSeparated (map residualHoleId holes)

residualSliceIndependentArtifacts
  :: String
  -> ResidualSlicePlan
  -> String
residualSliceIndependentArtifacts artifact = \case
  ResidualSlicePlanned (_ : _) | artifact == "packet-v2" -> "true"
  _ -> "false"

residualSliceExecution :: String -> ResidualSlicePlan -> String
residualSliceExecution artifact = \case
  ResidualSlicePlanned holes
    | artifact == "packet-v2"
    , any residualHoleSupportsAutomaticDependentGroundEnvironment holes ->
        "split-explicit-and-dependent-ground-lexical-environment-observation-by-id-whole-entry-reference"
    | artifact == "packet-v2"
    , any residualHoleSupportsAutomaticOrderedGroundEnvironment holes ->
        "split-explicit-and-ordered-ground-lexical-environment-observation-by-id-whole-entry-reference"
    | artifact == "packet-v2"
    , any residualHoleSupportsAutomaticGroundEnvironment holes ->
        "split-explicit-and-single-ground-lexical-environment-observation-by-id-whole-entry-reference"
    | artifact == "packet-v2"
    , any (not . residualHoleSourceClosed) holes ->
        "split-explicit-environment-observation-by-id-whole-entry-reference"
    | artifact == "packet-v2" ->
        "split-ground-observation-by-id-whole-entry-reference"
  _ -> "whole-entry"

residualHolePacketName :: Int -> FilePath
residualHolePacketName index =
  "typed-residual-hole-" ++ show index ++ ".bin"

residualStaticShellName :: FilePath
residualStaticShellName = "residual-static-shell.ss"

typedHoleGroundBridgeName :: FilePath
typedHoleGroundBridgeName = "typed-hole-ground-bridge.sh"

stageTimingsName :: FilePath
stageTimingsName = "stage-timings.tsv"

buildResidualStaticShell
  :: CompiledDef
  -> ResidualSlicePlan
  -> TCM (Maybe String)
buildResidualStaticShell entry slicePlan =
  either
    (backendAbortWith SchemeLoweringFailed)
    pure
    (renderResidualStaticShell entry slicePlan)

renderResidualStaticShell
  :: CompiledDef
  -> ResidualSlicePlan
  -> Either String (Maybe String)
renderResidualStaticShell _ (ResidualSliceNotApplicable _) = Right Nothing
renderResidualStaticShell entry slicePlan@(ResidualSlicePlanned holes) = do
  validateChezCoreAbi
  unless (not $ null holes) $
    Left "mixed residual static shell has no typed-hole imports"
  unless (Map.size imports == length holes) $
    Left "mixed residual static shell has duplicate typed-hole paths"
  unless (Map.size effectiveImports == Map.size imports) $
    Left "mixed residual static shell import inventory is incomplete"
  body <- compileTermWithHoleImports effectiveImports [] [] 0 $
    compiledTerm entry
  pure $ Just $ unlines
    [ "; Generated by CubicalChez 0.1.0-dev."
    , "; Mixed residual static shell; typed holes start as opaque imports."
    , "; Chez core ABI: " ++ chezCoreAbiVersion declaredChezCoreAbi ++ "."
    , "; " ++ residualSliceStaticShellHoleForcing slicePlan
        ++ " calls the checked v2 runtime."
    , "#!chezscheme"
    , "(define cubical-chez-artifact-directory"
    , "  (let* ((script (car (command-line)))"
    , "         (absolute (if (path-absolute? script)"
    , "                       script"
    , "                       (path-build (current-directory) script))))"
    , "    (path-parent absolute)))"
    , "(define (cubical-chez-absolute-artifact path)"
    , "  (if (path-absolute? path)"
    , "      path"
    , "      (path-build cubical-chez-artifact-directory path)))"
    , "(define (cubical-chez-shell-quote value)"
    , "  (let loop ((chars (string->list value)) (pieces '()))"
    , "    (if (null? chars)"
    , "        (string-append \"'\" (apply string-append (reverse pieces)) \"'\")"
    , "        (loop (cdr chars)"
    , "              (cons (if (char=? (car chars) (integer->char 39))"
    , "                        \"'\\\"'\\\"'\""
    , "                        (string (car chars)))"
    , "                    pieces)))))"
    , "(define (cubical-chez-bridge-fail code detail)"
    , "  (error 'cubical-chez-typed-hole (string-append code \"; \" detail)))"
    , "(define (cubical-chez-decode-ground datum status)"
    , "  (unless (and (list? status) (= (length status) 2)"
    , "               (eq? (car status) 'ccz-bridge-status-v1)"
    , "               (integer? (cadr status)) (exact? (cadr status))"
    , "               (>= (cadr status) 0))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"invalid bridge exit status\"))"
    , "  (cond"
    , "    ((and (list? datum) (= (length datum) 3)"
    , "          (eq? (car datum) 'ccz-ground-v1))"
    , "     (unless (= (cadr status) 0)"
    , "       (cubical-chez-bridge-fail"
    , "         \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"result with nonzero exit\"))"
    , "     (case (cadr datum)"
    , "       ((bool)"
    , "        (case (caddr datum)"
    , "          ((true) (vector 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true))"
    , "          ((false) (vector 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false))"
    , "          (else (cubical-chez-bridge-fail"
    , "                  \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"invalid Bool payload\"))))"
    , "       ((nat)"
    , "        (if (and (integer? (caddr datum)) (exact? (caddr datum))"
    , "                 (>= (caddr datum) 0))"
    , "            (caddr datum)"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"invalid Nat payload\")))"
    , "       (else (cubical-chez-bridge-fail"
    , "               \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"unknown ground type\"))))"
    , "    ((and (list? datum) (= (length datum) 3)"
    , "          (eq? (car datum) 'ccz-proxy-v1)"
    , "          (string? (cadr datum)) (string? (caddr datum)))"
    , "     (unless (= (cadr status) 0)"
    , "       (cubical-chez-bridge-fail"
    , "         \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"proxy with nonzero exit\"))"
    , "     (vector 'cubical-chez-typed-value-proxy-v1"
    , "             (cadr datum) (caddr datum)))"
    , "    ((and (list? datum) (= (length datum) 3)"
    , "          (eq? (car datum) 'ccz-bridge-error-v1)"
    , "          (symbol? (cadr datum)))"
    , "     (when (= (cadr status) 0)"
    , "       (cubical-chez-bridge-fail"
    , "         \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"error with zero exit\"))"
    , "     (cubical-chez-bridge-fail"
    , "       (symbol->string (cadr datum)) (format \"~a\" (caddr datum))))"
    , "    (else (cubical-chez-bridge-fail"
    , "            \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"invalid bridge response\"))))"
    , "(define cubical-chez-ordered-ground-capability-prefix"
    , "  \"ordered-\")"
    , renderSchemeGroundCodecRegistry
    , "(define cubical-chez-ground-codec-registry-fingerprint-v1"
    , "  " ++ schemeString renderResidualGroundCodecRegistry ++ ")"
    , "(define (cubical-chez-ground-codec-registry-fragment codecs)"
    , "  (let loop ((rest codecs) (fragment \"\"))"
    , "    (if (null? rest)"
    , "        fragment"
    , "        (loop (cdr rest)"
    , "          (string-append fragment"
    , "            (if (string=? fragment \"\") \"\" \",\")"
    , "            (car rest))))))"
    , "(define (cubical-chez-valid-ground-codec-registry? codecs)"
    , "  (and (list? codecs)"
    , "       (= (length codecs) " ++ show (length allResidualGroundCodecs) ++ ")"
    , "       (let loop ((rest codecs) (seen '()))"
    , "         (or (null? rest)"
    , "             (and (string? (car rest))"
    , "                  (> (string-length (car rest)) 0)"
    , "                  (not (member (car rest) seen))"
    , "                  (loop (cdr rest) (cons (car rest) seen)))))"
    , "       (string=?"
    , "         (cubical-chez-ground-codec-registry-fragment codecs)"
    , "         cubical-chez-ground-codec-registry-fingerprint-v1)))"
    , "(unless (cubical-chez-valid-ground-codec-registry?"
    , "          cubical-chez-ground-codec-registry-v1)"
    , "  (cubical-chez-bridge-fail"
    , "    \"CCZ-TYPED-BRIDGE-PROTOCOL\""
    , "    \"generated ground codec registry failed self-check\"))"
    , "(define (cubical-chez-ground-unary-capability codec)"
    , "  (string-append codec \"-unary-ground-elimination-v1\"))"
    , "(define (cubical-chez-valid-ground-unary-capability? capability)"
    , "  (and (string? capability)"
    , "       (let loop ((codecs cubical-chez-ground-codec-registry-v1))"
    , "         (and (pair? codecs)"
    , "              (or (string=? capability"
    , "                    (cubical-chez-ground-unary-capability (car codecs)))"
    , "                  (loop (cdr codecs)))))))"
    , "(define (cubical-chez-valid-ground-codec? codec)"
    , "  (and (string? codec)"
    , "       (member codec cubical-chez-ground-codec-registry-v1)))"
    , "(define (cubical-chez-valid-ground-codecs? codecs)"
    , "  (and (vector? codecs)"
    , "       (>= (vector-length codecs) 2)"
    , "       (<= (vector-length codecs) 64)"
    , "       (let loop ((index 0))"
    , "         (or (= index (vector-length codecs))"
    , "             (and (cubical-chez-valid-ground-codec?"
    , "                    (vector-ref codecs index))"
    , "                  (loop (+ index 1)))))))"
    , "(define (cubical-chez-ground-codecs-fragment codecs)"
    , "  (unless (cubical-chez-valid-ground-codecs? codecs)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"ordered environment requires 2..64 Bool/Nat/Word64/Char/Int codecs\"))"
    , "  (let loop ((index 0) (fragment \"\"))"
    , "    (if (= index (vector-length codecs))"
    , "        fragment"
    , "        (loop (+ index 1)"
    , "          (string-append fragment"
    , "            (if (= index 0) \"\" \"+\")"
    , "            (vector-ref codecs index))))))"
    , "(define (cubical-chez-ground-codecs-capability codecs)"
    , "  (string-append \"ordered-\""
    , "    (cubical-chez-ground-codecs-fragment codecs)"
    , "    \"-ground-environment-elimination-v1\"))"
    , "(define (cubical-chez-ordered-ground-capability? capability)"
    , "  (and (string? capability)"
    , "       (> (string-length capability)"
    , "          (string-length cubical-chez-ordered-ground-capability-prefix))"
    , "       (string=?"
    , "         (substring capability 0"
    , "           (string-length cubical-chez-ordered-ground-capability-prefix))"
    , "         cubical-chez-ordered-ground-capability-prefix)))"
    , "(define (cubical-chez-valid-typed-hole-handle? handle)"
    , "  (and (vector? handle) (= (vector-length handle) 4)"
    , "               (eq? (vector-ref handle 0)"
    , "                    'cubical-chez-typed-hole-import-v1)"
    , "               (string? (vector-ref handle 1))"
    , "               (string? (vector-ref handle 2))"
    , "               (or (string=? (vector-ref handle 3) \"none\")"
    , "                 (cubical-chez-valid-ground-unary-capability?"
    , "                   (vector-ref handle 3))"
    , "                 (string=? (vector-ref handle 3)"
    , "                   \"dependent-ground-environment-elimination-v1\")"
    , "                 (cubical-chez-ordered-ground-capability?"
    , "                   (vector-ref handle 3)))))"
    , "(define (cubical-chez-agda-bool-literal value)"
    , "  (unless (and (vector? value) (= (vector-length value) 1))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\" \"expected Chez Agda Bool\"))"
    , "  (case (vector-ref value 0)"
    , "    ((agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true) \"true\")"
    , "    ((agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false) \"false\")"
    , "    (else"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"unknown Chez Agda Bool constructor\"))))"
    , "(define (cubical-chez-valid-bound-bool-hole? value)"
    , "  (and (vector? value) (= (vector-length value) 3)"
    , "       (eq? (vector-ref value 0)"
    , "            'cubical-chez-typed-hole-bound-bool-v1)"
    , "       (cubical-chez-valid-typed-hole-handle? (vector-ref value 1))"
    , "       (member (vector-ref value 2) '(\"true\" \"false\"))))"
    , "(define (cubical-chez-bind-bool-environment handle value)"
    , "  (unless (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "               (string=? (vector-ref handle 3)"
    , "                 \"bool-unary-ground-elimination-v1\"))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"typed hole does not accept one Bool environment\"))"
    , "  (vector 'cubical-chez-typed-hole-bound-bool-v1"
    , "          handle (cubical-chez-agda-bool-literal value)))"
    , "(define (cubical-chez-valid-bound-nat-hole? value)"
    , "  (and (vector? value) (= (vector-length value) 3)"
    , "       (eq? (vector-ref value 0)"
    , "            'cubical-chez-typed-hole-bound-nat-v1)"
    , "       (cubical-chez-valid-typed-hole-handle? (vector-ref value 1))"
    , "       (integer? (vector-ref value 2))"
    , "       (exact? (vector-ref value 2))"
    , "       (>= (vector-ref value 2) 0)"
    , "       (<= (vector-ref value 2) 4294967295)))"
    , "(define (cubical-chez-bind-nat-environment handle value)"
    , "  (unless (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "               (string=? (vector-ref handle 3)"
    , "                 \"nat-unary-ground-elimination-v1\"))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"typed hole does not accept one Nat environment\"))"
    , "  (unless (and (integer? value) (exact? value)"
    , "               (>= value 0) (<= value 4294967295))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"expected bounded Chez Agda Nat\"))"
    , "  (vector 'cubical-chez-typed-hole-bound-nat-v1 handle value))"
    , "(define (cubical-chez-valid-bound-word64-hole? value)"
    , "  (and (vector? value) (= (vector-length value) 3)"
    , "       (eq? (vector-ref value 0)"
    , "            'cubical-chez-typed-hole-bound-word64-v1)"
    , "       (cubical-chez-valid-typed-hole-handle? (vector-ref value 1))"
    , "       (integer? (vector-ref value 2))"
    , "       (exact? (vector-ref value 2))"
    , "       (>= (vector-ref value 2) 0)"
    , "       (<= (vector-ref value 2) 18446744073709551615)))"
    , "(define (cubical-chez-bind-word64-environment handle value)"
    , "  (unless (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "               (string=? (vector-ref handle 3)"
    , "                 \"word64-unary-ground-elimination-v1\"))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"typed hole does not accept one Word64 environment\"))"
    , "  (unless (and (integer? value) (exact? value)"
    , "               (>= value 0)"
    , "               (<= value 18446744073709551615))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"expected bounded Chez Agda Word64\"))"
    , "  (vector 'cubical-chez-typed-hole-bound-word64-v1 handle value))"
    , "(define (cubical-chez-valid-char-codepoint? value)"
    , "  (and (integer? value) (exact? value)"
    , "       (>= value 0) (<= value 1114111)"
    , "       (not (and (>= value 55296) (<= value 57343)))))"
    , "(define (cubical-chez-valid-bound-char-hole? value)"
    , "  (and (vector? value) (= (vector-length value) 3)"
    , "       (eq? (vector-ref value 0)"
    , "            'cubical-chez-typed-hole-bound-char-v1)"
    , "       (cubical-chez-valid-typed-hole-handle? (vector-ref value 1))"
    , "       (cubical-chez-valid-char-codepoint? (vector-ref value 2))))"
    , "(define (cubical-chez-bind-char-environment handle value)"
    , "  (unless (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "               (string=? (vector-ref handle 3)"
    , "                 \"char-unary-ground-elimination-v1\"))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"typed hole does not accept one Char environment\"))"
    , "  (unless (char? value)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"expected Chez Agda Char\"))"
    , "  (vector 'cubical-chez-typed-hole-bound-char-v1"
    , "          handle (char->integer value)))"
    , "(define (cubical-chez-valid-int64? value)"
    , "  (and (integer? value) (exact? value)"
    , "       (>= value -9223372036854775808)"
    , "       (<= value 9223372036854775807)))"
    , "(define cubical-chez-agda-int-pos-tag"
    , "  'agda_Agda_2e_Builtin_2e_Int_2e_Int_2e_pos)"
    , "(define cubical-chez-agda-int-negsuc-tag"
    , "  'agda_Agda_2e_Builtin_2e_Int_2e_Int_2e_negsuc)"
    , "(define (cubical-chez-valid-agda-int? value)"
    , "  (and (vector? value) (= (vector-length value) 2)"
    , "       (let ((tag (vector-ref value 0)) (magnitude (vector-ref value 1)))"
    , "         (and (or (eq? tag cubical-chez-agda-int-pos-tag)"
    , "                  (eq? tag cubical-chez-agda-int-negsuc-tag))"
    , "              (integer? magnitude) (exact? magnitude)"
    , "              (>= magnitude 0)"
    , "              (<= magnitude 9223372036854775807)))))"
    , "(define (cubical-chez-agda-int->integer value)"
    , "  (unless (cubical-chez-valid-agda-int? value)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"expected signed-64 Chez Agda Int\"))"
    , "  (let ((magnitude (vector-ref value 1)))"
    , "    (if (eq? (vector-ref value 0) cubical-chez-agda-int-pos-tag)"
    , "        magnitude (- (+ magnitude 1)))))"
    , "(define (cubical-chez-integer->agda-int value)"
    , "  (unless (cubical-chez-valid-int64? value)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"Int argument must be within signed 64-bit range\"))"
    , "  (if (>= value 0)"
    , "      (vector cubical-chez-agda-int-pos-tag value)"
    , "      (vector cubical-chez-agda-int-negsuc-tag (- (- value) 1))))"
    , "(define (cubical-chez-int-term value)"
    , "  (unless (cubical-chez-valid-int64? value)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-CALL\""
    , "      \"Int argument must be within signed 64-bit range\"))"
    , "  (if (>= value 0)"
    , "      (string-append \"(Agda.Builtin.Int.pos \""
    , "        (number->string value) \" )\")"
    , "      (string-append \"(Agda.Builtin.Int.negsuc \""
    , "        (number->string (- (- value) 1)) \" )\")))"
    , "(define (cubical-chez-valid-bound-int-hole? value)"
    , "  (and (vector? value) (= (vector-length value) 3)"
    , "       (eq? (vector-ref value 0)"
    , "            'cubical-chez-typed-hole-bound-int-v1)"
    , "       (cubical-chez-valid-typed-hole-handle? (vector-ref value 1))"
    , "       (cubical-chez-valid-int64? (vector-ref value 2))))"
    , "(define (cubical-chez-bind-int-environment handle value)"
    , "  (unless (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "               (string=? (vector-ref handle 3)"
    , "                 \"int-unary-ground-elimination-v1\"))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"typed hole does not accept one Int environment\"))"
    , "  (vector 'cubical-chez-typed-hole-bound-int-v1 handle"
    , "          (cubical-chez-agda-int->integer value)))"
    , "(define (cubical-chez-ground-literal codec value)"
    , "  (cubical-chez-ground-codec-value-literal codec value))"
    , "(define (cubical-chez-valid-dependent-ground-value? value)"
    , "  (or"
    , "    (and (vector? value) (= (vector-length value) 1)"
    , "         (member (vector-ref value 0)"
    , "           '(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true"
    , "             agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false)))"
    , "    (char? value)"
    , "    (cubical-chez-valid-agda-int? value)"
    , "    (and (integer? value) (exact? value)"
    , "         (>= value -9223372036854775808)"
    , "         (<= value 18446744073709551615))))"
    , "(define (cubical-chez-bind-ground-environment handle codecs values)"
    , "  (unless (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "               (cubical-chez-valid-ground-codecs? codecs)"
    , "               (vector? values)"
    , "               (= (vector-length values) (vector-length codecs))"
    , "               (string=? (vector-ref handle 3)"
    , "                 (cubical-chez-ground-codecs-capability codecs)))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"typed hole does not accept the ordered ground environment\"))"
    , "  (let ((literals (make-vector (vector-length codecs))))"
    , "    (let loop ((index 0))"
    , "      (unless (= index (vector-length codecs))"
    , "        (vector-set! literals index"
    , "          (cubical-chez-ground-literal"
    , "            (vector-ref codecs index) (vector-ref values index)))"
    , "        (loop (+ index 1))))"
    , "    (vector 'cubical-chez-typed-hole-bound-ground-environment-v1"
    , "            handle codecs literals)))"
    , "(define (cubical-chez-bind-dependent-ground-environment handle arity values)"
    , "  (unless (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "               (string=? (vector-ref handle 3)"
    , "                 \"dependent-ground-environment-elimination-v1\")"
    , "               (integer? arity) (exact? arity)"
    , "               (>= arity 2) (<= arity 64)"
    , "               (vector? values) (= (vector-length values) arity))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"typed hole does not accept this dependent environment arity\"))"
    , "  (let loop ((index 0))"
    , "    (unless (= index arity)"
    , "      (unless (cubical-chez-valid-dependent-ground-value?"
    , "                (vector-ref values index))"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "          \"dependent environment value is not Bool/Nat/Word64 ground\"))"
    , "      (loop (+ index 1))))"
    , "  (vector"
    , "    'cubical-chez-typed-hole-bound-dependent-ground-environment-v1"
    , "    handle values))"
    , "(define (cubical-chez-force-typed-hole handle)"
    , "  (unless (cubical-chez-valid-typed-hole-handle? handle)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"invalid opaque import handle\"))"
    , "  (putenv \"CUBICAL_CHEZ_TYPED_HOLE_ID\" (vector-ref handle 1))"
    , "  (putenv \"CUBICAL_CHEZ_TYPED_PACKET\""
    , "          (cubical-chez-absolute-artifact (vector-ref handle 2)))"
    , "  (let ((command"
    , "          (string-append"
    , "            \"/bin/sh \""
    , "            (cubical-chez-shell-quote"
    , "              (path-build cubical-chez-artifact-directory"
    , "                          \"typed-hole-ground-bridge.sh\"))"
    , "            \"; cubical_chez_status=$?; \""
    , "            \"printf '(ccz-bridge-status-v1 %s)\\\\n' \""
    , "            \"\\\"$cubical_chez_status\\\"\")))"
    , "    (call-with-values"
    , "      (lambda () (open-process-ports command 'block (native-transcoder)))"
    , "      (lambda (to-stdin from-stdout from-stderr process-id)"
    , "        (close-output-port to-stdin)"
    , "        (let* ((datum (read from-stdout))"
    , "              (status (read from-stdout))"
    , "              (tail (read from-stdout))"
    , "              (dirty-error (get-string-all from-stderr)))"
    , "          (close-input-port from-stdout)"
    , "          (close-input-port from-stderr)"
    , "          (unless (eof-object? tail)"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"multiple bridge responses\"))"
    , "          (unless (eof-object? dirty-error)"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"bridge wrote stderr\"))"
    , "          (cubical-chez-decode-ground datum status))))))"
    , "(define cubical-chez-typed-holes '())"
    , "(define (cubical-chez-register-typed-hole id packet callable-abi)"
    , "  (let ((handle"
    , "          (vector 'cubical-chez-typed-hole-import-v1"
    , "                  id packet callable-abi)))"
    , "    (unless (cubical-chez-valid-typed-hole-handle? handle)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"invalid typed-hole capability\"))"
    , "    (when (assoc id cubical-chez-typed-holes)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROTOCOL\" \"duplicate typed-hole id\"))"
    , "    (set! cubical-chez-typed-holes"
    , "          (cons (cons id handle) cubical-chez-typed-holes))"
    , "    handle))"
    , unlines
        [ "(cubical-chez-register-typed-hole "
            ++ schemeString (residualHoleId hole)
            ++ " "
            ++ schemeString (residualHolePacketName index)
            ++ " "
            ++ schemeString
              (renderResidualHoleCallableAbi $ residualHoleCallableAbi hole)
            ++ ")"
        | (index, hole) <- zip [(1 :: Int) ..] holes
        ]
    , "(define (cubical-chez-typed-hole-reference id)"
    , "  (let ((entry (assoc id cubical-chez-typed-holes)))"
    , "    (if entry"
    , "        (cdr entry)"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROTOCOL\""
    , "          (string-append \"unregistered typed-hole id: \" id)))))"
    , "(define " ++ mangleQName (compiledName entry) ++ " " ++ body ++ ")"
    , "(define cubical-chez-planned-hole-ids"
    , "  (list "
        ++ unwords (map (schemeString . residualHoleId) holes)
        ++ "))"
    , "(define (cubical-chez-string-prefix? prefix value)"
    , "  (let ((prefix-length (string-length prefix)))"
    , "    (and (>= (string-length value) prefix-length)"
    , "         (string=? (substring value 0 prefix-length) prefix))))"
    , "(define cubical-chez-force-hole-prefix \"--force-hole=\")"
    , "(define (cubical-chez-force-hole-argument? argument)"
    , "  (cubical-chez-string-prefix? cubical-chez-force-hole-prefix argument))"
    , "(define (cubical-chez-requested-hole-ids arguments)"
    , "  (cond"
    , "    ((null? arguments) '())"
    , "    ((cubical-chez-force-hole-argument? (car arguments))"
    , "     (cons (substring (car arguments)"
    , "                      (string-length cubical-chez-force-hole-prefix)"
    , "                      (string-length (car arguments)))"
    , "           (cubical-chez-requested-hole-ids (cdr arguments))))"
    , "    (else (cubical-chez-requested-hole-ids (cdr arguments)))))"
    , "(define (cubical-chez-select-typed-hole arguments)"
    , "  (let ((ids (cubical-chez-requested-hole-ids arguments))"
    , "        (force-first? (member \"--force-first-hole\" arguments)))"
    , "    (when (or (> (length ids) 1) (and force-first? (pair? ids)))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-HOLE-SELECTION\""
    , "        \"choose exactly one forcing selector\"))"
    , "    (cond"
    , "      ((pair? ids)"
    , "       (when (string=? (car ids) \"\")"
    , "         (cubical-chez-bridge-fail"
    , "           \"CCZ-TYPED-BRIDGE-HOLE-SELECTION\" \"empty hole id\"))"
    , "       (let ((entry (assoc (car ids) cubical-chez-typed-holes)))"
    , "         (if entry"
    , "             (cdr entry)"
    , "             (cubical-chez-bridge-fail"
    , "               \"CCZ-TYPED-BRIDGE-HOLE-SELECTION\""
    , "               (string-append \"unknown hole id: \" (car ids))))))"
    , "      (force-first?"
    , "       (if (pair? cubical-chez-planned-hole-ids)"
    , "           (cdr (assoc (car cubical-chez-planned-hole-ids)"
    , "                       cubical-chez-typed-holes))"
    , "           (cubical-chez-bridge-fail"
    , "             \"CCZ-TYPED-BRIDGE-HOLE-SELECTION\""
    , "             \"static shell has no hole\")))"
    , "      (else #f))))"
    , "(define cubical-chez-hole-consumer-prefix \"--hole-consumer=\")"
    , "(define (cubical-chez-string-index value wanted start)"
    , "  (let loop ((index start))"
    , "    (cond"
    , "      ((>= index (string-length value)) #f)"
    , "      ((char=? (string-ref value index) wanted) index)"
    , "      (else (loop (+ index 1))))))"
    , "(define (cubical-chez-parse-hole-consumer argument)"
    , "  (let* ((prefix-length"
    , "           (string-length cubical-chez-hole-consumer-prefix))"
    , "         (payload (substring argument prefix-length"
    , "                             (string-length argument)))"
    , "         (separator (cubical-chez-string-index payload #\\= 0)))"
    , "    (unless (and separator (> separator 0)"
    , "                 (< separator (- (string-length payload) 1)))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-OBSERVATION\""
    , "        \"hole consumer must be ID=QNAME\"))"
    , "    (cons (substring payload 0 separator)"
    , "          (substring payload (+ separator 1)"
    , "                     (string-length payload)))))"
    , "(define (cubical-chez-requested-hole-consumers arguments)"
    , "  (cond"
    , "    ((null? arguments) '())"
    , "    ((cubical-chez-string-prefix? cubical-chez-hole-consumer-prefix"
    , "                                   (car arguments))"
    , "     (cons (cubical-chez-parse-hole-consumer (car arguments))"
    , "           (cubical-chez-requested-hole-consumers (cdr arguments))))"
    , "    (else (cubical-chez-requested-hole-consumers (cdr arguments)))))"
    , "(define (cubical-chez-validate-hole-consumers mappings)"
    , "  (let loop ((pending mappings) (validated '()))"
    , "    (if (null? pending)"
    , "        (begin"
    , "          (for-each"
    , "            (lambda (id)"
    , "              (unless (assoc id validated)"
    , "                (cubical-chez-bridge-fail"
    , "                  \"CCZ-TYPED-BRIDGE-OBSERVATION\""
    , "                  (string-append \"missing consumer for \" id))))"
    , "            cubical-chez-planned-hole-ids)"
    , "          validated)"
    , "        (let ((mapping (car pending)))"
    , "          (when (assoc (car mapping) validated)"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-OBSERVATION\""
    , "              (string-append \"duplicate consumer for \""
    , "                             (car mapping))))"
    , "          (unless (assoc (car mapping) cubical-chez-typed-holes)"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-OBSERVATION\""
    , "              (string-append \"consumer for unknown hole \""
    , "                             (car mapping))))"
    , "          (loop (cdr pending) (cons mapping validated))))))"
    , "(define (cubical-chez-observe-all-ground mappings)"
    , "  (list->vector"
    , "    (cons 'cubical-chez-ground-observations-v1"
    , "      (map"
    , "        (lambda (id)"
    , "          (let ((hole (assoc id cubical-chez-typed-holes))"
    , "                (consumer (assoc id mappings)))"
    , "            (putenv \"CUBICAL_CHEZ_TYPED_CONSUMER\" (cdr consumer))"
    , "            (vector id"
    , "                    (cubical-chez-force-typed-hole (cdr hole)))))"
    , "        cubical-chez-planned-hole-ids))))"
    , "(define cubical-chez-call-bool-hole-prefix \"--call-bool-hole=\")"
    , "(define cubical-chez-call-bool-argument-prefix \"--bool-argument=\")"
    , "(define cubical-chez-call-nat-hole-prefix \"--call-nat-hole=\")"
    , "(define cubical-chez-call-nat-argument-prefix \"--nat-argument=\")"
    , "(define cubical-chez-call-word64-hole-prefix \"--call-word64-hole=\")"
    , "(define cubical-chez-call-word64-argument-prefix \"--word64-argument=\")"
    , "(define cubical-chez-call-char-hole-prefix \"--call-char-hole=\")"
    , "(define cubical-chez-call-char-argument-prefix \"--char-codepoint=\")"
    , "(define cubical-chez-call-int-hole-prefix \"--call-int-hole=\")"
    , "(define cubical-chez-call-int-argument-prefix \"--int-argument=\")"
    , "(define cubical-chez-call-ground-hole-prefix \"--call-ground-hole=\")"
    , "(define cubical-chez-call-ground-argument-prefix"
    , "  \"--ground-argument=\")"
    , "(define cubical-chez-call-hole-type-prefix \"--call-hole-type=\")"
    , "(define cubical-chez-call-result-consumer-prefix"
    , "  \"--call-result-consumer=\")"
    , "(define cubical-chez-call-proxy-id-prefix \"--call-proxy-id=\")"
    , "(define (cubical-chez-call-argument? argument)"
    , "  (or"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-bool-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-bool-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-nat-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-nat-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-word64-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-word64-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-char-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-char-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-int-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-int-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-ground-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-ground-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-hole-type-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-result-consumer-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-call-proxy-id-prefix argument)))"
    , "(define (cubical-chez-call-requested? arguments)"
    , "  (cond"
    , "    ((null? arguments) #f)"
    , "    ((cubical-chez-call-argument? (car arguments)) #t)"
    , "    (else (cubical-chez-call-requested? (cdr arguments)))))"
    , "(define (cubical-chez-prefixed-values prefix arguments)"
    , "  (cond"
    , "    ((null? arguments) '())"
    , "    ((cubical-chez-string-prefix? prefix (car arguments))"
    , "     (cons"
    , "       (substring (car arguments) (string-length prefix)"
    , "                  (string-length (car arguments)))"
    , "       (cubical-chez-prefixed-values prefix (cdr arguments))))"
    , "    (else (cubical-chez-prefixed-values prefix (cdr arguments)))))"
    , "(define (cubical-chez-exactly-one-call-value prefix label arguments)"
    , "  (let ((values (cubical-chez-prefixed-values prefix arguments)))"
    , "    (unless (= (length values) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-CALL\""
    , "        (string-append \"call requires exactly one \" label)))"
    , "    (when (string=? (car values) \"\")"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-CALL\""
    , "        (string-append \"empty \" label)))"
    , "    (car values)))"
    , "(define (cubical-chez-safe-qname? value)"
    , "  (and (> (string-length value) 0)"
    , "       (let loop ((characters (string->list value)))"
    , "         (or (null? characters)"
    , "             (and"
    , "               (let ((character (car characters)))"
    , "                 (or (char-alphabetic? character)"
    , "                     (char-numeric? character)"
    , "                     (char=? character #\\.)"
    , "                     (char=? character #\\_)"
    , "                     (char=? character #\\-)"
    , "                     (char=? character #\\')))"
    , "               (loop (cdr characters)))))))"
    , "(define (cubical-chez-valid-bool-argument? value)"
    , "  (or (string=? value \"true\") (string=? value \"false\")))"
    , "(define (cubical-chez-valid-nat-argument? value)"
    , "  (and (> (string-length value) 0)"
    , "       (<= (string-length value) 10)"
    , "       (let loop ((characters (string->list value)))"
    , "         (or (null? characters)"
    , "             (and (char-numeric? (car characters))"
    , "                  (loop (cdr characters)))))"
    , "       (let ((number (string->number value)))"
    , "         (and number (integer? number) (exact? number)"
    , "              (>= number 0) (<= number 4294967295)))))"
    , "(define (cubical-chez-valid-word64-argument? value)"
    , "  (and (> (string-length value) 0)"
    , "       (<= (string-length value) 20)"
    , "       (let loop ((characters (string->list value)))"
    , "         (or (null? characters)"
    , "             (and (char-numeric? (car characters))"
    , "                  (loop (cdr characters)))))"
    , "       (let ((number (string->number value)))"
    , "         (and number (integer? number) (exact? number)"
    , "              (>= number 0)"
    , "              (<= number 18446744073709551615)))))"
    , "(define (cubical-chez-valid-char-argument? value)"
    , "  (and (> (string-length value) 0)"
    , "       (<= (string-length value) 7)"
    , "       (let loop ((characters (string->list value)))"
    , "         (or (null? characters)"
    , "             (and (char-numeric? (car characters))"
    , "                  (loop (cdr characters)))))"
    , "       (let ((number (string->number value)))"
    , "         (and number (cubical-chez-valid-char-codepoint? number)))))"
    , "(define (cubical-chez-valid-int-argument? value)"
    , "  (and (> (string-length value) 0)"
    , "       (<= (string-length value) 20)"
    , "       (let ((number (string->number value)))"
    , "         (and number"
    , "              (cubical-chez-valid-int64? number)"
    , "              (string=? value (number->string number))))))"
    , renderSchemeGroundCodecDescriptors
    , "(define (cubical-chez-ground-codec-descriptor codec)"
    , "  (let loop ((descriptors cubical-chez-ground-codec-descriptors-v1))"
    , "    (cond"
    , "      ((null? descriptors) #f)"
    , "      ((string=? codec (vector-ref (car descriptors) 0))"
    , "       (car descriptors))"
    , "      (else (loop (cdr descriptors))))))"
    , "(define (cubical-chez-valid-ground-codec-descriptors? descriptors codecs)"
    , "  (and (list? descriptors) (list? codecs)"
    , "       (= (length descriptors) (length codecs))"
    , "       (let loop ((remaining descriptors) (names codecs))"
    , "         (or (and (null? remaining) (null? names))"
    , "             (and (pair? remaining) (pair? names)"
    , "                  (let ((descriptor (car remaining))"
    , "                        (codec (car names)))"
    , "                    (and (vector? descriptor)"
    , "                         (= (vector-length descriptor) 7)"
    , "                         (string=? (vector-ref descriptor 0) codec)"
    , "                         (string=? (vector-ref descriptor 1)"
    , "                           (cubical-chez-ground-unary-capability codec))"
    , "                         (string=? (vector-ref descriptor 2)"
    , "                           (string-append codec \":\"))"
    , "                         (procedure? (vector-ref descriptor 3))"
    , "                         (procedure? (vector-ref descriptor 4))"
    , "                         (procedure? (vector-ref descriptor 5))"
    , "                         (procedure? (vector-ref descriptor 6))"
    , "                         (loop (cdr remaining) (cdr names)))))))))"
    , "(unless (cubical-chez-valid-ground-codec-descriptors?"
    , "          cubical-chez-ground-codec-descriptors-v1"
    , "          cubical-chez-ground-codec-registry-v1)"
    , "  (cubical-chez-bridge-fail"
    , "    \"CCZ-TYPED-BRIDGE-PROTOCOL\""
    , "    \"generated ground codec descriptors failed self-check\"))"
    , "(define (cubical-chez-ground-spec-descriptor spec failure-code detail)"
    , "  (let loop ((descriptors cubical-chez-ground-codec-descriptors-v1))"
    , "    (if (null? descriptors)"
    , "        (cubical-chez-bridge-fail failure-code detail)"
    , "        (let* ((descriptor (car descriptors))"
    , "               (prefix (vector-ref descriptor 2)))"
    , "          (if (cubical-chez-string-prefix? prefix spec)"
    , "              descriptor"
    , "              (loop (cdr descriptors)))))))"
    , "(define (cubical-chez-ground-codec-valid-argument? codec literal)"
    , "  (let ((descriptor (cubical-chez-ground-codec-descriptor codec)))"
    , "    (and descriptor ((vector-ref descriptor 3) literal))))"
    , "(define (cubical-chez-ground-codec-argument-literal codec literal)"
    , "  (let ((descriptor (cubical-chez-ground-codec-descriptor codec)))"
    , "    (unless (and descriptor ((vector-ref descriptor 3) literal))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-CALL\""
    , "        (string-append \"invalid \" codec \" argument\")))"
    , "    ((vector-ref descriptor 4) literal)))"
    , "(define (cubical-chez-ground-codec-entry-value codec literal)"
    , "  (let ((descriptor (cubical-chez-ground-codec-descriptor codec)))"
    , "    (unless descriptor"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\" \"unknown entry ground codec\"))"
    , "    ((vector-ref descriptor 5) literal)))"
    , "(define (cubical-chez-ground-codec-value-literal codec value)"
    , "  (let ((descriptor (cubical-chez-ground-codec-descriptor codec)))"
    , "    (unless descriptor"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"unknown ordered environment codec\"))"
    , "    ((vector-ref descriptor 6) value)))"
    , "(define (cubical-chez-call-action arguments)"
    , "  (let ((consumers"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-result-consumer-prefix arguments))"
    , "        (proxy-ids"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-proxy-id-prefix arguments)))"
    , "    (cond"
    , "      ((and (= (length consumers) 1) (null? proxy-ids)"
    , "            (not (string=? (car consumers) \"\")))"
    , "       (vector 'consume (car consumers)))"
    , "      ((and (= (length proxy-ids) 1) (null? consumers)"
    , "            (not (string=? (car proxy-ids) \"\")))"
    , "       (vector 'proxy (car proxy-ids)))"
    , "      (else"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-CALL\""
    , "          \"select exactly one call result consumer or proxy ID\")))))"
    , "(define (cubical-chez-call-ground-spec-codec spec)"
    , "  (vector-ref"
    , "    (cubical-chez-ground-spec-descriptor spec"
    , "      \"CCZ-TYPED-BRIDGE-CALL\" \"unknown ground argument codec\")"
    , "    0))"
    , "(define (cubical-chez-call-ground-spec-literal spec)"
    , "  (let* ((descriptor"
    , "           (cubical-chez-ground-spec-descriptor spec"
    , "             \"CCZ-TYPED-BRIDGE-CALL\" \"unknown ground argument codec\"))"
    , "         (codec (vector-ref descriptor 0))"
    , "         (prefix (vector-ref descriptor 2))"
    , "         (literal"
    , "           (substring spec (string-length prefix) (string-length spec))))"
    , "    (cubical-chez-ground-codec-argument-literal codec literal)))"
    , "(define (cubical-chez-call-ground-arguments arguments)"
    , "  (let ((specs"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-ground-argument-prefix arguments)))"
    , "    (unless (and (>= (length specs) 2) (<= (length specs) 64))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-CALL\""
    , "        \"explicit ground call requires 2..64 arguments\"))"
    , "    (vector"
    , "      (list->vector (map cubical-chez-call-ground-spec-codec specs))"
    , "      (list->vector (map cubical-chez-call-ground-spec-literal specs)))))"
    , "(define (cubical-chez-ordered-ground-call-abi codecs)"
    , "  (let loop ((index 0) (joined \"\"))"
    , "    (if (= index (vector-length codecs))"
    , "        (string-append"
    , "          \"ordered-\" joined \"-ground-environment-elimination-v1\")"
    , "        (loop (+ index 1)"
    , "          (string-append"
    , "            joined (if (= index 0) \"\" \"+\")"
    , "            (vector-ref codecs index))))))"
    , "(define (cubical-chez-call-mode arguments)"
    , "  (let ((bool-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-bool-hole-prefix arguments))"
    , "        (bool-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-bool-argument-prefix arguments))"
    , "        (nat-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-nat-hole-prefix arguments))"
    , "        (nat-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-nat-argument-prefix arguments))"
    , "        (word64-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-word64-hole-prefix arguments))"
    , "        (word64-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-word64-argument-prefix arguments))"
    , "        (char-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-char-hole-prefix arguments))"
    , "        (char-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-char-argument-prefix arguments))"
    , "        (int-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-int-hole-prefix arguments))"
    , "        (int-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-int-argument-prefix arguments))"
    , "        (ground-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-ground-hole-prefix arguments))"
    , "        (ground-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-call-ground-argument-prefix arguments)))"
    , "    (cond"
    , "      ((and (= (length bool-holes) 1)"
    , "            (= (length bool-arguments) 1)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? int-holes) (null? int-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"bool\")"
    , "      ((and (= (length nat-holes) 1)"
    , "            (= (length nat-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? int-holes) (null? int-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"nat\")"
    , "      ((and (= (length word64-holes) 1)"
    , "            (= (length word64-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? int-holes) (null? int-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"word64\")"
    , "      ((and (= (length char-holes) 1)"
    , "            (= (length char-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? int-holes) (null? int-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"char\")"
    , "      ((and (= (length int-holes) 1)"
    , "            (= (length int-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"int\")"
    , "      ((and (= (length ground-holes) 1)"
    , "            (>= (length ground-arguments) 2)"
    , "            (<= (length ground-arguments) 64)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? int-holes) (null? int-arguments))"
    , "       \"ground\")"
    , "      (else"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-CALL\""
    , "          \"select one unary codec or one 2..64 ground vector\")))))"
    , "(define (cubical-chez-call-ground-hole config)"
    , "  (let* ((codec (vector-ref config 0))"
    , "         (id (vector-ref config 1))"
    , "         (argument (vector-ref config 2))"
    , "         (hole-type (vector-ref config 3))"
    , "         (action (vector-ref config 4))"
    , "         (entry (assoc id cubical-chez-typed-holes)))"
    , "    (unless entry"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-CALL\""
    , "        (string-append \"unknown callable hole: \" id)))"
    , "    (let ((handle (cdr entry)))"
    , "      (unless (cubical-chez-valid-typed-hole-handle? handle)"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-CALL\""
    , "          \"selected call handle is invalid\"))"
    , "      (unless (cubical-chez-safe-qname? hole-type)"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-CALL\""
    , "          \"call hole type must be a safe QName\"))"
    , "      (unless"
    , "        (and (vector? action) (= (vector-length action) 2)"
    , "             (or"
    , "               (and (eq? (vector-ref action 0) 'consume)"
    , "                    (cubical-chez-safe-qname? (vector-ref action 1)))"
    , "               (and (eq? (vector-ref action 0) 'proxy)"
    , "                    (cubical-chez-safe-proxy-id?"
    , "                      (vector-ref action 1)))))"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-CALL\""
    , "          \"call completion action is invalid\"))"
    , "      (if (string=? codec \"ground\")"
    , "          (let* ((codecs (vector-ref argument 0))"
    , "                 (literals (vector-ref argument 1))"
    , "                 (callable-abi (vector-ref handle 3))"
    , "                 (ordered-abi"
    , "                   (cubical-chez-ordered-ground-call-abi codecs)))"
    , "            (unless"
    , "              (or (string=? callable-abi ordered-abi)"
    , "                  (string=? callable-abi"
    , "                    \"dependent-ground-environment-elimination-v1\"))"
    , "              (cubical-chez-bridge-fail"
    , "                \"CCZ-TYPED-BRIDGE-CALL\""
    , "                \"ground vector disagrees with callable capability\"))"
    , "            (cubical-chez-complete-bound-application"
    , "              handle hole-type"
    , "              (cubical-chez-apply-agda-literals"
    , "                \"cubicalChezHole\" literals)"
    , "              action))"
    , "          (begin"
    , "            (unless"
    , "              (string=? (vector-ref handle 3)"
    , "                (string-append codec"
    , "                  \"-unary-ground-elimination-v1\"))"
    , "              (cubical-chez-bridge-fail"
    , "                \"CCZ-TYPED-BRIDGE-CALL\""
    , "                \"selected hole does not support the unary codec\"))"
    , "            (unless"
    , "              (cubical-chez-ground-codec-valid-argument? codec argument)"
    , "              (cubical-chez-bridge-fail"
    , "                \"CCZ-TYPED-BRIDGE-CALL\""
    , "                (string-append \"invalid \" codec \" argument\")))"
    , "            (cubical-chez-complete-bound-application"
    , "              handle hole-type"
    , "              (string-append"
    , "                \"(cubicalChezHole \""
    , "                (cubical-chez-ground-codec-argument-literal codec argument)"
    , "                \")\")"
    , "              action))))))"
    , "(define cubical-chez-auto-bind-bool-hole-prefix"
    , "  \"--auto-bind-bool-hole=\")"
    , "(define cubical-chez-entry-bool-argument-prefix"
    , "  \"--entry-bool-argument=\")"
    , "(define cubical-chez-auto-bind-nat-hole-prefix"
    , "  \"--auto-bind-nat-hole=\")"
    , "(define cubical-chez-entry-nat-argument-prefix"
    , "  \"--entry-nat-argument=\")"
    , "(define cubical-chez-auto-bind-word64-hole-prefix"
    , "  \"--auto-bind-word64-hole=\")"
    , "(define cubical-chez-entry-word64-argument-prefix"
    , "  \"--entry-word64-argument=\")"
    , "(define cubical-chez-auto-bind-char-hole-prefix"
    , "  \"--auto-bind-char-hole=\")"
    , "(define cubical-chez-entry-char-argument-prefix"
    , "  \"--entry-char-codepoint=\")"
    , "(define cubical-chez-auto-bind-int-hole-prefix"
    , "  \"--auto-bind-int-hole=\")"
    , "(define cubical-chez-entry-int-argument-prefix"
    , "  \"--entry-int-argument=\")"
    , "(define cubical-chez-auto-bind-ground-hole-prefix"
    , "  \"--auto-bind-ground-hole=\")"
    , "(define cubical-chez-entry-ground-argument-prefix"
    , "  \"--entry-ground-argument=\")"
    , "(define cubical-chez-auto-bind-hole-type-prefix"
    , "  \"--auto-bind-hole-type=\")"
    , "(define cubical-chez-auto-bind-result-consumer-prefix"
    , "  \"--auto-bind-result-consumer=\")"
    , "(define cubical-chez-auto-bind-proxy-id-prefix"
    , "  \"--auto-bind-proxy-id=\")"
    , "(define (cubical-chez-auto-bind-argument? argument)"
    , "  (or"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-bool-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-entry-bool-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-nat-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-entry-nat-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-word64-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-entry-word64-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-char-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-entry-char-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-int-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-entry-int-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-ground-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-entry-ground-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-hole-type-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-result-consumer-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-auto-bind-proxy-id-prefix argument)))"
    , "(define (cubical-chez-auto-bind-requested? arguments)"
    , "  (cond"
    , "    ((null? arguments) #f)"
    , "    ((cubical-chez-auto-bind-argument? (car arguments)) #t)"
    , "    (else (cubical-chez-auto-bind-requested? (cdr arguments)))))"
    , "(define (cubical-chez-auto-bind-mode arguments)"
    , "  (let ((bool-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-auto-bind-bool-hole-prefix arguments))"
    , "        (bool-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-entry-bool-argument-prefix arguments))"
    , "        (nat-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-auto-bind-nat-hole-prefix arguments))"
    , "        (nat-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-entry-nat-argument-prefix arguments))"
    , "        (word64-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-auto-bind-word64-hole-prefix arguments))"
    , "        (word64-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-entry-word64-argument-prefix arguments))"
    , "        (char-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-auto-bind-char-hole-prefix arguments))"
    , "        (char-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-entry-char-argument-prefix arguments))"
    , "        (int-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-auto-bind-int-hole-prefix arguments))"
    , "        (int-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-entry-int-argument-prefix arguments))"
    , "        (ground-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-auto-bind-ground-hole-prefix arguments))"
    , "        (ground-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-entry-ground-argument-prefix arguments)))"
    , "    (cond"
    , "      ((and (= (length ground-holes) 1)"
    , "            (>= (length ground-arguments) 2)"
    , "            (<= (length ground-arguments) 64)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? int-holes) (null? int-arguments))"
    , "       \"ordered-ground\")"
    , "      ((and (= (length bool-holes) 1)"
    , "            (= (length bool-arguments) 1)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? int-holes) (null? int-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"bool\")"
    , "      ((and (= (length nat-holes) 1)"
    , "            (= (length nat-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? int-holes) (null? int-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"nat\")"
    , "      ((and (= (length word64-holes) 1)"
    , "            (= (length word64-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? int-holes) (null? int-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"word64\")"
    , "      ((and (= (length char-holes) 1)"
    , "            (= (length char-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? int-holes) (null? int-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"char\")"
    , "      ((and (= (length int-holes) 1)"
    , "            (= (length int-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments)"
    , "            (null? nat-holes) (null? nat-arguments)"
    , "            (null? word64-holes) (null? word64-arguments)"
    , "            (null? char-holes) (null? char-arguments)"
    , "            (null? ground-holes) (null? ground-arguments))"
    , "       \"int\")"
    , "      (else"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "          \"select one single or ordered Bool/Nat/Word64/Char/Int environment codec\")))))"
    , "(define (cubical-chez-exactly-one-auto-bind-value"
    , "          prefix label arguments)"
    , "  (let ((values (cubical-chez-prefixed-values prefix arguments)))"
    , "    (unless (= (length values) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        (string-append"
    , "          \"automatic binding requires exactly one \" label)))"
    , "    (when (string=? (car values) \"\")"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        (string-append \"empty \" label)))"
    , "    (car values)))"
    , "(define (cubical-chez-auto-bind-action arguments)"
    , "  (let ((consumers"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-auto-bind-result-consumer-prefix arguments))"
    , "        (proxy-ids"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-auto-bind-proxy-id-prefix arguments)))"
    , "    (cond"
    , "      ((and (= (length consumers) 1) (null? proxy-ids)"
    , "            (not (string=? (car consumers) \"\")))"
    , "       (vector 'consume (car consumers)))"
    , "      ((and (= (length proxy-ids) 1) (null? consumers)"
    , "            (not (string=? (car proxy-ids) \"\")))"
    , "       (vector 'proxy (car proxy-ids)))"
    , "      (else"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "          \"select exactly one result consumer or proxy ID\")))))"
    , "(define (cubical-chez-entry-ground-spec-value spec)"
    , "  (let* ((descriptor"
    , "           (cubical-chez-ground-spec-descriptor spec"
    , "             \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "             \"unknown entry ground codec\"))"
    , "         (prefix (vector-ref descriptor 2))"
    , "         (literal"
    , "           (substring spec (string-length prefix) (string-length spec))))"
    , "    ((vector-ref descriptor 5) literal)))"
    , "(define (cubical-chez-entry-ground-spec-codec spec)"
    , "  (vector-ref"
    , "    (cubical-chez-ground-spec-descriptor spec"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"unknown entry ground codec\")"
    , "    0))"
    , "(define (cubical-chez-entry-ground-values arguments)"
    , "  (let ((specs"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-entry-ground-argument-prefix arguments)))"
    , "    (unless (and (>= (length specs) 2) (<= (length specs) 64))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"ordered environment requires 2..64 entry arguments\"))"
    , "    (vector"
    , "      (list->vector (map cubical-chez-entry-ground-spec-codec specs))"
    , "      (map cubical-chez-entry-ground-spec-value specs))))"
    , "(define (cubical-chez-agda-bool-value literal)"
    , "  (cond"
    , "    ((string=? literal \"true\")"
    , "     (vector 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true))"
    , "    ((string=? literal \"false\")"
    , "     (vector 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false))"
    , "    (else"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"entry Bool argument must be true or false\"))))"
    , "(define (cubical-chez-collect-bound-bool-holes value wanted-id)"
    , "  (cond"
    , "    ((cubical-chez-valid-bound-bool-hole? value)"
    , "     (if (string=? (vector-ref (vector-ref value 1) 1) wanted-id)"
    , "         (list value)"
    , "         '()))"
    , "    ((vector? value)"
    , "     (let loop ((index 0) (found '()))"
    , "       (if (= index (vector-length value))"
    , "           found"
    , "           (loop (+ index 1)"
    , "             (append found"
    , "               (cubical-chez-collect-bound-bool-holes"
    , "                 (vector-ref value index) wanted-id))))))"
    , "    ((pair? value)"
    , "     (append"
    , "       (cubical-chez-collect-bound-bool-holes (car value) wanted-id)"
    , "       (cubical-chez-collect-bound-bool-holes (cdr value) wanted-id)))"
    , "    (else '())))"
    , "(define (cubical-chez-complete-bound-application"
    , "          handle hole-type application action)"
    , "  (unless"
    , "    (and (vector? action) (= (vector-length action) 2)"
    , "         (member (vector-ref action 0) '(consume proxy))"
    , "         (string? (vector-ref action 1)))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"invalid automatic binding completion action\"))"
    , "  (case (vector-ref action 0)"
    , "    ((consume)"
    , "     (unless (and (cubical-chez-safe-qname? hole-type)"
    , "                  (cubical-chez-safe-qname? (vector-ref action 1)))"
    , "       (cubical-chez-bridge-fail"
    , "         \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "         \"bound hole type and consumer must be safe QNames\"))"
    , "     (putenv \"CUBICAL_CHEZ_TYPED_MODE\" \"ground\")"
    , "     (putenv"
    , "       \"CUBICAL_CHEZ_TYPED_CONSUMER\""
    , "       (string-append"
    , "         \"(λ (cubicalChezHole : \" hole-type \") → \""
    , "         (vector-ref action 1) \" \" application \")\"))"
    , "     (cubical-chez-force-typed-hole handle))"
    , "    ((proxy)"
    , "     (cubical-chez-materialize-application-proxy"
    , "       handle hole-type application (vector-ref action 1)))))"
    , "(define (cubical-chez-force-bound-bool-hole"
    , "          bound-hole hole-type action)"
    , "  (unless (cubical-chez-valid-bound-bool-hole? bound-hole)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\" \"invalid bound Bool hole\"))"
    , "  (let ((handle (vector-ref bound-hole 1))"
    , "        (environment (vector-ref bound-hole 2)))"
    , "    (cubical-chez-complete-bound-application"
    , "      handle hole-type"
    , "      (string-append"
    , "        \"(cubicalChezHole Agda.Builtin.Bool.\" environment \")\")"
    , "      action)))"
    , "(define (cubical-chez-auto-observe-bound-bool config entry)"
    , "  (unless (procedure? entry)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry is not callable with one Bool environment\"))"
    , "  (let* ((id (vector-ref config 1))"
    , "         (entry-argument (vector-ref config 2))"
    , "         (hole-type (vector-ref config 3))"
    , "         (action (vector-ref config 4))"
    , "         (entry-result"
    , "           (entry (cubical-chez-agda-bool-value entry-argument)))"
    , "         (matches"
    , "           (cubical-chez-collect-bound-bool-holes entry-result id)))"
    , "    (unless (= (length matches) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"entry result must contain exactly one selected bound hole\"))"
    , "    (cubical-chez-force-bound-bool-hole"
    , "      (car matches) hole-type action)))"
    , "(define (cubical-chez-agda-nat-value literal)"
    , "  (unless (cubical-chez-valid-nat-argument? literal)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry Nat argument must be within 0..4294967295\"))"
    , "  (string->number literal))"
    , "(define (cubical-chez-agda-word64-value literal)"
    , "  (unless (cubical-chez-valid-word64-argument? literal)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry Word64 argument must be within 0..18446744073709551615\"))"
    , "  (string->number literal))"
    , "(define (cubical-chez-agda-char-value literal)"
    , "  (unless (cubical-chez-valid-char-argument? literal)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry Char codepoint must be a Unicode scalar\"))"
    , "  (integer->char (string->number literal)))"
    , "(define (cubical-chez-agda-int-value literal)"
    , "  (unless (cubical-chez-valid-int-argument? literal)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry Int argument must be within signed 64-bit range\"))"
    , "  (cubical-chez-integer->agda-int (string->number literal)))"
    , "(define (cubical-chez-collect-bound-nat-holes value wanted-id)"
    , "  (cond"
    , "    ((cubical-chez-valid-bound-nat-hole? value)"
    , "     (if (string=? (vector-ref (vector-ref value 1) 1) wanted-id)"
    , "         (list value)"
    , "         '()))"
    , "    ((vector? value)"
    , "     (let loop ((index 0) (found '()))"
    , "       (if (= index (vector-length value))"
    , "           found"
    , "           (loop (+ index 1)"
    , "             (append found"
    , "               (cubical-chez-collect-bound-nat-holes"
    , "                 (vector-ref value index) wanted-id))))))"
    , "    ((pair? value)"
    , "     (append"
    , "       (cubical-chez-collect-bound-nat-holes (car value) wanted-id)"
    , "       (cubical-chez-collect-bound-nat-holes (cdr value) wanted-id)))"
    , "    (else '())))"
    , "(define (cubical-chez-force-bound-nat-hole"
    , "          bound-hole hole-type action)"
    , "  (unless (cubical-chez-valid-bound-nat-hole? bound-hole)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\" \"invalid bound Nat hole\"))"
    , "  (let ((handle (vector-ref bound-hole 1))"
    , "        (environment (number->string (vector-ref bound-hole 2))))"
    , "    (cubical-chez-complete-bound-application"
    , "      handle hole-type"
    , "      (string-append \"(cubicalChezHole \" environment \")\")"
    , "      action)))"
    , "(define (cubical-chez-auto-observe-bound-nat config entry)"
    , "  (unless (procedure? entry)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry is not callable with one Nat environment\"))"
    , "  (let* ((id (vector-ref config 1))"
    , "         (entry-argument (vector-ref config 2))"
    , "         (hole-type (vector-ref config 3))"
    , "         (action (vector-ref config 4))"
    , "         (entry-result"
    , "           (entry (cubical-chez-agda-nat-value entry-argument)))"
    , "         (matches"
    , "           (cubical-chez-collect-bound-nat-holes entry-result id)))"
    , "    (unless (= (length matches) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"entry result must contain exactly one selected bound hole\"))"
    , "    (cubical-chez-force-bound-nat-hole"
    , "      (car matches) hole-type action)))"
    , "(define (cubical-chez-collect-bound-word64-holes value wanted-id)"
    , "  (cond"
    , "    ((cubical-chez-valid-bound-word64-hole? value)"
    , "     (if (string=? (vector-ref (vector-ref value 1) 1) wanted-id)"
    , "         (list value)"
    , "         '()))"
    , "    ((vector? value)"
    , "     (let loop ((index 0) (found '()))"
    , "       (if (= index (vector-length value))"
    , "           found"
    , "           (loop (+ index 1)"
    , "             (append found"
    , "               (cubical-chez-collect-bound-word64-holes"
    , "                 (vector-ref value index) wanted-id))))))"
    , "    ((pair? value)"
    , "     (append"
    , "       (cubical-chez-collect-bound-word64-holes (car value) wanted-id)"
    , "       (cubical-chez-collect-bound-word64-holes (cdr value) wanted-id)))"
    , "    (else '())))"
    , "(define (cubical-chez-force-bound-word64-hole"
    , "          bound-hole hole-type action)"
    , "  (unless (cubical-chez-valid-bound-word64-hole? bound-hole)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\" \"invalid bound Word64 hole\"))"
    , "  (let ((handle (vector-ref bound-hole 1))"
    , "        (environment (number->string (vector-ref bound-hole 2))))"
    , "    (cubical-chez-complete-bound-application"
    , "      handle hole-type"
    , "      (string-append"
    , "        \"(cubicalChezHole (Agda.Builtin.Word.primWord64FromNat \""
    , "        environment \" ))\")"
    , "      action)))"
    , "(define (cubical-chez-auto-observe-bound-word64 config entry)"
    , "  (unless (procedure? entry)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry is not callable with one Word64 environment\"))"
    , "  (let* ((id (vector-ref config 1))"
    , "         (entry-argument (vector-ref config 2))"
    , "         (hole-type (vector-ref config 3))"
    , "         (action (vector-ref config 4))"
    , "         (entry-result"
    , "           (entry (cubical-chez-agda-word64-value entry-argument)))"
    , "         (matches"
    , "           (cubical-chez-collect-bound-word64-holes entry-result id)))"
    , "    (unless (= (length matches) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"entry result must contain exactly one selected bound hole\"))"
    , "    (cubical-chez-force-bound-word64-hole"
    , "      (car matches) hole-type action)))"
    , "(define (cubical-chez-collect-bound-char-holes value wanted-id)"
    , "  (cond"
    , "    ((cubical-chez-valid-bound-char-hole? value)"
    , "     (if (string=? (vector-ref (vector-ref value 1) 1) wanted-id)"
    , "         (list value)"
    , "         '()))"
    , "    ((vector? value)"
    , "     (let loop ((index 0) (found '()))"
    , "       (if (= index (vector-length value))"
    , "           found"
    , "           (loop (+ index 1)"
    , "             (append found"
    , "               (cubical-chez-collect-bound-char-holes"
    , "                 (vector-ref value index) wanted-id))))))"
    , "    ((pair? value)"
    , "     (append"
    , "       (cubical-chez-collect-bound-char-holes (car value) wanted-id)"
    , "       (cubical-chez-collect-bound-char-holes (cdr value) wanted-id)))"
    , "    (else '())))"
    , "(define (cubical-chez-force-bound-char-hole"
    , "          bound-hole hole-type action)"
    , "  (unless (cubical-chez-valid-bound-char-hole? bound-hole)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\" \"invalid bound Char hole\"))"
    , "  (let ((handle (vector-ref bound-hole 1))"
    , "        (codepoint (number->string (vector-ref bound-hole 2))))"
    , "    (cubical-chez-complete-bound-application"
    , "      handle hole-type"
    , "      (string-append"
    , "        \"(cubicalChezHole (Agda.Builtin.Char.primNatToChar \""
    , "        codepoint \" ))\")"
    , "      action)))"
    , "(define (cubical-chez-auto-observe-bound-char config entry)"
    , "  (unless (procedure? entry)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry is not callable with one Char environment\"))"
    , "  (let* ((id (vector-ref config 1))"
    , "         (entry-argument (vector-ref config 2))"
    , "         (hole-type (vector-ref config 3))"
    , "         (action (vector-ref config 4))"
    , "         (entry-result"
    , "           (entry (cubical-chez-agda-char-value entry-argument)))"
    , "         (matches"
    , "           (cubical-chez-collect-bound-char-holes entry-result id)))"
    , "    (unless (= (length matches) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"entry result must contain exactly one selected bound hole\"))"
    , "    (cubical-chez-force-bound-char-hole"
    , "      (car matches) hole-type action)))"
    , "(define (cubical-chez-collect-bound-int-holes value wanted-id)"
    , "  (cond"
    , "    ((cubical-chez-valid-bound-int-hole? value)"
    , "     (if (string=? (vector-ref (vector-ref value 1) 1) wanted-id)"
    , "         (list value) '()))"
    , "    ((vector? value)"
    , "     (let loop ((index 0) (found '()))"
    , "       (if (= index (vector-length value))"
    , "           found"
    , "           (loop (+ index 1)"
    , "             (append found"
    , "               (cubical-chez-collect-bound-int-holes"
    , "                 (vector-ref value index) wanted-id))))))"
    , "    ((pair? value)"
    , "     (append"
    , "       (cubical-chez-collect-bound-int-holes (car value) wanted-id)"
    , "       (cubical-chez-collect-bound-int-holes (cdr value) wanted-id)))"
    , "    (else '())))"
    , "(define (cubical-chez-force-bound-int-hole"
    , "          bound-hole hole-type action)"
    , "  (unless (cubical-chez-valid-bound-int-hole? bound-hole)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\" \"invalid bound Int hole\"))"
    , "  (let ((handle (vector-ref bound-hole 1))"
    , "        (environment (vector-ref bound-hole 2)))"
    , "    (cubical-chez-complete-bound-application"
    , "      handle hole-type"
    , "      (string-append \"(cubicalChezHole \""
    , "        (cubical-chez-int-term environment) \")\")"
    , "      action)))"
    , "(define (cubical-chez-auto-observe-bound-int config entry)"
    , "  (unless (procedure? entry)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry is not callable with one Int environment\"))"
    , "  (let* ((id (vector-ref config 1))"
    , "         (entry-argument (vector-ref config 2))"
    , "         (hole-type (vector-ref config 3))"
    , "         (action (vector-ref config 4))"
    , "         (entry-result"
    , "           (entry (cubical-chez-agda-int-value entry-argument)))"
    , "         (matches"
    , "           (cubical-chez-collect-bound-int-holes entry-result id)))"
    , "    (unless (= (length matches) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"entry result must contain exactly one selected bound hole\"))"
    , "    (cubical-chez-force-bound-int-hole"
    , "      (car matches) hole-type action)))"
    , "(define (cubical-chez-valid-bound-ground-environment? value)"
    , "  (and (vector? value) (= (vector-length value) 4)"
    , "       (eq? (vector-ref value 0)"
    , "            'cubical-chez-typed-hole-bound-ground-environment-v1)"
    , "       (cubical-chez-valid-typed-hole-handle? (vector-ref value 1))"
    , "       (cubical-chez-valid-ground-codecs? (vector-ref value 2))"
    , "       (vector? (vector-ref value 3))"
    , "       (= (vector-length (vector-ref value 2))"
    , "          (vector-length (vector-ref value 3)))"
    , "       (let loop ((index 0))"
    , "         (or (= index (vector-length (vector-ref value 3)))"
    , "             (and (string? (vector-ref (vector-ref value 3) index))"
    , "                  (loop (+ index 1)))))))"
    , "(define (cubical-chez-valid-bound-dependent-ground-environment? value)"
    , "  (and (vector? value) (= (vector-length value) 3)"
    , "       (eq? (vector-ref value 0)"
    , "            'cubical-chez-typed-hole-bound-dependent-ground-environment-v1)"
    , "       (cubical-chez-valid-typed-hole-handle? (vector-ref value 1))"
    , "       (string=? (vector-ref (vector-ref value 1) 3)"
    , "         \"dependent-ground-environment-elimination-v1\")"
    , "       (vector? (vector-ref value 2))"
    , "       (>= (vector-length (vector-ref value 2)) 2)"
    , "       (<= (vector-length (vector-ref value 2)) 64)"
    , "       (let loop ((index 0))"
    , "         (or (= index (vector-length (vector-ref value 2)))"
    , "             (and (cubical-chez-valid-dependent-ground-value?"
    , "                    (vector-ref (vector-ref value 2) index))"
    , "                  (loop (+ index 1)))))))"
    , "(define (cubical-chez-collect-bound-ground-environments value wanted-id)"
    , "  (cond"
    , "    ((or (cubical-chez-valid-bound-ground-environment? value)"
    , "         (cubical-chez-valid-bound-dependent-ground-environment? value))"
    , "     (if (string=? (vector-ref (vector-ref value 1) 1) wanted-id)"
    , "         (list value)"
    , "         '()))"
    , "    ((vector? value)"
    , "     (let loop ((index 0) (found '()))"
    , "       (if (= index (vector-length value))"
    , "           found"
    , "           (loop (+ index 1)"
    , "             (append found"
    , "               (cubical-chez-collect-bound-ground-environments"
    , "                 (vector-ref value index) wanted-id))))))"
    , "    ((pair? value)"
    , "     (append"
    , "       (cubical-chez-collect-bound-ground-environments"
    , "         (car value) wanted-id)"
    , "       (cubical-chez-collect-bound-ground-environments"
    , "         (cdr value) wanted-id)))"
    , "    (else '())))"
    , "(define (cubical-chez-apply-agda-literals function literals)"
    , "  (let loop ((index 0) (application function))"
    , "    (if (= index (vector-length literals))"
    , "        application"
    , "        (loop (+ index 1)"
    , "          (string-append \"(\" application \" \""
    , "            (vector-ref literals index) \")\")))))"
    , "(define (cubical-chez-force-bound-ground-environment"
    , "          bound-hole hole-type action)"
    , "  (unless (cubical-chez-valid-bound-ground-environment? bound-hole)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"invalid bound ordered ground environment\"))"
    , "  (let ((handle (vector-ref bound-hole 1))"
    , "        (literals (vector-ref bound-hole 3)))"
    , "    (cubical-chez-complete-bound-application"
    , "      handle hole-type"
    , "      (cubical-chez-apply-agda-literals"
    , "        \"cubicalChezHole\" literals)"
    , "      action)))"
    , "(define (cubical-chez-dependent-ground-values-match? captured supplied)"
    , "  (and (vector? captured) (list? supplied)"
    , "       (= (vector-length captured) (length supplied))"
    , "       (let loop ((index 0) (remaining supplied))"
    , "         (or (= index (vector-length captured))"
    , "             (and (pair? remaining)"
    , "                  (equal? (vector-ref captured index) (car remaining))"
    , "                  (loop (+ index 1) (cdr remaining)))))))"
    , "(define (cubical-chez-dependent-ground-literals codecs values)"
    , "  (unless (and (cubical-chez-valid-ground-codecs? codecs)"
    , "               (vector? values)"
    , "               (= (vector-length codecs) (vector-length values)))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"dependent ground codec/value arity mismatch\"))"
    , "  (let ((literals (make-vector (vector-length codecs))))"
    , "    (let loop ((index 0))"
    , "      (unless (= index (vector-length codecs))"
    , "        (vector-set! literals index"
    , "          (cubical-chez-ground-literal"
    , "            (vector-ref codecs index) (vector-ref values index)))"
    , "        (loop (+ index 1))))"
    , "    literals))"
    , "(define (cubical-chez-force-bound-dependent-ground-environment"
    , "          bound-hole entry-codecs entry-arguments hole-type action)"
    , "  (unless (cubical-chez-valid-bound-dependent-ground-environment?"
    , "            bound-hole)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"invalid bound dependent ground environment\"))"
    , "  (let ((handle (vector-ref bound-hole 1))"
    , "        (values (vector-ref bound-hole 2)))"
    , "    (unless (cubical-chez-dependent-ground-values-match?"
    , "              values entry-arguments)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"captured dependent values disagree with entry arguments\"))"
    , "    (cubical-chez-complete-bound-application"
    , "      handle hole-type"
    , "      (cubical-chez-apply-agda-literals"
    , "        \"cubicalChezHole\""
    , "        (cubical-chez-dependent-ground-literals entry-codecs values))"
    , "      action)))"
    , "(define (cubical-chez-apply-entry-ground-arguments entry arguments)"
    , "  (let loop ((current entry) (remaining arguments))"
    , "    (if (null? remaining)"
    , "        current"
    , "        (begin"
    , "          (unless (procedure? current)"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "              \"entry ground argument count exceeds callable arity\"))"
    , "          (loop (current (car remaining)) (cdr remaining))))))"
    , "(define (cubical-chez-auto-observe-bound-ground config entry)"
    , "  (unless (procedure? entry)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "      \"entry is not callable with an ordered ground environment\"))"
    , "  (let* ((id (vector-ref config 1))"
    , "         (entry-ground (vector-ref config 2))"
    , "         (entry-codecs (vector-ref entry-ground 0))"
    , "         (entry-arguments (vector-ref entry-ground 1))"
    , "         (hole-type (vector-ref config 3))"
    , "         (action (vector-ref config 4))"
    , "         (entry-result"
    , "           (cubical-chez-apply-entry-ground-arguments"
    , "             entry entry-arguments))"
    , "         (matches"
    , "           (cubical-chez-collect-bound-ground-environments"
    , "             entry-result id)))"
    , "    (unless (= (length matches) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "        \"entry result must contain exactly one selected bound hole\"))"
    , "    (if (cubical-chez-valid-bound-dependent-ground-environment?"
    , "          (car matches))"
    , "        (cubical-chez-force-bound-dependent-ground-environment"
    , "          (car matches) entry-codecs entry-arguments hole-type action)"
    , "        (begin"
    , "          (unless (equal? entry-codecs (vector-ref (car matches) 2))"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "              \"entry ground codec vector disagrees with checked hole domains\"))"
    , "          (cubical-chez-force-bound-ground-environment"
    , "            (car matches) hole-type action)))))"
    , "(define cubical-chez-materialize-bool-hole-prefix"
    , "  \"--materialize-bool-hole=\")"
    , "(define cubical-chez-materialize-bool-argument-prefix"
    , "  \"--materialize-bool-argument=\")"
    , "(define cubical-chez-materialize-nat-hole-prefix"
    , "  \"--materialize-nat-hole=\")"
    , "(define cubical-chez-materialize-nat-argument-prefix"
    , "  \"--materialize-nat-argument=\")"
    , "(define cubical-chez-materialize-hole-type-prefix"
    , "  \"--materialize-hole-type=\")"
    , "(define cubical-chez-proxy-id-prefix \"--proxy-id=\")"
    , "(define cubical-chez-derive-proxy-prefix \"--derive-proxy=\")"
    , "(define cubical-chez-derive-proxy-consumer-prefix"
    , "  \"--derive-proxy-consumer=\")"
    , "(define cubical-chez-consume-proxy-prefix \"--consume-proxy=\")"
    , "(define cubical-chez-proxy-consumer-prefix \"--proxy-consumer=\")"
    , "(define cubical-chez-map-proxy-prefix \"--map-proxy=\")"
    , "(define cubical-chez-map-proxy-function-prefix"
    , "  \"--map-proxy-function=\")"
    , "(define cubical-chez-map-proxy-result-consumer-prefix"
    , "  \"--map-proxy-result-consumer=\")"
    , "(define cubical-chez-drop-proxy-prefix \"--drop-proxy=\")"
    , "(define cubical-chez-gc-proxies-argument \"--gc-proxies\")"
    , "(define (cubical-chez-proxy-argument? argument)"
    , "  (or"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-materialize-bool-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-materialize-bool-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-materialize-nat-hole-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-materialize-nat-argument-prefix argument)"
    , "    (cubical-chez-string-prefix?"
    , "      cubical-chez-materialize-hole-type-prefix argument)))"
    , "(define (cubical-chez-proxy-requested? arguments)"
    , "  (cond"
    , "    ((null? arguments) #f)"
    , "    ((cubical-chez-proxy-argument? (car arguments)) #t)"
    , "    (else (cubical-chez-proxy-requested? (cdr arguments)))))"
    , "(define (cubical-chez-prefix-requested? prefix arguments)"
    , "  (cond"
    , "    ((null? arguments) #f)"
    , "    ((cubical-chez-string-prefix? prefix (car arguments)) #t)"
    , "    (else (cubical-chez-prefix-requested? prefix (cdr arguments)))))"
    , "(define (cubical-chez-exactly-one-proxy-value prefix label arguments)"
    , "  (let ((values (cubical-chez-prefixed-values prefix arguments)))"
    , "    (unless (= (length values) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\""
    , "        (string-append \"proxy operation requires exactly one \" label)))"
    , "    (when (string=? (car values) \"\")"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\""
    , "        (string-append \"empty \" label)))"
    , "    (car values)))"
    , "(define (cubical-chez-zero-or-one-proxy-value prefix label arguments)"
    , "  (let ((values (cubical-chez-prefixed-values prefix arguments)))"
    , "    (when (> (length values) 1)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\""
    , "        (string-append \"proxy operation accepts at most one \" label)))"
    , "    (if (null? values)"
    , "        #f"
    , "        (begin"
    , "          (when (string=? (car values) \"\")"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-PROXY\""
    , "              (string-append \"empty \" label)))"
    , "          (car values)))))"
    , "(define (cubical-chez-safe-proxy-id? value)"
    , "  (and (> (string-length value) 0) (<= (string-length value) 64)"
    , "       (let loop ((characters (string->list value)))"
    , "         (or (null? characters)"
    , "             (let* ((character (car characters))"
    , "                    (code (char->integer character)))"
    , "               (and"
    , "                 (or (and (>= code 48) (<= code 57))"
    , "                     (and (>= code 65) (<= code 90))"
    , "                     (and (>= code 97) (<= code 122))"
    , "                     (char=? character #\\_)"
    , "                     (char=? character #\\-))"
    , "                 (loop (cdr characters))))))))"
    , "(define (cubical-chez-proxy-packet-name proxy-id)"
    , "  (string-append \"typed-proxy-\" proxy-id \".bin\"))"
    , "(define (cubical-chez-proxy-meta-name proxy-id)"
    , "  (string-append \"typed-proxy-\" proxy-id \".meta\"))"
    , "(define (cubical-chez-string-suffix? suffix value)"
    , "  (let ((suffix-length (string-length suffix))"
    , "        (value-length (string-length value)))"
    , "    (and (>= value-length suffix-length)"
    , "         (string=?"
    , "           (substring value (- value-length suffix-length) value-length)"
    , "           suffix))))"
    , "(define (cubical-chez-proxy-file-id filename suffix)"
    , "  (let ((prefix \"typed-proxy-\"))"
    , "    (and (cubical-chez-string-prefix? prefix filename)"
    , "         (cubical-chez-string-suffix? suffix filename)"
    , "         (let ((proxy-id"
    , "                 (substring filename (string-length prefix)"
    , "                   (- (string-length filename)"
    , "                      (string-length suffix)))))"
    , "           (and (cubical-chez-safe-proxy-id? proxy-id) proxy-id)))))"
    , "(define (cubical-chez-proxy-ids suffix)"
    , "  (let loop ((files (directory-list cubical-chez-artifact-directory))"
    , "             (ids '()))"
    , "    (if (null? files)"
    , "        (reverse ids)"
    , "        (let ((proxy-id"
    , "                (cubical-chez-proxy-file-id (car files) suffix)))"
    , "          (loop (cdr files)"
    , "                (if proxy-id (cons proxy-id ids) ids))))))"
    , "(define cubical-chez-proxy-store-lock"
    , "  (cubical-chez-absolute-artifact \".typed-proxy-store.lock\"))"
    , "(define cubical-chez-proxy-store-lock-owner"
    , "  (path-build cubical-chez-proxy-store-lock \"owner\"))"
    , "(define cubical-chez-proxy-store-lock-delay"
    , "  (make-time 'time-duration 10000000 0))"
    , "(define (cubical-chez-try-create-proxy-store-lock)"
    , "  (guard (condition (else #f))"
    , "    (mkdir cubical-chez-proxy-store-lock #o700)"
    , "    #t))"
    , "(define (cubical-chez-read-proxy-store-lock-owner)"
    , "  (and (file-exists? cubical-chez-proxy-store-lock-owner)"
    , "       (guard (condition (else #f))"
    , "         (call-with-input-file cubical-chez-proxy-store-lock-owner"
    , "           (lambda (port)"
    , "             (let* ((owner (read port)) (tail (read port)))"
    , "               (and (integer? owner) (exact? owner) (> owner 0)"
    , "                    (eof-object? tail) owner)))))))"
    , "(define (cubical-chez-proxy-store-owner-alive? owner)"
    , "  (= (system (string-append \"kill -0 \" (number->string owner)"
    , "                            \" 2>/dev/null\"))"
    , "     0))"
    , "(define (cubical-chez-remove-proxy-store-lock)"
    , "  (when (file-exists? cubical-chez-proxy-store-lock-owner)"
    , "    (guard (condition (else #f))"
    , "      (delete-file cubical-chez-proxy-store-lock-owner)))"
    , "  (when (file-directory? cubical-chez-proxy-store-lock)"
    , "    (guard (condition (else #f))"
    , "      (delete-directory cubical-chez-proxy-store-lock))))"
    , "(define (cubical-chez-acquire-proxy-store-lock)"
    , "  (let loop ((attempt 0))"
    , "    (if (cubical-chez-try-create-proxy-store-lock)"
    , "        (guard"
    , "          (condition"
    , "            (else"
    , "              (cubical-chez-remove-proxy-store-lock)"
    , "              (cubical-chez-bridge-fail"
    , "                \"CCZ-TYPED-BRIDGE-TRANSACTION\" \"lock owner write\")))"
    , "          (call-with-output-file"
    , "            cubical-chez-proxy-store-lock-owner"
    , "            (lambda (port)"
    , "              (write (get-process-id) port) (newline port))"
    , "            'error))"
    , "        (let ((owner (cubical-chez-read-proxy-store-lock-owner)))"
    , "          (cond"
    , "            ((and owner"
    , "                  (not (cubical-chez-proxy-store-owner-alive? owner)))"
    , "             (cubical-chez-remove-proxy-store-lock)"
    , "             (loop (+ attempt 1)))"
    , "            ((and (not owner) (>= attempt 100))"
    , "             (cubical-chez-remove-proxy-store-lock)"
    , "             (loop (+ attempt 1)))"
    , "            ((>= attempt 500)"
    , "             (cubical-chez-bridge-fail"
    , "               \"CCZ-TYPED-BRIDGE-TRANSACTION\" \"lock timeout\"))"
    , "            (else"
    , "              (sleep cubical-chez-proxy-store-lock-delay)"
    , "              (loop (+ attempt 1))))))))"
    , "(define (cubical-chez-release-proxy-store-lock)"
    , "  (let ((owner (cubical-chez-read-proxy-store-lock-owner)))"
    , "    (unless (and owner (= owner (get-process-id)))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-TRANSACTION\" \"lock ownership lost\"))"
    , "    (cubical-chez-remove-proxy-store-lock)))"
    , "(define (cubical-chez-with-proxy-store-lock action)"
    , "  (cubical-chez-acquire-proxy-store-lock)"
    , "  (dynamic-wind"
    , "    (lambda () #t)"
    , "    action"
    , "    cubical-chez-release-proxy-store-lock))"
    , "(define (cubical-chez-read-proxy-meta proxy-id)"
    , "  (let ((path"
    , "          (cubical-chez-absolute-artifact"
    , "            (cubical-chez-proxy-meta-name proxy-id))))"
    , "    (unless (file-exists? path)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\" \"proxy metadata does not exist\"))"
    , "    (call-with-input-file path"
    , "      (lambda (port)"
    , "        (let* ((meta (read port)) (tail (read port)))"
    , "          (unless"
    , "            (and (eof-object? tail)"
    , "                 (vector? meta) (= (vector-length meta) 4)"
    , "                 (eq? (vector-ref meta 0) 'ccz-proxy-meta-v1)"
    , "                 (string? (vector-ref meta 1))"
    , "                 (string=? (vector-ref meta 1) proxy-id)"
    , "                 (string? (vector-ref meta 2))"
    , "                 (or (string=? (vector-ref meta 2) \".\")"
    , "                     (cubical-chez-safe-proxy-id?"
    , "                       (vector-ref meta 2)))"
    , "                 (memq (vector-ref meta 3) '(active released)))"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-PROXY\" \"invalid proxy metadata\"))"
    , "          meta)))))"
    , "(define (cubical-chez-write-proxy-state proxy-id meta state)"
    , "  (let ((path"
    , "          (cubical-chez-absolute-artifact"
    , "            (cubical-chez-proxy-meta-name proxy-id)))"
    , "        (state-path"
    , "          (string-append"
    , "            (cubical-chez-absolute-artifact"
    , "              (cubical-chez-proxy-meta-name proxy-id))"
    , "            \".state\")))"
    , "    (when (file-exists? state-path) (delete-file state-path))"
    , "    (dynamic-wind"
    , "      (lambda () #t)"
    , "      (lambda ()"
    , "        (call-with-output-file state-path"
    , "          (lambda (port)"
    , "            (write"
    , "              (vector 'ccz-proxy-meta-v1 proxy-id"
    , "                      (vector-ref meta 2) state)"
    , "              port)"
    , "            (newline port))"
    , "          'error)"
    , "        (rename-file state-path path))"
    , "      (lambda ()"
    , "        (when (file-exists? state-path)"
    , "          (delete-file state-path))))))"
    , "(define (cubical-chez-proxy-pair-exists? proxy-id)"
    , "  (and"
    , "    (file-exists?"
    , "      (cubical-chez-absolute-artifact"
    , "        (cubical-chez-proxy-packet-name proxy-id)))"
    , "    (file-exists?"
    , "      (cubical-chez-absolute-artifact"
    , "        (cubical-chez-proxy-meta-name proxy-id)))))"
    , "(define (cubical-chez-proxy-children proxy-id)"
    , "  (let loop ((ids (cubical-chez-proxy-ids \".meta\"))"
    , "             (children '()))"
    , "    (if (null? ids)"
    , "        (reverse children)"
    , "        (let ((meta (cubical-chez-read-proxy-meta (car ids))))"
    , "          (loop (cdr ids)"
    , "            (if (string=? (vector-ref meta 2) proxy-id)"
    , "                (cons (car ids) children)"
    , "                children))))))"
    , "(define (cubical-chez-delete-proxy-pair proxy-id)"
    , "  (let ((packet"
    , "          (cubical-chez-absolute-artifact"
    , "            (cubical-chez-proxy-packet-name proxy-id)))"
    , "        (meta"
    , "          (cubical-chez-absolute-artifact"
    , "            (cubical-chez-proxy-meta-name proxy-id))))"
    , "    (when (file-exists? packet) (delete-file packet))"
    , "    (when (file-exists? meta) (delete-file meta))))"
    , "(define (cubical-chez-gc-proxy-pass)"
    , "  (let ((removed 0))"
    , "    (for-each"
    , "      (lambda (filename)"
    , "        (when"
    , "          (and (cubical-chez-string-prefix? \"typed-proxy-\" filename)"
    , "               (cubical-chez-string-suffix? \".meta.state\" filename))"
    , "          (delete-file"
    , "            (cubical-chez-absolute-artifact filename))"
    , "          (set! removed (+ removed 1))))"
    , "      (directory-list cubical-chez-artifact-directory))"
    , "    (for-each"
    , "      (lambda (proxy-id)"
    , "        (unless"
    , "          (file-exists?"
    , "            (cubical-chez-absolute-artifact"
    , "              (cubical-chez-proxy-meta-name proxy-id)))"
    , "          (delete-file"
    , "            (cubical-chez-absolute-artifact"
    , "              (cubical-chez-proxy-packet-name proxy-id)))"
    , "          (set! removed (+ removed 1))))"
    , "      (cubical-chez-proxy-ids \".bin\"))"
    , "    (for-each"
    , "      (lambda (proxy-id)"
    , "        (let ((meta-path"
    , "                (cubical-chez-absolute-artifact"
    , "                  (cubical-chez-proxy-meta-name proxy-id)))"
    , "              (packet-path"
    , "                (cubical-chez-absolute-artifact"
    , "                  (cubical-chez-proxy-packet-name proxy-id))))"
    , "          (when (file-exists? meta-path)"
    , "            (if (not (file-exists? packet-path))"
    , "                (begin (delete-file meta-path)"
    , "                       (set! removed (+ removed 1)))"
    , "                (let* ((meta (cubical-chez-read-proxy-meta proxy-id))"
    , "                       (parent (vector-ref meta 2))"
    , "                       (released?"
    , "                         (eq? (vector-ref meta 3) 'released))"
    , "                       (orphan?"
    , "                         (and (not (string=? parent \".\"))"
    , "                              (not"
    , "                                (cubical-chez-proxy-pair-exists?"
    , "                                  parent)))))"
    , "                  (when"
    , "                    (or orphan?"
    , "                        (and released?"
    , "                             (null?"
    , "                               (cubical-chez-proxy-children proxy-id))))"
    , "                    (cubical-chez-delete-proxy-pair proxy-id)"
    , "                    (set! removed (+ removed 1))))))))"
    , "      (cubical-chez-proxy-ids \".meta\"))"
    , "    removed))"
    , "(define (cubical-chez-gc-proxies-unlocked)"
    , "  (let loop ((total 0))"
    , "    (let ((removed (cubical-chez-gc-proxy-pass)))"
    , "      (if (= removed 0)"
    , "          total"
    , "          (loop (+ total removed))))))"
    , "(define (cubical-chez-gc-proxies)"
    , "  (cubical-chez-with-proxy-store-lock"
    , "    cubical-chez-gc-proxies-unlocked))"
    , "(define (cubical-chez-materialize-mode arguments)"
    , "  (let ((bool-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-materialize-bool-hole-prefix arguments))"
    , "        (bool-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-materialize-bool-argument-prefix arguments))"
    , "        (nat-holes"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-materialize-nat-hole-prefix arguments))"
    , "        (nat-arguments"
    , "          (cubical-chez-prefixed-values"
    , "            cubical-chez-materialize-nat-argument-prefix arguments)))"
    , "    (cond"
    , "      ((and (= (length bool-holes) 1)"
    , "            (= (length bool-arguments) 1)"
    , "            (null? nat-holes) (null? nat-arguments))"
    , "       \"bool\")"
    , "      ((and (= (length nat-holes) 1)"
    , "            (= (length nat-arguments) 1)"
    , "            (null? bool-holes) (null? bool-arguments))"
    , "       \"nat\")"
    , "      (else"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\""
    , "          \"select exactly one matching Bool or Nat proxy codec\")))))"
    , "(define (cubical-chez-materialize-application-proxy"
    , "          handle hole-type application proxy-id)"
    , "  (cubical-chez-gc-proxies)"
    , "  (unless (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "               (cubical-chez-safe-qname? hole-type)"
    , "               (string? application)"
    , "               (cubical-chez-safe-proxy-id? proxy-id))"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-PROXY\""
    , "      \"invalid bound application proxy configuration\"))"
    , "  (let* ((packet-name (cubical-chez-proxy-packet-name proxy-id))"
    , "         (packet-path (cubical-chez-absolute-artifact packet-name))"
    , "         (meta-name (cubical-chez-proxy-meta-name proxy-id))"
    , "         (meta-path (cubical-chez-absolute-artifact meta-name)))"
    , "    (when (or (file-exists? packet-path) (file-exists? meta-path))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\" \"proxy ID already exists\"))"
    , "    (putenv \"CUBICAL_CHEZ_TYPED_MODE\" \"materialize-proxy\")"
    , "    (putenv \"CUBICAL_CHEZ_TYPED_PROXY_ID\" proxy-id)"
    , "    (putenv \"CUBICAL_CHEZ_TYPED_PROXY_PACKET_NAME\" packet-name)"
    , "    (putenv \"CUBICAL_CHEZ_TYPED_RESULT_PACKET\" packet-path)"
    , "    (putenv \"CUBICAL_CHEZ_TYPED_PROXY_META_NAME\" meta-name)"
    , "    (putenv \"CUBICAL_CHEZ_TYPED_RESULT_META\" meta-path)"
    , "    (putenv \"CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID\" \".\")"
    , "    (putenv \"CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR\""
    , "            cubical-chez-artifact-directory)"
    , "    (putenv"
    , "      \"CUBICAL_CHEZ_TYPED_CONSUMER\""
    , "      (string-append"
    , "        \"(λ (cubicalChezHole : \" hole-type \") → \" application \")\"))"
    , "    (let ((proxy (cubical-chez-force-typed-hole handle)))"
    , "      (unless"
    , "        (and (vector? proxy) (= (vector-length proxy) 3)"
    , "             (eq? (vector-ref proxy 0)"
    , "                  'cubical-chez-typed-value-proxy-v1)"
    , "             (string=? (vector-ref proxy 1) proxy-id)"
    , "             (string=? (vector-ref proxy 2) packet-name)"
    , "             (cubical-chez-proxy-pair-exists? proxy-id)"
    , "             (eq? (vector-ref"
    , "                    (cubical-chez-read-proxy-meta proxy-id) 3)"
    , "                  'active))"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROTOCOL\""
    , "          \"bound application proxy identity mismatch\"))"
    , "      proxy)))"
    , "(define (cubical-chez-materialize-ground-proxy config)"
    , "  (cubical-chez-gc-proxies)"
    , "  (let* ((codec (vector-ref config 0))"
    , "         (id (vector-ref config 1))"
    , "         (argument (vector-ref config 2))"
    , "         (hole-type (vector-ref config 3))"
    , "         (proxy-id (vector-ref config 4))"
    , "         (entry (assoc id cubical-chez-typed-holes)))"
    , "    (unless entry"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\""
    , "        (string-append \"unknown proxy source hole: \" id)))"
    , "    (unless (cubical-chez-safe-proxy-id? proxy-id)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\" \"invalid proxy ID\"))"
    , "    (let* ((handle (cdr entry))"
    , "           (packet-name (cubical-chez-proxy-packet-name proxy-id))"
    , "           (packet-path (cubical-chez-absolute-artifact packet-name)))"
    , "      (unless"
    , "        (and (cubical-chez-valid-typed-hole-handle? handle)"
    , "             (string=? (vector-ref handle 3)"
    , "               (string-append codec"
    , "                 \"-unary-ground-elimination-v1\")))"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\""
    , "          \"source hole does not support the proxy argument codec\"))"
    , "      (unless"
    , "        (if (string=? codec \"bool\")"
    , "            (or (string=? argument \"true\")"
    , "                (string=? argument \"false\"))"
    , "            (cubical-chez-valid-nat-argument? argument))"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\""
    , "          (string-append \"invalid \" codec \" proxy argument\")))"
    , "      (unless (cubical-chez-safe-qname? hole-type)"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\" \"proxy type must be a safe QName\"))"
    , "      (when (or (file-exists? packet-path)"
    , "                (file-exists?"
    , "                  (cubical-chez-absolute-artifact"
    , "                    (cubical-chez-proxy-meta-name proxy-id))))"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\" \"proxy ID already exists\"))"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_MODE\" \"materialize-proxy\")"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_ID\" proxy-id)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_PACKET_NAME\" packet-name)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_RESULT_PACKET\" packet-path)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_META_NAME\""
    , "              (cubical-chez-proxy-meta-name proxy-id))"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_RESULT_META\""
    , "              (cubical-chez-absolute-artifact"
    , "                (cubical-chez-proxy-meta-name proxy-id)))"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID\" \".\")"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR\""
    , "              cubical-chez-artifact-directory)"
    , "      (putenv"
    , "        \"CUBICAL_CHEZ_TYPED_CONSUMER\""
    , "        (string-append"
    , "          \"(λ (cubicalChezHole : \" hole-type \" ) → cubicalChezHole \""
    , "          (if (string=? codec \"bool\")"
    , "              (string-append \"Agda.Builtin.Bool.\" argument)"
    , "              argument)"
    , "          \")\"))"
    , "      (let ((proxy (cubical-chez-force-typed-hole handle)))"
    , "        (unless"
    , "          (and (vector? proxy) (= (vector-length proxy) 3)"
    , "               (eq? (vector-ref proxy 0)"
    , "                    'cubical-chez-typed-value-proxy-v1)"
    , "               (string=? (vector-ref proxy 1) proxy-id)"
    , "               (string=? (vector-ref proxy 2) packet-name)"
    , "               (cubical-chez-proxy-pair-exists? proxy-id)"
    , "               (eq? (vector-ref"
    , "                      (cubical-chez-read-proxy-meta proxy-id) 3)"
    , "                    'active))"
    , "          (cubical-chez-bridge-fail"
    , "            \"CCZ-TYPED-BRIDGE-PROTOCOL\""
    , "            \"materialized proxy identity mismatch\"))"
    , "        proxy))))"
    , "(define (cubical-chez-derive-proxy config)"
    , "  (cubical-chez-gc-proxies)"
    , "  (let* ((source-id (vector-ref config 0))"
    , "         (consumer (vector-ref config 1))"
    , "         (proxy-id (vector-ref config 2)))"
    , "    (unless"
    , "      (and (cubical-chez-safe-proxy-id? source-id)"
    , "           (cubical-chez-safe-proxy-id? proxy-id)"
    , "           (not (string=? source-id proxy-id))"
    , "           (cubical-chez-safe-qname? consumer))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\""
    , "        \"invalid derived proxy source, target, or consumer\"))"
    , "    (unless (cubical-chez-proxy-pair-exists? source-id)"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\" \"source proxy does not exist\"))"
    , "    (let* ((source-meta (cubical-chez-read-proxy-meta source-id))"
    , "           (packet-name (cubical-chez-proxy-packet-name proxy-id))"
    , "           (packet-path (cubical-chez-absolute-artifact packet-name))"
    , "           (meta-name (cubical-chez-proxy-meta-name proxy-id))"
    , "           (meta-path (cubical-chez-absolute-artifact meta-name)))"
    , "      (unless (eq? (vector-ref source-meta 3) 'active)"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\" \"source proxy is released\"))"
    , "      (when (or (file-exists? packet-path) (file-exists? meta-path))"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\" \"derived proxy ID already exists\"))"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_MODE\" \"materialize-proxy\")"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_ID\" proxy-id)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_PACKET_NAME\" packet-name)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_RESULT_PACKET\" packet-path)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_META_NAME\" meta-name)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_RESULT_META\" meta-path)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID\" source-id)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR\""
    , "              cubical-chez-artifact-directory)"
    , "      (putenv \"CUBICAL_CHEZ_TYPED_CONSUMER\" consumer)"
    , "      (let ((proxy"
    , "              (cubical-chez-force-typed-hole"
    , "                (vector 'cubical-chez-typed-hole-import-v1"
    , "                        source-id"
    , "                        (cubical-chez-proxy-packet-name source-id)"
    , "                        \"none\"))))"
    , "        (unless"
    , "          (and (vector? proxy) (= (vector-length proxy) 3)"
    , "               (eq? (vector-ref proxy 0)"
    , "                    'cubical-chez-typed-value-proxy-v1)"
    , "               (string=? (vector-ref proxy 1) proxy-id)"
    , "               (string=? (vector-ref proxy 2) packet-name)"
    , "               (cubical-chez-proxy-pair-exists? proxy-id)"
    , "               (let ((meta"
    , "                       (cubical-chez-read-proxy-meta proxy-id)))"
    , "                 (and (string=? (vector-ref meta 2) source-id)"
    , "                      (eq? (vector-ref meta 3) 'active))))"
    , "          (cubical-chez-bridge-fail"
    , "            \"CCZ-TYPED-BRIDGE-PROTOCOL\""
    , "            \"derived proxy identity mismatch\"))"
    , "        proxy))))"
    , "(define (cubical-chez-consume-proxy config)"
    , "  (let ((proxy-id (vector-ref config 0))"
    , "        (consumer (vector-ref config 1)))"
    , "    (unless (and (cubical-chez-safe-proxy-id? proxy-id)"
    , "                 (cubical-chez-safe-qname? consumer))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\" \"invalid proxy ID or consumer QName\"))"
    , "    (cubical-chez-with-proxy-store-lock"
    , "      (lambda ()"
    , "        (cubical-chez-gc-proxies-unlocked)"
    , "        (let* ((packet-name (cubical-chez-proxy-packet-name proxy-id))"
    , "               (packet-path"
    , "                 (cubical-chez-absolute-artifact packet-name)))"
    , "          (unless (file-exists? packet-path)"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-PROXY\""
    , "              \"proxy packet does not exist\"))"
    , "          (unless"
    , "            (eq?"
    , "              (vector-ref (cubical-chez-read-proxy-meta proxy-id) 3)"
    , "              'active)"
    , "            (cubical-chez-bridge-fail"
    , "              \"CCZ-TYPED-BRIDGE-PROXY\" \"proxy is released\"))"
    , "          (putenv \"CUBICAL_CHEZ_TYPED_MODE\" \"ground\")"
    , "          (putenv \"CUBICAL_CHEZ_TYPED_CONSUMER\" consumer)"
    , "          (cubical-chez-force-typed-hole"
    , "            (vector 'cubical-chez-typed-hole-import-v1"
    , "                    proxy-id packet-name \"none\")))))))"
    , "(define (cubical-chez-map-proxy config)"
    , "  (let* ((source-id (vector-ref config 0))"
    , "         (mapper (vector-ref config 1))"
    , "         (target-id (vector-ref config 2))"
    , "         (result-consumer (vector-ref config 3)))"
    , "    (unless (and (cubical-chez-safe-proxy-id? source-id)"
    , "                 (cubical-chez-safe-qname? mapper))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\""
    , "        \"invalid map source proxy ID or function QName\"))"
    , "    (unless (not (eq? (if target-id #t #f)"
    , "                         (if result-consumer #t #f)))"
    , "      (cubical-chez-bridge-fail"
    , "        \"CCZ-TYPED-BRIDGE-PROXY\""
    , "        \"map requires exactly one target proxy or result consumer\"))"
    , "    (when target-id"
    , "      (unless (and (cubical-chez-safe-proxy-id? target-id)"
    , "                   (not (string=? source-id target-id)))"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\""
    , "          \"invalid map target proxy ID\")))"
    , "    (when result-consumer"
    , "      (unless (cubical-chez-safe-qname? result-consumer)"
    , "        (cubical-chez-bridge-fail"
    , "          \"CCZ-TYPED-BRIDGE-PROXY\""
    , "          \"invalid map result consumer QName\")))"
    , "    (if target-id"
    , "        (cubical-chez-derive-proxy"
    , "          (vector source-id mapper target-id))"
    , "        (cubical-chez-with-proxy-store-lock"
    , "          (lambda ()"
    , "            (cubical-chez-gc-proxies-unlocked)"
    , "            (unless (cubical-chez-proxy-pair-exists? source-id)"
    , "              (cubical-chez-bridge-fail"
    , "                \"CCZ-TYPED-BRIDGE-PROXY\""
    , "                \"map source proxy does not exist\"))"
    , "            (unless"
    , "              (eq?"
    , "                (vector-ref"
    , "                  (cubical-chez-read-proxy-meta source-id) 3)"
    , "                'active)"
    , "              (cubical-chez-bridge-fail"
    , "                \"CCZ-TYPED-BRIDGE-PROXY\""
    , "                \"map source proxy is released\"))"
    , "            (putenv \"CUBICAL_CHEZ_TYPED_MODE\" \"map-ground\")"
    , "            (putenv \"CUBICAL_CHEZ_TYPED_MAPPER\" mapper)"
    , "            (putenv"
    , "              \"CUBICAL_CHEZ_TYPED_CONSUMER\" result-consumer)"
    , "            (cubical-chez-force-typed-hole"
    , "              (vector 'cubical-chez-typed-hole-import-v1"
    , "                      source-id"
    , "                      (cubical-chez-proxy-packet-name source-id)"
    , "                      \"none\")))))))"
    , "(define (cubical-chez-drop-proxy proxy-id)"
    , "  (unless (cubical-chez-safe-proxy-id? proxy-id)"
    , "    (cubical-chez-bridge-fail"
    , "      \"CCZ-TYPED-BRIDGE-PROXY\" \"invalid proxy ID\"))"
    , "  (cubical-chez-with-proxy-store-lock"
    , "    (lambda ()"
    , "      (cubical-chez-gc-proxies-unlocked)"
    , "      (let* ((packet-name (cubical-chez-proxy-packet-name proxy-id))"
    , "             (packet-path"
    , "               (cubical-chez-absolute-artifact packet-name)))"
    , "        (unless (cubical-chez-proxy-pair-exists? proxy-id)"
    , "          (cubical-chez-bridge-fail"
    , "            \"CCZ-TYPED-BRIDGE-PROXY\""
    , "            \"proxy packet does not exist\"))"
    , "        (let ((meta (cubical-chez-read-proxy-meta proxy-id)))"
    , "          (when (eq? (vector-ref meta 3) 'active)"
    , "            (cubical-chez-write-proxy-state"
    , "              proxy-id meta 'released)))"
    , "        (cubical-chez-gc-proxies-unlocked)"
    , "        (if (cubical-chez-proxy-pair-exists? proxy-id)"
    , "            (vector"
    , "              'cubical-chez-typed-value-proxy-retained-v1 proxy-id)"
    , "            (vector"
    , "              'cubical-chez-typed-value-proxy-dropped-v1 proxy-id))))))"
    , "(define cubical-chez-shell-arguments (command-line-arguments))"
    , "(define cubical-chez-selected-typed-hole"
    , "  (cubical-chez-select-typed-hole cubical-chez-shell-arguments))"
    , "(define cubical-chez-observe-all?"
    , "  (member \"--observe-all-ground\" cubical-chez-shell-arguments))"
    , "(define cubical-chez-hole-consumers"
    , "  (cubical-chez-requested-hole-consumers cubical-chez-shell-arguments))"
    , "(define cubical-chez-call-requested"
    , "  (cubical-chez-call-requested? cubical-chez-shell-arguments))"
    , "(define cubical-chez-call-config"
    , "  (if cubical-chez-call-requested"
    , "      (let ((mode"
    , "              (cubical-chez-call-mode"
    , "                cubical-chez-shell-arguments)))"
    , "        (vector"
    , "          mode"
    , "          (cubical-chez-exactly-one-call-value"
    , "            (cond"
    , "              ((string=? mode \"bool\")"
    , "               cubical-chez-call-bool-hole-prefix)"
    , "              ((string=? mode \"nat\")"
    , "               cubical-chez-call-nat-hole-prefix)"
    , "              ((string=? mode \"word64\")"
    , "               cubical-chez-call-word64-hole-prefix)"
    , "              ((string=? mode \"char\")"
    , "               cubical-chez-call-char-hole-prefix)"
    , "              ((string=? mode \"int\")"
    , "               cubical-chez-call-int-hole-prefix)"
    , "              (else cubical-chez-call-ground-hole-prefix))"
    , "            \"callable hole ID\" cubical-chez-shell-arguments)"
    , "          (if (string=? mode \"ground\")"
    , "              (cubical-chez-call-ground-arguments"
    , "                cubical-chez-shell-arguments)"
    , "              (cubical-chez-exactly-one-call-value"
    , "                (cond"
    , "                  ((string=? mode \"bool\")"
    , "                   cubical-chez-call-bool-argument-prefix)"
    , "                  ((string=? mode \"nat\")"
    , "                   cubical-chez-call-nat-argument-prefix)"
    , "                  ((string=? mode \"word64\")"
    , "                   cubical-chez-call-word64-argument-prefix)"
    , "                  ((string=? mode \"char\")"
    , "                   cubical-chez-call-char-argument-prefix)"
    , "                  (else cubical-chez-call-int-argument-prefix))"
    , "                \"ground argument\" cubical-chez-shell-arguments))"
    , "          (cubical-chez-exactly-one-call-value"
    , "            cubical-chez-call-hole-type-prefix \"hole type QName\""
    , "            cubical-chez-shell-arguments)"
    , "          (cubical-chez-call-action"
    , "            cubical-chez-shell-arguments)))"
    , "      #f))"
    , "(define cubical-chez-auto-bind-requested"
    , "  (cubical-chez-auto-bind-requested?"
    , "    cubical-chez-shell-arguments))"
    , "(define cubical-chez-auto-bind-config"
    , "  (if cubical-chez-auto-bind-requested"
    , "      (let ((mode"
    , "              (cubical-chez-auto-bind-mode"
    , "                cubical-chez-shell-arguments)))"
    , "        (vector"
    , "          mode"
    , "          (cubical-chez-exactly-one-auto-bind-value"
    , "            (cond"
    , "              ((string=? mode \"bool\")"
    , "               cubical-chez-auto-bind-bool-hole-prefix)"
    , "              ((string=? mode \"nat\")"
    , "               cubical-chez-auto-bind-nat-hole-prefix)"
    , "              ((string=? mode \"word64\")"
    , "               cubical-chez-auto-bind-word64-hole-prefix)"
    , "              ((string=? mode \"char\")"
    , "               cubical-chez-auto-bind-char-hole-prefix)"
    , "              ((string=? mode \"int\")"
    , "               cubical-chez-auto-bind-int-hole-prefix)"
    , "              (else cubical-chez-auto-bind-ground-hole-prefix))"
    , "            \"auto-bound hole ID\" cubical-chez-shell-arguments)"
    , "          (if (string=? mode \"ordered-ground\")"
    , "              (cubical-chez-entry-ground-values"
    , "                cubical-chez-shell-arguments)"
    , "              (cubical-chez-exactly-one-auto-bind-value"
    , "                (cond"
    , "                  ((string=? mode \"bool\")"
    , "                   cubical-chez-entry-bool-argument-prefix)"
    , "                  ((string=? mode \"nat\")"
    , "                   cubical-chez-entry-nat-argument-prefix)"
    , "                  ((string=? mode \"word64\")"
    , "                   cubical-chez-entry-word64-argument-prefix)"
    , "                  ((string=? mode \"char\")"
    , "                   cubical-chez-entry-char-argument-prefix)"
    , "                  (else cubical-chez-entry-int-argument-prefix))"
    , "                \"entry ground argument\""
    , "                cubical-chez-shell-arguments))"
    , "          (cubical-chez-exactly-one-auto-bind-value"
    , "            cubical-chez-auto-bind-hole-type-prefix"
    , "            \"auto-bound hole type QName\" cubical-chez-shell-arguments)"
    , "          (cubical-chez-auto-bind-action"
    , "            cubical-chez-shell-arguments)))"
    , "      #f))"
    , "(define cubical-chez-proxy-requested"
    , "  (cubical-chez-proxy-requested? cubical-chez-shell-arguments))"
    , "(define cubical-chez-proxy-config"
    , "  (if cubical-chez-proxy-requested"
    , "      (let ((mode"
    , "              (cubical-chez-materialize-mode"
    , "                cubical-chez-shell-arguments)))"
    , "        (vector"
    , "          mode"
    , "          (cubical-chez-exactly-one-proxy-value"
    , "            (if (string=? mode \"bool\")"
    , "                cubical-chez-materialize-bool-hole-prefix"
    , "                cubical-chez-materialize-nat-hole-prefix)"
    , "            \"source hole ID\" cubical-chez-shell-arguments)"
    , "          (cubical-chez-exactly-one-proxy-value"
    , "            (if (string=? mode \"bool\")"
    , "                cubical-chez-materialize-bool-argument-prefix"
    , "                cubical-chez-materialize-nat-argument-prefix)"
    , "            \"ground argument\" cubical-chez-shell-arguments)"
    , "          (cubical-chez-exactly-one-proxy-value"
    , "            cubical-chez-materialize-hole-type-prefix"
    , "            \"hole type QName\" cubical-chez-shell-arguments)"
    , "          (cubical-chez-exactly-one-proxy-value"
    , "            cubical-chez-proxy-id-prefix"
    , "            \"proxy ID\" cubical-chez-shell-arguments)))"
    , "      #f))"
    , "(define cubical-chez-consume-proxy-requested"
    , "  (or"
    , "    (cubical-chez-prefix-requested?"
    , "      cubical-chez-consume-proxy-prefix cubical-chez-shell-arguments)"
    , "    (cubical-chez-prefix-requested?"
    , "      cubical-chez-proxy-consumer-prefix cubical-chez-shell-arguments)))"
    , "(define cubical-chez-consume-proxy-config"
    , "  (if cubical-chez-consume-proxy-requested"
    , "      (vector"
    , "        (cubical-chez-exactly-one-proxy-value"
    , "          cubical-chez-consume-proxy-prefix"
    , "          \"proxy ID\" cubical-chez-shell-arguments)"
    , "        (cubical-chez-exactly-one-proxy-value"
    , "          cubical-chez-proxy-consumer-prefix"
    , "          \"proxy consumer QName\" cubical-chez-shell-arguments))"
    , "      #f))"
    , "(define cubical-chez-map-proxy-requested"
    , "  (or"
    , "    (cubical-chez-prefix-requested?"
    , "      cubical-chez-map-proxy-prefix cubical-chez-shell-arguments)"
    , "    (cubical-chez-prefix-requested?"
    , "      cubical-chez-map-proxy-function-prefix"
    , "      cubical-chez-shell-arguments)"
    , "    (cubical-chez-prefix-requested?"
    , "      cubical-chez-map-proxy-result-consumer-prefix"
    , "      cubical-chez-shell-arguments)))"
    , "(define cubical-chez-map-proxy-config"
    , "  (if cubical-chez-map-proxy-requested"
    , "      (vector"
    , "        (cubical-chez-exactly-one-proxy-value"
    , "          cubical-chez-map-proxy-prefix"
    , "          \"map source proxy ID\" cubical-chez-shell-arguments)"
    , "        (cubical-chez-exactly-one-proxy-value"
    , "          cubical-chez-map-proxy-function-prefix"
    , "          \"map function QName\" cubical-chez-shell-arguments)"
    , "        (cubical-chez-zero-or-one-proxy-value"
    , "          cubical-chez-proxy-id-prefix"
    , "          \"map target proxy ID\" cubical-chez-shell-arguments)"
    , "        (cubical-chez-zero-or-one-proxy-value"
    , "          cubical-chez-map-proxy-result-consumer-prefix"
    , "          \"map result consumer QName\" cubical-chez-shell-arguments))"
    , "      #f))"
    , "(define cubical-chez-drop-proxy-requested"
    , "  (cubical-chez-prefix-requested?"
    , "    cubical-chez-drop-proxy-prefix cubical-chez-shell-arguments))"
    , "(define cubical-chez-drop-proxy-id"
    , "  (if cubical-chez-drop-proxy-requested"
    , "      (cubical-chez-exactly-one-proxy-value"
    , "        cubical-chez-drop-proxy-prefix"
    , "        \"proxy ID\" cubical-chez-shell-arguments)"
    , "      #f))"
    , "(define cubical-chez-derive-proxy-requested"
    , "  (or"
    , "    (cubical-chez-prefix-requested?"
    , "      cubical-chez-derive-proxy-prefix cubical-chez-shell-arguments)"
    , "    (cubical-chez-prefix-requested?"
    , "      cubical-chez-derive-proxy-consumer-prefix"
    , "      cubical-chez-shell-arguments)))"
    , "(define cubical-chez-derive-proxy-config"
    , "  (if cubical-chez-derive-proxy-requested"
    , "      (vector"
    , "        (cubical-chez-exactly-one-proxy-value"
    , "          cubical-chez-derive-proxy-prefix"
    , "          \"source proxy ID\" cubical-chez-shell-arguments)"
    , "        (cubical-chez-exactly-one-proxy-value"
    , "          cubical-chez-derive-proxy-consumer-prefix"
    , "          \"derived proxy consumer QName\""
    , "          cubical-chez-shell-arguments)"
    , "        (cubical-chez-exactly-one-proxy-value"
    , "          cubical-chez-proxy-id-prefix"
    , "          \"target proxy ID\" cubical-chez-shell-arguments))"
    , "      #f))"
    , "(define cubical-chez-gc-proxies-count"
    , "  (length"
    , "    (filter"
    , "      (lambda (argument)"
    , "        (string=? argument cubical-chez-gc-proxies-argument))"
    , "      cubical-chez-shell-arguments)))"
    , "(when (> cubical-chez-gc-proxies-count 1)"
    , "  (cubical-chez-bridge-fail"
    , "    \"CCZ-TYPED-BRIDGE-PROXY\" \"duplicate proxy GC argument\"))"
    , "(define cubical-chez-gc-proxies-requested"
    , "  (= cubical-chez-gc-proxies-count 1))"
    , "(define cubical-chez-proxy-operation-count"
    , "  (+ (if cubical-chez-proxy-requested 1 0)"
    , "     (if cubical-chez-derive-proxy-requested 1 0)"
    , "     (if cubical-chez-consume-proxy-requested 1 0)"
    , "     (if cubical-chez-map-proxy-requested 1 0)"
    , "     (if cubical-chez-drop-proxy-requested 1 0)"
    , "     (if cubical-chez-gc-proxies-requested 1 0)))"
    , "(when (and cubical-chez-auto-bind-requested"
    , "           (or cubical-chez-call-requested"
    , "               (> cubical-chez-proxy-operation-count 0)"
    , "               cubical-chez-observe-all?"
    , "               cubical-chez-selected-typed-hole"
    , "               (pair? cubical-chez-hole-consumers)))"
    , "  (cubical-chez-bridge-fail"
    , "    \"CCZ-TYPED-BRIDGE-ENVIRONMENT\""
    , "    \"automatic environment binding conflicts with another execution mode\"))"
    , "(when (or (> cubical-chez-proxy-operation-count 1)"
    , "          (and (> cubical-chez-proxy-operation-count 0)"
    , "               (or cubical-chez-call-requested"
    , "                   cubical-chez-auto-bind-requested"
    , "                   cubical-chez-observe-all?"
    , "                   cubical-chez-selected-typed-hole"
    , "                   (pair? cubical-chez-hole-consumers))))"
    , "  (cubical-chez-bridge-fail"
    , "    \"CCZ-TYPED-BRIDGE-PROXY\""
    , "    \"proxy operation conflicts with another execution mode\"))"
    , "(when (and cubical-chez-call-requested"
    , "           (or cubical-chez-auto-bind-requested"
    , "               cubical-chez-observe-all?"
    , "               cubical-chez-selected-typed-hole))"
    , "  (cubical-chez-bridge-fail"
    , "    \"CCZ-TYPED-BRIDGE-CALL\""
    , "    \"callable elimination conflicts with another execution mode\"))"
    , "(when (and cubical-chez-observe-all?"
    , "           cubical-chez-selected-typed-hole)"
    , "  (cubical-chez-bridge-fail"
    , "    \"CCZ-TYPED-BRIDGE-OBSERVATION\""
    , "    \"batch observation conflicts with single-hole forcing\"))"
    , "(when (and (not cubical-chez-observe-all?)"
    , "           (pair? cubical-chez-hole-consumers))"
    , "  (cubical-chez-bridge-fail"
    , "    \"CCZ-TYPED-BRIDGE-OBSERVATION\""
    , "    \"hole consumer mappings require --observe-all-ground\"))"
    , "(define cubical-chez-validated-hole-consumers"
    , "  (if cubical-chez-observe-all?"
    , "      (cubical-chez-validate-hole-consumers"
    , "        cubical-chez-hole-consumers)"
    , "      '()))"
    , "(display"
    , "  (cond"
    , "    (cubical-chez-proxy-requested"
    , "     (cubical-chez-materialize-ground-proxy cubical-chez-proxy-config))"
    , "    (cubical-chez-derive-proxy-requested"
    , "     (cubical-chez-derive-proxy cubical-chez-derive-proxy-config))"
    , "    (cubical-chez-consume-proxy-requested"
    , "     (cubical-chez-consume-proxy"
    , "       cubical-chez-consume-proxy-config))"
    , "    (cubical-chez-map-proxy-requested"
    , "     (cubical-chez-map-proxy cubical-chez-map-proxy-config))"
    , "    (cubical-chez-drop-proxy-requested"
    , "     (cubical-chez-drop-proxy cubical-chez-drop-proxy-id))"
    , "    (cubical-chez-gc-proxies-requested"
    , "     (vector 'cubical-chez-typed-value-proxy-gc-v1"
    , "             (cubical-chez-gc-proxies)))"
    , "    (cubical-chez-auto-bind-requested"
    , "     ((cond"
    , "        ((string=? (vector-ref cubical-chez-auto-bind-config 0)"
    , "                   \"bool\")"
    , "         cubical-chez-auto-observe-bound-bool)"
    , "        ((string=? (vector-ref cubical-chez-auto-bind-config 0)"
    , "                   \"nat\")"
    , "         cubical-chez-auto-observe-bound-nat)"
    , "        ((string=? (vector-ref cubical-chez-auto-bind-config 0)"
    , "                   \"word64\")"
    , "         cubical-chez-auto-observe-bound-word64)"
    , "        ((string=? (vector-ref cubical-chez-auto-bind-config 0)"
    , "                   \"char\")"
    , "         cubical-chez-auto-observe-bound-char)"
    , "        ((string=? (vector-ref cubical-chez-auto-bind-config 0)"
    , "                   \"int\")"
    , "         cubical-chez-auto-observe-bound-int)"
    , "        (else cubical-chez-auto-observe-bound-ground))"
    , "       cubical-chez-auto-bind-config "
        ++ mangleQName (compiledName entry) ++ "))"
    , "    (cubical-chez-call-requested"
    , "     (cubical-chez-call-ground-hole cubical-chez-call-config))"
    , "    (cubical-chez-observe-all?"
    , "     (cubical-chez-observe-all-ground"
    , "       cubical-chez-validated-hole-consumers))"
    , "    (cubical-chez-selected-typed-hole"
    , "     (cubical-chez-force-typed-hole cubical-chez-selected-typed-hole))"
    , "    (else " ++ mangleQName (compiledName entry) ++ ")))"
    , "(newline)"
    ]
  where
    imports = Map.fromList
      [ (residualHolePath hole, (index, hole))
      | (index, hole) <- zip [(1 :: Int) ..] holes
      ]
    effectiveImports = testResidualShellImports imports

testResidualShellImports
  :: Map.Map String (Int, ResidualHolePlan)
  -> Map.Map String (Int, ResidualHolePlan)
#if defined(CUBICAL_CHEZ_TEST_RESIDUAL_SHELL_UNCOVERED)
testResidualShellImports _ = Map.empty
#else
testResidualShellImports = id
#endif

typedHoleGroundBridgeScript :: String
typedHoleGroundBridgeScript = unlines
  [ "#!/bin/sh"
  , ""
  , "set -u"
  , ""
  , "bridge_error() {"
  , "  printf '(ccz-bridge-error-v1 %s %s)\\n' \"$1\" \"$2\""
  , "  exit \"$3\""
  , "}"
  , ""
  , "if [ -z \"${CUBICAL_CHEZ_TYPED_RUNNER:-}\" ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-CONFIG runner 64"
  , "fi"
  , "if [ -z \"${CUBICAL_CHEZ_AGDA_DATADIR:-}\" ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-CONFIG agda-datadir 64"
  , "fi"
  , "if [ -z \"${CUBICAL_CHEZ_TYPED_SOURCE:-}\" ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-CONFIG source 64"
  , "fi"
  , "if [ -z \"${CUBICAL_CHEZ_TYPED_INCLUDE:-}\" ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-CONFIG include 64"
  , "fi"
  , "if [ -z \"${CUBICAL_CHEZ_TYPED_CONSUMER:-}\" ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-CONFIG consumer 64"
  , "fi"
  , "if [ -z \"${CUBICAL_CHEZ_TYPED_PACKET:-}\" ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-CONFIG packet 64"
  , "fi"
  , "if [ ! -x \"$CUBICAL_CHEZ_TYPED_RUNNER\" ] ||"
  , "   [ ! -d \"$CUBICAL_CHEZ_AGDA_DATADIR\" ] ||"
  , "   [ ! -f \"$CUBICAL_CHEZ_TYPED_SOURCE\" ] ||"
  , "   [ ! -d \"$CUBICAL_CHEZ_TYPED_INCLUDE\" ] ||"
  , "   [ ! -f \"$CUBICAL_CHEZ_TYPED_PACKET\" ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-CONFIG invalid-path 64"
  , "fi"
  , ""
  , "bridge_mode=${CUBICAL_CHEZ_TYPED_MODE:-ground}"
  , "bridge_result_temp="
  , "bridge_meta_temp="
  , "bridge_mapped_temp="
  , "bridge_store_lock="
  , "bridge_store_lock_owner="
  , "bridge_store_lock_acquired=0"
  , "bridge_current_proxy_bytes=0"
  , "bridge_packet_published=0"
  , "case \"$bridge_mode\" in"
  , "  ground)"
  , "    ;;"
  , "  map-ground)"
  , "    if [ -z \"${CUBICAL_CHEZ_TYPED_MAPPER:-}\" ]; then"
  , "      bridge_error CCZ-TYPED-BRIDGE-CONFIG mapper 64"
  , "    fi"
  , "    ;;"
  , "  materialize-proxy)"
  , "    if [ -z \"${CUBICAL_CHEZ_TYPED_RESULT_PACKET:-}\" ] ||"
  , "       [ -z \"${CUBICAL_CHEZ_TYPED_RESULT_META:-}\" ] ||"
  , "       [ -z \"${CUBICAL_CHEZ_TYPED_PROXY_ID:-}\" ] ||"
  , "       [ -z \"${CUBICAL_CHEZ_TYPED_PROXY_PACKET_NAME:-}\" ] ||"
  , "       [ -z \"${CUBICAL_CHEZ_TYPED_PROXY_META_NAME:-}\" ] ||"
  , "       [ -z \"${CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID:-}\" ] ||"
  , "       [ -z \"${CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR:-}\" ]; then"
  , "      bridge_error CCZ-TYPED-BRIDGE-CONFIG proxy-config 64"
  , "    fi"
  , "    if [ ! -d \"$CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR\" ]; then"
  , "      bridge_error CCZ-TYPED-BRIDGE-CONFIG proxy-store 64"
  , "    fi"
  , "    case \"$CUBICAL_CHEZ_TYPED_PROXY_ID\" in"
  , "      *[!A-Za-z0-9_-]* )"
  , "        bridge_error CCZ-TYPED-BRIDGE-PROXY proxy-id 65 ;;"
  , "    esac"
  , "    case \"$CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID\" in"
  , "      .) ;;"
  , "      *[!A-Za-z0-9_-]*|'')"
  , "        bridge_error CCZ-TYPED-BRIDGE-PROXY proxy-parent-id 65 ;;"
  , "    esac"
  , "    if [ \"${#CUBICAL_CHEZ_TYPED_PROXY_ID}\" -gt 64 ] ||"
  , "       [ \"${#CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID}\" -gt 64 ] ||"
  , "       [ -e \"$CUBICAL_CHEZ_TYPED_RESULT_PACKET\" ] ||"
  , "       [ -e \"$CUBICAL_CHEZ_TYPED_RESULT_META\" ]; then"
  , "      bridge_error CCZ-TYPED-BRIDGE-PROXY proxy-exists-or-too-long 65"
  , "    fi"
  , "    case \"$CUBICAL_CHEZ_TYPED_RESULT_PACKET\" in"
  , "      \"$CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR\"/typed-proxy-*.bin) ;;"
  , "      *) bridge_error CCZ-TYPED-BRIDGE-CONFIG proxy-packet-path 64 ;;"
  , "    esac"
  , "    case \"$CUBICAL_CHEZ_TYPED_RESULT_META\" in"
  , "      \"$CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR\"/typed-proxy-*.meta) ;;"
  , "      *) bridge_error CCZ-TYPED-BRIDGE-CONFIG proxy-meta-path 64 ;;"
  , "    esac"
  , "    proxy_max_count=${CUBICAL_CHEZ_TYPED_PROXY_MAX_COUNT:-256}"
  , "    proxy_max_bytes=${CUBICAL_CHEZ_TYPED_PROXY_MAX_BYTES:-67108864}"
  , "    case \"$proxy_max_count\" in"
  , "      ''|*[!0-9]*) bridge_error CCZ-TYPED-BRIDGE-QUOTA count 73 ;;"
  , "    esac"
  , "    case \"$proxy_max_bytes\" in"
  , "      ''|*[!0-9]*) bridge_error CCZ-TYPED-BRIDGE-QUOTA bytes 73 ;;"
  , "    esac"
  , "    if [ \"$proxy_max_count\" -lt 1 ] ||"
  , "       [ \"$proxy_max_count\" -gt 65536 ] ||"
  , "       [ \"$proxy_max_bytes\" -lt 1 ] ||"
  , "       [ \"$proxy_max_bytes\" -gt 1073741824 ]; then"
  , "      bridge_error CCZ-TYPED-BRIDGE-QUOTA range 73"
  , "    fi"
  , "    bridge_result_temp=\"$CUBICAL_CHEZ_TYPED_RESULT_PACKET.tmp.$$\""
  , "    bridge_meta_temp=\"$CUBICAL_CHEZ_TYPED_RESULT_META.tmp.$$\""
  , "    if [ -e \"$bridge_result_temp\" ] ||"
  , "       [ -e \"$bridge_meta_temp\" ]; then"
  , "      bridge_error CCZ-TYPED-BRIDGE-PROXY proxy-temp-exists 65"
  , "    fi"
  , "    ;;"
  , "  *)"
  , "    bridge_error CCZ-TYPED-BRIDGE-PROXY invalid-mode 65"
  , "    ;;"
  , "esac"
  , ""
  , "bridge_tmp=$(mktemp -d \"${TMPDIR:-/tmp}/cubical-chez-bridge.XXXXXX\") ||"
  , "  bridge_error CCZ-TYPED-BRIDGE-CONFIG tempdir 64"
  , "if [ \"$bridge_mode\" = map-ground ]; then"
  , "  bridge_mapped_temp=\"$bridge_tmp/mapped.bin\""
  , "fi"
  , "bridge_cleanup() {"
  , "  rm -f \"$bridge_tmp/stdout\" \"$bridge_tmp/stderr\" \"$bridge_mapped_temp\""
  , "  rmdir \"$bridge_tmp\" 2>/dev/null || true"
  , "  if [ \"$bridge_mode\" = materialize-proxy ] &&"
  , "     [ -n \"$bridge_result_temp\" ]; then"
  , "    rm -f \"$bridge_result_temp\""
  , "  fi"
  , "  if [ \"$bridge_mode\" = materialize-proxy ] &&"
  , "     [ -n \"$bridge_meta_temp\" ]; then"
  , "    rm -f \"$bridge_meta_temp\""
  , "  fi"
  , "  if [ \"$bridge_store_lock_acquired\" -eq 1 ]; then"
  , "    rm -f \"$bridge_store_lock_owner\""
  , "    rmdir \"$bridge_store_lock\" 2>/dev/null || true"
  , "    bridge_store_lock_acquired=0"
  , "  fi"
  , "}"
  , "trap bridge_cleanup EXIT HUP INT TERM"
  , ""
  , "bridge_acquire_proxy_store_lock() {"
  , "  bridge_store_lock=\"$CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR/.typed-proxy-store.lock\""
  , "  bridge_store_lock_owner=\"$bridge_store_lock/owner\""
  , "  lock_attempt=0"
  , "  while ! mkdir \"$bridge_store_lock\" 2>/dev/null; do"
  , "    lock_attempt=$((lock_attempt + 1))"
  , "    lock_owner_pid="
  , "    if [ -f \"$bridge_store_lock_owner\" ]; then"
  , "      IFS= read -r lock_owner_pid < \"$bridge_store_lock_owner\" || true"
  , "    fi"
  , "    case \"$lock_owner_pid\" in"
  , "      ''|*[!0-9]*)"
  , "        if [ \"$lock_attempt\" -ge 100 ]; then"
  , "          rm -f \"$bridge_store_lock_owner\""
  , "          rmdir \"$bridge_store_lock\" 2>/dev/null || true"
  , "        fi"
  , "        ;;"
  , "      *)"
  , "        if ! kill -0 \"$lock_owner_pid\" 2>/dev/null; then"
  , "          rm -f \"$bridge_store_lock_owner\""
  , "          rmdir \"$bridge_store_lock\" 2>/dev/null || true"
  , "        fi"
  , "        ;;"
  , "    esac"
  , "    if [ \"$lock_attempt\" -ge 500 ]; then"
  , "      bridge_error CCZ-TYPED-BRIDGE-QUOTA lock-timeout 73"
  , "    fi"
  , "    sleep 0.01"
  , "  done"
  , "  bridge_store_lock_acquired=1"
  , "  if ! printf '%s\\n' \"$$\" > \"$bridge_store_lock_owner\"; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-QUOTA lock-owner 73"
  , "  fi"
  , "}"
  , ""
  , "bridge_measure_proxy_store() {"
  , "  bridge_proxy_store_count=0"
  , "  bridge_current_proxy_bytes=0"
  , "  for proxy_meta in \"$CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR\"/typed-proxy-*.meta; do"
  , "    [ -f \"$proxy_meta\" ] || continue"
  , "    proxy_packet=${proxy_meta%.meta}.bin"
  , "    [ -f \"$proxy_packet\" ] || continue"
  , "    proxy_packet_bytes=$(wc -c < \"$proxy_packet\" | tr -d ' ')"
  , "    proxy_meta_bytes=$(wc -c < \"$proxy_meta\" | tr -d ' ')"
  , "    bridge_proxy_store_count=$((bridge_proxy_store_count + 1))"
  , "    bridge_current_proxy_bytes=$((bridge_current_proxy_bytes + proxy_packet_bytes + proxy_meta_bytes))"
  , "  done"
  , "}"
  , ""
  , "if [ \"$bridge_mode\" = materialize-proxy ]; then"
  , "  bridge_acquire_proxy_store_lock"
  , "  if [ -e \"$CUBICAL_CHEZ_TYPED_RESULT_PACKET\" ] ||"
  , "     [ -e \"$CUBICAL_CHEZ_TYPED_RESULT_META\" ]; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-PROXY publish-conflict 65"
  , "  fi"
  , "  if [ \"$CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID\" != . ]; then"
  , "    parent_packet=\"$CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR/typed-proxy-$CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID.bin\""
  , "    parent_meta=\"$CUBICAL_CHEZ_TYPED_PROXY_STORE_DIR/typed-proxy-$CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID.meta\""
  , "    if [ ! -f \"$parent_packet\" ] || [ ! -f \"$parent_meta\" ] ||"
  , "       ! grep -Eq \"^#\\(ccz-proxy-meta-v1 \\\"$CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID\\\" \\\"(\\\\.|[A-Za-z0-9_-]+)\\\" active\\)$\" \"$parent_meta\"; then"
  , "      bridge_error CCZ-TYPED-BRIDGE-PROXY inactive-parent 65"
  , "    fi"
  , "  fi"
  , "  bridge_measure_proxy_store"
  , "  if [ \"$bridge_proxy_store_count\" -ge \"$proxy_max_count\" ]; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-QUOTA count-exceeded 73"
  , "  fi"
  , "  if [ \"$bridge_current_proxy_bytes\" -gt \"$proxy_max_bytes\" ]; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-QUOTA bytes-already-exceeded 73"
  , "  fi"
  , "fi"
  , ""
  , "if [ \"$bridge_mode\" = materialize-proxy ]; then"
  , "  Agda_datadir=\"$CUBICAL_CHEZ_AGDA_DATADIR\" \"$CUBICAL_CHEZ_TYPED_RUNNER\" \\"
  , "    -v0 \\"
  , "    --cubical-import=\"$CUBICAL_CHEZ_TYPED_CONSUMER\" \\"
  , "    --cubical-term-file=\"$CUBICAL_CHEZ_TYPED_PACKET\" \\"
  , "    --cubical-result-term-file=\"$bridge_result_temp\" \\"
  , "    --no-libraries \\"
  , "    --no-write-interfaces \\"
  , "    -i \"$CUBICAL_CHEZ_TYPED_INCLUDE\" \\"
  , "    \"$CUBICAL_CHEZ_TYPED_SOURCE\" \\"
  , "    > \"$bridge_tmp/stdout\" 2> \"$bridge_tmp/stderr\""
  , "elif [ \"$bridge_mode\" = map-ground ]; then"
  , "  Agda_datadir=\"$CUBICAL_CHEZ_AGDA_DATADIR\" \"$CUBICAL_CHEZ_TYPED_RUNNER\" \\"
  , "    -v0 \\"
  , "    --cubical-import=\"$CUBICAL_CHEZ_TYPED_MAPPER\" \\"
  , "    --cubical-term-file=\"$CUBICAL_CHEZ_TYPED_PACKET\" \\"
  , "    --cubical-result-term-file=\"$bridge_mapped_temp\" \\"
  , "    --no-libraries \\"
  , "    --no-write-interfaces \\"
  , "    -i \"$CUBICAL_CHEZ_TYPED_INCLUDE\" \\"
  , "    \"$CUBICAL_CHEZ_TYPED_SOURCE\" \\"
  , "    > \"$bridge_tmp/stdout\" 2> \"$bridge_tmp/stderr\""
  , "  mapper_status=$?"
  , "  if [ \"$mapper_status\" -ne 0 ]; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-RUNNER-EXIT \"$mapper_status\" 70"
  , "  fi"
  , "  if [ -s \"$bridge_tmp/stdout\" ] ||"
  , "     [ -s \"$bridge_tmp/stderr\" ] ||"
  , "     [ ! -s \"$bridge_mapped_temp\" ]; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-DIRTY-OUTPUT mapped-result 71"
  , "  fi"
  , "  Agda_datadir=\"$CUBICAL_CHEZ_AGDA_DATADIR\" \"$CUBICAL_CHEZ_TYPED_RUNNER\" \\"
  , "    -v0 \\"
  , "    --cubical-import=\"$CUBICAL_CHEZ_TYPED_CONSUMER\" \\"
  , "    --cubical-term-file=\"$bridge_mapped_temp\" \\"
  , "    --no-libraries \\"
  , "    --no-write-interfaces \\"
  , "    -i \"$CUBICAL_CHEZ_TYPED_INCLUDE\" \\"
  , "    \"$CUBICAL_CHEZ_TYPED_SOURCE\" \\"
  , "    > \"$bridge_tmp/stdout\" 2> \"$bridge_tmp/stderr\""
  , "else"
  , "  Agda_datadir=\"$CUBICAL_CHEZ_AGDA_DATADIR\" \"$CUBICAL_CHEZ_TYPED_RUNNER\" \\"
  , "    -v0 \\"
  , "    --cubical-import=\"$CUBICAL_CHEZ_TYPED_CONSUMER\" \\"
  , "    --cubical-term-file=\"$CUBICAL_CHEZ_TYPED_PACKET\" \\"
  , "    --no-libraries \\"
  , "    --no-write-interfaces \\"
  , "    -i \"$CUBICAL_CHEZ_TYPED_INCLUDE\" \\"
  , "    \"$CUBICAL_CHEZ_TYPED_SOURCE\" \\"
  , "    > \"$bridge_tmp/stdout\" 2> \"$bridge_tmp/stderr\""
  , "fi"
  , "runner_status=$?"
  , "if [ \"$runner_status\" -ne 0 ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-RUNNER-EXIT \"$runner_status\" 70"
  , "fi"
  , "if [ -s \"$bridge_tmp/stderr\" ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-DIRTY-OUTPUT stderr 71"
  , "fi"
  , "if [ \"$bridge_mode\" = materialize-proxy ]; then"
  , "  if [ -s \"$bridge_tmp/stdout\" ] ||"
  , "     [ ! -s \"$bridge_result_temp\" ]; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-DIRTY-OUTPUT proxy-result 71"
  , "  fi"
  , "  printf '#(ccz-proxy-meta-v1 \"%s\" \"%s\" active)\\n' \\"
  , "    \"$CUBICAL_CHEZ_TYPED_PROXY_ID\" \\"
  , "    \"$CUBICAL_CHEZ_TYPED_PROXY_PARENT_ID\" > \"$bridge_meta_temp\" ||"
  , "    bridge_error CCZ-TYPED-BRIDGE-PROXY meta-temp-write 65"
  , "  bridge_new_packet_bytes=$(wc -c < \"$bridge_result_temp\" | tr -d ' ')"
  , "  bridge_new_meta_bytes=$(wc -c < \"$bridge_meta_temp\" | tr -d ' ')"
  , "  bridge_projected_proxy_bytes=$((bridge_current_proxy_bytes + bridge_new_packet_bytes + bridge_new_meta_bytes))"
  , "  if [ \"$bridge_projected_proxy_bytes\" -gt \"$proxy_max_bytes\" ]; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-QUOTA bytes-exceeded 73"
  , "  fi"
  , "  if ! ln \"$bridge_result_temp\" \"$CUBICAL_CHEZ_TYPED_RESULT_PACKET\" 2>/dev/null; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-PROXY publish-conflict 65"
  , "  fi"
  , "  bridge_packet_published=1"
  , "  if ! ln \"$bridge_meta_temp\" \"$CUBICAL_CHEZ_TYPED_RESULT_META\" 2>/dev/null; then"
  , "    if [ \"$bridge_packet_published\" -eq 1 ]; then"
  , "      rm -f \"$CUBICAL_CHEZ_TYPED_RESULT_PACKET\""
  , "      bridge_packet_published=0"
  , "    fi"
  , "    bridge_error CCZ-TYPED-BRIDGE-PROXY publish-conflict 65"
  , "  fi"
  , "  rm -f \"$bridge_result_temp\""
  , "  rm -f \"$bridge_meta_temp\""
  , "  bridge_result_temp="
  , "  bridge_meta_temp="
  , "  if [ ! -s \"$CUBICAL_CHEZ_TYPED_RESULT_PACKET\" ] ||"
  , "     [ ! -s \"$CUBICAL_CHEZ_TYPED_RESULT_META\" ]; then"
  , "    bridge_error CCZ-TYPED-BRIDGE-PROTOCOL proxy-publish 72"
  , "  fi"
  , "  printf '(ccz-proxy-v1 \"%s\" \"%s\")\\n' \\"
  , "    \"$CUBICAL_CHEZ_TYPED_PROXY_ID\" \\"
  , "    \"$CUBICAL_CHEZ_TYPED_PROXY_PACKET_NAME\""
  , "  exit 0"
  , "fi"
  , "line_count=$(wc -l < \"$bridge_tmp/stdout\" | tr -d ' ' )"
  , "if [ \"$line_count\" != 1 ]; then"
  , "  bridge_error CCZ-TYPED-BRIDGE-DIRTY-OUTPUT line-count 71"
  , "fi"
  , "IFS= read -r ground_result < \"$bridge_tmp/stdout\""
  , "case \"$ground_result\" in"
  , "  true|false)"
  , "    printf '(ccz-ground-v1 bool %s)\\n' \"$ground_result\""
  , "    ;;"
  , "  ''|*[!0-9]*)"
  , "    bridge_error CCZ-TYPED-BRIDGE-DIRTY-OUTPUT ground-result 71"
  , "    ;;"
  , "  *)"
  , "    printf '(ccz-ground-v1 nat %s)\\n' \"$ground_result\""
  , "    ;;"
  , "esac"
  ]

renderResidualHoles :: String -> ResidualSlicePlan -> [String]
renderResidualHoles artifact = \case
  ResidualSliceNotApplicable _ -> []
  ResidualSlicePlanned holes -> concat
    [ let closure = residualHoleClosure hole
          residual = residualClosurePayload closure
          field suffix value =
            "residual-slice-hole-" ++ show index ++ "-" ++ suffix ++ ": " ++ value
      in [ field "id" (residualHoleId hole)
      , field "path" (residualHolePath hole)
      , field "blockers" (renderBlockers $ residualHoleBlockers hole)
      , field "materialization" "checked"
      , field "closed" "true"
      , field "source-closed" $
          renderBoolean (residualHoleSourceClosed hole)
      , field "packet-closed" "true"
      , field "environment-abi" $
          if residualHoleSourceClosed hole
            then "none"
            else "lambda-lifted-explicit-environment-v1"
      , field "environment-arity" $
          show (residualHoleEnvironmentArity hole)
      , field "environment-binding-abi" $
          residualHoleAutomaticEnvironmentBindingAbi hole
      , field "meta-free" "true"
      , field "typechecked" "true"
      , field "callable-abi" $
          renderResidualHoleCallableAbi (residualHoleCallableAbi hole)
      , field "artifact" $
          if artifact == "packet-v2"
            then residualHolePacketName index
            else "none"
      , field "direct-dependency-count" $
          show (length $ residualDirectDependencies residual)
      , field "direct-dependencies" $
          renderBlockers (residualDirectDependencies residual)
      , field "dependency-slice" "checked-type+definition-body-v1"
      , field "resolved-dependency-count" $
          show (length $ residualClosureResolvedDependencies closure)
      , field "resolved-dependencies" $
          renderBlockers (residualClosureResolvedDependencies closure)
      , field "expanded-definitions" $
          renderBlockers (residualClosureExpandedDefinitions closure)
      , field "signature-leaves" $
          renderBlockers (residualClosureSignatureLeaves closure)
      , field "excluded-presentation-dependency-count" $
          show
            (length $ residualClosureExcludedPresentationDependencies closure)
      , field "excluded-presentation-dependencies" $
          renderBlockers
            (residualClosureExcludedPresentationDependencies closure)
      , field "type" (prettyShow $ residualType residual)
      , field "term" (prettyShow $ residualTerm residual)
      ]
    | (index, hole) <- zip [(1 :: Int) ..] holes
    ]

renderResidualHoleCallableAbi :: ResidualHoleCallableAbi -> String
renderResidualHoleCallableAbi = \case
  ResidualHoleObservationOnly -> "none"
  ResidualHoleUnaryGroundElimination codec ->
    renderResidualGroundCodec codec
      ++ "-unary-ground-elimination-v1"
  ResidualHoleOrderedGroundEnvironmentElimination codecs ->
    "ordered-"
      ++ intercalate "+" (map renderResidualGroundCodec codecs)
      ++ "-ground-environment-elimination-v1"
  ResidualHoleDependentGroundEnvironmentElimination ->
    "dependent-ground-environment-elimination-v1"

renderResidualGroundCodec :: ResidualGroundCodec -> String
renderResidualGroundCodec =
  groundCodecDescriptorName . residualGroundCodecDescriptor

renderResidualGroundCodecRegistry :: String
renderResidualGroundCodecRegistry =
  intercalate "," (map renderResidualGroundCodec allResidualGroundCodecs)

renderSchemeGroundCodecRegistry :: String
renderSchemeGroundCodecRegistry =
  "(define cubical-chez-ground-codec-registry-v1 '("
    ++ unwords
      (map (schemeString . renderResidualGroundCodec) allResidualGroundCodecs)
    ++ "))"

renderSchemeGroundCodecDescriptors :: String
renderSchemeGroundCodecDescriptors =
  unlines $
    [ "(define cubical-chez-ground-codec-descriptors-v1"
    , "  (list"
    ]
      ++ map renderDescriptor residualGroundCodecDescriptors
      ++ ["  ))"]
  where
    renderDescriptor descriptor =
      "    (vector "
        ++ schemeString (groundCodecDescriptorName descriptor)
        ++ " "
        ++ schemeString
          ( groundCodecDescriptorName descriptor
              ++ "-unary-ground-elimination-v1"
          )
        ++ " "
        ++ schemeString (groundCodecDescriptorName descriptor ++ ":")
        ++ " "
        ++ groundCodecDescriptorArgumentValidator descriptor
        ++ " "
        ++ groundCodecDescriptorArgumentReifier descriptor
        ++ " "
        ++ groundCodecDescriptorEntryParser descriptor
        ++ " "
        ++ groundCodecDescriptorValueReifier descriptor
        ++ ")"

residualHoleAutomaticSingleGroundCodec
  :: ResidualHolePlan
  -> Maybe ResidualGroundCodec
residualHoleAutomaticSingleGroundCodec hole
  | residualHoleSourceClosed hole = Nothing
  | residualHoleEnvironmentArity hole /= 1 = Nothing
  | otherwise = case residualHoleCallableAbi hole of
      ResidualHoleUnaryGroundElimination codec -> Just codec
      _ -> Nothing

residualHoleSupportsPersistentTypedValueProxy :: ResidualHolePlan -> Bool
residualHoleSupportsPersistentTypedValueProxy hole =
  residualHoleSupportsAutomaticGroundEnvironment hole
    || case residualHoleCallableAbi hole of
      ResidualHoleUnaryGroundElimination _ -> True
      _ -> False

residualHoleSupportsAutomaticGroundEnvironment :: ResidualHolePlan -> Bool
residualHoleSupportsAutomaticGroundEnvironment hole =
  case residualHoleAutomaticSingleGroundCodec hole of
    Just _ -> True
    Nothing ->
      residualHoleSupportsAutomaticOrderedGroundEnvironment hole
        || residualHoleSupportsAutomaticDependentGroundEnvironment hole

residualHoleSupportsAutomaticDependentGroundEnvironment
  :: ResidualHolePlan
  -> Bool
residualHoleSupportsAutomaticDependentGroundEnvironment hole =
  not (residualHoleSourceClosed hole)
    && residualHoleEnvironmentArity hole > 1
    && residualHoleEnvironmentArity hole <= residualHoleEnvironmentLimit
    && residualHoleCallableAbi hole
      == ResidualHoleDependentGroundEnvironmentElimination

residualHoleSupportsAutomaticOrderedGroundEnvironment
  :: ResidualHolePlan
  -> Bool
residualHoleSupportsAutomaticOrderedGroundEnvironment hole =
  not (residualHoleSourceClosed hole)
    && residualHoleEnvironmentArity hole > 1
    && case residualHoleCallableAbi hole of
      ResidualHoleOrderedGroundEnvironmentElimination codecs ->
        length codecs == residualHoleEnvironmentArity hole
      _ -> False

residualHoleOrderedGroundEnvironmentCodecs
  :: ResidualHolePlan
  -> [ResidualGroundCodec]
residualHoleOrderedGroundEnvironmentCodecs hole =
  case residualHoleCallableAbi hole of
    ResidualHoleOrderedGroundEnvironmentElimination codecs -> codecs
    _ -> []

residualHoleAutomaticEnvironmentBindingAbi :: ResidualHolePlan -> String
residualHoleAutomaticEnvironmentBindingAbi hole
  | residualHoleSupportsAutomaticDependentGroundEnvironment hole =
      "dependent-ground-chez-lexical-binding-v1"
  | residualHoleSupportsAutomaticOrderedGroundEnvironment hole =
      "ordered-"
        ++ intercalate "+"
          (map renderResidualGroundCodec $
            residualHoleOrderedGroundEnvironmentCodecs hole)
        ++ "-chez-lexical-binding-v1"
  | otherwise = case residualHoleAutomaticSingleGroundCodec hole of
      Just codec ->
        "single-"
          ++ renderResidualGroundCodec codec
          ++ "-chez-lexical-binding-v1"
      Nothing -> "none"

backendAbortWith :: BackendFailureClass -> String -> TCM a
backendAbortWith failureClass message = liftIO $ ioError $ userError $
  "Cubical Chez backend [" ++ failureCode failureClass ++ "]: " ++ message

failureCode :: BackendFailureClass -> String
failureCode = \case
  InvalidConfiguration -> "CCZ-INVALID-CONFIG"
  EntryRejected -> "CCZ-ENTRY-REJECTED"
  NbeUnavailable -> "CCZ-NBE-UNAVAILABLE"
  NbeUnsupportedFeature -> "CCZ-NBE-UNSUPPORTED"
  EngineTimeout -> "CCZ-ENGINE-TIMEOUT"
  NbeExecutionFailed -> "CCZ-NBE-FAILED"
  EngineResultInvalid -> "CCZ-ENGINE-RESULT-INVALID"
  UnsupportedProgram -> "CCZ-UNSUPPORTED"
  ResidualRequired -> "CCZ-RESIDUAL-REQUIRED"
  ResidualizationFailed -> "CCZ-RESIDUALIZATION-FAILED"
  SchemeLoweringFailed -> "CCZ-SCHEME-LOWERING-FAILED"

renderProgram :: CompiledDef -> [CompiledDef] -> Either String String
renderProgram entry defs = do
  validateChezCoreAbi
  definitions <- traverse renderDefinition defs
  pure $ unlines $
    [ "; Generated by CubicalChez 0.1.0-dev."
    , "; Static closure audited by CubicalChez."
    , "; Chez core ABI: " ++ chezCoreAbiVersion declaredChezCoreAbi ++ "."
    , "#!chezscheme"
    ]
      ++ definitions
      ++ [ "(display " ++ mangleQName (compiledName entry) ++ ")"
         , "(newline)"
         ]

reachableDefinitions :: [CompiledDef] -> CompiledDef -> ([CompiledDef], [QName])
reachableDefinitions defs entry =
  let (_, ordered, unresolved) = visit Set.empty Set.empty entry
  in (ordered, Set.toList unresolved)
  where
    definitionsByName = Map.fromList [(compiledName def, def) | def <- defs]

    visit seen unresolved def
      | compiledName def `Set.member` seen = (seen, [], unresolved)
      | otherwise =
          let seenWithCurrent = Set.insert (compiledName def) seen
              (seenAfterDependencies, orderedDependencies, unresolvedDependencies) =
                foldl visitDependency
                  (seenWithCurrent, [], unresolved)
                  (referencedDefinitions (compiledTerm def))
          in (seenAfterDependencies, orderedDependencies ++ [def], unresolvedDependencies)

    visitDependency (seen, ordered, unresolved) name
      | name `Set.member` seen = (seen, ordered, unresolved)
      | otherwise = case Map.lookup name definitionsByName of
          Nothing -> (Set.insert name seen, ordered, Set.insert name unresolved)
          Just dependency ->
            let (seenAfterDependency, dependencyOrder, unresolvedAfterDependency) =
                  visit seen unresolved dependency
            in (seenAfterDependency, ordered ++ dependencyOrder, unresolvedAfterDependency)

referencedDefinitions :: TTerm -> [QName]
referencedDefinitions = \case
  TVar _ -> []
  TPrim _ -> []
  TDef name -> [name]
  TApp function arguments -> referencedDefinitions function ++ concatMap referencedDefinitions arguments
  TLam body -> referencedDefinitions body
  TLit _ -> []
  TCon _ -> []
  TLet value body -> referencedDefinitions value ++ referencedDefinitions body
  TCase _ _ fallback alternatives ->
    referencedDefinitions fallback ++ concatMap referencedAlternative alternatives
  TUnit -> []
  TSort -> []
  TErased -> []
  TCoerce term -> referencedDefinitions term
  TError _ -> []
  where
    referencedAlternative = \case
      TACon _ _ body -> referencedDefinitions body
      TAGuard guard body -> referencedDefinitions guard ++ referencedDefinitions body
      TALit _ body -> referencedDefinitions body

-- | Catalog lookup retained for identifying typed-hole candidates after the
-- entry has passed the semantic audit. It is not the publication classifier.
typedInternalBlockers :: NamesIn internal => internal -> [QName]
typedInternalBlockers internal =
  Set.toList $ Set.filter needsTypedRuntime (namesIn internal :: Set.Set QName)

-- | Resolve the Internal names against Agda's semantic Cubical registry. A
-- pinned QName is accepted as a blocker only when the current checked
-- signature also identifies it as the corresponding builtin/primitive, or as
-- a generated Kan operation. This prevents a same-spelled postulate or a
-- stale catalog entry from acquiring runtime authority by name alone.
auditTypedInternal :: NamesIn internal => internal -> TCM InternalSemanticAudit
auditTypedInternal internal = do
  let occurrences = namesIn internal :: Set.Set QName
      catalog = Set.filter needsTypedRuntime occurrences
      shapedUnknown = Set.filter isUnknownCubicalPrimitive occurrences
  registrySources <- resolveCubicalRegistrySources
  kanSources <- resolveKanOperationSources occurrences
  let availableSources = testInternalSemanticSources $
        registrySources ++ kanSources
      sourceMap = Map.fromListWith mergeSourceLabels availableSources
      semantic = Set.intersection occurrences (Map.keysSet sourceMap)
      disagreements = Set.union
        (Set.difference semantic catalog)
        (Set.difference catalog semantic)
      semanticUnknown = Set.filter (not . needsTypedRuntime) semantic
      evidence =
        [ (name, source)
        | name <- Set.toList semantic
        , Just source <- [Map.lookup name sourceMap]
        ]
  pure InternalSemanticAudit
    { internalSemanticBlockers = Set.toList semantic
    , internalCatalogBlockers = Set.toList catalog
    , internalSemanticSources = evidence
    , internalSemanticCatalogDisagreements = Set.toList disagreements
    , internalUnknownCubicalPrimitives =
        Set.toList (Set.union shapedUnknown semanticUnknown)
    }

mergeSourceLabels :: String -> String -> String
mergeSourceLabels left right
  | left == right = left
  | otherwise = left ++ "+" ++ right

resolveCubicalRegistrySources :: TCM [(QName, String)]
resolveCubicalRegistrySources = do
  builtinSources <- fmap catMaybes $ forM cubicalBuiltinBindings $
    \(label, builtinId) -> do
      maybeName <- Builtin.getBuiltinName' builtinId
      pure $ fmap (\name -> (name, "builtin:" ++ label)) maybeName
  primitiveSources <- fmap catMaybes $ forM cubicalPrimitiveBindings $
    \(label, primitiveId) -> do
      maybeName <- Builtin.getPrimitiveName' primitiveId
      pure $ fmap (\name -> (name, "primitive:" ++ label)) maybeName
  pure $ builtinSources ++ primitiveSources

resolveKanOperationSources :: Set.Set QName -> TCM [(QName, String)]
resolveKanOperationSources occurrences = fmap catMaybes $
  forM (Set.toList occurrences) $ \name -> do
    definitionResult <- getConstInfo' name
    pure $ case definitionResult of
      Right definition -> case theDef definition of
        Function {funIsKanOp = Just _} -> Just (name, "definition:kan-operation")
        _ -> Nothing
      Left _ -> Nothing

-- Stable semantic identities exported by Agda, deliberately separate from
-- the rendered-QName compatibility catalog below.
cubicalBuiltinBindings :: [(String, Builtin.BuiltinId)]
cubicalBuiltinBindings =
  [ ("interval-universe", Builtin.builtinIntervalUniv)
  , ("interval", Builtin.builtinInterval)
  , ("interval-zero", Builtin.builtinIZero)
  , ("interval-one", Builtin.builtinIOne)
  , ("path", Builtin.builtinPath)
  , ("path-dependent", Builtin.builtinPathP)
  , ("partial", Builtin.builtinPartial)
  , ("partial-dependent", Builtin.builtinPartialP)
  , ("is-one", Builtin.builtinIsOne)
  , ("it-is-one", Builtin.builtinItIsOne)
  , ("is-one-left", Builtin.builtinIsOne1)
  , ("is-one-right", Builtin.builtinIsOne2)
  , ("is-one-empty", Builtin.builtinIsOneEmpty)
  , ("transp-proof", Builtin.builtinTranspProof)
  , ("sub", Builtin.builtinSub)
  , ("sub-in", Builtin.builtinSubIn)
  ]

cubicalPrimitiveBindings :: [(String, Builtin.PrimitiveId)]
cubicalPrimitiveBindings =
  [ ("interval-min", Builtin.builtinIMin)
  , ("interval-max", Builtin.builtinIMax)
  , ("interval-neg", Builtin.builtinINeg)
  , ("partial", Builtin.PrimPartial)
  , ("partial-dependent", Builtin.PrimPartialP)
  , ("sub-out", Builtin.builtinSubOut)
  , ("glue", Builtin.builtinGlue)
  , ("glue-intro", Builtin.builtin_glue)
  , ("glue-elim", Builtin.builtin_unglue)
  , ("glue-universe-intro", Builtin.builtin_glueU)
  , ("glue-universe-elim", Builtin.builtin_unglueU)
  , ("face-forall", Builtin.builtinFaceForall)
  , ("composition", Builtin.builtinComp)
  , ("partial-or", Builtin.builtinPOr)
  , ("transport", Builtin.builtinTrans)
  , ("homogeneous-composition", Builtin.builtinHComp)
  ]

-- Compile-time-only semantic-registry fault. The verifier uses it to prove
-- that a correct spelling in the pinned catalog cannot bypass semantic
-- identity validation.
testInternalSemanticSources :: [(QName, String)] -> [(QName, String)]
#if defined(CUBICAL_CHEZ_TEST_INTERNAL_SEMANTIC_CATALOG_DISAGREEMENT)
testInternalSemanticSources _ = []
#else
testInternalSemanticSources = id
#endif

-- | Defense-in-depth audit of the candidate erased term.  It can catch a
-- blocker introduced or exposed by Treeless conversion.
typedTreelessBlockers :: TTerm -> [QName]
typedTreelessBlockers =
  Set.toList . Set.fromList . filter needsTypedRuntime . referencedDefinitions

-- | Names which look like Cubical primitives but are not in the pinned Agda
-- 2.8/2.9 catalog are kept separate from supported runtime blockers.  An
-- executable occurrence is fail-closed so an Agda upgrade cannot silently
-- route a newly introduced primitive through erased Chez code.
typedTreelessUnknownCubical :: TTerm -> [QName]
typedTreelessUnknownCubical =
  Set.toList
    . Set.fromList
    . filter isUnknownCubicalPrimitive
    . referencedDefinitions

-- | The two syntax layers must at least agree on whether executable typed
-- semantics survive.  Exact QName sets need not match because Treeless erases
-- helper names such as interval endpoints.  A runtime-headed residual is
-- dynamic; a blocker below a static constructor/control node is mixed. Mixed
-- can publish a static shell plus typed-hole artifacts and a checked-ground or
-- explicit-environment bridge, while the whole-entry packet remains the equivalence
-- reference.
classifyBindingTime
  :: [QName]
  -> [QName]
  -> [QName]
  -> [QName]
  -> [QName]
  -> TTerm
  -> (BindingTimeClass, BindingTimeReason)
classifyBindingTime
  internalBlockers
  treelessBlockers
  internalUnknownCubical
  treelessUnknownCubical
  semanticCatalogDisagreements
  term
  | not (null internalUnknownCubical && null treelessUnknownCubical) =
      (BindingUnsupported, UnknownCubicalPrimitive)
  | not (null semanticCatalogDisagreements) =
      (BindingUnsupported, InternalSemanticCatalogDisagreement)
  | null internalBlockers && null treelessBlockers =
      (BindingStatic, NoRuntimeBlockers)
  | null internalBlockers || null treelessBlockers =
      (BindingUnsupported, InternalTreelessAuditDisagreement)
  | runtimeBlockerAtHead term =
      (BindingDynamic, WholeEntryRuntimeHead)
  | otherwise =
      (BindingMixed, StaticContextAroundRuntimeBlocker)

runtimeBlockerAtHead :: TTerm -> Bool
runtimeBlockerAtHead = \case
  TDef name -> needsTypedRuntime name
  TApp function _ -> runtimeBlockerAtHead function
  TLam body -> runtimeBlockerAtHead body
  TLet _ body -> runtimeBlockerAtHead body
  TCoerce term -> runtimeBlockerAtHead term
  _ -> False

-- Compile-time-only audit fault for the unsupported-class verifier.
testTreelessBlockers :: [QName] -> [QName]
#if defined(CUBICAL_CHEZ_TEST_BINDING_AUDIT_DISAGREEMENT)
testTreelessBlockers _ = []
#else
testTreelessBlockers = id
#endif

renderBindingTime :: BindingTimeClass -> String
renderBindingTime = \case
  BindingStatic -> "static"
  BindingDynamic -> "dynamic"
  BindingMixed -> "mixed"
  BindingUnsupported -> "unsupported"

bindingTimeReason :: BindingTimeReason -> String
bindingTimeReason = \case
  NoRuntimeBlockers -> "no-runtime-blockers"
  WholeEntryRuntimeHead -> "whole-entry-runtime-head"
  StaticContextAroundRuntimeBlocker -> "static-context-around-runtime-blocker"
  InternalSemanticCatalogDisagreement ->
    "internal-semantic-catalog-disagreement"
  InternalTreelessAuditDisagreement -> "internal-treeless-audit-disagreement"
  UnknownCubicalPrimitive -> "unknown-cubical-primitive"

bindingTimeAction :: BindingTimeClass -> String
bindingTimeAction = \case
  BindingStatic -> "erase-types-and-emit"
  BindingDynamic -> "typed-residual-whole-entry"
  BindingMixed ->
    "typed-residual-split-shell-ground-observation-by-id-whole-entry-reference"
  BindingUnsupported -> "reject"

bindingTimeDecision :: BindingTimeClass -> String
bindingTimeDecision = \case
  BindingStatic -> "static-closed"
  BindingDynamic -> "typed-residual"
  BindingMixed -> "typed-residual"
  BindingUnsupported -> "unsupported"

compiledRuntimeBlockers :: CompiledDef -> [QName]
compiledRuntimeBlockers entry = mergeBlockers
  (compiledInternalTermBlockers entry)
  (compiledTreelessBlockers entry)

compiledUnknownCubicalPrimitives :: CompiledDef -> [QName]
compiledUnknownCubicalPrimitives entry = mergeBlockers
  (compiledInternalTermUnknownCubical entry)
  (compiledTreelessUnknownCubical entry)

mergeBlockers :: [QName] -> [QName] -> [QName]
mergeBlockers left right = Set.toList $ Set.fromList (left ++ right)

renderBlockers :: [QName] -> String
renderBlockers = \case
  [] -> "none"
  blockers -> commaSeparated (map prettyShow blockers)

renderSemanticSources :: [(QName, String)] -> String
renderSemanticSources = \case
  [] -> "none"
  sources -> commaSeparated
    [ prettyShow name ++ "=" ++ source
    | (name, source) <- sources
    ]

semanticCatalogStatus :: [QName] -> String
semanticCatalogStatus [] = "agree"
semanticCatalogStatus _ = "disagree"

needsTypedRuntime :: QName -> Bool
needsTypedRuntime name =
  prettyShow name `elem` knownCubicalRuntimeQNames
    || "transpX-" `isInfixOf` prettyShow name

isUnknownCubicalPrimitive :: QName -> Bool
isUnknownCubicalPrimitive name =
  isCubicalPrimitiveCandidate rendered
    && not (needsTypedRuntime name)
  where
    rendered = prettyShow name

isCubicalPrimitiveCandidate :: String -> Bool
isCubicalPrimitiveCandidate rendered =
  "Agda.Primitive.Cubical." `isPrefixOf` rendered
    || (isPrimitiveNamespace rendered && "prim" `isPrefixOf` localName rendered)
  where
    isPrimitiveNamespace name = any (`isPrefixOf` name)
      [ "Agda.Builtin.Cubical."
      , "Cubical.Primitive."
      , "Cubical.Primitives."
      ]

localName :: String -> String
localName = reverse . takeWhile (/= '.') . reverse

-- Pinned union of the runtime-sensitive names declared by the Agda 2.8 and
-- Agda 2.9 primitive libraries.  Keep this explicit: a new QName must first
-- be reviewed and added here, otherwise the unknown-primitive gate rejects it.
knownCubicalRuntimeQNames :: [String]
knownCubicalRuntimeQNames =
  [ "Agda.Primitive.Cubical.IUniv"
  , "Agda.Primitive.Cubical.I"
  , "Agda.Primitive.Cubical.i0"
  , "Agda.Primitive.Cubical.i1"
  , "Agda.Primitive.Cubical.primIMin"
  , "Agda.Primitive.Cubical.primIMax"
  , "Agda.Primitive.Cubical.primINeg"
  , "Agda.Primitive.Cubical.IsOne"
  , "Agda.Primitive.Cubical.itIsOne"
  , "Agda.Primitive.Cubical.IsOne1"
  , "Agda.Primitive.Cubical.IsOne2"
  , "Agda.Primitive.Cubical.Partial"
  , "Agda.Primitive.Cubical.PartialP"
  , "Agda.Primitive.Cubical.isOneEmpty"
  , "Agda.Primitive.Cubical.primPOr"
  , "Agda.Primitive.Cubical.primComp"
  , "Agda.Primitive.Cubical.primTransp"
  , "Agda.Primitive.Cubical.primHComp"
  , "Agda.Primitive.Cubical.PathP"
  , "Agda.Builtin.Cubical.Glue.primGlue"
  , "Agda.Builtin.Cubical.Glue.prim^glue"
  , "Agda.Builtin.Cubical.Glue.prim^unglue"
  , "Agda.Builtin.Cubical.HCompU.prim^glueU"
  , "Agda.Builtin.Cubical.HCompU.prim^unglueU"
  , "Agda.Builtin.Cubical.HCompU.primFaceForall"
  , "Agda.Builtin.Cubical.Sub.primSubOut"
  ]

findEntry :: ChezOptions -> [CompiledDef] -> Either String CompiledDef
findEntry opts defs = case filter isEntry defs of
  [entry] -> Right entry
  [] -> Left $ "no closed, argument-free entry matched "
    ++ show (chezEntry opts)
  entries -> Left $ "ambiguous entry "
    ++ show (chezEntry opts)
    ++ ": "
    ++ show (map (prettyShow . compiledName) entries)
  where
    isEntry def =
      compiledFromMainModule def
        && compiledIsEntry def

isRequestedEntryName :: String -> QName -> Bool
isRequestedEntryName requested name =
  rendered == requested
    || ('.' `notElem` requested && ('.' : requested) `isSuffixOf` rendered)
  where
    rendered = prettyShow name

renderDefinition :: CompiledDef -> Either String String
renderDefinition compiled = do
  body <- compileTerm [] 0 (compiledTerm compiled)
  pure $ "(define " ++ mangleQName (compiledName compiled) ++ " " ++ body ++ ")"

renderChezConstructor :: QName -> [String] -> String
renderChezConstructor name = renderChezConstructorSymbol (mangleQName name)

renderChezConstructorSymbol :: String -> [String] -> String
renderChezConstructorSymbol symbol fields =
  "(vector '" ++ symbol ++ concatMap (" " ++) fields ++ ")"

renderChezConstructorTag :: String -> String
renderChezConstructorTag value =
  renderChezVectorRef value $
    chezCoreAbiConstructorTagIndex implementedChezCoreAbi

renderChezConstructorField :: String -> Int -> String
renderChezConstructorField value offset =
  renderChezVectorRef value $
    chezCoreAbiConstructorFieldBaseIndex implementedChezCoreAbi + offset

renderChezVectorRef :: String -> Int -> String
renderChezVectorRef value index =
  "(vector-ref " ++ value ++ " " ++ show index ++ ")"

renderChezApplication :: String -> [String] -> String
renderChezApplication = foldl applyOne

renderChezLambda :: String -> String -> String
renderChezLambda variable body =
  "(lambda (" ++ variable ++ ") " ++ body ++ ")"

compileTerm :: [String] -> Int -> TTerm -> Either String String
compileTerm env depth = \case
  TVar index -> lookupVariable env index
  TDef name -> pure (mangleQName name)
  TApp (TCon name) args -> do
    rendered <- traverse (compileTerm env depth) args
    pure $ renderChezConstructor name rendered
  TApp (TPrim primitive) args -> compilePrimitiveApplication env depth primitive args
  TApp function args -> do
    renderedFunction <- compileTerm env depth function
    renderedArgs <- traverse (compileTerm env depth) args
    pure (renderChezApplication renderedFunction renderedArgs)
  TLam body -> do
    let variable = "v" ++ show depth
    renderedBody <- compileTerm (variable : env) (depth + 1) body
    pure $ renderChezLambda variable renderedBody
  TLit literal -> compileLiteral literal
  TCon name -> pure $ renderChezConstructor name []
  TLet value body -> do
    renderedValue <- compileTerm env depth value
    let variable = "v" ++ show depth
    renderedBody <- compileTerm (variable : env) (depth + 1) body
    pure $ "(let ((" ++ variable ++ " " ++ renderedValue ++ ")) " ++ renderedBody ++ ")"
  TCase scrutinee caseInfo fallback alternatives ->
    compileCase env depth scrutinee caseInfo fallback alternatives
  TPrim primitive -> compilePrimitiveValue primitive
  TUnit -> pure "#f"
  TSort -> pure "#f"
  TErased -> pure "#f"
  TCoerce term -> compileTerm env depth term
  TError TUnreachable -> pure "(error 'agda-chez \"unreachable code reached\")"
  TError (TMeta message) -> pure $ "(error 'agda-chez " ++ schemeString message ++ ")"

-- | Lower a mixed static shell while replacing every planned blocker-headed
-- subtree with an opaque import handle.  The handle is data, never a fake
-- implementation of the typed term. Any runtime-headed subtree not covered by
-- the exact path inventory rejects lowering.
compileTermWithHoleImports
  :: Map.Map String (Int, ResidualHolePlan)
  -> [String]
  -> [String]
  -> Int
  -> TTerm
  -> Either String String
compileTermWithHoleImports imports path env depth term =
  case Map.lookup (renderResidualHolePath path) imports of
    Just (_, hole)
      | residualHoleSupportsAutomaticDependentGroundEnvironment hole ->
          let arity = residualHoleEnvironmentArity hole
              available = take arity env
              orderedVariables = reverse available
          in if length available == arity
            then pure $
              "(cubical-chez-bind-dependent-ground-environment "
                ++ "(cubical-chez-typed-hole-reference "
                ++ schemeString (residualHoleId hole)
                ++ ") "
                ++ show arity
                ++ " "
                ++ "(vector "
                ++ unwords orderedVariables
                ++ "))"
            else Left $
              "dependent ground lexical environment is unavailable at "
                ++ renderResidualHolePath path
      | residualHoleSupportsAutomaticOrderedGroundEnvironment hole ->
          let arity = residualHoleEnvironmentArity hole
              available = take arity env
              orderedVariables = reverse available
              codecs = residualHoleOrderedGroundEnvironmentCodecs hole
          in if length available == arity && length codecs == arity
            then pure $
              "(cubical-chez-bind-ground-environment "
                ++ "(cubical-chez-typed-hole-reference "
                ++ schemeString (residualHoleId hole)
                ++ ") "
                ++ "(vector "
                ++ unwords (map (schemeString . renderResidualGroundCodec) codecs)
                ++ ") "
                ++ "(vector "
                ++ unwords orderedVariables
                ++ "))"
            else Left $
              "ordered ground lexical environment is unavailable at "
                ++ renderResidualHolePath path
      | Just codec <- residualHoleAutomaticSingleGroundCodec hole ->
          case env of
            variable : _ -> pure $
              "(cubical-chez-bind-"
                ++ renderResidualGroundCodec codec
                ++ "-environment "
                ++ "(cubical-chez-typed-hole-reference "
                ++ schemeString (residualHoleId hole)
                ++ ") "
                ++ variable
                ++ ")"
            [] -> Left $
              "single-"
                ++ renderResidualGroundCodec codec
                ++ " lexical environment is unavailable at "
                ++ renderResidualHolePath path
      | otherwise -> pure $
          "(cubical-chez-typed-hole-reference "
            ++ schemeString (residualHoleId hole)
            ++ ")"
    Nothing
      | runtimeBlockerAtHead term -> Left $
          "mixed residual static shell has an uncovered runtime subtree at "
            ++ renderResidualHolePath path
      | otherwise -> lower term
  where
    descend segment = compileTermWithHoleImports imports (path ++ [segment])
    lower = \case
      TVar index -> lookupVariable env index
      TPrim primitive -> compilePrimitiveValue primitive
      TDef name -> pure (mangleQName name)
      TApp (TCon name) args -> do
        rendered <- traverseIndexed "app-argument-" args
        pure $ renderChezConstructor name rendered
      TApp (TPrim primitive) args -> do
        rendered <- traverseIndexed "app-argument-" args
        compilePrimitiveApplicationRendered primitive rendered
      TApp function args -> do
        renderedFunction <- descend "app-function" env depth function
        renderedArgs <- traverseIndexed "app-argument-" args
        pure (renderChezApplication renderedFunction renderedArgs)
      TLam body -> do
        let variable = "v" ++ show depth
        renderedBody <- descend "lambda-body" (variable : env) (depth + 1) body
        pure $ renderChezLambda variable renderedBody
      TLit literal -> compileLiteral literal
      TCon name -> pure $ renderChezConstructor name []
      TLet value body -> do
        renderedValue <- descend "let-value" env depth value
        let variable = "v" ++ show depth
        renderedBody <- descend "let-body" (variable : env) (depth + 1) body
        pure $ "(let ((" ++ variable ++ " " ++ renderedValue
          ++ ")) " ++ renderedBody ++ ")"
      TCase scrutinee caseInfo fallback alternatives ->
        compileCaseWithHoleImports
          imports path env depth scrutinee caseInfo fallback alternatives
      TUnit -> pure "#f"
      TSort -> pure "#f"
      TErased -> pure "#f"
      TCoerce coerced -> descend "coerce-body" env depth coerced
      TError TUnreachable ->
        pure "(error 'agda-chez \"unreachable code reached\")"
      TError (TMeta message) ->
        pure $ "(error 'agda-chez " ++ schemeString message ++ ")"

    traverseIndexed prefix terms = sequence
      [ descend (prefix ++ show index) env depth child
      | (index, child) <- zip [(0 :: Int) ..] terms
      ]

compileCaseWithHoleImports
  :: Map.Map String (Int, ResidualHolePlan)
  -> [String]
  -> [String]
  -> Int
  -> Int
  -> CaseInfo
  -> TTerm
  -> [TAlt]
  -> Either String String
compileCaseWithHoleImports
  imports path env depth scrutinee caseInfo fallback alternatives = do
    value <- lookupVariable env scrutinee
    renderedFallback <- compileTermWithHoleImports
      imports (path ++ ["case-fallback"]) env depth fallback
    case caseType caseInfo of
      CTData _ -> do
        clauses <- sequence
          [ compileDataAlternativeWithHoleImports
              imports
              (path ++ ["case-alternative-" ++ show index])
              env depth value alternative
          | (index, alternative) <- zip [(0 :: Int) ..] alternatives
          ]
        pure $ "(case " ++ renderChezConstructorTag value ++ " " ++ unwords clauses
          ++ " (else " ++ renderedFallback ++ "))"
      CTNat -> do
        clauses <- sequence
          [ compileLiteralAlternativeWithHoleImports
              imports
              (path ++ ["case-alternative-" ++ show index])
              env depth value alternative
          | (index, alternative) <- zip [(0 :: Int) ..] alternatives
          ]
        pure $ "(cond " ++ unwords clauses
          ++ " (else " ++ renderedFallback ++ "))"
      other -> Left $
        "Cubical Chez backend: unsupported mixed-shell case type " ++ show other

compileDataAlternativeWithHoleImports
  :: Map.Map String (Int, ResidualHolePlan)
  -> [String]
  -> [String]
  -> Int
  -> String
  -> TAlt
  -> Either String String
compileDataAlternativeWithHoleImports imports path env depth value = \case
  TACon constructor arity body -> do
    let fields =
          [ "field" ++ show depth ++ "_" ++ show index
          | index <- [0 .. arity - 1]
          ]
        bindings = zipWith
          (\field index ->
            "(" ++ field ++ " "
              ++ renderChezConstructorField value index ++ ")")
          fields
          [0 :: Int ..]
        bodyEnv = reverse fields ++ env
    renderedBody <- compileTermWithHoleImports
      imports (path ++ ["constructor-body"]) bodyEnv (depth + arity) body
    pure $ "((" ++ mangleQName constructor ++ ") (let ("
      ++ unwords bindings ++ ") " ++ renderedBody ++ "))"
  alternative -> Left $
    "Cubical Chez backend: unsupported mixed-shell data alternative "
      ++ show alternative

compileLiteralAlternativeWithHoleImports
  :: Map.Map String (Int, ResidualHolePlan)
  -> [String]
  -> [String]
  -> Int
  -> String
  -> TAlt
  -> Either String String
compileLiteralAlternativeWithHoleImports imports path env depth value = \case
  TALit literal body -> do
    renderedLiteral <- compileLiteral literal
    renderedBody <- compileTermWithHoleImports
      imports (path ++ ["literal-body"]) env depth body
    pure $ "((equal? " ++ value ++ " " ++ renderedLiteral
      ++ ") " ++ renderedBody ++ ")"
  TAGuard guard body -> do
    renderedGuard <- compileTermWithHoleImports
      imports (path ++ ["guard-test"]) env depth guard
    renderedBody <- compileTermWithHoleImports
      imports (path ++ ["guard-body"]) env depth body
    pure $ "(" ++ renderedGuard ++ " " ++ renderedBody ++ ")"
  alternative -> Left $
    "Cubical Chez backend: unsupported mixed-shell literal alternative "
      ++ show alternative

compileCase :: [String] -> Int -> Int -> CaseInfo -> TTerm -> [TAlt] -> Either String String
compileCase env depth scrutinee caseInfo fallback alternatives = do
  value <- lookupVariable env scrutinee
  renderedFallback <- compileTerm env depth fallback
  case caseType caseInfo of
    CTData _ -> do
      clauses <- traverse (compileDataAlternative env depth value) alternatives
      pure $ "(case " ++ renderChezConstructorTag value ++ " " ++ unwords clauses
        ++ " (else " ++ renderedFallback ++ "))"
    CTNat -> do
      clauses <- traverse (compileLiteralAlternative env depth value) alternatives
      pure $ "(cond " ++ unwords clauses ++ " (else " ++ renderedFallback ++ "))"
    other -> Left $ "Cubical Chez backend: unsupported case type " ++ show other

compileDataAlternative :: [String] -> Int -> String -> TAlt -> Either String String
compileDataAlternative env depth value = \case
  TACon constructor arity body -> do
    let fields = ["field" ++ show depth ++ "_" ++ show index | index <- [0 .. arity - 1]]
        bindings = zipWith
          (\field index ->
            "(" ++ field ++ " "
              ++ renderChezConstructorField value index ++ ")")
          fields
          [0 :: Int ..]
        bodyEnv = reverse fields ++ env
    renderedBody <- compileTerm bodyEnv (depth + arity) body
    pure $ "((" ++ mangleQName constructor ++ ") (let (" ++ unwords bindings ++ ") " ++ renderedBody ++ "))"
  alternative -> Left $ "Cubical Chez backend: unsupported data alternative " ++ show alternative

compileLiteralAlternative :: [String] -> Int -> String -> TAlt -> Either String String
compileLiteralAlternative env depth value = \case
  TALit literal body -> do
    renderedLiteral <- compileLiteral literal
    renderedBody <- compileTerm env depth body
    pure $ "((equal? " ++ value ++ " " ++ renderedLiteral ++ ") " ++ renderedBody ++ ")"
  TAGuard guard body -> do
    renderedGuard <- compileTerm env depth guard
    renderedBody <- compileTerm env depth body
    pure $ "(" ++ renderedGuard ++ " " ++ renderedBody ++ ")"
  alternative -> Left $ "Cubical Chez backend: unsupported literal alternative " ++ show alternative

compilePrimitiveApplication :: [String] -> Int -> TPrim -> [TTerm] -> Either String String
compilePrimitiveApplication env depth primitive args = do
  rendered <- traverse (compileTerm env depth) args
  compilePrimitiveApplicationRendered primitive rendered

compilePrimitiveApplicationRendered
  :: TPrim
  -> [String]
  -> Either String String
compilePrimitiveApplicationRendered primitive rendered =
  case
    [ form
    | (candidate, arity, form) <- chezPrimitiveApplicationTable
    , candidate == primitive
    , arity == length rendered
    ] of
    ChezPrimitiveBinary operator : _ -> case rendered of
      [x, y] -> pure $ "(" ++ operator ++ " " ++ x ++ " " ++ y ++ ")"
      _ -> unsupported
    ChezPrimitiveIf : _ -> case rendered of
      [condition, yes, no] -> pure $
        "(if " ++ condition ++ " " ++ yes ++ " " ++ no ++ ")"
      _ -> unsupported
    ChezPrimitiveBegin : _ -> case rendered of
      [first, second] -> pure $
        "(begin " ++ first ++ " " ++ second ++ ")"
      _ -> unsupported
    ChezPrimitiveIdentity : _ -> case rendered of
      [value] -> pure value
      _ -> unsupported
    [] -> unsupported
  where
    unsupported = Left $
      "Cubical Chez backend: unsupported primitive application "
        ++ show primitive ++ "/" ++ show (length rendered)

compilePrimitiveValue :: TPrim -> Either String String
compilePrimitiveValue primitive = case
  [ operator
  | (candidate, operator) <- chezPrimitiveFirstClassTable
  , candidate == primitive
  ] of
  operator : _ -> curried2 operator
  [] -> Left $
    "Cubical Chez backend: unsupported first-class primitive " ++ show primitive
  where
    curried2 operator = pure $
      renderChezLambda "x" $
        renderChezLambda "y" $ "(" ++ operator ++ " x y)"

compileLiteral :: Literal -> Either String String
compileLiteral = \case
  LitNat number -> pure (show number)
  LitWord64 number -> pure (show number)
  LitFloat number -> pure (show number)
  LitString value -> pure (schemeString (Text.unpack value))
  LitChar value -> pure $ "#\\" ++ [value]
  LitQName value -> pure $ "'" ++ mangleQName value
  literal@LitMeta {} -> Left $ "Cubical Chez backend: cannot compile meta literal " ++ show literal

lookupVariable :: [String] -> Int -> Either String String
lookupVariable env index = case drop index env of
  variable : _ -> Right variable
  [] -> Left $ "Cubical Chez backend: invalid de Bruijn index " ++ show index

applyOne :: String -> String -> String
applyOne function argument = "(" ++ function ++ " " ++ argument ++ ")"

mangleQName :: QName -> String
mangleQName = ("agda_" ++) . concatMap encode . prettyShow
  where
    encode character
      | isAlphaNum character = [character]
      | otherwise = "_" ++ showHex (ord character) "_"

schemeString :: String -> String
schemeString = show

renderDump :: [CompiledDef] -> [QName] -> String
renderDump defs unresolved = unlines $
  concatMap render defs
    ++ case unresolved of
      [] -> []
      names -> "Unresolved runtime definitions:" : map (("  " ++) . prettyShow) names
  where
    render compiled =
      [ prettyShow (compiledName compiled)
      , "  " ++ summarizeTerm (compiledTerm compiled)
      ]

summarizeTerm :: TTerm -> String
summarizeTerm = \case
  TVar index -> "TVar " ++ show index
  TPrim primitive -> "TPrim " ++ show primitive
  TDef name -> "TDef(" ++ prettyShow name ++ ")"
  TApp function arguments ->
    "TApp(" ++ summarizeTerm function ++ ", [" ++ commaSeparated (map summarizeTerm arguments) ++ "])"
  TLam body -> "TLam(" ++ summarizeTerm body ++ ")"
  TLit literal -> "TLit(" ++ show literal ++ ")"
  TCon name -> "TCon(" ++ prettyShow name ++ ")"
  TLet value body -> "TLet(" ++ summarizeTerm value ++ ", " ++ summarizeTerm body ++ ")"
  TCase scrutinee info fallback alternatives ->
    "TCase(" ++ show scrutinee ++ ", " ++ summarizeCaseType (caseType info) ++ ", "
      ++ summarizeTerm fallback ++ ", [" ++ commaSeparated (map summarizeAlternative alternatives) ++ "])"
  TUnit -> "TUnit"
  TSort -> "TSort"
  TErased -> "TErased"
  TCoerce term -> "TCoerce(" ++ summarizeTerm term ++ ")"
  TError problem -> "TError(" ++ show problem ++ ")"
  where
    summarizeAlternative = \case
      TACon constructor arity body ->
        "TACon(" ++ prettyShow constructor ++ ", " ++ show arity ++ ", " ++ summarizeTerm body ++ ")"
      TAGuard guard body ->
        "TAGuard(" ++ summarizeTerm guard ++ ", " ++ summarizeTerm body ++ ")"
      TALit literal body ->
        "TALit(" ++ show literal ++ ", " ++ summarizeTerm body ++ ")"

summarizeCaseType :: CaseType -> String
summarizeCaseType = \case
  CTData name -> "CTData(" ++ prettyShow name ++ ")"
  CTNat -> "CTNat"
  CTInt -> "CTInt"
  CTChar -> "CTChar"
  CTString -> "CTString"
  CTFloat -> "CTFloat"
  CTQName -> "CTQName"

commaSeparated :: [String] -> String
commaSeparated = foldr join ""
  where
    join item "" = item
    join item rest = item ++ ", " ++ rest
