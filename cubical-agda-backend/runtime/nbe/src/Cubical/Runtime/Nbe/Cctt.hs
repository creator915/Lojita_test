{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE PatternSynonyms #-}

-- | Input-driven adapter to the linked cctt normalization engine.
--
-- Values in the Agda wire fragment are encoded as closed cctt terms.  The
-- requested transport, composition and Glue elimination are represented by
-- cctt's own 'Coe', 'HCom', 'GlueTy', 'Glue', and 'Unglue' syntax.  Those terms
-- are evaluated by 'Core.eval', quoted by 'Quotation.quoteUnfold', and decoded
-- back to the shape of the actual input.  Church encodings are only the closed
-- data representation at this bounded ABI; transport and composition are not
-- implemented by applying a separately hand-written host operation.
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
  , Sys (..)
  , SysHCom (..)
  , Tm (..)
  )
import Cubical (Cof (CEq), I, pattern I0, pattern I1, pattern IVar, emptyNCof, idSub)
import Cubical.Runtime.Nbe.Wire (Equiv (..), Face (..), Family (..), Ty (..))
import qualified Cubical.Runtime.Nbe.Wire as Wire
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
  case family of
    FamilyCompose first second -> case direction of
      ProviderForward ->
        providerTransport direction first input >>= providerTransport direction second
      ProviderBackward ->
        providerTransport direction second input >>= providerTransport direction first
    _ -> do
      transportTerm <- encodeTransport direction family (encode input)
      decodeLike input (normalize transportTerm)

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
providerSelect face system base = do
  valueType <- commonProviderType system base
  let cofibration = case face of
        FaceOne -> CEq I0 I0
        FaceZero -> CEq I0 I1
      inputShape = case face of
        FaceOne -> system
        FaceZero -> base
      term = HCom I0 I1 valueType
        (SHCons cofibration N_ (encode system) SHEmpty)
        (encode base)
  decodeLike inputShape (normalize term)

