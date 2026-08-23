{-# OPTIONS --cubical --safe #-}

module NbeAdapterSpikeCubicalUnsupported where

open import Agda.Primitive.Cubical using (I; i0)
open import Agda.Builtin.Cubical.HCompU using (primFaceForall)

main : I
main = primFaceForall (\ _ → i0)
