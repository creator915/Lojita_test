{-# OPTIONS --cubical #-}

module RuntimeTransp where

open import Agda.Builtin.Bool
open import Agda.Builtin.Cubical.Glue
open import Agda.Builtin.Cubical.Path
open import Agda.Builtin.Nat
open import Agda.Builtin.Sigma
open import Agda.Primitive.Cubical

-- The type on which transport acts is selected by ordinary runtime data.  If
-- b is neutral, Ty b is neutral too, so primTransp cannot inspect its head and
-- remains stuck.  Once b is supplied by the runner, the existing Cubical
-- reducer sees either Nat or Bool and computes the transport.
Ty : Bool -> Set
Ty false = Bool
Ty true  = Nat

runtimeTransp : (b : Bool) -> Ty b -> Ty b
runtimeTransp b x = primTransp (\ _ -> Ty b) i0 x

runtimeHComp : (b : Bool) -> Ty b -> Ty b
runtimeHComp b x =
  primHComp {A = Ty b} {φ = i0} (\ _ -> isOneEmpty) x

-- A small, self-contained univalence example.  The runtime selector chooses
-- between the identity equivalence and Boolean negation.  Transport along the
-- resulting Glue path therefore needs the selected equivalence at runtime.

pathRefl : ∀ {ℓ} {A : Set ℓ} {x : A} -> x ≡ x
pathRefl {x = x} = \ _ -> x

pathSym : ∀ {ℓ} {A : Set ℓ} {x y : A} -> x ≡ y -> y ≡ x
pathSym p i = p (primINeg i)

module _ {ℓ ℓ'} {A : Set ℓ} {x : A}
         (P : ∀ y -> x ≡ y -> Set ℓ') (d : P x (\ _ -> x)) where
  pathJ : (y : A) -> (p : x ≡ y) -> P y p
  pathJ _ p =
    primTransp
      (\ i -> P (p i) (\ j -> p (primIMin i j)))
      i0 d

idIsEquiv : ∀ {ℓ} (A : Set ℓ) -> isEquiv (\ (x : A) -> x)
equiv-proof (idIsEquiv A) y =
  ((y , \ _ -> y) , \ z i -> z .snd (primINeg i)
  , \ j -> z .snd (primIMax (primINeg i) j))

idEquiv : ∀ {ℓ} (A : Set ℓ) -> A ≃ A
idEquiv A = (\ x -> x) , idIsEquiv A

ua : ∀ {ℓ} {A B : Set ℓ} -> A ≃ B -> A ≡ B
ua {A = A} {B = B} e i =
  primGlue B
    (\ { (i = i0) -> A ; (i = i1) -> B })
    (\ { (i = i0) -> e ; (i = i1) -> idEquiv B })

boolNot : Bool -> Bool
boolNot true  = false
boolNot false = true

notnot : ∀ y -> y ≡ boolNot (boolNot y)
notnot true  = pathRefl
notnot false = pathRefl

nothelp :
  ∀ y (fiberPoint : Σ Bool (\ x -> boolNot x ≡ y)) ->
  (boolNot y , pathSym (notnot y)) ≡ fiberPoint
nothelp y (true , eq) =
  pathJ
    (\ y' eq' -> (boolNot y' , pathSym (notnot y')) ≡ (true , eq'))
    pathRefl _ eq
nothelp y (false , eq) =
  pathJ
    (\ y' eq' -> (boolNot y' , pathSym (notnot y')) ≡ (false , eq'))
    pathRefl _ eq

notEquiv : Bool ≃ Bool
notEquiv =
  boolNot , (\ { .equiv-proof y ->
    (boolNot y , pathSym (notnot y)) , nothelp y })

selectedEquiv : Bool -> Bool ≃ Bool
selectedEquiv false = idEquiv Bool
selectedEquiv true  = notEquiv

-- A top-level eta record reproducer.  The primitive reducer intentionally
-- waits for projections before unfolding record transport; the runtime
-- backend must therefore perform type-directed eta-long read-back.
runtimeSigmaTransp : Σ Bool (\ _ -> Nat)
runtimeSigmaTransp =
  primTransp
    (\ i -> Σ (ua notEquiv i) (\ _ -> Nat))
    i0 (true , 3)

-- A closed higher-order value used by the two-process packet test.
runtimeFunctionProducer : Bool -> Bool
runtimeFunctionProducer =
  primTransp
    (\ i -> ua notEquiv i -> ua notEquiv i)
    i0 (\ b -> b)

runtimeFunctionConsumer : (Bool -> Bool) -> Bool
runtimeFunctionConsumer f = f true

runtimeGlueTransp : Bool -> Bool -> Bool
runtimeGlueTransp selector x =
  primTransp (\ i -> ua (selectedEquiv selector) i) i0 x

natAcceptance : Nat
natAcceptance = runtimeTransp true 42

boolAcceptance : Bool
boolAcceptance = runtimeTransp false true

hcompAcceptance : Nat
hcompAcceptance = runtimeHComp true 17

glueAcceptance : Bool
glueAcceptance = runtimeGlueTransp true true

sigmaAcceptance : Σ Bool (\ _ -> Nat)
sigmaAcceptance = runtimeSigmaTransp

functionAcceptance : Bool
functionAcceptance = runtimeFunctionConsumer runtimeFunctionProducer
