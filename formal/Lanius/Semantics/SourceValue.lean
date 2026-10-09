import Lanius.TypedIR.Surface.Labels

namespace Lanius.Semantics

open Lean Elab Term Meta

/-- Name a source constructor in a semantic value. Nominal identity and ordinal
    come from its existing declaration metadata; payloads are ordinary Core
    values, not a second typing tree. Subsequent execution proofs still check
    this proposed representation against the actual function body. -/
syntax "source_value " ident "[" term,* "]" : term

elab_rules : term
  | `(source_value $constructor:ident [$payload:term,*]) => do
    let declaration ← elabTerm constructor none
    let some name := declaration.getAppFn.constName? | throwError "source constructor required"
    let info ← getConstInfoCtor name
    let some (record, id) := TypedIR.Surface.Labels.nominalTypes.getParam? (← getEnv) info.induct
      | throwError "source constructor has no Lanius nominal metadata"
    let values ← payload.getElems.toList.mapM (fun value =>
      elabTermEnsuringType value.raw (some (mkConst ``Core.Value)))
    let values ← mkListLit (mkConst ``Core.Value) values
    if record then
      return mkApp2 (mkConst ``Core.Value.structure) (mkNatLit id) values
    else return mkApp3 (mkConst ``Core.Value.enumeration) (mkNatLit id) (mkNatLit info.cidx) values

end Lanius.Semantics
