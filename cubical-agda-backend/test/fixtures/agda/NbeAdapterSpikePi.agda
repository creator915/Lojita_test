module NbeAdapterSpikePi where

polymorphicId : (A : Set) → A → A
polymorphicId A value = value

main : (A : Set) → A → A
main = λ A value → polymorphicId A value
