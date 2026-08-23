module RuntimeNbeBridge where

open import Agda.Builtin.Bool
open import Agda.Builtin.Nat

bridgeTrue : Bool
bridgeTrue = true

bridgeSeven : Nat
bridgeSeven = 7

bridgeIdentity : Bool → Bool
bridgeIdentity value = value

bridgeNot : Bool → Bool
bridgeNot true = false
bridgeNot false = true
