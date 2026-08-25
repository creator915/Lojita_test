module NativeNoMain where

open import Agda.Builtin.Nat

-- The checked entry is static, but the module deliberately has no executable
-- main.  The real Stock Agda/MAlonzo compiler must therefore fail to publish a
-- native program rather than letting the integration test inject a fake tool.
analysis : Nat
analysis = 42
