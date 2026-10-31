import Lanius.Mini.DetSteps
import Lanius.Mini.Bytes

/-! The SSE code of a float operation (`FOp.opcodeBytes`) as x86 steps: each
instruction decodes, reads no flags and is not a division, so its run is
`Det`; and it leaves `FOp.apply` of rax and rcx in rax, writing no other
general register and no memory. -/

namespace Lanius.X86.Machine

/-- Execute each decoded instruction in turn, each its bytes' length long. -/
def runPlain : List (List UInt8 × Instruction) → State → State
  | [], s => s
  | (bytes, i) :: rest, s => runPlain rest (execute i bytes.length s)

/-- Each instruction decodes from its bytes, is not a division, reads no
flags, and writes no memory, advancing rip by its length. -/
def Plain (prog : List (List UInt8 × Instruction)) : Prop :=
  ∀ p ∈ prog, decode p.1 = some (p.2, p.1.length) ∧ p.2.isDivision = false ∧ p.2.readsFlags = false ∧
    ∀ s : State, (execute p.2 p.1.length s).memory = s.memory ∧
      (execute p.2 p.1.length s).rip = s.rip + BitVec.ofNat 64 p.1.length

theorem runPlain_steps : ∀ (prog : List (List UInt8 × Instruction)) (s : State), Plain prog →
    CodeAt s.memory s.rip (prog.flatMap Prod.fst) →
    Steps prog.length s (runPlain prog s) ∧ Det prog.length s (runPlain prog s)
  | [], s, _, _ => ⟨.refl _, Det.refl _⟩
  | (bytes, i) :: rest, s, plain, loaded => by
    obtain ⟨decoded, nonDivision, noRead, effect⟩ := plain (bytes, i) (by simp)
    have here : CodeAt s.memory s.rip bytes := by
      simp only [List.flatMap_cons] at loaded; exact loaded.prefix
    have step : Step s (execute i bytes.length s) := .decoded bytes here i _ decoded rfl nonDivision
    have later : CodeAt (execute i bytes.length s).memory (execute i bytes.length s).rip
        (rest.flatMap Prod.fst) := by
      rw [(effect s).1, (effect s).2]
      simp only [List.flatMap_cons] at loaded
      exact loaded.suffix
    obtain ⟨run, det⟩ := runPlain_steps rest _ (fun p mem => plain p (by simp [mem])) later
    exact ⟨.cons step run, Det.cons step (NoRead.of here decoded noRead) det⟩

end Lanius.X86.Machine

namespace Lanius.Mini
open Lanius.X86.Machine

def FloatTy.double : FloatTy → Bool
  | .f32 => false
  | .f64 => true

def Word.wide : Word → Bool
  | .s32 => false
  | .u64 => true

def FArith.sse : FArith → SseArith
  | .fAdd => .add
  | .fSub => .sub
  | .fMul => .mul
  | .fDiv => .div

def FCmp.sse : FCmp → SsePredicate
  | .fEq => .eq
  | .fLt => .lt
  | .fLe => .le

/-- movd/movq xmm0, rax; movd/movq xmm1, rcx -/
def floatOperandSteps (t : FloatTy) : List (List UInt8 × Instruction) :=
  [([102] ++ t.rex ++ [15, 110, 192], .moveToXmm t.double 0 0),
   ([102] ++ t.rex ++ [15, 110, 201], .moveToXmm t.double 1 1)]

/-- movd/movq rax, xmm0 -/
def floatResultStep (t : FloatTy) : List UInt8 × Instruction :=
  ([102] ++ t.rex ++ [15, 126, 192], .moveFromXmm t.double 0 0)

/-- The instructions of `FOp.opcodeBytes`. -/
def FOp.program : FOp → List (List UInt8 × Instruction)
  | .basic t operation => floatOperandSteps t ++
      [([t.scalarPrefix, 15, operation.opcode, 193], .sseArith t.double operation.sse 0 1), floatResultStep t]
  | .fCompare t operation => floatOperandSteps t ++
      [([t.scalarPrefix, 15, 194, 193, operation.predicate], .sseCompare t.double operation.sse 0 1),
       ([102, 15, 126, 192], .moveFromXmm false 0 0), ([247, 216], .negate32 0)]
  | .fromInt t word =>
      [([t.scalarPrefix] ++ word.rex ++ [15, 42, 193], .convertInt t.double word.wide 0 1), floatResultStep t]
  | .widen => [([102, 15, 110, 193], .moveToXmm false 0 1), ([243, 15, 90, 192], .convertFloat false 0 0),
      floatResultStep .f64]
  | .narrow => [([102, 72, 15, 110, 193], .moveToXmm true 0 1), ([242, 15, 90, 192], .convertFloat true 0 0),
      floatResultStep .f32]

theorem FOp.program_bytes (operation : FOp) : operation.program.flatMap Prod.fst = operation.opcodeBytes := by
  rcases operation with ⟨t, operation⟩ | ⟨t, operation⟩ | ⟨t, word⟩ | _ | _ <;>
    (try cases t) <;> (try cases operation) <;> (try cases word) <;> rfl

