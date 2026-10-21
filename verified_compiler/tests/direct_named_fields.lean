import Lanius.Execution
import Lanius.Compiler.DirectCoreCheck
import GeneratedDirectCore

open Lanius Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface

-- Proof-side construction with imported labels follows source field names,
-- even when written in the reverse of their declaration order.
open Extracted.«app::records».Types in
private def reconstructed : Function [] Outer :=
  function (id := 100, name := "reconstructed", arguments := [], bindings := []) do
    return { value := { value := 7, ignored := 99 : Inner } : Outer }

example :
    (match extractedProgram.function? extractedEntrypoint with
      | some { body := some (.letLocal _ _ initializer _), .. } => some initializer
      | _ => none) =
    (match reconstructed.core.body with
      | some (.returnValue value) => value
      | _ => none) := rfl

example : (match Execution.run 128
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 7) _ => true
  | _ => false) = true := by decide

def main (paths : List String) : IO UInt32 := do
  let sources ← paths.mapM fun path => do
    let bytes ← IO.FS.readBinFile (System.FilePath.mk path)
    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : Extraction.SourceFile)
  let check := fun program => Compiler.DirectCoreCheck.checkTyped
    (extractedFrontend sources) sources program extractedEntrypoint (fun _ => none)
  match check extractedProgram with
  | .error failure =>
      IO.eprintln s!"source-shaped fields do not match source/Core semantics: {repr failure}"
      return 1
  | .ok _ => pure ()
  let some selected := extractedProgram.functions[1]? | return 2
  let some (.returnValue (some (.field base 1))) := selected.body | return 3
  let wrong := { selected with body := some (.returnValue (some (.field base 0))) }
  let altered := { extractedProgram with
    functions := extractedProgram.functions.set 1 wrong }
  let some entry := extractedProgram.functions[0]? | return 6
  let some (.letLocal id ty (.structValue outer [.structValue inner [left, right]]) tail) :=
    entry.body | return 7
  let swapped := { entry with body := some (.letLocal id ty
      (.structValue outer [.structValue inner [right, left]]) tail) }
  let wrongValues := { extractedProgram with
    functions := extractedProgram.functions.set 0 swapped }
  -- Both mutations preserve typing. Source agreement must reject the wrong
  -- field ordinal as well as swapping same-typed constructor values.
  for (label, candidate) in [("field", altered), ("constructor", wrongValues)] do
    if (Typing.Check.checkProgramWellTyped candidate).isNone then
      IO.eprintln s!"{label} mutation unexpectedly changed the program's typing"
      return 5
    match check candidate with
    | .error (.lowering .missingBodies) => pure ()
    | _ =>
        IO.eprintln s!"source/Core checking did not reject the wrong {label}"
        return 4
  IO.println "nested records agree with source; same-typed field and initializer mutations rejected"
  return 0
