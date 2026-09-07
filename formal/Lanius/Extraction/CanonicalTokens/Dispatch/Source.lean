import Lanius.Core.Equality

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core

structure Rule where
  text : String
  kind : ConstantId

structure Group where
  width : Nat
  rules : List Rule

def returned (kind : ConstantId) : Stmt :=
  .sequence (.returnValue (some (.constant kind))) .skip

def condition (matcher : FunctionId) (width : Nat) (rule : Rule) : Expr :=
  .call matcher [.local 0, .local 1, .value (.string rule.text), .value (.signed .i32 width)]

def choices (matcher : FunctionId) (width : Nat) : List Rule → Stmt
  | [] => .skip
  | rule :: rest => .sequence
      (.ifThenElse (condition matcher width rule) (returned rule.kind) .skip)
      (choices matcher width rest)

def branches (matcher : FunctionId) (fallback : ConstantId) : List Group → Stmt
  | [] => returned fallback
  | group :: rest => .sequence
      (.ifThenElse (.binary .equal (.local 3) (.value (.signed .i32 group.width)))
        (choices matcher group.width group.rules) .skip)
      (branches matcher fallback rest)

def body (matcher : FunctionId) (fallback : ConstantId) (groups : List Group) : Stmt :=
  .letLocal 3 (.scalar (.signed .i32)) (.binary .subtract (.local 2) (.local 1))
    (branches matcher fallback groups)

def sourceFunction (id matcher : FunctionId) (fallback : ConstantId) (groups : List Group) : Function := {
  id
  parameters := [(0, .slice (.scalar (.signed .i32))), (1, .scalar (.signed .i32)),
    (2, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (body matcher fallback groups)
}

private def recoverChoices? : Stmt → Option (List Rule)
  | .skip => some []
  | .sequence (.ifThenElse (.call _ [_, _, .value (.string text), _])
      (.sequence (.returnValue (some (.constant kind))) _) _) rest => do
      pure (⟨text, kind⟩ :: (← recoverChoices? rest))
  | _ => none

private def recoverBranches? : Stmt → Option (List Group × ConstantId)
  | .sequence (.returnValue (some (.constant fallback))) .skip => some ([], fallback)
  | .sequence (.ifThenElse (.binary .equal _ (.value (.signed .i32 width))) rules _) rest => do
      let selected ← recoverChoices? rules
      let (groups, fallback) ← recoverBranches? rest
      pure (⟨width.toNat, selected⟩ :: groups, fallback)
  | _ => none

structure CheckedBody (matcher : FunctionId) (statement : Stmt) where
  groups : List Group
  fallback : ConstantId
  exactSource : statement = body matcher fallback groups

/-- Recover candidate table data, then prove equality of the entire body.
Malformed argument order, lengths, locals, branches, or returns are rejected;
the recovery routines themselves are not a trust boundary. -/
def checkBody? (matcher : FunctionId) (statement : Stmt) : Option (CheckedBody matcher statement) := do
  let .letLocal _ _ _ rest := statement | none
  let (groups, fallback) ← recoverBranches? rest
  let exactSource ← Equality.statement? statement (body matcher fallback groups)
  pure ⟨groups, fallback, exactSource.equal⟩

end Lanius.Extraction.CanonicalTokens.Dispatch
