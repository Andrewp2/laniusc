import Lean.Compiler.LCNF.Main

namespace Lanius.TypedIR.Surface.DataCompiler
open Lean Lean.Compiler.LCNF

-- Closed constructor data has no branches, local functions, or calls to
-- specialize. Recognition is conservative; any other value uses normal passes.
private def constructorData (env : Environment) : Code .pure → Bool
  | .return _ => true
  | .let binding next =>
    let simple := match binding.value with
      | .lit _ | .erased => true
      | .const name _ args _ =>
        match env.find? name with
        | some (.ctorInfo info) => args.size == info.numParams + info.numFields
        | _ => false
      | _ => false
    simple && constructorData env next
  | _ => false

private def isData (env : Environment) (decl : Decl .pure) : Bool :=
  decl.params.isEmpty && match decl.value with
    | .code code => constructorData env code
    | _ => false

-- These are optimizer-cache entries, not kernel definitions or executable IR.
-- Lean already uses this opaque-body format for non-inlineable module exports.
-- Keep signatures and explicitly requested inlining; compile the original body.
private def saveDataSignature (decl : Decl .pure) : CompilerM Unit :=
  ({ decl with value := .extern { entries := [.opaque] } }).save

private def canCompact (env : Environment) (decl : Decl .pure) : Bool :=
  decl.inlineAttr?.isNone && isData env decl

private meta def optionalPass (pass : Pass) : Bool :=
  (pass.phase == .base && pass.name ∈ [
    `floatLetIn, `findJoinPoints, `pullFunDecls, `reduceJpArity,
    `eagerLambdaLifting, `specialize]) ||
  (pass.phase == .base && pass.name == `simp && pass.occurrence > 0) ||
  (pass.phase == .mono && pass.name ∈ [
    `simp, `reduceJpArity, `structProjCases, `extendJoinPointContext,
    `floatLetIn, `reduceArity, `commonJoinPointArgs, `elimDeadBranches])

private meta def wrapPasses (phase : Phase) : PassInstaller := {
  phase
  install := fun passes => pure <| passes.map fun pass =>
    if optionalPass pass then
      match pass with
      | ⟨occurrence, .base, .base, phaseInv, check, name, run⟩ =>
        { occurrence, phase := .base, phaseInv, shouldAlwaysRunCheck := check, name,
          run := fun decls => do
          if decls.all (isData (← getEnv)) then return decls
          run decls }
      | ⟨occurrence, .mono, .mono, phaseInv, check, name, run⟩ =>
        { occurrence, phase := .mono, phaseInv, shouldAlwaysRunCheck := check, name,
          run := fun decls => do
          if decls.all (isData (← getEnv)) then return decls
          run decls }
      | _ => pass
    else pass
}

-- Only optional, same-phase optimizations can become identity passes. Type
-- erasure, lowering, reference counting, code generation, saving, and the
-- compiler's checks still run. Kernel checking is entirely unchanged.
@[cpass] meta def constructorDataBase : PassInstaller := wrapPasses .base
@[cpass] meta def constructorDataMono : PassInstaller := wrapPasses .mono

@[cpass] meta def constructorDataBaseCache : PassInstaller :=
  PassInstaller.replacePass .base `saveBase fun pass =>
    match pass with
    | ⟨occurrence, .base, .base, phaseInv, check, name, _⟩ =>
      { occurrence, phase := .base, phaseInv, shouldAlwaysRunCheck := check, name,
        run := fun decls => do
          for decl in decls do
            if canCompact (← getEnv) decl then saveDataSignature decl
            else (← normalizeFVarIds decl).saveBase
          return decls }
    | _ => pass

-- Mono saving follows lambda lifting, outside the extensible mono pass list.
-- Compact that cache after lowering, without changing the executable decls.
@[cpass] meta def constructorDataMonoCache : PassInstaller :=
  PassInstaller.installAtEnd .impure {
    phase := .impure
    name := `compactConstructorDataCache
    run := fun decls => do
      for decl in decls do
        if let some mono ← getMonoDecl? decl.name then
          if canCompact (← getEnv) mono then
            withPhase .mono (saveDataSignature mono)
      return decls
  }

end Lanius.TypedIR.Surface.DataCompiler
