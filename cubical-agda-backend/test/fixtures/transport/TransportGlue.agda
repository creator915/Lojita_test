{-# OPTIONS --cubical --safe #-}

-- Low-memory, independent reproduction of test/fixtures/TransportTests.agda t03/t04/t08.
-- Source SHA-256: 8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b

module TransportGlue where

open import Cubical.Foundations.Prelude
open import Cubical.Foundations.Isomorphism
open import Cubical.Foundations.Equiv
open import Cubical.Foundations.Univalence

open import Cubical.Data.Bool using (Bool; true; false; not)
open import Cubical.Data.List using (List; _∷_; [])

private
  notnot : ∀ b → not (not b) ≡ b
  notnot true  = refl
  notnot false = refl

  notEq : Bool ≃ Bool
  notEq = isoToEquiv (iso not not notnot notnot)

  notPath : Bool ≡ Bool
  notPath = ua notEq

  ConstantType : ∀ {A : Type} → A → Type
  ConstantType _ = Bool

  SameType : (A : Type) → A → Type
  SameType A _ = A

  ParameterizedConstantType : ∀ {A : Type} → Bool → A → Type
  ParameterizedConstantType _ _ = List Bool

  data Tagged {A : Type} (tag : A) : Type where
    tagged : Tagged tag

  data PayloadTagged {A : Type} (tag : A) : Type where
    payloadTagged : Bool → PayloadTagged tag

  data ClosedPayload : Type where
    closedPayload : ClosedPayload

  data NestedPayloadTagged {A : Type} (tag : A) : Type where
    nestedPayloadTagged : ClosedPayload → NestedPayloadTagged tag

  data DependentPayloadTagged (A : Type) (tag : A) : Type where
    dependentPayloadTagged : A → DependentPayloadTagged A tag

  data StableBox (A : Type) : Type where
    box : Bool → StableBox A

  record StableRecord (A : Type) : Type where
    constructor stableRecord
    field
      stableFlag : Bool

  open StableRecord

  record StableFunctionRecord : Type where
    constructor stableFunctionRecord
    field
      stableFunction : Bool → Bool

  open StableFunctionRecord

  StableBoxType : ∀ {A : Type} → A → Type
  StableBoxType _ = StableBox Bool

  StableRecordType : ∀ {A : Type} → A → Type
  StableRecordType _ = StableRecord Bool

  DependentFunctionType : ∀ {A : Type} → A → Type
  DependentFunctionType flag = Tagged flag → Bool

  PayloadDependentFunctionType : ∀ {A : Type} → A → Type
  PayloadDependentFunctionType flag = PayloadTagged flag → Bool

  NestedPayloadDependentFunctionType : ∀ {A : Type} → A → Type
  NestedPayloadDependentFunctionType flag = NestedPayloadTagged flag → Bool

  DependentPayloadFunctionType : (A : Type) → A → Type
  DependentPayloadFunctionType A flag = DependentPayloadTagged A flag → Bool

  consumeTagged : ∀ {A : Type} {tag : A} → Tagged tag → Bool
  consumeTagged tagged = true

  consumePayloadTagged :
    ∀ {A : Type} {tag : A} → PayloadTagged tag → Bool
  consumePayloadTagged (payloadTagged flag) = flag

  bothFalse : Bool → Bool → Bool
  bothFalse false false = true
  bothFalse false true  = false
  bothFalse true  _     = false

  observeSigmaSpineFields :
    (b : Bool) →
    (Σ[ x ∈ Bool ] Σ[ y ∈ Bool ] Σ[ z ∈ Bool ] b ≡ x) → Bool
  observeSigmaSpineFields _ value =
    bothFalse (fst (snd value)) (fst (snd (snd value)))

  observeNestedField :
    (b : Bool) → (Σ[ x ∈ Bool ] Σ[ y ∈ Bool ] b ≡ x) → Bool
  observeNestedField _ value = not (fst (snd value))

  observeStableNestedField :
    (b : Bool) → (Σ[ x ∈ Bool ] Σ[ y ∈ Bool ] b ≡ x) → Bool
  observeStableNestedField _ value = fst (snd value)

  headOrFalse : List Bool → Bool
  headOrFalse [] = false
  headOrFalse (head ∷ _) = head

  observeParameterizedStableNestedField :
    (b : Bool) →
    (Σ[ x ∈ Bool ] Σ[ y ∈ List Bool ] b ≡ x) → Bool
  observeParameterizedStableNestedField _ value =
    headOrFalse (fst (snd value))

  boxFlag : StableBox Bool → Bool
  boxFlag (box flag) = flag

  bothTrue : Bool → Bool → Bool
  bothTrue true true = true
  bothTrue _ _ = false

  observeStableStructureFields :
    (b : Bool) →
    (Σ[ x ∈ Bool ]
     Σ[ y ∈ StableBox Bool ]
     Σ[ z ∈ StableRecord Bool ] b ≡ x) → Bool
  observeStableStructureFields _ value =
    bothTrue
      (boxFlag (fst (snd value)))
      (stableFlag (fst (snd (snd value))))

  observeStableFunctionField :
    (b : Bool) →
    (Σ[ x ∈ Bool ] Σ[ y ∈ StableFunctionRecord ] b ≡ x) → Bool
  observeStableFunctionField _ value =
    stableFunction (fst (snd value)) true

  observeDirectStableFunctionField :
    (b : Bool) →
    (Σ[ x ∈ Bool ] Σ[ f ∈ (Bool → Bool) ] b ≡ x) → Bool
  observeDirectStableFunctionField _ value =
    fst (snd value) true

  observeOuterIndexedFunctionField :
    (b : Bool) →
    (Σ[ x ∈ Bool ] Σ[ f ∈ DependentFunctionType x ] b ≡ x) → Bool
  observeOuterIndexedFunctionField _ value =
    fst (snd value) tagged

  observePayloadIndexedFunctionField :
    (b : Bool) →
    (Σ[ x ∈ Bool ]
     Σ[ f ∈ PayloadDependentFunctionType x ] b ≡ x) → Bool
  observePayloadIndexedFunctionField _ value =
    fst (snd value) (payloadTagged true)

  observeNestedPayloadIndexedFunctionField :
    (b : Bool) →
    (Σ[ x ∈ Bool ]
     Σ[ f ∈ NestedPayloadDependentFunctionType x ] b ≡ x) → Bool
  observeNestedPayloadIndexedFunctionField _ value =
    fst (snd value) (nestedPayloadTagged closedPayload)

  observeDependentPayloadIndexedFunctionField :
    (b : Bool) →
    (Σ[ x ∈ Bool ]
     Σ[ f ∈ DependentPayloadFunctionType Bool x ] b ≡ x) → Bool
  observeDependentPayloadIndexedFunctionField _ value =
    fst (snd value) (dependentPayloadTagged true)

t03 : Bool
t03 = transport notPath true

e03 : Bool
e03 = false

_ : t03 ≡ e03
_ = refl

t04 : Bool
t04 = transport (notPath ∙ notPath) true

e04 : Bool
e04 = true

_ : t04 ≡ e04
_ = refl

t08 : Bool
t08 = (transport (λ i → notPath i → Bool) (λ b → b)) true

e08 : Bool
e08 = false

_ : t08 ≡ e08
_ = refl

-- Fail-closed control for the narrow double-composition rule.  Its left
-- boundary is another non-trivial ua path rather than refl, so the adapter
-- must not classify it as homogeneous single-path composition.
nonCanonicalDoubleComp : Bool
nonCanonicalDoubleComp =
  transport (notPath ∙∙ notPath ∙∙ notPath) true

-- Local positive extension beyond the original t03/t04/t08 projection.  Both
-- sides of the non-dependent function type follow the same canonical ua path.
-- Correct function transport is contravariant in the domain and covariant in
-- the codomain, so the transported identity remains the identity.
varyingCodomainPi : Bool
varyingCodomainPi =
  (transport (λ i → notPath i → notPath i) (λ b → b)) true

varyingCodomainPiExpected : Bool
varyingCodomainPiExpected = true

_ : varyingCodomainPi ≡ varyingCodomainPiExpected
_ = refl

-- The codomain mentions the function argument syntactically, but its checked
-- definition erases that argument and evaluates to the same closed Bool type
-- at every interval observation.
semanticConstantCodomainPi : Bool
semanticConstantCodomainPi =
  (transport (λ i → (b : notPath i) → ConstantType b) (λ b → b)) true

semanticConstantCodomainPiExpected : Bool
semanticConstantCodomainPiExpected = false

_ : semanticConstantCodomainPi ≡ semanticConstantCodomainPiExpected
_ = refl

-- Restricted genuinely dependent positive: transport preserves the canonical
-- reflexive inhabitant of the pointwise self-path family.  Applying the path
-- at an endpoint keeps the backend observation ground.
dependentSelfPathPi : Bool
dependentSelfPathPi =
  ((transport (λ i → (b : notPath i) → b ≡ b) (λ b → refl)) true) i0

dependentSelfPathPiExpected : Bool
dependentSelfPathPiExpected = true

_ : dependentSelfPathPi ≡ dependentSelfPathPiExpected
_ = refl

-- Restricted dependent singleton positive: the source function returns the
-- canonical inhabitant (b , refl), so transport may rebuild (target , refl).
-- Projecting fst keeps the observation inside the currently supported slice.
dependentSingletonPi : Bool
dependentSingletonPi =
  fst
    ((transport
      (λ i → (b : notPath i) → Σ[ x ∈ notPath i ] b ≡ x)
      (λ b → b , refl))
     true)

dependentSingletonPiExpected : Bool
dependentSingletonPiExpected = true

_ : dependentSingletonPi ≡ dependentSingletonPiExpected
_ = refl

-- The symmetric endpoint orientation has its own guarded classifier and
-- telemetry, while retaining the same canonical (b , refl) value condition.
reversedDependentSingletonPi : Bool
reversedDependentSingletonPi =
  fst
    ((transport
      (λ i → (b : notPath i) → Σ[ x ∈ notPath i ] x ≡ b)
      (λ b → b , refl))
     true)

reversedDependentSingletonPiExpected : Bool
reversedDependentSingletonPiExpected = true

_ : reversedDependentSingletonPi ≡ reversedDependentSingletonPiExpected
_ = refl

-- One exact nested Sigma layer is admitted when both points and the final
-- reflexive proof are canonical.
nestedDependentSingletonPi : Bool
nestedDependentSingletonPi =
  fst
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ] Σ[ y ∈ notPath i ] b ≡ x)
      (λ b → b , (b , refl)))
     true)