theorem FOp.program_plain (operation : FOp) : Plain operation.program := by
  rcases operation with ⟨t, operation⟩ | ⟨t, operation⟩ | ⟨t, word⟩ | _ | _ <;>
    (try cases t) <;> (try cases operation) <;> (try cases word) <;>
    · intro p mem
      simp only [FOp.program, floatOperandSteps, floatResultStep, List.cons_append, List.nil_append,
        List.mem_cons, List.not_mem_nil, or_false] at mem
      rcases mem with rfl | rfl | rfl | rfl | rfl <;>
        exact ⟨by decide, rfl, rfl, fun _ => ⟨rfl, rfl⟩⟩

theorem setLow32_low (x : BitVec 64) (v : Nat) : (setLow32 x v).toNat % 2 ^ 32 = v % 2 ^ 32 := by
  have := x.isLt
  simp only [setLow32, BitVec.toNat_ofNat]
  omega

theorem FArith.sse_apply (operation : FArith) (F : IEEE.Format) : operation.sse.apply F = operation.apply F := by
  cases operation <;> rfl

theorem FCmp.sse_holds (operation : FCmp) (F : IEEE.Format) : operation.sse.holds F = operation.holds F := by
  cases operation <;> rfl

theorem fin16_ne : ((0 : Fin 16) = 1) = False ∧ ((1 : Fin 16) = 0) = False := by decide

theorem low_low (x : BitVec 64) : (BitVec.ofNat 64 (x.toNat % 2 ^ 32)).toNat % 2 ^ 32 = x.toNat % 2 ^ 32 := by
  have := x.isLt
  simp only [BitVec.toNat_ofNat]
  omega

theorem toNat_mod64 (x : BitVec 64) : x.toNat % 2 ^ 64 = x.toNat := Nat.mod_eq_of_lt x.isLt

theorem ofNat_mod64 (v : Nat) : BitVec.ofNat 64 (v % 2 ^ 64) = BitVec.ofNat 64 v := by
  apply BitVec.eq_of_toNat_eq; simp

theorem FOp.program_acc (operation : FOp) (s : State) :
    (runPlain operation.program s).registers 0 = operation.apply (s.registers 0) (s.registers 1) := by
  rcases operation with ⟨t, operation⟩ | ⟨t, operation⟩ | ⟨t, word⟩ | _ | _ <;>
    (try cases t) <;> (try cases word) <;>
    simp only [FOp.program, floatOperandSteps, floatResultStep, List.cons_append, List.nil_append, runPlain,
      execute, State.moveFromXmm, State.sseArith, State.moveToXmm, State.setXmm, State.sseCompare,
      State.convertInt, State.convertFloat, State.negate] <;>
    simp only [FloatTy.double, Word.wide, if_true, if_false, sseOperand, sseResult, sseFormat, sseMask,
      fin16_ne, setLow32_low, low_low, FOp.apply, FloatTy.word, FloatTy.bits, FloatTy.width, FloatTy.format,
      FArith.sse_apply, FCmp.sse_holds, toNat_mod64, ofNat_mod64, Bool.not_true, Bool.not_false, Bool.false_eq_true]
  all_goals (split <;> first | decide | (rename_i h; simp only [h, ↓reduceIte]; decide))

theorem FOp.program_other (operation : FOp) (s : State) {r : Register} (other : r ≠ 0) :
    (runPlain operation.program s).registers r = s.registers r := by
  rcases operation with ⟨t, operation⟩ | ⟨t, operation⟩ | ⟨t, word⟩ | _ | _ <;>
    (try cases t) <;> (try cases word) <;>
    simp only [FOp.program, floatOperandSteps, floatResultStep, List.cons_append, List.nil_append, runPlain,
      execute, State.moveFromXmm, State.sseArith, State.moveToXmm, State.setXmm, State.sseCompare,
      State.convertInt, State.convertFloat, State.negate, if_neg other]

end Lanius.Mini

namespace Lanius.X86.Machine

theorem runPlain_effect : ∀ (prog : List (List UInt8 × Instruction)) (s : State), Plain prog →
    (runPlain prog s).memory = s.memory ∧
      (runPlain prog s).rip = s.rip + BitVec.ofNat 64 (prog.flatMap Prod.fst).length
  | [], s, _ => ⟨rfl, by simp [runPlain]⟩
  | (bytes, i) :: rest, s, plain => by
    simp only [runPlain]
    obtain ⟨-, -, -, effect⟩ := plain (bytes, i) (by simp)
    obtain ⟨memory, rip⟩ := runPlain_effect rest (execute i bytes.length s)
      (fun p mem => plain p (by simp [mem]))
    refine ⟨memory.trans (effect s).1, ?_⟩
    rw [rip, (effect s).2, List.flatMap_cons, List.length_append, BitVec.ofNat_add (bytes.length), BitVec.add_assoc]

end Lanius.X86.Machine
