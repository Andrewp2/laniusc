import Lanius.X86.Machine.Scalar
import Lanius.Mini.Compiler

/-! The x86 model's `decode` and `execute`, compiled, for
formal/tools/x86_model_test.py, which compares them with this CPU.

    lake exe x86ModelTest CASES RESULTS

Runs them on the states in CASES (one per line, as `runCase` reads them)
and writes the results to RESULTS, then the bytes of every mini compiler
instruction form. -/

namespace Lanius.Tools.X86ModelTest
open Lanius.X86.Machine

def digit (c : Char) : Nat :=
  if c.isDigit then c.toNat - 48 else c.toLower.toNat - 87

def hexNat (s : String) : Nat :=
  s.foldl (fun acc c => acc * 16 + digit c) 0

def hexBytes (s : String) : ByteArray := Id.run do
  let cs := s.toList.toArray
  let mut out := ByteArray.empty
  for i in [0:cs.size / 2] do
    out := out.push (UInt8.ofNat (digit cs[2 * i]! * 16 + digit cs[2 * i + 1]!))
  return out

def hexChar (n : Nat) : Char :=
  if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)

def showByte (b : UInt8) : String :=
  String.ofList [hexChar (b.toNat / 16), hexChar (b.toNat % 16)]

def showNat (n : Nat) : String :=
  String.ofList (Nat.toDigits 16 n)

def initial (regs : Array Nat) (rip flags base : Nat) (mem : ByteArray) (x0 x1 : Nat) : State :=
  { registers := fun r => BitVec.ofNat 64 (regs.getD r.val 0)
    xmm := fun r => if r.val = 0 then BitVec.ofNat 64 x0 else if r.val = 1 then BitVec.ofNat 64 x1 else 0
    rip := BitVec.ofNat 64 rip
    memory := fun a =>
      let n := a.toNat
      if base ≤ n ∧ n - base < mem.size then mem.get! (n - base) else 0
    flags := BitVec.ofNat 64 flags }

/-- `id bytes rip flags base mem tail r0 .. r15 xmm0 xmm1`, all hex. -/
def runCase (line : String) : String :=
  let f := (line.splitOn " ").toArray
  let ident := f[0]!
  let bytes := (hexBytes f[1]!).toList
  let rip := hexNat f[2]!
  let flags := hexNat f[3]!
  let base := hexNat f[4]!
  let mem := hexBytes f[5]!
  let tail := (hexBytes f[6]!).toList
  let regs := (f.extract 7 23).map hexNat
  let s := initial regs rip flags base mem (hexNat f[23]!) (hexNat f[24]!)
  match decode bytes with
  | none => ident ++ " none"
  | some (instruction, size) =>
    let prefixes := (List.range bytes.length).all fun k => decode (bytes.take k) == none
    let tailed := decode (bytes ++ tail) == some (instruction, size)
    let after := execute instruction size s
    let regsOut := (List.range 16).map fun r =>
      if h : r < 16 then showNat (after.registers ⟨r, h⟩).toNat else "0"
    let memOut := String.join ((List.range mem.size).map fun i =>
      showByte (after.memory (BitVec.ofNat 64 (base + i))))
    let shown := (toString (repr instruction)).replace "\n" " "
    ident ++ " some " ++ toString size ++ " " ++ toString prefixes ++ " " ++ toString tailed ++ " " ++
      toString instruction.isDivision ++ " " ++ " ".intercalate regsOut ++ " " ++
      showNat after.rip.toNat ++ " " ++ showNat after.flags.toNat ++ " " ++ memOut ++ " " ++
      showNat (after.xmm 0).toNat ++ " " ++ showNat (after.xmm 1).toNat ++ " | " ++ shown

def bytesHex (bytes : List UInt8) : String := String.join (bytes.map showByte)

open Lanius.Mini in
def encodings : List (String × List UInt8) :=
  let place : Place := { body := 4096, slots := 9, entries := [0, 2000, 3000] }
  let words := [Word.s32, Word.u64]
  let binops := [BinOp.add, BinOp.sub, BinOp.mul, BinOp.and, BinOp.or, BinOp.xor, BinOp.shl, BinOp.shr, BinOp.sar]
  let cmpops := [CmpOp.eq, CmpOp.ne, CmpOp.lt, CmpOp.le, CmpOp.gt, CmpOp.ge]
  let ops := words.flatMap fun w => binops.map fun o => (s!"op {repr w} {repr o}", Instr.op w o 3)
  let cmps := words.flatMap fun w => cmpops.map fun o => (s!"cmp {repr w} {repr o}", Instr.cmp w o 1048575)
  let divops := [DivOp.sDiv, DivOp.sRem, DivOp.uDiv, DivOp.uRem]
  let divs := words.flatMap fun w => divops.map fun o => (s!"div {repr w} {repr o}", Instr.div w o 5)
  let rest : List (String × Instr) :=
    [("imm", .imm 0x123456789abcdef0), ("load", .load 0), ("load far", .load 1048575),
     ("store", .store 7), ("neg", .neg), ("jmp back", .jmp 0), ("jmp", .jmp 900),
     ("jz", .jz 50), ("call", .call 1 [0, 1, 2] 3 2), ("ret", .ret [0, 1]),
     ("bump 0", .bump 0), ("bump 3", .bump 3), ("bump 31", .bump 31),
     ("loadAt", .loadAt), ("storeAt", .storeAt 4),
     ("loadWordAt m32", .loadWordAt .m32), ("loadWordAt m64", .loadWordAt .m64),
     ("storeWordAt m32", .storeWordAt .m32 4), ("storeWordAt m64", .storeWordAt .m64 4)]
  let fts := [FloatTy.f32, FloatTy.f64]
  let fops : List (String × Instr) :=
    (fts.flatMap fun t => [FArith.fAdd, .fSub, .fMul, .fDiv].map fun o =>
        (s!"fp {repr t} {repr o}", Instr.fp (.basic t o) 3)) ++
    (fts.flatMap fun t => [FCmp.fEq, .fLt, .fLe].map fun o =>
        (s!"fp {repr t} {repr o}", Instr.fp (.fCompare t o) 3)) ++
    (fts.flatMap fun t => words.map fun w => (s!"fp fromInt {repr t} {repr w}", Instr.fp (.fromInt t w) 3)) ++
    [("fp widen", Instr.fp .widen 3), ("fp narrow", Instr.fp .narrow 3)]
  (ops ++ cmps ++ divs ++ rest ++ fops).map (fun (n, i) => (n, Instr.encode i place 100)) ++
    [("prologue", prologue 5), ("prologue big", prologue 1048576), ("epilogue", epilogue)]

def run (cases results : String) : IO Unit := do
  let text ← IO.FS.readFile cases
  let lines := (text.splitOn "\n").filter (· ≠ "")
  let out := lines.map runCase
  let enc := encodings.map fun (n, b) => "enc " ++ n.replace " " "_" ++ " " ++ bytesHex b
  IO.FS.writeFile results ("\n".intercalate (out ++ enc) ++ "\n")

end Lanius.Tools.X86ModelTest

def main (args : List String) : IO UInt32 := do
  match args with
  | [cases, results] => Lanius.Tools.X86ModelTest.run cases results; return 0
  | _ => IO.eprintln "usage: x86ModelTest CASES RESULTS"; return 2
