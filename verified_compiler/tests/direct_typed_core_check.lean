import Lanius.Compiler.DirectCoreCheck
import GeneratedDirectCore

open Lanius Lanius.Extraction Lanius.Core

private def changeAssignment : Stmt → Stmt
  | .expression (.assign .set target value) => .expression (.assign .add target value)
  | .sequence first second => .sequence (changeAssignment first) (changeAssignment second)
  | .letLocal id ty value body => .letLocal id ty value (changeAssignment body)
  | .letUninitialized id ty body => .letUninitialized id ty (changeAssignment body)
  | .whileLoop condition body => .whileLoop condition (changeAssignment body)
  | .ifThenElse condition first second =>
      .ifThenElse condition (changeAssignment first) (changeAssignment second)
  | other => other

private def changeDivision : Stmt → Stmt
  | .returnValue (some (.binary .divide left right)) =>
      .returnValue (some (.binary .remainder left right))
  | other => other

private def changeString : Stmt → Stmt
  | .returnValue (some (.value (.string value))) =>
      .returnValue (some (.value (.string (value ++ "!"))))
  | other => other

private def initializeLocal : Stmt → Stmt
  | .letUninitialized id (.scalar (.signed .i32)) body =>
      .letLocal id (.scalar (.signed .i32)) (.value (.signed .i32 0)) body
  | .sequence first second => .sequence (initializeLocal first) (initializeLocal second)
  | .letLocal id ty value body => .letLocal id ty value (initializeLocal body)
  | other => other

def checkDirect (sources : List SourceFile) (program : Program)
    (entrypoint : FunctionId) (expected : Lanius.Compiler.DirectCoreCheck.TypedFailure)
    (resolver : Lanius.Compiler.ProgramLowering.ExternalBehaviorResolver :=
      Lanius.Compiler.RuntimeImports.resolve) : IO UInt32 := do
  match Lanius.Compiler.DirectCoreCheck.checkTyped
      (extractedFrontend sources) sources program entrypoint resolver with
  | .error failure =>
      if failure == expected then
        IO.println s!"typed direct checker rejected as expected: {repr failure}"
        return 0
      IO.eprintln s!"unexpected typed direct rejection: {repr failure}"
      return 1
  | .ok _ =>
      IO.eprintln "typed direct checker accepted a deliberate mismatch"
      return 1

