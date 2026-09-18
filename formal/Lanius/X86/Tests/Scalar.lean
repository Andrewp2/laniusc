import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Harness
import Lanius.X86.Frame.Function
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract
import Lanius.ExecutionRules
import Lanius.X86.Tests.Binary

open Lanius.X86.Tests.Harness
open Lanius.Core Lanius.Semantics Lanius.Separation Lanius.Extraction Lanius.Extraction.CoreSynthesis.Program

private def casesFor (name : String) : List (List Int) :=
  match name with
  | "nested" => [[1, 2, 3], [-7, 11, 19], [2147483647, 2, -1], [-2147483648, -1, 2147483647]]
  | "bits" => [[0, 0], [-1, 305419896], [-2147483648, 2147483647], [65536, -12345]]
  | "quotient" | "remainder" => [[10, 3], [-10, 3], [10, -3], [-10, -3], [-2147483648, 1], [2147483647, -1], [1, 0], [-2147483648, -1]]
  | "shift" => [[1, 0], [1, 31], [-1, 5], [123, -1], [123, 32], [123, 2147483647]]
  | "short_circuit" => [[99, 0], [-1, 0], [30, 4], [-30, 4], [3, 4], [0, 0]]
  | "branches" => [[1, 4], [9, 2], [0, 0], [-1, 1], [2147483647, -1]]
  | "loops" => [[0, 5], [1, 1], [5, 5], [8, 9], [-1, 0], [3, 2]]
  | "stack_arguments" => [[1,2,3,4,5,6,7,8,9], [-1,-2,-3,-4,-5,-6,-7,-8,-9],
      [2147483647, -2147483648, 0, 1, 2, 3, 4, -123, 305419896]]
  | "booleans" => [[0,0,0], [1,0,99], [1,1,7], [1,1,8], [0,1,-1]]
  | "constant" | "literal" => [[]]
  | _ => []

private def valueOf (type : Ty) (value : Int) : Value :=
  if type == .scalar .bool then .boolean (value != 0) else .signed .i32 value

private def machineSteps : Nat → Lanius.X86.Machine.State → Option Lanius.X86.Machine.State
  | 0, state => some state
  | count + 1, state => do
    let bytes := (List.range 15).map fun index => state.memory (state.rip + BitVec.ofNat 64 index)
    let (instruction, size) ← Lanius.X86.Machine.decode bytes
    machineSteps count (Lanius.X86.Machine.execute instruction size state)

/-- Check the proved frame protocol against bytes emitted by the actual
backend. Only setup/teardown run in the machine model here; the separate
native/Core comparison below executes the full function body. -/
private def checkProtocol (name : String) (code : List UInt8) : IO _root_.Unit := do
  let some word := Lanius.X86.Control.displacement? (code.drop 6)
    | throw (IO.userError "missing frame allocation immediate")
  let amount := word.toNat
  unless amount % 16 == 0 && amount ≤ 528384 &&
      code.take 13 == Lanius.X86.Frame.prologue amount &&
      code.drop (code.length - 7) == Lanius.X86.Frame.epilogue ++ [15, 11] do
    throw (IO.userError s!"{name}: emitted frame protocol differs from the proved bytes")
  if name == "literal" && amount != 0 then throw (IO.userError "literal-only function unnecessarily allocates frame slots")
  let image := 4194304
  let stack := 2097160
  let destination := 7340032
  let memory : Lanius.X86.Machine.Memory := fun address =>
    if image ≤ address.toNat then (code[address.toNat - image]?).getD 0 else UInt8.ofNat address.toNat
  let before : Lanius.X86.Machine.State := {
    registers := fun register => if register == 4 then BitVec.ofNat 64 stack
      else BitVec.ofNat 64 (1311768467750121217 + register.val * 257)
    rip := BitVec.ofNat 64 image
    memory := Lanius.X86.Machine.write64 memory (BitVec.ofNat 64 stack) (BitVec.ofNat 64 destination)
    flags := 1538 }
  let some started := machineSteps 4 before | throw (IO.userError "model could not execute emitted prologue")
  unless started.registers 5 == before.registers 4 - 8 &&
      started.registers 4 == before.registers 4 - 8 - BitVec.ofNat 64 amount &&
      (started.registers 4).toNat % 16 == 0 && started.flags.getLsbD 10 == before.flags.getLsbD 10 do
    throw (IO.userError "prologue stack, alignment, or direction flag differs")
  for register in List.finRange 16 do
    if register.val != 4 && register.val != 5 && register.val != 11 then
      unless started.registers register == before.registers register do
        throw (IO.userError "prologue clobbered an argument or preserved register")
  let result : BitVec 64 := 18446744071562067975
  let completed : Lanius.X86.Machine.State := { started with
    registers := fun register => if register == 0 then result else
      if register == 4 then started.registers 4 - 32 else started.registers register
    rip := BitVec.ofNat 64 (image + code.length - 7) }
  let some returned := machineSteps 3 completed | throw (IO.userError "model could not execute emitted epilogue")
  unless returned.registers 0 == result && returned.registers 4 == before.registers 4 + 8 &&
      returned.registers 5 == before.registers 5 && returned.rip == BitVec.ofNat 64 destination &&
      returned.flags == completed.flags do throw (IO.userError "epilogue result, return address, or caller frame differs")
  for register in ([3, 12, 13, 14, 15] : List (Fin 16)) do
    unless returned.registers register == before.registers register do throw (IO.userError "callee-saved register changed")

