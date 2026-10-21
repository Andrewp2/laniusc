import Lanius.Semantics.SourceValue

namespace Lanius.Semantics

open Lanius.Core

private inductive Choice where
  | empty
  | selected (value : Int)
private inductive Pair where
  | mk (left right : Int)
attribute [lanius_type enum 42] Choice
attribute [lanius_type record 9] Pair

example : (source_value Choice.empty []) = Value.enumeration 42 0 [] := rfl
example (value : Int) : (source_value Choice.selected [.signed .i32 value]) =
    Value.enumeration 42 1 [.signed .i32 value] := rfl
example (left right : Value) : (source_value Pair.mk [left, right]) =
    Value.structure 9 [left, right] := rfl

-- This is representation notation, not a typing checker or a trust shortcut.
-- Deliberately malformed payloads can be represented for rejection proofs.
example : (source_value Choice.selected []) = Value.enumeration 42 1 [] := rfl
example : True := by
  fail_if_success
    suffices wrong : (source_value Choice.empty []) = Value.enumeration 42 1 [] by trivial
    rfl
  trivial

end Lanius.Semantics
