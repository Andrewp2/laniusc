import SelfCore
import Lanius.Core.Quote
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.ArtifactCacheQuote
import Lanius.Extraction.KernelReduction
import Lean.Util.CollectAxioms
import Lean.Meta.Reduce

/-! Certify the complete lowering equation for the frozen Surface units and the
single saved Core candidate. Native decoding only proposes the units; their
binding to the original source bytes remains a separate Surface certificate.
This does not prove extractor execution or general x86 semantic preservation.
The entire recipe runs in one invocation with no saved lowering subproofs. -/

open Lean Elab Lanius.Extraction
namespace Lanius.Surface
deriving instance ToExpr for PathSegment, TypeExpr, ArrayLength
deriving instance ToExpr for Path
deriving instance ToExpr for Literal
deriving instance ToExpr for UnaryOp
deriving instance ToExpr for BinaryOp
deriving instance ToExpr for AssignOp
deriving instance ToExpr for RangeKind
deriving instance ToExpr for Pattern, Expr, RangeBound, ForIterable, Stmt
deriving instance ToExpr for TypeParameter
deriving instance ToExpr for ConstParameter
deriving instance ToExpr for GenericParameter
deriving instance ToExpr for WherePredicate
deriving instance ToExpr for Parameter
deriving instance ToExpr for Function
deriving instance ToExpr for ExternFunction
deriving instance ToExpr for StructField
deriving instance ToExpr for StructDecl
deriving instance ToExpr for EnumVariant
deriving instance ToExpr for EnumDecl
deriving instance ToExpr for TraitMethod
deriving instance ToExpr for TraitDecl
deriving instance ToExpr for ImplDecl
deriving instance ToExpr for Item
deriving instance ToExpr for File
end Lanius.Surface
namespace Lanius.Extraction.CoreSynthesis.Program
deriving instance ToExpr for Unit
end Lanius.Extraction.CoreSynthesis.Program

namespace Lanius.Extraction.Self.Lowering
set_option maxRecDepth 4096
set_option maxHeartbeats 2000000
set_option Elab.async false
set_option compiler.extract_closed false

private def mark (message : String) : IO Unit :=
  IO.FS.withFile "target/verified-compiler/self-lowering-phases.log" .append fun handle => do
    handle.putStrLn s!"[{← IO.monoMsNow}] {message}"
    handle.flush

private def generateModules : TermElabM Unit := do
  let mut names : Array Name := #[]
  for index in [0:18] do
    mark s!"module {index} start"
    let within ← Meta.mkDecideProof (← Meta.mkLt (mkNatLit index) (mkNatLit 18))
    let indexValue := mkApp3 (mkConst ``Fin.mk) (mkNatLit 18) (mkNatLit index) within
    let goal := mkApp (mkConst `Lanius.Extraction.Self.Lowering.moduleCorrect) indexValue
    let proof ← Term.elabTermEnsuringType (← `(by kernel_rfl)) goal
    Term.synthesizeSyntheticMVarsNoPostponing
    let proof ← instantiateMVars proof
    let name ← mkAuxDeclName `moduleLowered
    addDecl (.thmDecl { name, levelParams := [], type := goal, value := proof })
    names := names.push name
    mark s!"module {index} checked"
  mark "composing modules"
  let mut proof := mkConst `Lanius.Extraction.Self.Lowering.empty
  for name in names.reverse do
    proof ← Meta.mkAppM ``CoreSynthesis.Program.lowerFunctions_cons #[mkConst name, proof]
  let goal := mkConst `Lanius.Extraction.Self.Lowering.allFunctionsCorrect
  let completedProof ← instantiateMVars proof
  addDecl (.thmDecl {
    name := `Lanius.Extraction.Self.Lowering.allFunctions
    levelParams := [], type := goal, value := completedProof })
  mark "composed function list checked"

private def proposedSurfaces : (units : List Artifact) →
    Option (ArtifactPackChecker.CheckedUnitSurfaces units)
  | [] => some .nil
  | unit :: units => do
    let bytes ← decodeSingleSource unit.sources
    let cache : ArtifactCache := {
      leafCapacity := 16
      parseNodes := proposeSeqTree 16 unit.parse_nodes
      tokens := proposeSeqTree 16 unit.tokens
      primarySourceBytes := proposeSeqTree 16 bytes }
    let view ← cache.checked? unit
    let checked ← checkSurfaceArtifactView? unit view
    return .cons checked (← proposedSurfaces units)