nestedDependentSingletonPiExpected : Bool
nestedDependentSingletonPiExpected = true

_ : nestedDependentSingletonPi ≡ nestedDependentSingletonPiExpected
_ = refl

-- The reversed final path uses the same nested structure under an explicit
-- endpoint direction.
reversedNestedDependentSingletonPi : Bool
reversedNestedDependentSingletonPi =
  fst
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ] Σ[ y ∈ notPath i ] x ≡ b)
      (λ b → b , (b , refl)))
     true)

reversedNestedDependentSingletonPiExpected : Bool
reversedNestedDependentSingletonPiExpected = true

_ : reversedNestedDependentSingletonPi ≡
    reversedNestedDependentSingletonPiExpected
_ = refl

-- The same guarded shape is rebuilt recursively through the bounded
-- three-Sigma spine instead of a third handwritten transport branch.
dependentSigmaSpinePi : Bool
dependentSigmaSpinePi =
  fst
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ y ∈ notPath i ]
        Σ[ z ∈ notPath i ] b ≡ x)
      (λ b → b , (b , (b , refl))))
     true)

dependentSigmaSpinePiExpected : Bool
dependentSigmaSpinePiExpected = true

_ : dependentSigmaSpinePi ≡ dependentSigmaSpinePiExpected
_ = refl

