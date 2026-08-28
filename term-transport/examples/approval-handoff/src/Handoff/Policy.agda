module Handoff.Policy where

open import Agda.Builtin.Bool using (Bool; false; true)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat; _<_)
open import Handoff.Domain
open import Handoff.Util

requiredReviews : Nat → Nat
requiredReviews value with value < 1001
... | true = 1
... | false with value < 5001
...   | true = 2
...   | false = 3

allAccepted : List Review → Bool
allAccepted [] = true
allAccepted (current ∷ remaining) with decision current
... | accept = allAccepted remaining
... | deny = false

hasDenial : List Review → Bool
hasDenial [] = false
hasDenial (current ∷ remaining) with decision current
... | accept = hasDenial remaining
... | deny = true

enoughReviews : Envelope → Bool
enoughReviews current = requiredReviews (amount current) ≤ᵇ length (reviews current)

classify : Envelope → HandoffState
classify current with hasDenial (reviews current)
... | true = denied
... | false with enoughReviews current && allAccepted (reviews current)
...   | true = readyToPay
...   | false = awaitingReview
