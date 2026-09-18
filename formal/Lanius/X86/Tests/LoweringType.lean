import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Memory
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

/-! The source-authenticated Lanius type-lowering component, checked against
the language's primitive namespace and the existing x86 transport boundary.
This is an execution/differential test, not a correctness theorem. -/
namespace Lanius.X86.Tests.LoweringType

open Lanius.Core Lanius.Semantics Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program

private def node (kind first : Int) (token : Int := -1) (next : Int := -1) : List Int :=
  [kind, 0, first, -1, token, -1, -1, next]

private def pathArena (names : List String) : List Int :=
  let segments := names.zipIdx.flatMap fun (_, index) =>
    node 0 (-1) index (if index + 1 < names.length then index + 1 else -1)
  [(names.length : Int) + 2] ++ segments ++ node 1 0 ++ node 2 names.length

private def tokenRows (names : List String) : List Int := Id.run do
  let mut position : Int := 0
  let mut result : List Int := []
  for name in names do
    result := result ++ [1, position, position + name.utf8ByteSize]
    position := position + name.utf8ByteSize + 2
  return result

private structure Case where
  label : String
  source : String
  tokens : List Int
  arena : List Int
  root : Int
  resolutions : List Int := []
  expected : Int
  sourceLength : Option Int := none
  tokenCount : Option Int := none
  arenaLength : Option Int := none
  resolutionLength : Option Int := none
  capacity : Option Int := none

private def path (names : List String) (expected : Int) (resolutions : List Int := []) : Case := {
  label := String.intercalate "::" names
  source := String.intercalate "::" names
  tokens := tokenRows names
  arena := pathArena names
  root := names.length + 1
  resolutions
  expected
}

private def slice (base : Case) (expected : Int) : Case :=
  let count := base.arena.head!.toNat
  { base with
    label := s!"[{base.label}]"
    arena := (base.arena.set 0 (count + 1)) ++ node 4 base.root
    root := count
    expected := expected }

private def multiplePaths (names : List String) (expected : Int) : Case := {
  label := "shared catalog across " ++ String.intercalate "," names
  source := String.intercalate "::" names
  tokens := tokenRows names
  arena := [(names.length : Int) * 3] ++ names.zipIdx.flatMap (fun (_, index) =>
    node 0 (-1) index ++ node 1 (index * 3) ++ node 2 (index * 3 + 1))
  root := names.length * 3 - 1
  expected := expected
}

private def cases : List Case := Id.run do
  let mut result := []
  for name in ["bool", "i8", "i16", "i32", "i64", "isize", "u8", "u16", "u32", "u64",
      "usize", "f32", "f64", "char", "str", "ptr"] do
    let type := Lanius.Elaboration.builtinScalar? name
    let expected := (type.bind fun scalar => Transport.type? (.scalar scalar)).getD (-2)
    result := result ++ [path [name] expected,
      -- Builtins take precedence even when an alias/nominal row claims them.
      path [name] expected [1, 16], slice (path [name] expected) (if expected == 1 then 6 else -2)]
  result := result ++ [path ["Record"] 16 [1, 16], path ["Record"] 2147483647 [1, 2147483647],
    multiplePaths ["i32", "bool", "usize", "ptr", "str"] 5,
    multiplePaths ["str", "i32", "bool", "usize", "ptr"] 4,
    multiplePaths ["i32", "bool", "i64"] (-2),
    path ["Count"] 1 [1, 1], path ["Scan"] 23 [1, 23], path ["Buffer"] 6 [1, 6],
    path ["verified", "lexer", "Scan"] 23 [3, 23],
    path ["other", "i32"] 16 [2, 16], path ["other", "i32"] (-1),
    path ["I32"] (-1), path ["i32suffix"] (-1), path ["Record"] (-1),
    path ["Record"] (-1) [1, 16, 1, 16], path ["Record"] (-1) [1, 16, 1, 17],
    path ["Record"] (-1) [1, 0], path ["Record"] (-1) [1, 7],
    path ["Record"] (-1) [1, 15], path ["Record"] (-1) [0, 16],
    path ["Record"] (-1) [3, 16], path ["Record"] (-1) [1],
    path ["i32"] (-1) [1, 16, 1, 16],
    slice (path ["Count"] 1 [1, 1]) 6, slice (path ["Record"] 16 [1, 16]) (-2),
    slice (slice (path ["i32"] 1) 6) (-2)]
  let base := path ["i32"] 1
  for count in [-1, 0, 4, 2147483647] do
    result := result ++ [{ base with label := s!"bad arena count {count}", arena := base.arena.set 0 count, expected := -1 }]
  for root in [-1, 0, 1, 3, 2147483647] do
    result := result ++ [{ base with label := s!"bad root {root}", root, expected := -1 }]
  for (offset, value) in [(1, 9), (3, 0), (5, -1), (5, 1), (8, 0), (8, 1),
      (11, 1), (11, -1), (19, 2), (19, 0)] do
    let expected := if offset == 3 then -2 else -1
    result := result ++ [{ base with
      label := s!"bad arena field {offset}={value}"
      arena := base.arena.set offset value
      expected := expected }]
  for (offset, value) in [(1, -1), (1, 3), (1, 4), (2, -1), (2, 0), (2, 4)] do
    result := result ++ [{ base with
      label := s!"bad token span {offset}={value}"
      tokens := base.tokens.set offset value
      expected := -1 }]
  for kind in [3, 5] do
    result := result ++ [{ (slice base (-2)) with
      label := s!"unsupported constructor {kind}"
      arena := ((slice base (-2)).arena.set 25 kind) }]
  result := result ++ [{ base with label := "negative source length", sourceLength := some (-1), expected := -1 },
    { base with label := "short source interval", sourceLength := some 2, expected := -1 },
    { base with label := "negative token count", tokenCount := some (-1), expected := -1 },
    { base with label := "empty token prefix", tokenCount := some 0, expected := -1 },
    { base with label := "token count overflow", tokenCount := some 715827883, expected := -1 },
    { base with label := "negative arena length", arenaLength := some (-1), expected := -1 },
    { base with label := "zero arena length", arenaLength := some 0, expected := -1 },
    { base with label := "short arena", arenaLength := some 24, expected := -1 },
    { base with label := "negative resolution length", resolutionLength := some (-1), expected := -1 },
    { base with label := "negative capacity", capacity := some (-1), expected := -1 },
    { base with label := "short output", capacity := some 2, expected := -1 }]
  return result

