import Lanius.Semantics.NativeRecordStore
import Lanius.Semantics.NativeSliceStore
import Lanius.Semantics.ExpressionProof

namespace Lanius.Semantics

open Lean Meta Elab Tactic

initialize nativeStoreRules : LabelExtension ←
  registerLabelAttr `native_store_rule "proved native value codecs"
syntax "native_store" : tactic

private def listItems (list : Expr) : MetaM (Array Expr) := do
  let mut current := list
  let mut result := #[]
  repeat
    let next ← whnf current
    if next.isAppOfArity ``List.nil 1 then return result
    unless next.isAppOfArity ``List.cons 3 do throwError "concrete native field list required"
    result := result.push next.getAppArgs[1]!
    current := next.getAppArgs[2]!
  return result

private def recordData (program id : Expr) : MetaM Expr := do
  let entries ← listItems (← mkAppM ``Lanius.Core.Program.structures #[program])
  for entry in entries do
    if ← isDefEq id (← mkAppM ``Lanius.Core.StructDecl.id #[entry]) then return entry
  throwError "native record declaration missing"

private def wordSize (program type : Expr) : MetaM Nat := do
  let result ← whnf (← mkAppM ``Lanius.NativeLayout.words? #[mkNatLit 63, program, type])
  unless result.isAppOfArity ``Option.some 2 do throwError "unsupported native field layout"
  let number ← whnf result.getAppArgs[1]!
  let .lit (.natVal words) := number | throwError "closed native field width required"
  return words * 8

private def finiteCases (index : TSyntax `ident) : Nat → TSyntax `tactic → TacticM (TSyntax `tactic)
  | 0, _ => `(tactic| (simp only [List.length_cons, List.length_nil] at *; omega))
  | count + 1, leaf => do
      let tail ← finiteCases index count leaf
      `(tactic| cases $index:ident with | zero => $leaf:tactic | succ $index:ident => $tail:tactic)

private def solveRecord (program id values : Expr) : TacticM Unit := do
  let fields ← listItems (← mkAppM ``Lanius.Core.StructDecl.fields #[← recordData program id])
  let values ← listItems values
  unless fields.size == values.size do throwError "native record arity mismatch"
  let mut offsets := #[]
  let mut widths := #[]
  let mut offset := 0
  for field in fields do
    offsets := offsets.push (mkNatLit offset)
    let width ← wordSize program field
    widths := widths.push (mkNatLit width)
    offset := offset + width
  let offsetTerms ← Term.exprToSyntax (← mkListLit (mkConst ``Nat) offsets.toList)
  let widthTerms ← Term.exprToSyntax (← mkListLit (mkConst ``Nat) widths.toList)
  evalTactic (← `(tactic| apply NativeStoreSpec.record
    (offset := fun index => (($offsetTerms)[index]?).getD 0)
    (width := fun index => (($widthTerms)[index]?).getD 0)))
  evalTactic (← `(tactic| next => core_lookup))
  evalTactic (← `(tactic| next => rfl))
  let leaf ← `(tactic| first | native_store | rfl | decide +kernel | omega)
  for _ in [:3] do
    let index := mkIdent (← mkFreshUserName `field)
    let bound := mkIdent (← mkFreshUserName `inside)
    let cases ← finiteCases index fields.size leaf
    evalTactic (← `(tactic| next => intro $index:ident $bound:ident; $cases:tactic))
  let left := mkIdent (← mkFreshUserName `left)
  let right := mkIdent (← mkFreshUserName `right)
  let reduce ← `(tactic| simp only [List.getElem?_cons_zero, List.getElem?_cons_succ,
    Option.getD_some, List.length_cons, List.length_nil] at *)
  let rightCases ← finiteCases right fields.size (← `(tactic| ($reduce:tactic; omega)))
  let leftCases ← finiteCases left fields.size rightCases
  evalTactic (← `(tactic| next => intro $left:ident $right:ident _ _; $leftCases:tactic))
  let index := mkIdent (← mkFreshUserName `field)
  let cases ← finiteCases index fields.size leaf
  evalTactic (← `(tactic| intro $index:ident _; $cases:tactic))

elab_rules : tactic
  | `(tactic| native_store) => focusAndDone <| withMainContext do
    -- Do not unfold the store contract into arbitrary heaps during search.
    let target ← instantiateMVars (← (← getMainGoal).getType)
    unless target.getAppFn.constName? == some ``NativeStoreSpec do throwError "native codec goal required"
    let saved ← saveState
    try
      evalTactic (← `(tactic| assumption))
      return
    catch _ => saved.restore
    for name in nativeStoreRules.getState (← getEnv) do
      let saved ← saveState
      try
        evalTactic (← `(tactic| apply $(mkIdent name):ident))
        evalTactic (← `(tactic| all_goals first | assumption | omega | decide +kernel))
        unless (← getGoals).isEmpty do throwError "native codec premises remain"
        return
      catch _ => saved.restore
    let #[_, program, _, value, size] := target.getAppArgs | throwError "native codec arguments required"
    let value ← whnf value
    if value.isAppOfArity ``Lanius.Core.Value.structure 2 then
      solveRecord program value.getAppArgs[0]! value.getAppArgs[1]!
    else if value.isAppOfArity ``Lanius.Core.Value.enumeration 3 then
      let payload ← listItems value.getAppArgs[2]!
      if payload.isEmpty then
        evalTactic (← `(tactic| exact (NativeStoreSpec.enumEmpty (by core_lookup) rfl (by decide)).enlarge (by decide)))
      else if payload.size == 1 then
        let size ← whnf size
        let .lit (.natVal bytes) := size | throwError "closed enum slot size required"
        if bytes < 16 then throwError "enum slot too small"
        let bytes := Syntax.mkNumLit (toString (bytes - 8))
        evalTactic (← `(tactic| apply NativeStoreSpec.enumSingle (size := $bytes)
          (by core_lookup) rfl (by decide) (by decide)))
        evalTactic (← `(tactic| native_store))
      else throwError "multi-payload native enum codec required"
    else if value.isAppOfArity ``Lanius.Core.Value.boolean 1 then
      let value ← Term.exprToSyntax value.getAppArgs[0]!
      evalTactic (← `(tactic| exact (NativeStoreSpec.boolean $value).enlarge (by decide)))
    else if value.isAppOfArity ``Lanius.Core.Value.rawSlice 3 then
      evalTactic (← `(tactic| apply NativeStoreSpec.enlarge (size := 24)))
      evalTactic (← `(tactic| next => apply NativeStoreSpec.rawSlice
        <;> first | assumption | decide +kernel | omega))
      evalTactic (← `(tactic| decide +kernel))
    else if value.isAppOfArity ``Lanius.Core.Value.signed 2 then
      let number := value.getAppArgs[1]!
      let word ← if number.isAppOfArity ``BitVec.toInt 2 then pure number.getAppArgs[1]!
        else if number.isAppOfArity ``Int32.toInt 1 then mkAppM ``Int32.toBitVec #[number.getAppArgs[0]!]
        else throwError "represented i32 payload required"
      let word ← Term.exprToSyntax word
      evalTactic (← `(tactic| exact (NativeStoreSpec.i32 $word).enlarge (by decide)))
    else throwError "no proved native codec for this value"

end Lanius.Semantics