-- The bounded spine keeps the final PathP direction explicit at depth three.
reversedDependentSigmaSpinePi : Bool
reversedDependentSigmaSpinePi =
  fst
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ y ∈ notPath i ]
        Σ[ z ∈ notPath i ] x ≡ b)
      (λ b → b , (b , (b , refl))))
     true)

reversedDependentSigmaSpinePiExpected : Bool
reversedDependentSigmaSpinePiExpected = true

_ : reversedDependentSigmaSpinePi ≡ reversedDependentSigmaSpinePiExpected
_ = refl

-- Auxiliary points are independent of the final PathP.  They are transported
-- fieldwise through the checked canonical domain path, not copied or replaced
-- with the target binder.  At the source b=false, both fields are true; after
-- the canonical `not` forward they must both be false.
varyingSigmaSpineFieldsPi : Bool
varyingSigmaSpineFieldsPi =
  observeSigmaSpineFields true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ y ∈ notPath i ]
        Σ[ z ∈ notPath i ] b ≡ x)
      (λ b → b , (not b , (not b , refl))))
     true)

varyingSigmaSpineFieldsPiExpected : Bool
varyingSigmaSpineFieldsPiExpected = true

_ : varyingSigmaSpineFieldsPi ≡ varyingSigmaSpineFieldsPiExpected
_ = refl

