import Lanius.Extraction.ExtractorContract
import Lanius.Extraction.CoreDecode
import Lanius.Core.Relocation.Permutation
import Lanius.Core.Relocation.Program
import Lanius.Semantics.Relocation.Execution
import Lanius.Extraction.ArtifactPackChecker

/-! Check exact frontend relocation and the assumptions of the generic
execution-transport theorem against the actual self-embedding. This is not
the whole extractor's correctness proof. -/

open Lanius Lanius.Core Lanius.Extraction Lanius.Extraction.ExtractorContract
open Lanius.Extraction.EntrypointAnalysis

private structure Offsets where
  function : Nat
  constant : Nat
  typeId : Nat
  typeCount : Nat

private def Offsets.symbols (offsets : Offsets) : Relocation.Symbols :=
  ⟨Relocation.rotateTypes offsets.typeId offsets.typeCount,
    (offsets.function + ·), (offsets.constant + ·)⟩

def main (arguments : List String) : IO UInt32 := do
  let modulePath :: oldDirectory :: paths := arguments
    | throw (IO.userError "expected self-module, old artifact directory, then ordered source paths")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith modulePrefix && emitted.endsWith moduleSuffix do
    throw (IO.userError "self-module framing differs from the extraction contract")
  let encoded := ((emitted.drop modulePrefix.length).dropEnd moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : SourceFile)
  let .success checked := checkExtractorCoreSourcePack encoded sources
    | throw (IO.userError "self-embedding rejected")
  let mut mismatches := 0
  for name in ["lexer", "token_scan", "parser"] do
    let some allocation := checked.checked.program.prepared.allocations.find?
        (fun allocation => allocation.unit.modulePath == ["verified", name])
      | throw (IO.userError s!"{name} module not found")
    let oldPath := System.FilePath.mk oldDirectory / (name ++ ".json")
    let oldJson ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile oldPath))
    let oldCore ← IO.ofExcept (oldJson.getObjValAs? CoreProgram "core_program")
    unless CoreDecode.target oldCore.target == checked.checked.program.core.target do
      throw (IO.userError s!"{name} target differs")
    let offsets : Offsets := ⟨allocation.functionIdStart, allocation.constantIdStart,
      allocation.structureTypeStart, oldCore.structures.length⟩
    let some matching := Relocation.checkProgram? offsets.symbols (CoreDecode.program oldCore)
        checked.checked.program.core
      | throw (IO.userError s!"{name} proof-producing lookup check rejected relocation")
    let some ⟨internal⟩ := Semantics.Relocation.Execution.checkInternal? (CoreDecode.program oldCore)
      | throw (IO.userError s!"{name} requires an external-call transport contract")
    have _preserved : ∀ {before expr value after},
        Semantics.Evaluates (CoreDecode.program oldCore) before expr value after →
        Semantics.Evaluates checked.checked.program.core
          (Semantics.Relocation.state offsets.symbols before) (Relocation.expression offsets.symbols expr)
          (Relocation.value offsets.symbols value) (Semantics.Relocation.state offsets.symbols after) :=
      Semantics.Relocation.Execution.evaluates matching
        (Relocation.rotateTypes_injective offsets.typeId offsets.typeCount) internal
    IO.println s!"{name} relocation offsets: functions={offsets.function}, constants={offsets.constant}, structures={offsets.typeId}"
    let mut matched := 0
    for oldWire in oldCore.functions do
      let old := CoreDecode.function oldWire
      let some current := checked.checked.program.core.function? (offsets.function + old.id)
        | throw (IO.userError s!"missing relocated {name} function {old.id}")
      if Relocation.function offsets.symbols old == current then
        matched := matched + 1
      else
        IO.println s!"{name} function {old.id}: differs after relocation"
        mismatches := mismatches + 1
    IO.println s!"{matched}/{oldCore.functions.length} old {name} functions match"
    for oldWire in oldCore.constants do
      let old := CoreDecode.constant oldWire
      let some current := checked.checked.program.core.constant? (offsets.constant + old.id)
        | throw (IO.userError s!"missing relocated {name} constant {old.id}")
      unless Relocation.constant offsets.symbols old == current do
        throw (IO.userError s!"{name} constant {old.id} differs after relocation")
    for oldWire in oldCore.structures do
      let old := CoreDecode.structDecl oldWire
      let some current := checked.checked.program.core.structure? (offsets.typeId + old.id)
        | throw (IO.userError s!"missing relocated {name} structure {old.id}")
      unless old.fields.map (Relocation.ty offsets.symbols) == current.fields do
        throw (IO.userError s!"{name} structure {old.id} differs after relocation")
    IO.println s!"{name}: {oldCore.constants.length} constants and {oldCore.structures.length} structure layouts match"
  IO.println "Execution-transport assumptions checked for all three internal frontend modules."
  let packJson ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile
    (System.FilePath.mk oldDirectory / "frontend_pack.json")))
  let oldUnits ← IO.ofExcept (packJson.getObjValAs? (List Lean.Json) "units")
  let mut wire : Option CoreProgram := none
  let mut functions : List (Nat × Nat) := []
  let mut constants : List (Nat × Nat) := []
  let mut types : List (Nat × Nat) := []
  for unitJson in oldUnits do
    let sources ← IO.ofExcept (unitJson.getObjValAs? (List SourceFile) "sources")
    let some source := sources.head? | throw (IO.userError "old frontend unit has no source")
    let name := (((source.path.splitOn "/").getLast!).dropEnd 5).toString
    let some allocation := checked.checked.program.prepared.allocations.find?
        (fun allocation => allocation.unit.modulePath == ["verified", name])
      | throw (IO.userError s!"merged frontend module {name} not found")
    let fragment ← IO.ofExcept (unitJson.getObjValAs? CoreProgram "core_program")
    wire ← match wire with
      | none => pure (some fragment)
      | some previous =>
          let some merged := ArtifactPackChecker.appendCorePrograms? previous fragment
            | throw (IO.userError "old merged frontend targets disagree")
          pure (some merged)
    let surface ← IO.ofExcept (unitJson.getObjValAs? SurfaceFile "surface")
    let sourceFunctions := ScopedSurface.collectFunctions surface.value.items
    unless sourceFunctions.length == fragment.functions.length do
      throw (IO.userError s!"{name} old source/Core function counts disagree")
    for (declaration, (_, sourceFunction)) in fragment.functions.zip sourceFunctions do
      let some current := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
          ["verified", name] sourceFunction.name.text
        | throw (IO.userError s!"{name}::{sourceFunction.name.text} was not found in the checked source")
      functions := functions ++ [(declaration.id, current.source.id)]
    constants := constants ++ fragment.constants.zipIdx.map
      (fun (declaration, index) => (declaration.id, allocation.constantIdStart + index))
    types := types ++ fragment.structures.zipIdx.map
      (fun (declaration, index) => (declaration.id, allocation.structureTypeStart + index))
    unless fragment.enumerations.isEmpty do
      throw (IO.userError "merged frontend enumeration mapping needs an explicit allocation")
  let some mergedWire := wire | throw (IO.userError "old merged frontend is empty")
  let lookup := fun (entries : List (Nat × Nat)) (id : Nat) =>
    ((entries.find? fun pair => pair.1 == id).map Prod.snd).getD id
  let symbols : Relocation.Symbols := ⟨Relocation.permuteTypes types, lookup functions, lookup constants⟩
  let oldProgram := CoreDecode.program mergedWire
  let some matching := Relocation.checkProgram? symbols oldProgram checked.checked.program.core
    | do
      for function in oldProgram.functions do
        let current := checked.checked.program.core.function? (symbols.functionId function.id)
        unless current == some (Relocation.function symbols function) do
          IO.println s!"merged frontend function {function.id} differs at destination {symbols.functionId function.id}"
      throw (IO.userError "merged frontend proof-producing relocation check rejected")
  let some ⟨internal⟩ := Semantics.Relocation.Execution.checkInternal? oldProgram
    | throw (IO.userError "merged frontend requires an external-call contract")
  have _preserved : ∀ {before expr value after}, Semantics.Evaluates oldProgram before expr value after →
      Semantics.Evaluates checked.checked.program.core (Semantics.Relocation.state symbols before)
        (Relocation.expression symbols expr) (Relocation.value symbols value)
        (Semantics.Relocation.state symbols after) :=
    Semantics.Relocation.Execution.evaluates matching (Relocation.permuteTypes_injective types) internal
  IO.println s!"Merged frontend: {oldProgram.functions.length} functions and {oldProgram.constants.length} constants have checked execution transport."
  IO.println "The whole extractor contract and public frontend contract instantiation remain separate obligations."
  return if mismatches == 0 then 0 else 1