{-# NOINLINE providerPreserve #-}
providerPreserve :: ProviderValue -> Either String ProviderValue
providerPreserve input =
  decodeLike input (normalize
    (Unglue (Glue (encode input) SEmpty SEmpty) SEmpty))

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
  in eraseEmptyGlue (quoteUnfold (eval term))

-- cctt deliberately quotes a Glue type with an empty neutral system instead
-- of eta-contracting it to its base.  At this ABI boundary the empty system
-- carries no face data, so readback observes the base.  This is readback of a
-- cctt-produced normal form, not an implementation of Coe/HCom itself.
eraseEmptyGlue :: Tm -> Tm
eraseEmptyGlue term = case term of
  GlueTy base SEmpty -> eraseEmptyGlue base
  Glue base SEmpty SEmpty -> eraseEmptyGlue base
  Unglue glued SEmpty -> eraseEmptyGlue glued
  Lam name body -> Lam name (eraseEmptyGlue body)
  App function argument -> App (eraseEmptyGlue function) (eraseEmptyGlue argument)
  Pair name first second -> Pair name (eraseEmptyGlue first) (eraseEmptyGlue second)
  Proj1 pair name -> Proj1 (eraseEmptyGlue pair) name
  Proj2 pair name -> Proj2 (eraseEmptyGlue pair) name
  Coe left right name ty value ->
    Coe left right name (eraseEmptyGlue ty) (eraseEmptyGlue value)
  HCom left right ty system base ->
    HCom left right (eraseEmptyGlue ty) system (eraseEmptyGlue base)
  _ -> term

encodeTransport :: ProviderDirection -> Family -> Tm -> Either String Tm
encodeTransport direction family input = case family of
  FamilyCompose {} -> Left "composed paths are normalized one cctt Coe at a time"
  FamilyPi {} -> Left "Pi transport is represented extensionally at application"
  _ -> do
    familyType <- encodeFamilyType direction family (IVar 0)
    let coerced = Coe I0 I1 N_ familyType input
    pure (eliminateGlue family coerced)

-- Coe over Sigma/Vec returns the same outer constructor while each varying
-- Glue component remains a Glue value at the empty endpoint.  Eliminate only
-- those components, preserving cctt's Coe-produced structure.
eliminateGlue :: Family -> Tm -> Tm
eliminateGlue family term = case family of
  FamilyGlue {} -> Unglue term SEmpty
  FamilyVec element size -> eliminateVectorGlue element size term
  FamilySigma first second -> Pair N_
    (eliminateGlue first (Proj1 term N_))
    (eliminateGlue second (Proj2 term N_))
  FamilyConst {} -> term
  FamilyCompose {} -> term
  FamilyPi {} -> term

eliminateVectorGlue :: Family -> Int -> Tm -> Tm
eliminateVectorGlue _ size _ | size <= 0 = U
eliminateVectorGlue element size term = Pair N_
  (eliminateGlue element (Proj1 term N_))
  (eliminateVectorGlue element (size - 1) (Proj2 term N_))

encodeFamilyType :: ProviderDirection -> Family -> I -> Either String Tm
encodeFamilyType direction family interval = case family of
  FamilyConst ty -> encodeTy ty
  FamilyGlue equivalence -> do
    valueType <- equivalenceType equivalence
    Right (gluePathType interval valueType
      (equivalenceFunction direction equivalence)
      (equivalenceFunction (reverseDirection direction) equivalence))
  FamilyVec elementFamily size
    | size < 0 -> Left "negative Vec length at cctt provider boundary"
    | otherwise -> vectorType size <$> encodeFamilyType direction elementFamily interval
  FamilySigma firstFamily secondFamily ->
    Sg N_ <$> encodeFamilyType direction firstFamily interval
      <*> encodeFamilyType direction secondFamily interval
  FamilyCompose {} -> Left "composed paths are transported one cctt Coe at a time"
  FamilyPi domainFamily codomainFamily ->
    Pi N_ <$> encodeFamilyType (reverseDirection direction) domainFamily interval
      <*> encodeFamilyType direction codomainFamily interval

-- | A path from the fiber type on @i = 0@ to the base type on @i = 1@.
-- The equivalence package is consumed by cctt's native Glue coercion code.
gluePathType :: I -> Tm -> Tm -> Tm -> Tm
gluePathType interval valueType forward backward =
  GlueTy valueType
    (SCons (CEq interval I0)
      (Pair N_ valueType (equivalencePackage forward backward))
      SEmpty)

equivalencePackage :: Tm -> Tm -> Tm
equivalencePackage forward backward =
  Pair N_ forward
    (Pair N_ backward
      (Pair N_ (inverseWitness forward backward)
        (Pair N_ (inverseWitness backward forward)
          (Pack N_ (coherenceWitness forward)))))

inverseWitness :: Tm -> Tm -> Tm
inverseWitness forward backward =
  Lam N_ (PLam
    (App backward (App forward (LocalVar 0)))
    (LocalVar 0)
    N_
    (LocalVar 0))

coherenceWitness :: Tm -> Tm
coherenceWitness forward =
  Lam N_ (let result = App forward (LocalVar 0)
          in PLam (Refl result) (Refl result) N_ (Refl result))

equivalenceType :: Equiv -> Either String Tm
equivalenceType equivalence = case equivalence of
  EquivIdentity ty -> encodeTy ty
  EquivBoolNot -> Right churchBoolType
  EquivIntSucc -> Right churchIntType
  EquivCompose first _ -> equivalenceType first
  EquivInverse inner -> equivalenceType inner

encodeTy :: Ty -> Either String Tm
encodeTy ty = case ty of
  TyUniverse -> Right U
  TyBool -> Right churchBoolType
  TyNat -> Right churchNatType
  TyInt -> Right churchIntType
  TyS1 -> Right churchIntType
  TyVec element size
    | size < 0 -> Left "negative Vec length at cctt type boundary"
    | otherwise -> vectorType size <$> encodeTy element
  TyPi domain codomain -> Pi N_ <$> encodeTy domain <*> encodeTy codomain
  TySigma first second -> Sg N_ <$> encodeTy first <*> encodeTy second
  TyPath pathTy left right ->
    Path N_ <$> encodeTy pathTy <*> encodeTerm left <*> encodeTerm right

encodeTerm :: Wire.Term -> Either String Tm
encodeTerm term = case term of
  Wire.BoolLit value -> Right (encode (ProviderBool value))
  Wire.NatLit value -> Right (encode (ProviderNat value))
  Wire.IntLit value -> Right (encode (ProviderInt value))
  Wire.VecLit _ values -> encode . ProviderVec <$> mapM wireLiteral values
  Wire.Pair first second -> do
    firstValue <- wireLiteral first
    secondValue <- wireLiteral second
    Right (encode (ProviderPair firstValue secondValue))
  _ -> Left "non-literal path endpoint is outside the bounded cctt type boundary"

wireLiteral :: Wire.Term -> Either String ProviderValue
wireLiteral term = case term of
  Wire.BoolLit value -> Right (ProviderBool value)
  Wire.NatLit value -> Right (ProviderNat value)
  Wire.IntLit value -> Right (ProviderInt value)
  Wire.VecLit _ values -> ProviderVec <$> mapM wireLiteral values
  Wire.Pair first second -> ProviderPair <$> wireLiteral first <*> wireLiteral second
  _ -> Left "non-literal value is outside the bounded cctt type boundary"

vectorType :: Int -> Tm -> Tm
vectorType size elementType
  | size <= 0 = U
  | otherwise = Sg N_ elementType (vectorType (size - 1) elementType)

commonProviderType :: ProviderValue -> ProviderValue -> Either String Tm
commonProviderType left right = do
  leftType <- providerType left
  _ <- providerType right
  if providerShape left == providerShape right
    then Right leftType
    else Left ("HCom system/base shape mismatch: " ++ providerShape left ++ " /= " ++ providerShape right)

providerType :: ProviderValue -> Either String Tm
providerType value = case value of
  ProviderBool _ -> Right churchBoolType
  ProviderNat _ -> Right churchNatType
  ProviderInt _ -> Right churchIntType
  ProviderVec values -> case values of
    [] -> Right U
    first : rest
      | all ((== providerShape first) . providerShape) rest ->
          vectorType (length values) <$> providerType first
      | otherwise -> Left "heterogeneous ProviderVec cannot form a cctt HCom type"
  ProviderPair first second -> Sg N_ <$> providerType first <*> providerType second

providerShape :: ProviderValue -> String
providerShape value = case value of
  ProviderBool _ -> "Bool"
  ProviderNat _ -> "Nat"
  ProviderInt _ -> "Int"
  ProviderVec values -> "Vec[" ++ show (length values) ++ "](" ++
    (case values of [] -> "empty"; first : _ -> providerShape first) ++ ")"
  ProviderPair first second -> "Sigma(" ++ providerShape first ++ "," ++ providerShape second ++ ")"

churchBoolType :: Tm
churchBoolType = Pi N_ U (Pi N_ U U)

churchNatType :: Tm
churchNatType = Pi N_ (Pi N_ U U) (Pi N_ U U)

churchIntType :: Tm
churchIntType = churchNatType

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
intSuccFunction = Lam N_ (let
  input = LocalVar 0
  isZero = App natIsZeroFunction input
  isEven = App natEvenFunction input
  plusTwo = App natSuccFunction (App natSuccFunction input)
  minusTwo = App natPredFunction (App natPredFunction input)
  in churchIf isZero (churchNat 2) (churchIf isEven plusTwo minusTwo))

intPredFunction :: Tm
intPredFunction = Lam N_ (let
  input = LocalVar 0
  isZero = App natIsZeroFunction input
  isEven = App natEvenFunction input
  plusTwo = App natSuccFunction (App natSuccFunction input)
  minusTwo = App natPredFunction (App natPredFunction input)
  in churchIf isZero (churchNat 1) (churchIf isEven minusTwo plusTwo))

churchIf :: Tm -> Tm -> Tm -> Tm
churchIf condition ifTrue ifFalse = App (App condition ifTrue) ifFalse

natIsZeroFunction :: Tm
natIsZeroFunction = Lam N_
  (App (App (LocalVar 0) (Lam N_ churchFalse)) churchTrue)

natEvenFunction :: Tm
natEvenFunction = Lam N_
  (App (App (LocalVar 0) boolNotFunction) churchTrue)

-- Standard Church predecessor.  Keeping predecessor inside the cctt term
-- makes zig-zag integer successor/predecessor inverse actions on the canonical
-- closed numeral representation used at this boundary.
natPredFunction :: Tm
natPredFunction = Lam N_ (Lam N_ (Lam N_ (let
  stepFunction = Lam N_ (Lam N_
    (App (LocalVar 0) (App (LocalVar 1) (LocalVar 3))))
  zeroFunction = Lam N_ (LocalVar 1)
  identity = Lam N_ (LocalVar 0)
  in App (App (App (LocalVar 2) stepFunction) zeroFunction) identity)))

encode :: ProviderValue -> Tm
encode value = case value of
  ProviderBool bool -> if bool then churchTrue else churchFalse
  ProviderNat natural -> churchNat natural
  ProviderInt integer -> churchNat (zigZagEncode integer)
  ProviderVec elements -> foldr (Pair N_) U (map encode elements)
  ProviderPair first second -> Pair N_ (encode first) (encode second)

decodeLike :: ProviderValue -> Tm -> Either String ProviderValue
decodeLike shape term = case shape of
  ProviderBool _ -> ProviderBool <$> decodeBool term
  ProviderNat _ -> ProviderNat <$> decodeNat term
  ProviderInt _ -> ProviderInt . zigZagDecode <$> decodeNat term
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

zigZagEncode :: Integer -> Integer
zigZagEncode integer
  | integer >= 0 = 2 * integer
  | otherwise = (-2 * integer) - 1

zigZagDecode :: Integer -> Integer
zigZagDecode natural
  | even natural = natural `div` 2
  | otherwise = -((natural + 1) `div` 2)

shapeError :: String -> Tm -> String
shapeError expected actual =
  "cctt normal form is not a " ++ expected ++ " encoding: " ++ show actual
