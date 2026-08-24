module Main (main) where

import Cubical.Runtime.Nbe.Cctt
import Cubical.Runtime.Nbe.Wire
import Control.Monad (unless)
import System.Exit (die)

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  unless (actual == expected)
    (die (label ++ ": expected " ++ show expected ++ ", got " ++ show actual))

expectRight :: Show e => String -> Either e a -> IO a
expectRight label result = case result of
  Left failure -> die (label ++ ": provider rejected actual input: " ++ show failure)
  Right value -> pure value

main :: IO ()
main = do
  let boolVector = ProviderVec [ProviderBool True, ProviderBool False]
      reversedBoolVector = ProviderVec [ProviderBool False, ProviderBool True]
      vectorFamily = FamilyVec (FamilyGlue EquivBoolNot) 2
      constantVector = FamilyConst (TyVec TyBool 2)
      sigmaFamily = FamilySigma (FamilyGlue EquivBoolNot) (FamilyConst TyNat)

  first <- expectRight "t11 true/false" (providerTransport ProviderForward vectorFamily boolVector)
  assertEqual "t11 true/false" reversedBoolVector first

  second <- expectRight "t11 false/true" (providerTransport ProviderForward vectorFamily reversedBoolVector)
  assertEqual "t11 false/true" boolVector second
  unless (first /= second)
    (die "cctt transport is not input-driven: distinct vectors produced the same result")

  constant <- expectRight "t11b constant" (providerTransport ProviderForward constantVector boolVector)
  assertEqual "t11b constant" boolVector constant

  sigma <- expectRight "Sigma" (providerTransport ProviderForward sigmaFamily
    (ProviderPair (ProviderBool True) (ProviderNat 3)))
  assertEqual "Sigma" (ProviderPair (ProviderBool False) (ProviderNat 3)) sigma

  integer <- expectRight "composed Int transport" (providerTransport ProviderForward
    (FamilyCompose (FamilyGlue EquivIntSucc) (FamilyGlue EquivIntSucc))
    (ProviderInt (-2)))
  assertEqual "composed Int transport" (ProviderInt 0) integer

  integerBack <- expectRight "inverse Int transport" (providerTransport ProviderBackward
    (FamilyGlue EquivIntSucc) (ProviderInt 4))
  assertEqual "inverse Int transport" (ProviderInt 3) integerBack

  selectedOne <- expectRight "hcomp face one" (providerSelect FaceOne
    (ProviderBool True) (ProviderBool False))
  assertEqual "hcomp face one" (ProviderBool True) selectedOne

  selectedZero <- expectRight "hcomp face zero" (providerSelect FaceZero
    (ProviderBool True) (ProviderBool False))
  assertEqual "hcomp face zero" (ProviderBool False) selectedZero

  preserved <- expectRight "Glue payload" (providerPreserve
    (ProviderPair (ProviderBool False) (ProviderNat 8)))
  assertEqual "Glue payload" (ProviderPair (ProviderBool False) (ProviderNat 8)) preserved

  winding <- expectRight "path winding" (providerAddInt (-3) 5)
  assertEqual "path winding" 2 winding

  case providerTransport ProviderForward (FamilyVec (FamilyGlue EquivBoolNot) 3) boolVector of
    Left _ -> pure ()
    Right value -> die ("wrong Vec spine was accepted: " ++ show value)

  putStrLn "CcttProvider PASS (11 input-driven cases)"
