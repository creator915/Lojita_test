module NbeAdapterSpikeUniverseAlias where

open import Agda.Primitive using (Level; _⊔_)

Alias : ∀ {ℓ : Level} → Set ℓ → Set ℓ
Alias A = A

main : (a b : Level) (A : Set a) (B : Set b) →
  Alias (A → B) → A → B
main = λ a b A B function value → function value
