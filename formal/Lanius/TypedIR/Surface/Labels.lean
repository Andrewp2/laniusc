import Lanius.TypedIR.Surface
import Lean.Elab.Term
import Lean.Meta.Reduce

namespace Lanius.TypedIR.Surface.Labels
open Lean Lean.Elab.Term Lean.Meta

syntax (name := lanius_type) "lanius_type" ident num : attr

/-- A source declaration owns one nominal identity. This is notation metadata,
    not typing evidence or a second copy of its fields and constructors. -/
initialize nominalTypes : ParametricAttribute (Bool × Nat) ← registerParametricAttribute {
  name := `lanius_type
  descr := "resolved Lanius nominal kind and ID"
  getParam := fun declaration stx => do
    let .inductInfo info ← getConstInfo declaration
      | throwError "Lanius nominal metadata requires an inductive type"
    unless info.numIndices == 0 do
      throwError "Lanius nominal metadata requires an unindexed type"
    let kind := stx[1].getId
    unless kind == `record || kind == `enum do
      throwError "nominal kind must be record or enum"
    let isRecord := kind == `record
    if isRecord && info.ctors.length != 1 then
      throwError "Lanius record metadata requires exactly one constructor"
    let some id := stx[2].isNatLit? | throwError "resolved nominal ID required"
    return (isRecord, id)
}

/-- Read a label's Core type without constructing a typing judgment. -/
partial def coreType (label : Lean.Expr) : TermElabM Lean.Expr := do
  let reduced ← whnf label
  if let some name := reduced.getAppFn.constName? then
    if let some (isRecord, id) := nominalTypes.getParam? (← getEnv) name then
      return mkApp (mkConst (if isRecord then ``Core.Ty.structure else ``Core.Ty.enumeration))
        (mkNatLit id)
  if reduced.isAppOfArity ``Slice 1 then
    return mkApp (mkConst ``Core.Ty.slice) (← coreType reduced.getAppArgs[0]!)
  -- Abstract labels supplied by a Lean caller still use its Code parameter.
  let dictionary ← synthInstance (mkApp (mkConst ``Code) label)
  reduce (mkApp2 (mkConst ``Code.ty) label dictionary)

def nominalId (owner : Lean.Expr) (kind : Name) : TermElabM Lean.Expr := do
  let type ← coreType owner
  unless type.isAppOfArity kind 1 do throwError "wrong nominal source kind"
  return type.getAppArgs[0]!

def nominal (owner : Lean.Expr) : TermElabM (Lean.Expr × InductiveVal) := do
  let owner ← whnf owner
  let some name := owner.getAppFn.constName? | throwError "nominal source label required"
  let info ← getConstInfoInduct name
  unless info.numIndices == 0 && owner.getAppNumArgs == info.numParams do
    throwError "source labels require an unindexed nominal type"
  return (owner, info)

/-- Read source labels, not typing evidence, from the native constructor. -/
def constructorFields (owner : Lean.Expr) (info : ConstructorVal) :
    TermElabM (Array (Name × Lean.Expr)) := do
  let mut type ← inferType (mkAppN (mkConst info.name owner.getAppFn.constLevels!) owner.getAppArgs)
  let mut fields := #[]
  for _ in *...info.numFields do
    let .forallE name label body _ := type | throwError "constructor field required"
    if label.hasLooseBVars then throwError "dependent fields are not source labels"
    fields := fields.push (name, label)
    type := body
  return fields

end Lanius.TypedIR.Surface.Labels
