{-# OPTIONS --cubical --safe #-}

-- Low-memory, independent reproduction of test/fixtures/TransportTests.agda t01/t02/t07.
-- Source SHA-256: 8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b

module TransportBase where

open import Cubical.Foundations.Prelude
open import Cubical.Data.Nat using (ℕ; suc)

t01 : ℕ
t01 = transp (λ _ → ℕ) i1 7

e01 : ℕ
e01 = 7

_ : t01 ≡ e01
_ = refl

t02 : ℕ
t02 = transport (λ _ → ℕ) 7

e02 : ℕ
e02 = 7

_ : t02 ≡ e02
_ = refl

t07 : ℕ
t07 = (transport (λ _ → ℕ → ℕ) suc) 3

e07 : ℕ
e07 = 4

_ : t07 ≡ e07
_ = refl
