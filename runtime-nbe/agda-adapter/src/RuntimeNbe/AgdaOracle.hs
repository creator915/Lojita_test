{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module RuntimeNbe.AgdaOracle (runtimeNbeOracleBackend) where

import Control.Monad.IO.Class (liftIO)

import Agda.Compiler.Backend
import Agda.Syntax.Abstract.Pretty (prettyA)
import Agda.Syntax.Common (ProjOrigin(ProjSystem))
import Agda.Syntax.Common.Pretty (prettyShow, render)
import Agda.Syntax.Internal (Dom'(unDom), Elim'(Proj), Term)
import qualified Agda.Syntax.Internal as Internal
import Agda.Syntax.Translation.InternalToAbstract (reify)
import qualified Agda.TypeChecking.Monad.Builtin as Builtin
import Agda.TypeChecking.Reduce (normalise)
import Agda.TypeChecking.Substitute (applyE)

import RuntimeNbe.AgdaProducer
  ( ProducerOptions(producerOutput), producerAbort, runtimeNbeBackendWith )


-- This backend is test-only oracle machinery.  It is a separate executable and
-- is never linked into or invoked by the runtime producer/final program.
runtimeNbeOracleBackend :: Backend
runtimeNbeOracleBackend = runtimeNbeBackendWith
  "RuntimeNbeOracle" "oracle-v1" publishOracle

publishOracle :: ProducerOptions -> Definition -> Term -> String -> TCM ()
publishOracle opts definition body _ = do
  normalTermSyntaxRaw <- sigmaOracle definition >>= \case
    Just syntax -> pure syntax
    Nothing -> do
      normalTerm <- normalise body
      render <$> (prettyA =<< reify normalTerm)
  normalType <- normalise (defType definition)
  typeSyntaxRaw <- render <$> (prettyA =<< reify normalType)
  let normalTermSyntax = singleLine normalTermSyntaxRaw
      typeSyntax = singleLine typeSyntaxRaw
  output <- maybe (producerAbort "missing runtime NbE oracle output path") pure $
    producerOutput opts
  liftIO $ writeFile output $ unlines
    [ "schema=runtime-nbe-agda-oracle-v1"
    , "source-qname=" ++ prettyShow (defName definition)
    , "term-syntax=" ++ normalTermSyntax
    , "type-syntax=" ++ typeSyntax
    ]

singleLine :: String -> String
singleLine = unwords . words

sigmaOracle :: Definition -> TCM (Maybe String)
sigmaOracle definition = do
  sigmaName <- Builtin.getBuiltinName' Builtin.builtinSigma
  case (sigmaName, defType definition) of
    (Just sigma, Internal.El _ (Internal.Def typeName _))
      | sigma == typeName -> do
          sigmaDefinition <- getConstInfo sigma
          case theDef sigmaDefinition of
            Record { recFields = [firstField, secondField] } -> do
              let source = Internal.Def (defName definition) []
              first <- normalise $ source `applyE` [Proj ProjSystem (unDom firstField)]
              second <- normalise $ source `applyE` [Proj ProjSystem (unDom secondField)]
              firstSyntax <- render <$> (prettyA =<< reify first)
              secondSyntax <- render <$> (prettyA =<< reify second)
              pure $ Just (firstSyntax ++ " , " ++ secondSyntax)
            _ -> pure Nothing
    _ -> pure Nothing
