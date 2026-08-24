{-# LANGUAGE ImplicitParams #-}

-- | Input-driven adapter to the linked cctt normalization engine.
--
-- Values in the Agda wire fragment are encoded as closed cctt terms.  The
-- requested transport/selection/composition is encoded as a cctt function,
-- evaluated by 'Core.eval', quoted by 'Quotation.quoteUnfold', and decoded
-- back to the shape of the actual input.  Consequently the returned value is
-- the cctt normal form of that input; this module contains no canned probes or
-- success Boolean that can authorize a separately computed result.
module Cubical.Runtime.Nbe.Cctt
  ( ProviderValue (..)
  , ProviderDirection (..)
  , providerTransport
  , providerSelect
  , providerPreserve
  , providerAddInt
  ) where

import Common (Name (N_))
import Core (eval)
import CoreTypes
  ( Env (ENil)
  , Recurse (DontRecurse)
  , Tm (..)
  )
import Cubical (emptyNCof, idSub)
import Cubical.Runtime.Nbe.Wire (Equiv (..), Face (..), Family (..))
import Quotation (quoteUnfold)

data ProviderValue
  = ProviderBool Bool
  | ProviderNat Integer
  | ProviderInt Integer
  | ProviderVec [ProviderValue]
  | ProviderPair ProviderValue ProviderValue
  deriving (Eq, Show)

data ProviderDirection = ProviderForward | ProviderBackward
  deriving (Eq, Show)

{-# NOINLINE providerTransport #-}
providerTransport :: ProviderDirection -> Family -> ProviderValue -> Either String ProviderValue
providerTransport direction family input = do
  validateFamilyShape family input
  function <- familyFunction direction family
  decodeLike input (normalize (App function (encode input)))

validateFamilyShape :: Family -> ProviderValue -> Either String ()
validateFamilyShape family input = case (family, input) of
  (FamilyVec elementFamily size, ProviderVec elements)
    | size /= length elements -> Left "Vec length does not match transport family"
    | otherwise -> mapM_ (validateFamilyShape elementFamily) elements
  (FamilyVec {}, _) -> Left "Vec transport received a non-Vec provider value"
  (FamilySigma firstFamily secondFamily, ProviderPair first second) ->
    validateFamilyShape firstFamily first >> validateFamilyShape secondFamily second
  (FamilySigma {}, _) -> Left "Sigma transport received a non-pair provider value"
  (FamilyGlue EquivBoolNot, ProviderBool _) -> Right ()
  (FamilyGlue EquivIntSucc, ProviderInt _) -> Right ()
  (FamilyGlue (EquivIdentity _), _) -> Right ()
  (FamilyGlue (EquivCompose first second), _) ->
    validateFamilyShape (FamilyGlue first) input >> validateFamilyShape (FamilyGlue second) input
  (FamilyGlue (EquivInverse equivalence), _) ->
    validateFamilyShape (FamilyGlue equivalence) input
  (FamilyGlue {}, _) -> Left "equivalence transport received a provider value of the wrong shape"
  (FamilyCompose first second, _) ->
    validateFamilyShape first input >> validateFamilyShape second input
  (FamilyConst _, _) -> Right ()
  (FamilyPi {}, _) -> Left "Pi transport is represented extensionally at application"

{-# NOINLINE providerSelect #-}
providerSelect :: Face -> ProviderValue -> ProviderValue -> Either String ProviderValue
providerSelect face system base =
  let selector = case face of
        FaceOne -> churchTrue
        FaceZero -> churchFalse
      inputShape = case face of
        FaceOne -> system
        FaceZero -> base
      term = App (App selector (encode system)) (encode base)
  in decodeLike inputShape (normalize term)

{-# NOINLINE providerPreserve #-}
providerPreserve :: ProviderValue -> Either String ProviderValue
providerPreserve input =
  decodeLike input (normalize (App identityFunction (encode input)))

{-# NOINLINE providerAddInt #-}
providerAddInt :: Integer -> Integer -> Either String Integer
providerAddInt left right = do
  positive <- addNats (max 0 left) (max 0 right)
  negative <- addNats (max 0 (-left)) (max 0 (-right))
  Right (positive - negative)
  where
    addNats first second = decodeNat
      (normalize (App (App natAddFunction (churchNat first)) (churchNat second)))

normalize :: Tm -> Tm
normalize term =
  let ?cof = emptyNCof
      ?dom = 0
      ?sub = idSub 0
      ?env = ENil
      ?recurse = DontRecurse
  in quoteUnfold (eval term)

familyFunction :: ProviderDirection -> Family -> Either String Tm
familyFunction direction family = case family of
  FamilyConst _ -> Right identityFunction
  FamilyGlue equivalence -> Right (equivalenceFunction direction equivalence)
  FamilyVec elementFamily size
    | size < 0 -> Left "negative Vec length at cctt provider boundary"
    | otherwise -> do
        elementFunction <- familyFunction direction elementFamily
        Right (Lam N_ (mapVector size elementFunction (LocalVar 0)))
  FamilySigma firstFamily secondFamily -> do
    firstFunction <- familyFunction direction firstFamily
    secondFunction <- familyFunction direction secondFamily
    Right (Lam N_ (Pair N_
      (App firstFunction (Proj1 (LocalVar 0) N_))
      (App secondFunction (Proj2 (LocalVar 0) N_))))
  FamilyCompose first second -> do
    firstFunction <- familyFunction direction first
    secondFunction <- familyFunction direction second
    Right $ case direction of
      ProviderForward -> composeFunctions firstFunction secondFunction
      ProviderBackward -> composeFunctions secondFunction firstFunction
  FamilyPi _ _ -> Left "Pi transport is represented extensionally at application"

mapVector :: Int -> Tm -> Tm -> Tm
mapVector size function vector
  | size == 0 = U
  | otherwise = Pair N_
      (App function (Proj1 vector N_))
      (mapVector (size - 1) function (Proj2 vector N_))

equivalenceFunction :: ProviderDirection -> Equiv -> Tm
equivalenceFunction direction equivalence = case equivalence of
  EquivIdentity _ -> identityFunction
  EquivBoolNot -> boolNotFunction
  EquivIntSucc -> case direction of
    ProviderForward -> intSuccFunction
    ProviderBackward -> intPredFunction
  EquivCompose first second -> case direction of
    ProviderForward -> composeFunctions
      (equivalenceFunction ProviderForward first)
      (equivalenceFunction ProviderForward second)
    ProviderBackward -> composeFunctions
      (equivalenceFunction ProviderBackward second)
      (equivalenceFunction ProviderBackward first)
  EquivInverse inner -> equivalenceFunction (reverseDirection direction) inner

reverseDirection :: ProviderDirection -> ProviderDirection
reverseDirection direction = case direction of
  ProviderForward -> ProviderBackward
  ProviderBackward -> ProviderForward

composeFunctions :: Tm -> Tm -> Tm
composeFunctions first second = Lam N_ (App second (App first (LocalVar 0)))

identityFunction :: Tm
identityFunction = Lam N_ (LocalVar 0)

churchTrue :: Tm
churchTrue = Lam N_ (Lam N_ (LocalVar 1))

churchFalse :: Tm
churchFalse = Lam N_ (Lam N_ (LocalVar 0))

boolNotFunction :: Tm
boolNotFunction = Lam N_ (Lam N_ (Lam N_
  (App (App (LocalVar 2) (LocalVar 0)) (LocalVar 1))))

churchNat :: Integer -> Tm
churchNat value = Lam N_ (Lam N_ (applyMany value (LocalVar 1) (LocalVar 0)))

applyMany :: Integer -> Tm -> Tm -> Tm
applyMany count function argument
  | count <= 0 = argument
  | otherwise = App function (applyMany (count - 1) function argument)

natSuccFunction :: Tm
natSuccFunction = Lam N_ (Lam N_ (Lam N_
  (App (LocalVar 1)
    (App (App (LocalVar 2) (LocalVar 1)) (LocalVar 0)))))

natAddFunction :: Tm
natAddFunction = Lam N_ (Lam N_ (Lam N_ (Lam N_
  (App (App (LocalVar 3) (LocalVar 1))
    (App (App (LocalVar 2) (LocalVar 1)) (LocalVar 0))))))

intSuccFunction :: Tm
intSuccFunction = Lam N_ (Pair N_
  (App natSuccFunction (Proj1 (LocalVar 0) N_))
  (Proj2 (LocalVar 0) N_))

intPredFunction :: Tm
intPredFunction = Lam N_ (Pair N_
  (Proj1 (LocalVar 0) N_)
  (App natSuccFunction (Proj2 (LocalVar 0) N_)))

encode :: ProviderValue -> Tm
encode value = case value of
  ProviderBool bool -> if bool then churchTrue else churchFalse
  ProviderNat natural -> churchNat natural
  ProviderInt integer -> Pair N_
    (churchNat (max 0 integer))
    (churchNat (max 0 (-integer)))
  ProviderVec elements -> foldr (Pair N_) U (map encode elements)
  ProviderPair first second -> Pair N_ (encode first) (encode second)

decodeLike :: ProviderValue -> Tm -> Either String ProviderValue
decodeLike shape term = case shape of
  ProviderBool _ -> ProviderBool <$> decodeBool term
  ProviderNat _ -> ProviderNat <$> decodeNat term
  ProviderInt _ -> case term of
    Pair _ positive negative -> do
      positiveValue <- decodeNat positive
      negativeValue <- decodeNat negative
      pure (ProviderInt (positiveValue - negativeValue))
    _ -> Left (shapeError "Int" term)
  ProviderVec elements -> ProviderVec <$> decodeVector elements term
  ProviderPair first second -> case term of
    Pair _ firstTerm secondTerm ->
      ProviderPair <$> decodeLike first firstTerm <*> decodeLike second secondTerm
    _ -> Left (shapeError "Sigma" term)

decodeBool :: Tm -> Either String Bool
decodeBool term = case term of
  Lam _ (Lam _ (LocalVar 1)) -> Right True
  Lam _ (Lam _ (LocalVar 0)) -> Right False
  _ -> Left (shapeError "Bool" term)

decodeNat :: Tm -> Either String Integer
decodeNat term = case term of
  Lam _ (Lam _ body) -> countApplications body
  _ -> Left (shapeError "Nat" term)
  where
    countApplications current = case current of
      LocalVar 0 -> Right 0
      App (LocalVar 1) rest -> (1 +) <$> countApplications rest
      _ -> Left (shapeError "Nat body" current)

decodeVector :: [ProviderValue] -> Tm -> Either String [ProviderValue]
decodeVector shapes term = case (shapes, term) of
  ([], U) -> Right []
  (shape : rest, Pair _ element tailTerm) ->
    (:) <$> decodeLike shape element <*> decodeVector rest tailTerm
  _ -> Left (shapeError "Vec" term)

shapeError :: String -> Tm -> String
shapeError expected actual =
  "cctt normal form is not a " ++ expected ++ " encoding: " ++ show actual
