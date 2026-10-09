import Lanius.TypedIR.Surface.Syntax
import Lanius.TypedIR.Surface.DataCompiler

namespace Lanius.TypedIR.Surface
open Lean Lean.Elab Lean.Elab.Term Lean.Meta Labels

private def fields (owner : Lean.Expr) (name : Name) : TermElabM Lean.Expr := do
  let labels ← constructorFields owner (← getConstInfoCtor name)
  mkListLit (mkConst ``Core.Ty) (← labels.toList.mapM fun (_, label) => coreType label)

/-- Assemble the supplied declarations once. Lanius owns typing and symbol
    validation; native declarations supply nominal shape, not typing proofs. -/
scoped elab "link" "(" typesKey:ident ":=" "[" types:term,* "]" ","
    constantsKey:ident ":=" constants:term "," functionsKey:ident ":=" functions:term ")" : term => do
  unless typesKey.getId == `types && constantsKey.getId == `constants &&
      functionsKey.getId == `functions do throwUnsupportedSyntax
  let mut structures := #[]
  let mut enumerations := #[]
  for type in types.getElems do
    let (owner, info) ← nominal (← elabType type)
    let code ← coreType owner
    if code.isAppOfArity ``Core.Ty.structure 1 then
      let [constructor] := info.ctors | throwErrorAt type "record label required"
      structures := structures.push (mkApp2 (mkConst ``Core.StructDecl.mk)
        code.getAppArgs[0]! (← fields owner constructor))
    else if code.isAppOfArity ``Core.Ty.enumeration 1 then
      let variants ← info.ctors.mapM (fields owner)
      enumerations := enumerations.push (mkApp2 (mkConst ``Core.EnumDecl.mk)
        code.getAppArgs[0]! (← mkListLit (mkApp (mkConst ``List [0]) (mkConst ``Core.Ty)) variants))
    else
      throwErrorAt type "nominal Core type required"
  let constants ← elabTermEnsuringType constants
    (some (mkApp (mkConst ``List [0]) (mkConst ``Core.Constant)))
  let functions ← elabTermEnsuringType functions
    (some (mkApp (mkConst ``List [0]) (mkConst ``Core.Function)))
  return mkAppN (mkConst ``Core.Program.mk) #[mkConst ``Core.Target.x86_64,
    ← mkListLit (mkConst ``Core.StructDecl) structures.toList,
    ← mkListLit (mkConst ``Core.EnumDecl) enumerations.toList, constants, functions]

end Lanius.TypedIR.Surface