def main (args : List String) : IO UInt32 := do
  let (mode, paths) := match args with
    | "--wrong-entry" :: paths => (1, paths)
    | "--mutate-return" :: paths => (2, paths)
    | "--mutate-assignment" :: paths => (3, paths)
    | "--mutate-division" :: paths => (4, paths)
    | "--mutate-string" :: paths => (5, paths)
    | "--mutate-initializer" :: paths => (6, paths)
    | "--mutate-constant" :: paths => (7, paths)
    | "--mutate-runtime" :: paths => (8, paths)
    | paths => (0, paths)
  if paths.isEmpty then
    IO.eprintln "usage: direct_typed_core_check [--wrong-entry|--mutate-return|--mutate-assignment|--mutate-division|--mutate-string|--mutate-initializer|--mutate-constant|--mutate-runtime] SOURCE..."
    return 1
  let sources ← paths.mapM fun path => do
    let bytes ← IO.FS.readBinFile (System.FilePath.mk path)
    let source : SourceFile :=
      { path, bytes := bytes.toList.map UInt8.toNat }
    pure source
  if mode == 1 then
    return ← checkDirect sources extractedProgram (extractedEntrypoint + 1) .entrypoint
  if mode == 8 then
    let mut tested := 0
    for selected in extractedProgram.functions do
      let external := match selected.external with
        | some (.host .openRead) => some (.host .writeStdout)
        | some (.host .writeStdout) => some (.host .openRead)
        | some (.host .close) => some (.host .argLen)
        | some (.host .argLen) => some (.host .close)
        | some (.host .read) => some (.host .argRead)
        | some (.host .argRead) => some (.host .read)
        | other => other
      if external == selected.external then continue
      let changed := extractedProgram.functions.map fun declaration =>
        if declaration.id == selected.id then { declaration with external } else declaration
      let candidate := { extractedProgram with functions := changed }
      if (Typing.Check.checkProgramWellTyped candidate).isNone then
        IO.eprintln "runtime substitution must preserve typing"
        return 1
      let result ← checkDirect sources candidate extractedEntrypoint (.lowering .missingExternals)
      if result != 0 then return result
      -- Even a policy that agrees with the tampered Core cannot override the ABI.
      let result ← checkDirect sources candidate extractedEntrypoint (.lowering .missingExternals)
        (fun header => (candidate.functions.find? (·.id == header.declaration)).bind (·.external))
      if result != 0 then return result
      tested := tested + 1
    if tested == 0 then
      IO.eprintln "runtime fixture must contain services with identical signatures"
      return 1
    IO.println s!"rejected {tested} same-signature runtime substitutions, including forged policies"
    return 0
  if mode == 7 then
    match Lanius.Compiler.DirectCoreCheck.checkTyped
        (extractedFrontend sources) sources extractedProgram extractedEntrypoint Lanius.Compiler.RuntimeImports.resolve with
    | .error failure =>
        IO.eprintln s!"unmodified constant fixture must pass: {repr failure}"
        return 1
    | .ok _ => pure ()
    let mut tested := 0
    for selected in extractedProgram.constants do
      let value := match selected.value with
        | .signed type value => .signed type (if value == 0 then 1 else 0)
        | .unsigned type value => .unsigned type (if value == 0 then 1 else 0)
        | .boolean value => .boolean (!value)
        | .string value => .string (value ++ "!")
        | .pointer address => .pointer (if address == 0 then 1 else 0)
        | other => other
      if value == selected.value then continue
      let changed := extractedProgram.constants.map fun declaration =>
        if declaration.id == selected.id then { declaration with value } else declaration
      let candidate := { extractedProgram with constants := changed }
      if (Typing.Check.checkProgramWellTyped candidate).isNone then
        IO.eprintln "constant mutation must preserve typing"
        return 1
      let result ← checkDirect sources candidate extractedEntrypoint (.lowering .missingConstants)
      if result != 0 then return result
      tested := tested + 1
    if tested == 0 then
      IO.eprintln "constant fixture must exercise at least one changed value"
      return 1
    IO.println s!"rejected {tested} independently changed constant values"
    return 0
  if mode == 2 then
    match extractedProgram.functions with
    | [function] =>
        let wrong : Function := { function with
          body := some (.returnValue (some (.value (.signed .i32 43)))) }
        let wrongProgram : Program :=
          { extractedProgram with functions := [wrong] }
        return ← checkDirect sources wrongProgram extractedEntrypoint
          (.lowering .missingBodies)
    | _ =>
        IO.eprintln "return mutation requires a one-function fixture"
        return 1
  if mode == 3 || mode == 4 || mode == 5 || mode == 6 then
    let change := match mode with
      | 3 => changeAssignment
      | 4 => changeDivision
      | 6 => initializeLocal
      | _ => changeString
    let changed := extractedProgram.functions.map fun decl =>
      { decl with body := decl.body.map change }
    let candidate := { extractedProgram with functions := changed }
    if candidate == extractedProgram || (Typing.Check.checkProgramWellTyped candidate).isNone then
      IO.eprintln "mutation must change behavior while preserving typing"
      return 1
    return ← checkDirect sources candidate extractedEntrypoint (.lowering .missingBodies)
  match Lanius.Compiler.DirectCoreCheck.checkTyped
      (extractedFrontend sources) sources extractedProgram extractedEntrypoint
      Lanius.Compiler.RuntimeImports.resolve with
  | .error failure =>
      IO.eprintln s!"typed source-to-Core rejected: {repr failure}"
      return 1
  | .ok checked =>
      let _ := Lanius.Compiler.DirectCoreCheck.checked_typed_source_and_program checked
      let _ := Lanius.Compiler.DirectCoreCheck.typed_emitted_executable_wellFormed checked
      IO.println "direct Lean frontend, Core, and entrypoint accepted without compact artifact"
      return 0