-- The auxiliary field family mentions x syntactically, but checked evaluation
-- reduces `SameType (notPath i) x` to the exact outer domain path, including
-- at the open interval probe.  Its independent source `true` must map to false.
dependentAliasSigmaFieldPi : Bool
dependentAliasSigmaFieldPi =
  observeNestedField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ] Σ[ y ∈ SameType (notPath i) x ] b ≡ x)
      (λ b → b , (not b , refl)))
     true)

dependentAliasSigmaFieldPiExpected : Bool
dependentAliasSigmaFieldPiExpected = true

_ : dependentAliasSigmaFieldPi ≡ dependentAliasSigmaFieldPiExpected
_ = refl

-- The field family depends syntactically on x but reduces to the same closed
-- Bool definition at the probe and both endpoints.  Its explicit per-layer
-- plan is stable identity, so the independent source true remains true while
-- the outer x still follows notPath.
stableDependentSigmaFieldPi : Bool
stableDependentSigmaFieldPi =
  observeStableNestedField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ] Σ[ y ∈ ConstantType x ] b ≡ x)
      (λ b → b , (true , refl)))
     true)

stableDependentSigmaFieldPiExpected : Bool
stableDependentSigmaFieldPiExpected = true

_ : stableDependentSigmaFieldPi ≡ stableDependentSigmaFieldPiExpected
_ = refl

-- Parameterized stable type applications are admitted only when all retained
-- arguments are closed and binder-free.  `List Bool` therefore uses identity
-- transport, including its closed constructor spine and erased type parameter.
parameterizedStableDependentSigmaFieldPi : Bool
parameterizedStableDependentSigmaFieldPi =
  observeParameterizedStableNestedField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ y ∈ ParameterizedConstantType true x ] b ≡ x)
      (λ b → b , (true ∷ [] , refl)))
     true)

parameterizedStableDependentSigmaFieldPiExpected : Bool
parameterizedStableDependentSigmaFieldPiExpected = true

_ : parameterizedStableDependentSigmaFieldPi ≡
    parameterizedStableDependentSigmaFieldPiExpected
_ = refl

-- The metadata-driven stable-value validator handles ordinary parameterized
-- data and record constructors, recursively checking their exact payloads.
-- Both type aliases erase the apparent dependency on earlier Sigma fields.
stableDataRecordDependentSigmaFieldPi : Bool
stableDataRecordDependentSigmaFieldPi =
  observeStableStructureFields true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ y ∈ StableBoxType x ]
        Σ[ z ∈ StableRecordType y ] b ≡ x)
      (λ b → b , (box true , (stableRecord true , refl))))
     true)

stableDataRecordDependentSigmaFieldPiExpected : Bool
stableDataRecordDependentSigmaFieldPiExpected = true

_ : stableDataRecordDependentSigmaFieldPi ≡
    stableDataRecordDependentSigmaFieldPiExpected
_ = refl

-- A reversed open Glue shell has Bool endpoints too, but is neither stable nor
-- the canonical outer domain path.  It must not be misclassified as identity.
unsupportedMismatchedDependentSigmaFieldPi : Bool
unsupportedMismatchedDependentSigmaFieldPi =
  observeNestedField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ] Σ[ y ∈ notPath (~ i) ] b ≡ x)
      (λ b → b , (not b , refl)))
     true)

-- Equal readback under one reused field neutral is not enough for stability:
-- the retained `Tagged x` argument exposes the prior Sigma-field neutral and
-- would change from `Tagged false` to `Tagged true` at runtime.
unsupportedBinderIndexedStableSigmaFieldPi : Bool
unsupportedBinderIndexedStableSigmaFieldPi =
  fst
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ] Σ[ y ∈ Tagged x ] b ≡ x)
      (λ b → b , (tagged , refl)))
     true)

-- A normal function closure may be preserved inside a stable constructor only
-- after semantic readback proves the resulting Agda lambda is closed.  The
-- observer applies the preserved identity function instead of ignoring it.
stableFunctionRecordDependentSigmaFieldPi : Bool
stableFunctionRecordDependentSigmaFieldPi =
  observeStableFunctionField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ y ∈ StableFunctionRecord ] b ≡ x)
      (λ b → b , (stableFunctionRecord (λ value → value) , refl)))
     true)

stableFunctionRecordDependentSigmaFieldPiExpected : Bool
stableFunctionRecordDependentSigmaFieldPiExpected = true

_ : stableFunctionRecordDependentSigmaFieldPi ≡
    stableFunctionRecordDependentSigmaFieldPiExpected
_ = refl

