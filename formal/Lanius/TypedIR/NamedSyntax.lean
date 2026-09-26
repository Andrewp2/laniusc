import Lanius.TypedIR.Named
import Lean.Elab.Macro
import Lean.Elab.Quotation
import Lean.Parser.Do

namespace Lanius.TypedIR.Named

open Lean
open Lean.Parser.Term

private abbrev Scope := List (Name × TSyntax `term)

private def local? (scope : Scope) (name : Name) : Option (TSyntax `term) :=
  (scope.find? fun entry => entry.1 == name).map Prod.snd

private def bindingTerm (name : TSyntax `ident) (id : TSyntax ``Parser.Term.num) :
    MacroM (TSyntax `term) := do
  let spelling := quote name.getId.toString
  let idTerm : TSyntax `term := ⟨id.raw⟩
  `(Var.named $idTerm $spelling)

mutual
  private partial def lowerExpression (input : TSyntax `term)
      (scope : Scope) (ids : Array (TSyntax ``Parser.Term.num)) (cursor : Nat) :
      MacroM (TSyntax `term × Nat) := do
    match input with
    | `($value:num) => return (← `(Expr.i32 $value), cursor)
    | `(($inner:term)) => lowerExpression inner scope ids cursor
    | `($left:term + $right:term) =>
        let (left, cursor) ← lowerExpression left scope ids cursor
        let (right, cursor) ← lowerExpression right scope ids cursor
        return (← `(Expr.add $left $right), cursor)
    | `($left:term - $right:term) =>
        let (left, cursor) ← lowerExpression left scope ids cursor
        let (right, cursor) ← lowerExpression right scope ids cursor
        return (← `(Expr.subtract $left $right), cursor)
    | `($left:term * $right:term) =>
        let (left, cursor) ← lowerExpression left scope ids cursor
        let (right, cursor) ← lowerExpression right scope ids cursor
        return (← `(Expr.multiply $left $right), cursor)
    | `($binding:ident) =>
        if let some varTerm := local? scope binding.getId then
          return (← `(Expr.local $varTerm), cursor)
        return (← `(Expr.variant $binding .nil), cursor)
    | `(match $discriminant:matchDiscr with $arms:matchAlt*) =>
        let `(matchDiscr| $scrutinee:term) := discriminant
          | Macro.throwUnsupported
        let (scrutinee, firstCursor) ← lowerExpression scrutinee scope ids cursor
        let mut cursor := firstCursor
        let mut lowered := #[]
        for arm in arms do
          let (value, next) ← lowerArm arm scope ids cursor
          lowered := lowered.push value
          cursor := next
        return (← `(Expr.matchValue $scrutinee [$[$lowered],*]), cursor)
    | `($constructor:ident $payload:term) =>
        let (payload, cursor) ← lowerExpression payload scope ids cursor
        return (← `(Expr.variant $constructor (.cons $payload .nil)), cursor)
    | _ => return (input, cursor)

  private partial def lowerArm (input : TSyntax ``matchAlt)
      (scope : Scope) (ids : Array (TSyntax ``Parser.Term.num)) (cursor : Nat) :
      MacroM (TSyntax `term × Nat) := do
    match input.raw with
    | `(matchAltExpr| | $pattern:term => $body:term) =>
        match pattern with
        | `($constructor:ident $binding:ident) =>
            let some id := ids[cursor]? | Macro.throwUnsupported
            let varTerm ← bindingTerm binding id
            let (body, cursor) ← lowerExpression body
              ((binding.getId, varTerm) :: scope) ids (cursor + 1)
            return (← `(Arm.variant $constructor (.cons $varTerm .nil) $body), cursor)
        | `($constructor:ident) =>
            let (body, cursor) ← lowerExpression body scope ids cursor
            return (← `(Arm.variant $constructor .nil $body), cursor)
        | _ => Macro.throwUnsupported
    | _ => Macro.throwUnsupported
end

private partial def lowerStatements (elements : List DoElem)
    (scope : Scope) (ids : Array (TSyntax ``Parser.Term.num)) (cursor : Nat) :
    MacroM (TSyntax `term × Nat) := do
  match elements with
  | [] => Macro.throwUnsupported
  | element :: rest =>
      match element.raw with
      | `(doReturn| return $value:term) =>
          unless rest.isEmpty do Macro.throwUnsupported
          let (value, cursor) ← lowerExpression value scope ids cursor
          return (← `(Stmt.returnValue $value), cursor)
      | `(doLet| let $binding:ident : $type:term := $initializer:term) =>
          let some id := ids[cursor]? | Macro.throwUnsupported
          let varTerm ← bindingTerm binding id
          let varTerm ← `(($varTerm : Var $type))
          let (initializer, cursor) ← lowerExpression initializer scope ids (cursor + 1)
          let (body, cursor) ← lowerStatements rest
            ((binding.getId, varTerm) :: scope) ids cursor
          return (← `(Stmt.letLocal $varTerm $initializer $body), cursor)
      | _ => Macro.throwUnsupported

/-- Source-shaped function notation, elaborated to the single typed Core
    embedding. The binding IDs are the resolved IR identities, not a second
    syntax tree; every ID must be consumed by a source binder. -/
scoped macro "function" "(" idKey:ident ":=" id:term "," nameKey:ident ":=" name:term ","
    argumentsKey:ident ":=" arguments:term "," bindingsKey:ident ":=" "[" ids:num,* "]"
    ")" "do" body:doSeq : term => do
  unless idKey.getId == `id && nameKey.getId == `name
      && argumentsKey.getId == `arguments && bindingsKey.getId == `bindings do
    Macro.throwUnsupported
  let ids := ids.getElems
  let (statements, consumed) ← lowerStatements
    (Parser.Term.getDoElems body).toList [] ids 0
  unless consumed == ids.size do Macro.throwUnsupported
  `({ id := $id, name := $name, arguments := $arguments,
      body := some $statements, external := none })

end Lanius.TypedIR.Named
