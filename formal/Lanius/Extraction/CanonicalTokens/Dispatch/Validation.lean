import Lanius.Extraction.CanonicalTokens.Dispatch.Rule

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core

def ConstantValid (program : Program) (kind : ConstantId) : Prop :=
  program.constant? kind = some {
    id := kind, type := .scalar (.signed .i32), value := .signed .i32 (tag program kind) }

def checkConstant? (program : Program) (kind : ConstantId) : Option (PLift (ConstantValid program kind)) := do
  match found : program.constant? kind with
  | none => none
  | some value =>
      let same ← Equality.constant? value {
        id := kind, type := .scalar (.signed .i32), value := .signed .i32 (tag program kind) }
      pure ⟨found.trans (congrArg some same.equal)⟩

def checkRule? (program : Program) (width : Nat) (rule : Rule) : Option (PLift (ValidRule program width rule)) := do
  if padded : (Lanius.World.utf8Bytes rule.text).length = ((width + 3) / 4) * 4 then
    if countBound : width + 3 ≤ 2147483647 then
      let constant ← checkConstant? program rule.kind
      pure ⟨⟨padded, countBound, constant.down⟩⟩
    else none
  else none

def checkRules? (program : Program) (width : Nat) : (rules : List Rule) →
    Option (PLift (∀ rule ∈ rules, ValidRule program width rule))
  | [] => some ⟨by simp⟩
  | rule :: rest => do
      let first ← checkRule? program width rule
      let remaining ← checkRules? program width rest
      pure ⟨by
        intro candidate member
        rcases List.mem_cons.mp member with rfl | later
        · exact first.down
        · exact remaining.down candidate later⟩

def checkGroups? (program : Program) : (groups : List Group) →
    Option (PLift (∀ group ∈ groups, ∀ rule ∈ group.rules, ValidRule program group.width rule))
  | [] => some ⟨by simp⟩
  | group :: rest => do
      let first ← checkRules? program group.width group.rules
      let remaining ← checkGroups? program rest
      pure ⟨by
        intro candidate member
        rcases List.mem_cons.mp member with rfl | later
        · exact first.down
        · exact remaining.down candidate later⟩

end Lanius.Extraction.CanonicalTokens.Dispatch
