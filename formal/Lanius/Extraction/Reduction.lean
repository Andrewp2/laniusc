import Lean.Meta.Reduce
import Lean.Elab.Term
import Lean.Elab.SyntheticMVars

namespace Lanius.Extraction
open Lean Meta Elab Term

/-- Normalize data while allowing a caller to retain a proof-rich substructure
that its consumers do not inspect. Retained terms are unchanged, not erased;
the enclosing reflexivity proof still authenticates the complete value. -/
private partial def reduceData (input : Expr) (retained : Array Name) : MetaM Expr := do
  let rec visit (value : Expr) : MonadCacheT Expr Expr MetaM Expr :=
    checkCache value fun _ => Core.withIncRecDepth do
      if (← isType value) || (← isProof value) then
        return value
      let type ← inferType value
      if retained.any fun name => (type.find? (·.isConstOf name)).isSome then
        return value
      let value ← whnf value
      match value with
      | .app .. =>
        let function ← visit value.getAppFn
        let arguments ← value.getAppArgs.mapM visit
        if function.isConstOf ``Nat.succ && arguments.size == 1 &&
            arguments[0]!.isRawNatLit then
          return mkRawNatLit (arguments[0]!.rawNatLit?.get! + 1)
        return mkAppN function arguments
      | .lam .. => lambdaTelescope value fun variables body => do
        mkLambdaFVars variables (← visit body)
      | .forallE .. => forallTelescope value fun variables body => do
        mkForallFVars variables (← visit body)
      | .proj name index object => return mkProj name index (← visit object)
      | _ => return value
  visit input |>.run

/-- Materialize a computation once as ordinary constructor data, retaining a
kernel-checked equality to the original expression. The elaborator proposes
the reduced value; reflexivity must check against that value before Lean can
accept the subtype. No native evaluation or new axiom supplies the equality.
Proof fields are retained, not normalized or discarded. `retaining [T, ...]`
also leaves subterms whose types mention the named declarations unchanged. -/
syntax "reduce_data% " ("retaining " "[" ident,* "] ")? term : term

elab_rules : term
  | `(reduce_data% $[retaining [$retained:ident,*]]? $input:term) => do
    let original ← elabTerm input none
    synthesizeSyntheticMVarsNoPostponing
    let original ← instantiateMVars original
    let type ← inferType original
    let level ← getLevel type
    let retained ← match retained with
      | none => pure #[]
      | some names => names.getElems.mapM fun name => do
          realizeGlobalConstNoOverloadWithInfo name
    let reduced ← withTransparency .all <| reduceData original retained
    let predicate ← withLocalDeclD `value type fun value => do
      mkLambdaFVars #[value] (← mkEq value original)
    pure (mkApp4 (mkConst ``Subtype.mk [level]) type predicate reduced (← mkEqRefl original))

end Lanius.Extraction