def main (arguments : List String) : IO UInt32 := do
  Lanius.X86.Tests.Binary.check
  let [backend, modulePath, sourcePath, directory] := arguments
    | throw (IO.userError "expected backend executable, extracted module, exact source file, fixture directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid source pack framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let contents ← IO.FS.readBinFile sourcePath
  let source : SourceFile := ⟨sourcePath, contents.toList.map UInt8.toNat⟩
  let .success checked := checkCompactCoreSourcePack encoded [source]
    | throw (IO.userError "actual scalar source validation failed")
  let mut successes := 0
  let mut traps := 0
  let mut rejected := 0
  for name in ["nested", "bits", "quotient", "remainder", "shift", "short_circuit", "branches", "loops",
      "stack_arguments", "booleans", "constant", "literal"] do
    let some located := checkSourceFunction? checked.program ["examples", "scalars"] name
      | throw (IO.userError s!"missing actual Core function {name}")
    let some words := Lanius.X86.Transport.program? checked.program.core located.function.id
      | throw (IO.userError s!"unsupported Core syntax in {name}")
    let transport := directory / s!"{name}.core"
    IO.FS.writeBinFile transport ⟨(words.flatMap i32Bytes).toArray⟩
    let (status, code) ← outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", transport.toString]
    unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected {name}: status={status}, words={words}")
    unless code.toList.take 5 == [233, 0, 0, 0, 0] do throw (IO.userError "single-function entry jump differs")
    Lanius.X86.Tests.Binary.checkEmitted name code.toList
    checkProtocol name (code.toList.drop 5)
    let binary := directory / s!"{name}.bin"
    IO.FS.writeBinFile binary code
    for values in casesFor name do
      let bindings := located.function.parameters.zip values |>.map fun (parameter, value) => (parameter.1, valueOf parameter.2 value)
      let some body := located.function.body | throw (IO.userError "missing Core body")
      let core := execStmt 5000 checked.program.core (enterCall {} bindings) body
      let assembly := directory / "run.s"
      let object := directory / "run.o"
      let executable := directory / "run"
      IO.FS.writeFile assembly (harness binary located.function.parameters values)
      run "as" #["--64", "-o", object.toString, assembly.toString]
      run "ld" #["-m", "elf_x86_64", "-e", "_start", "-o", executable.toString, object.toString]
      let (nativeStatus, returned) ← outputBytes "timeout" #["--kill-after=1s", "2s", executable.toString]
      match core with
      | .done (.returned (some value)) _ =>
          let expected ← match value with
            | .signed .i32 n => pure n
            | .boolean b => pure (if b then 1 else 0)
            | _ => throw (IO.userError "unexpected Core result")
          unless nativeStatus == 0 && returned.toList == i32Bytes expected ++ [0,0,0,0] do
            throw (IO.userError s!"Core/native mismatch {name}, args={values}, expected={expected}, status={nativeStatus}, bytes={returned.toList}")
          successes := successes + 1
      | .trapped reason _ =>
          let expectedStatus := match reason with
            | .divisionByZero | .signedDivisionOverflow => 136
            | .invalidShift => 132
            | _ => 0
          unless expectedStatus != 0 && nativeStatus == expectedStatus && returned.isEmpty do
            throw (IO.userError s!"Core/native trap mismatch {name}: expected={repr reason}, native={nativeStatus}")
          traps := traps + 1
      | _ => throw (IO.userError s!"Core {name} neither returned nor trapped")
    -- Truncation and impossible header sizes must reject without publishing.
    for bad in [words.take 0, words.take 5, words.dropLast, words ++ [0], words.set 4 2147483647,
        words.set 5 2147483647, words.set 3 99] do
      let path := directory / "bad.core"
      IO.FS.writeBinFile path ⟨(bad.flatMap i32Bytes).toArray⟩
      let (badStatus, unexpected) ← outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", path.toString]
      unless badStatus == 7 && unexpected.isEmpty do
        throw (IO.userError s!"malformed {name} was not rejected cleanly: status={badStatus}")
      rejected := rejected + 1
  IO.println s!"{successes} actual-source Core/native scalar results, {traps} matching arithmetic traps, {rejected} malformed transports; 12 emitted frame protocols match the machine model, including zero-slot allocation; scoped locals, nested loops, short circuit, nine arguments, dirty upper bits, and callee-saved stack/register frames passed"
  pure 0