private def arguments (test : Case) (spare : Nat) : List Value × List (List Int) :=
  let source := test.source.toUTF8.toList.map fun byte => (byte.toNat : Int)
  let output := List.replicate (test.arena.head!.toNat.min 32 + spare) (777 : Int)
  let buffers := [source, test.tokens, test.arena, test.resolutions, output]
  let buffer (index : Nat) := Value.slice (.scalar (.signed .i32)) index [] 0 (buffers[index]!).length
  ([buffer 0, .signed .i32 (test.sourceLength.getD source.length),
    buffer 1, .signed .i32 (test.tokenCount.getD (test.tokens.length / 3)),
    buffer 2, .signed .i32 (test.arenaLength.getD test.arena.length), .signed .i32 test.root,
    buffer 3, .signed .i32 (test.resolutionLength.getD test.resolutions.length),
    buffer 4, .signed .i32 (test.capacity.getD output.length)], buffers)

def main (arguments : List String) : IO UInt32 := do
  let [backend, modulePath, sourcePath, hostPath, directory] := arguments
    | throw (IO.userError "expected backend, lowering extraction, exact source, exact host source, and output directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid lowering fixture framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let sources ← ([sourcePath, hostPath] : List String).mapM fun (path : String) => do
    let source ← IO.FS.readBinFile path
    pure ({ path, bytes := source.toList.map UInt8.toNat } : SourceFile)
  let checked ← match checkCompactCoreSourcePack encoded sources with
    | .success checked => pure checked
    | .failure stage => throw (IO.userError s!"lowering source validation failed: {stage}")
  let program := checked.program.core
  let some located := checkSourceFunction? checked.program ["lowering", "types"] "lower"
    | throw (IO.userError "missing actual lowering::types::lower")
  let some transport := Transport.program? program located.function.id
    | throw (IO.userError "type lowering is not representable by the existing backend")
  let corePath := directory / "types.core"
  IO.FS.writeBinFile corePath ⟨(transport.flatMap i32Bytes).toArray⟩
  let (status, code) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", corePath.toString]
  unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected type lowering: {status}")
  let binary := directory / "types.bin"
  IO.FS.writeBinFile binary code
  let mut count := 0
  for test in cases do
    let (args, buffers) := LoweringType.arguments test 3
    let initial := Memory.state buffers
    match evalExpr 20000 program initial (.call located.function.id (args.map Expr.value)) with
    | .done (.signed .i32 value) after =>
      unless value == test.expected do
        throw (IO.userError s!"{test.label}: returned {value}, expected {test.expected}")
      unless after.heap.blocks.length <= 1 do
        throw (IO.userError s!"{test.label}: allocated the builtin catalog more than once")
      for index in [0, 1, 2, 3] do
        unless after.cell? index == initial.cell? index do
          throw (IO.userError s!"{test.label}: changed input buffer {index}")
      let some (.array output) := after.cell? 4
        | throw (IO.userError s!"{test.label}: missing output buffer")
      unless output.drop (buffers[4]!.length - 3) == List.replicate 3 (.signed .i32 777) do
        throw (IO.userError s!"{test.label}: changed spare output capacity")
      if value > 0 then
        unless output[test.root.toNat]? == some (.signed .i32 value) do
          throw (IO.userError s!"{test.label}: root tag does not match returned type")
    | _ => throw (IO.userError s!"{test.label}: source lowering trapped or exhausted fuel")
    if ← Memory.check program located.function.id binary directory args buffers test.label then
      throw (IO.userError s!"{test.label}: unexpected native trap")
    count := count + 1
  IO.println s!"{count} source-authenticated Core/native type-lowering cases: complete primitive precedence, x86 representability, slices, qualified/alias resolutions, malformed records, capacity and input/output framing"
  pure 0

end Lanius.X86.Tests.LoweringType

def main := Lanius.X86.Tests.LoweringType.main
