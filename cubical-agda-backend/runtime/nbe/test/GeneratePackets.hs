module Main (main) where

import Cubical.Runtime.Nbe
import System.Environment (getArgs)
import System.Exit (die)

contextIdentity :: String
contextIdentity = "transport-fixtures-v1:b150186d2544e7ef"

packet :: Term -> Ty -> [Definition] -> Packet
packet term ty definitions = Packet
  { packetAbi = abiVersion
  , packetProvider = providerIdentity
  , packetContext = contextIdentity
  , packetRequest = Request term ty definitions
  }

boolVector :: [Bool] -> Term
boolVector values = VecLit TyBool (map BoolLit values)

fixtures :: [(FilePath, Packet)]
fixtures =
  [ ("t11.packet", packet
      (Transp (TypePath (FamilyVec (FamilyGlue EquivBoolNot) 2)) (boolVector [True, False]))
      (TyVec TyBool 2) [])
  , ("t11b.packet", packet
      (Transp (TypePath (FamilyConst (TyVec TyBool 2))) (boolVector [True, False]))
      (TyVec TyBool 2) [])
  , ("t16a.packet", packet
      (App
        (Transp
          (TypePath (FamilyPi (FamilyGlue EquivBoolNot) (FamilyGlue EquivBoolNot)))
          (Def "checked.identity-bool"))
        (BoolLit True))
      TyBool
      [Definition "checked.identity-bool" (TyPi TyBool TyBool) (Lam TyBool (Var 0))])
  , ("t16b.packet", packet
      (Transp
        (Concat (TypePath (FamilyGlue EquivIntSucc)) (TypePath (FamilyGlue EquivIntSucc)))
        (IntLit 0))
      TyInt [])
  , ("t16c.packet", packet (Winding (Concat Loop Loop)) TyInt [])
  , ("glue.packet", packet
      (Unglue EquivBoolNot (Glue EquivBoolNot (BoolLit True))) TyBool [])
  , ("record.packet", packet
      (Transp
        (TypePath (FamilySigma (FamilyGlue EquivBoolNot) (FamilyConst TyNat)))
        (Pair (BoolLit True) (NatLit 3)))
      (TySigma TyBool TyNat) [])
  , ("hcomp-one.packet", packet (HComp TyBool FaceOne (BoolLit True) (BoolLit False)) TyBool [])
  , ("hcomp-zero.packet", packet (HComp TyBool FaceZero (BoolLit True) (BoolLit False)) TyBool [])
  , ("lambda.packet", packet (Lam TyBool (Not (Var 0))) (TyPi TyBool TyBool) [])
  , ("cache.packet", packet
      (Pair (Def "checked.true") (Def "checked.true"))
      (TySigma TyBool TyBool)
      [Definition "checked.true" TyBool (BoolLit True)])
  , ("cycle.packet", packet
      (Def "checked.cycle") TyBool
      [Definition "checked.cycle" TyBool (Def "checked.cycle")])
  , ("wrong-type.packet", packet (BoolLit True) TyNat [])
  ]

main :: IO ()
main = do
  arguments <- getArgs
  case arguments of
    [outputDirectory] -> mapM_ (writeFixture outputDirectory) fixtures
    _ -> die "usage: generate-runtime-nbe-packets OUTPUT-DIRECTORY"

writeFixture :: FilePath -> (FilePath, Packet) -> IO ()
writeFixture outputDirectory (name, value) =
  writeFile (outputDirectory ++ "/" ++ name) (encodePacket value)