-- Stable identity may also classify a direct Pi field type.  All three type
-- views must read back to the same closed Pi, and the value closure must pass
-- the independent closed-function readback gate before it is preserved.
stableDirectFunctionDependentSigmaFieldPi : Bool
stableDirectFunctionDependentSigmaFieldPi =
  observeDirectStableFunctionField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ f ∈ (Bool → Bool) ] b ≡ x)
      (λ b → b , ((λ value → value) , refl)))
     true)

stableDirectFunctionDependentSigmaFieldPiExpected : Bool
stableDirectFunctionDependentSigmaFieldPiExpected = true

_ : stableDirectFunctionDependentSigmaFieldPi ≡
    stableDirectFunctionDependentSigmaFieldPiExpected
_ = refl

-- The function domain is a non-indexed, parameter-only data family whose
-- sole open parameter is the outer Sigma field.  The adapter remaps the
-- target `tagged` constructor to the source parameter before invoking this
-- pattern-matching source function.
outerIndexedFunctionDependentSigmaFieldPi : Bool
outerIndexedFunctionDependentSigmaFieldPi =
  observeOuterIndexedFunctionField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ f ∈ DependentFunctionType x ] b ≡ x)
      (λ b → b , (consumeTagged , refl)))
     true)

outerIndexedFunctionDependentSigmaFieldPiExpected : Bool
outerIndexedFunctionDependentSigmaFieldPiExpected = true

_ : outerIndexedFunctionDependentSigmaFieldPi ≡
    outerIndexedFunctionDependentSigmaFieldPiExpected
_ = refl

-- The constructor has one independent, closed Bool payload.  The adapter
-- remaps only the indexed family parameters, preserves the payload, and then
-- lets the source function pattern-match it.
groundPayloadIndexedFunctionDependentSigmaFieldPi : Bool
groundPayloadIndexedFunctionDependentSigmaFieldPi =
  observePayloadIndexedFunctionField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ f ∈ PayloadDependentFunctionType x ] b ≡ x)
      (λ b → b , (consumePayloadTagged , refl)))
     true)

groundPayloadIndexedFunctionDependentSigmaFieldPiExpected : Bool
groundPayloadIndexedFunctionDependentSigmaFieldPiExpected = true

_ : groundPayloadIndexedFunctionDependentSigmaFieldPi ≡
    groundPayloadIndexedFunctionDependentSigmaFieldPiExpected
_ = refl

-- A custom nested constructor remains outside the exact ground-payload
-- whitelist, even though this concrete value is closed.  It must fail closed
-- before the source function is invoked.
unsupportedNestedPayloadIndexedFunctionSigmaFieldPi : Bool
unsupportedNestedPayloadIndexedFunctionSigmaFieldPi =
  observeNestedPayloadIndexedFunctionField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ f ∈ NestedPayloadDependentFunctionType x ] b ≡ x)
      (λ b → b , ((λ _ → true) , refl)))
     true)

-- A ground Bool value is not sufficient when its declared constructor field
-- type is the outer type parameter.  Preserving it would skip the required
-- universe-path transport, so the constructor-type independence check rejects.
unsupportedDependentPayloadTypeIndexedFunctionSigmaFieldPi : Bool
unsupportedDependentPayloadTypeIndexedFunctionSigmaFieldPi =
  observeDependentPayloadIndexedFunctionField true
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ f ∈ DependentPayloadFunctionType (notPath i) x ] b ≡ x)
      (λ b → b , ((λ _ → true) , refl)))
     true)

-- An internal canonical-transport closure is deliberately not a normal Agda
-- lambda readback candidate.  Even though the enclosing record type is stable,
-- this payload must fail closed rather than escape the exact application slice.
unsupportedTransportFunctionRecordSigmaFieldPi : Bool
unsupportedTransportFunctionRecordSigmaFieldPi =
  fst
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ y ∈ StableFunctionRecord ] b ≡ x)
      (λ b → b ,
        ( stableFunctionRecord
            (transport (λ i → notPath i → notPath i) (λ value → value))
        , refl)))
     true)

-- A fourth Sigma is deliberately outside the audited recursion bound.
unsupportedOverLimitDependentSigmaPi : Bool
unsupportedOverLimitDependentSigmaPi =
  fst
    ((transport
      (λ i → (b : notPath i) →
        Σ[ x ∈ notPath i ]
        Σ[ y ∈ notPath i ]
        Σ[ z ∈ notPath i ]
        Σ[ w ∈ notPath i ] b ≡ x)
      (λ b → b , (b , (b , (b , refl)))))
     true)