elab "lowering_input%" : term => do
  IO.FS.writeFile "target/verified-compiler/self-lowering-phases.log" ""
  mark "reading self-extraction and source bytes"
  let emitted ← IO.FS.readFile "target/verified-compiler/SelfCompactRequirements.lean"
  let some first := (emitted.splitOn "def encodedPack : String := \"")[1]?
    | throwError "missing compact literal"
  let some encoded := (first.splitOn "\"").head? | throwError "missing literal end"
  let paths ← IO.FS.lines "verified_compiler/source-closure.txt"
  let sources ← paths.toList.mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    return ({path, bytes := bytes.toList.map UInt8.toNat} : SourceFile)
  let some pack := decodeCompactArtifactPack? encoded | throwError "compact proposal failed"
  unless compactPackSources pack == sources do throwError "source bytes differ"
  mark "source bytes checked; proposing indexed Surface data"
  let some data := proposedSurfaces pack.units | throwError "Surface proposal failed"
  let some units := CoreSynthesis.Program.decodeUnitsFrom 0 data | throwError "unit proposal failed"
  mark "quoting proposed Surface units"
  quoteBounded units (compile := false)

noncomputable def units : List CoreSynthesis.Program.Unit := lowering_input%

-- Normalize data constructors, not proofs or function bodies. The result is
-- an untrusted proposal until both its declaration and exact equation pass.
private partial def dataOnly (input : Expr) : MetaM Expr := do
  let rec visit (input : Expr) : MonadCacheT Expr Expr MetaM Expr :=
    checkCache input fun _ => Lean.Core.withIncRecDepth do
      if (← Meta.isProof input) || (← Meta.isType input) then return input
      let value ← Meta.whnf input
      let environment ← getEnv
      match value.getAppFn.constName?.bind environment.find? with
      | some (.ctorInfo _) =>
          let arguments ← value.getAppArgs.mapM visit
          return mkAppN value.getAppFn arguments
      | _ => return value
  visit input |>.run

elab "prepared_data%" : term => do
  mark "materializing preparation data"
  let value ← Meta.withTransparency .all do
    let result ← dataOnly (mkApp (mkConst ``CoreSynthesis.Program.prepareUnits?) (mkConst ``units))
    unless result.isAppOfArity ``Option.some 2 do throwError "declaration preparation rejected"
    pure result.appArg!
  mark "checking materialized declaration"
  return value

noncomputable def frozen : CoreSynthesis.Program.Prepared := prepared_data%
run_elab mark "checking exact preparation equation"
theorem frozen_exact : CoreSynthesis.Program.prepareUnits? units = some frozen := by kernel_rfl
run_elab mark "preparation exact; checking modules"
theorem allocation_count : frozen.allocations.length = 18 := by kernel_rfl

noncomputable def allocation (index : Fin 18) : CoreSynthesis.Program.Allocation :=
  frozen.allocations[index.val]'(by rw [allocation_count]; exact index.isLt)

noncomputable def expectedFunctions (allocation : CoreSynthesis.Program.Allocation) : List Lanius.Core.Function :=
  let count := (ArtifactContextChecker.collectFunctions allocation.unit.surface.items).length +
    (CoreSynthesis.Program.collectExternFunctions allocation.unit.surface.items).length
  (Self.Core.program.functions.drop allocation.functionIdStart).take count

def moduleCorrect (index : Fin 18) : Prop :=
  (CoreSynthesis.Program.lowerFunctions frozen.context [allocation index]).toOption.map (·.core) =
    some (expectedFunctions (allocation index))

theorem empty : (CoreSynthesis.Program.lowerFunctions frozen.context []).toOption.map (·.core) =
    some [] := rfl

def FunctionResult (prepared : CoreSynthesis.Program.Prepared) (functions : List Lanius.Core.Function) : Prop :=
  (CoreSynthesis.Program.lowerFunctions prepared.context prepared.allocations).toOption.map
    (·.core) = some functions

def allFunctionsCorrect : Prop := FunctionResult frozen Self.Core.program.functions

run_elab generateModules

theorem all_lowered :
    (CoreSynthesis.Program.lowerUnits? units).map (·.core) = some Self.Core.program := by
  refine (CoreSynthesis.Program.lowerUnits_of_functions
    (units := units) (prepared := frozen) (functions := Self.Core.program.functions)
    frozen_exact allFunctions).trans ?_
  kernel_rfl

run_elab do
  for assumption in ← Lean.collectAxioms ``all_lowered do
    unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
      throwError "invalid whole-lowering proof: {assumption}"
  mark "whole lowering checked and audited"

end Lanius.Extraction.Self.Lowering
