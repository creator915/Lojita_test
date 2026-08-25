{-# OPTIONS --cubical --safe #-}

module RuntimeNbeCubical where

open import Agda.Builtin.Bool
open import Agda.Primitive.Cubical

transpBool : Bool
transpBool = primTransp (λ _ → Bool) i0 true

transpFaceOne : Bool
transpFaceOne = primTransp (λ _ → Bool) i1 true

hcompBool : Bool
hcompBool = primHComp {A = Bool} {φ = i1} (λ _ _ → true) true
