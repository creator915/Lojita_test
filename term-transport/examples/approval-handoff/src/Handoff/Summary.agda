module Handoff.Summary where

open import Handoff.Domain
open import Handoff.Policy
open import Handoff.Util using (length)

summarise : Envelope → Summary
summarise current = summary
  (requestId current)
  (amount current)
  (length (reviews current))
  (classify current)
