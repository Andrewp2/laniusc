import Lanius.Mini.Grows

/-! Core's heap and the mini heap.

Core allocates blocks at increasing addresses from `nextAddress`, with no
budget; the mini heap keeps one byte per address and a bump cursor. They
agree when the cursor is Core's `nextAddress`, every live block's bytes sit at
its addresses, and the bytes from the cursor up are zero (Core's fresh blocks
are zeroed, the bump allocator's are not). The blocks lie below the cursor,
in address order, without overlapping. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Memory (Block)
open Lanius.Semantics (State evalExpr evalExprs)

/-- `omega` through `Address`, which it does not unfold. -/
macro "addr_omega" : tactic => `(tactic| ((try simp only [Lanius.Address] at *) <;> omega))

/-- The bytes a trace wrote to `fd`, in order. -/
def outputOf (fd : Nat) : List Lanius.X86.Machine.Event → List UInt8
  | [] => []
  | .write target bytes :: rest =>
      (if target = fd then bytes else []) ++ outputOf fd rest

theorem outputOf_append (fd : Nat) (first second : List Lanius.X86.Machine.Event) :
    outputOf fd (first ++ second) = outputOf fd first ++ outputOf fd second := by
  induction first with
  | nil => rfl
  | cons event rest ih =>
      cases event with
      | write target bytes =>
          simp only [List.cons_append, outputOf, ih, List.append_assoc]

theorem outputOf_write (fd target : Nat) (bytes : List UInt8) :
    outputOf fd [.write target bytes] = if target = fd then bytes else [] := by
  simp only [outputOf, List.append_nil]

/-- Core's heap `h` and world `w`, and the mini heap `hp` with its trace. The
world's standard output and error are what the trace wrote to fds 1 and 2
(roadmap F8), its standard input is what the process has still to read, and
no file is open, so a `write_byte` to another handle returns -1. -/
structure HeapCorr (h : Memory.Heap) (w : World.State) (hp : Heap) : Prop where
  cursor : hp.cursor = h.nextAddress
  pos : 1 ≤ h.nextAddress
  unbounded : h.remaining = none
  small : hp.limit < 2 ^ 62
  sized : ∀ b ∈ h.blocks, b.bytes.length = b.size
  below : ∀ b ∈ h.blocks, b.base + max b.size 1 ≤ h.nextAddress
  apart : ∀ b ∈ h.blocks, ∀ b' ∈ h.blocks, b.base < b'.base → b.base + b.size ≤ b'.base
  unique : ∀ b ∈ h.blocks, ∀ b' ∈ h.blocks, b.base = b'.base → b = b'
  bytes : ∀ b ∈ h.blocks, b.live = true → ∀ i (lt : i < b.bytes.length), hp.bytes (b.base + i) = b.bytes[i]
  zero : ∀ a, h.nextAddress ≤ a → hp.bytes a = 0
  out : w.standardOutput = outputOf 1 hp.io.trace
  err : w.standardError = outputOf 2 hp.io.trace
  closed : w.fileHandles = []
  input : w.standardInput = hp.io.input

/-- Frame memory starts at the limit. -/
theorem HeapCorr.topped {h : Memory.Heap} {w : World.State} {hp : Heap} (_ : HeapCorr h w hp) :
    hp.limit ≤ hp.top :=
  hp.limit_le_top

/-- The correspondence does not see the frame pointer. -/
theorem HeapCorr.withFsp {h : Memory.Heap} {w : World.State} {hp : Heap} (hc : HeapCorr h w hp) (fsp : Nat) :
    HeapCorr h w { hp with fsp := fsp } :=
  ⟨hc.cursor, hc.pos, hc.unbounded, hc.small, hc.sized, hc.below, hc.apart, hc.unique, hc.bytes, hc.zero,
    hc.out, hc.err, hc.closed, hc.input⟩

/-! ## Lists of blocks -/

theorem setByte_length : ∀ (bs : List UInt8) (i : Nat) (v : UInt8), (Memory.setByte bs i v).length = bs.length
  | [], _, _ => rfl
  | _ :: _, 0, _ => rfl
  | _ :: rest, i + 1, v => by simp [Memory.setByte, setByte_length rest i v]

theorem setByte_get : ∀ (bs : List UInt8) (i : Nat) (v : UInt8) (j : Nat) (lt : j < (Memory.setByte bs i v).length),
    (Memory.setByte bs i v)[j] = if j = i then v else bs[j]'(by rw [setByte_length] at lt; exact lt)
  | [], _, _, _, lt => by simp [Memory.setByte] at lt
  | _ :: _, 0, _, 0, _ => by simp [Memory.setByte]
  | _ :: _, 0, _, j + 1, _ => by simp [Memory.setByte]
  | _ :: _, i + 1, _, 0, _ => by simp [Memory.setByte]
  | _ :: rest, i + 1, v, j + 1, lt => by
    simp only [Memory.setByte, List.getElem_cons_succ]
    rw [setByte_get rest i v j]
    simp

theorem mem_replaceBlock : ∀ {bs : List Block} {r b : Block}, b ∈ Memory.replaceBlock bs r →
    b = r ∨ (b ∈ bs ∧ b.base ≠ r.base)
  | [], _, _, mem => by simp [Memory.replaceBlock] at mem
  | c :: rest, r, b, mem => by
    simp only [Memory.replaceBlock, List.mem_cons] at mem
    rcases mem with eq | mem
    · by_cases same : c.base = r.base
      · simp only [same, beq_self_eq_true, ite_true] at eq
        exact .inl eq
      · simp only [beq_iff_eq, same, ite_false] at eq
        exact .inr ⟨eq ▸ List.mem_cons_self .., eq ▸ same⟩
    · rcases mem_replaceBlock mem with eq | ⟨mem', ne⟩
      · exact .inl eq
      · exact .inr ⟨List.mem_cons_of_mem _ mem', ne⟩

theorem find?_mem {bs : List Block} {p : Block → Bool} {b : Block} (found : bs.find? p = some b) :
    b ∈ bs ∧ p b = true :=
  ⟨List.mem_of_find?_eq_some found, List.find?_some found⟩

/-- What a successful `loadByte` or `storeByte` found: a live block holding
the address. -/
theorem containing {h : Memory.Heap} {a : Nat} {b : Block} (found : h.containingBlock? a = some b) :
    b ∈ h.blocks ∧ b.live = true ∧ b.base ≤ a ∧ a < b.base + b.size := by
  obtain ⟨mem, holds⟩ := find?_mem found
  simp only [Bool.and_eq_true, decide_eq_true_eq] at holds
  exact ⟨mem, holds.1.1, holds.1.2, holds.2⟩

/-! ## Operations -/

theorem HeapCorr.load {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) {p o : Nat} {v : UInt8}
    (ok : h.loadByte p o = .ok v) : hp.bytes (p + o) = v ∧ p + o < h.nextAddress := by
  simp only [Memory.Heap.loadByte] at ok
  split at ok
  · split at ok <;> (try split at ok) <;> simp at ok
  rename_i b found
  obtain ⟨mem, live, ge, lt⟩ := containing found
  split at ok
  · simp at ok
  rename_i w got
  simp only [Except.ok.injEq] at ok
  subst ok
  have len := corr.sized b mem
  have inside : p + o - b.base < b.bytes.length := by addr_omega
  rw [List.getElem?_eq_getElem inside, Option.some.injEq] at got
  refine ⟨?_, by have := corr.below b mem; addr_omega⟩
  rw [show p + o = b.base + (p + o - b.base) by addr_omega, corr.bytes b mem live _ inside, got]

theorem HeapCorr.store {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) {p o : Nat} {v : UInt8}
    {h' : Memory.Heap} (ok : h.storeByte p o v = .ok h') :
    p + o < h.nextAddress ∧ HeapCorr h' w (hp.write (p + o) v) := by
  simp only [Memory.Heap.storeByte] at ok
  split at ok
  · split at ok <;> (try split at ok) <;> simp at ok
  rename_i blk found
  obtain ⟨mem, live, ge, lt⟩ := containing found
  simp only [Except.ok.injEq] at ok
  subst ok
  have inBelow := corr.below blk mem
  have addrBelow : p + o < h.nextAddress := by addr_omega
  refine ⟨addrBelow, ?_⟩
  -- every block of the new heap is the updated one or an old one with another base
  have cases : ∀ b ∈ Memory.replaceBlock h.blocks { blk with bytes := Memory.setByte blk.bytes (p + o - blk.base) v },
      (b = { blk with bytes := Memory.setByte blk.bytes (p + o - blk.base) v }) ∨ (b ∈ h.blocks ∧ b.base ≠ blk.base) :=
    fun b m => mem_replaceBlock m
  refine ⟨corr.cursor, corr.pos, corr.unbounded, corr.small, ?_, ?_, ?_, ?_, ?_, ?_, corr.out, corr.err, corr.closed, corr.input⟩
  · intro b m
    rcases cases b m with rfl | ⟨m', -⟩
    · simp only [setByte_length]
      exact corr.sized blk mem
    · exact corr.sized b m'
  · intro b m
    rcases cases b m with rfl | ⟨m', -⟩
    · exact inBelow
    · exact corr.below b m'
  · intro b m b' m' less
    rcases cases b m with rfl | ⟨mb, -⟩ <;> rcases cases b' m' with rfl | ⟨mb', -⟩
    · exact absurd less (Nat.lt_irrefl _)
    · exact corr.apart blk mem b' mb' less
    · exact corr.apart b mb blk mem less
    · exact corr.apart b mb b' mb' less
  · intro b m b' m' same
    rcases cases b m with rfl | ⟨mb, nb⟩ <;> rcases cases b' m' with rfl | ⟨mb', nb'⟩
    · rfl
    · exact absurd same.symm nb'
    · exact absurd same nb
    · exact corr.unique b mb b' mb' same
  · intro b m bl i inside
    simp only [Heap.write]
    rcases cases b m with rfl | ⟨mb, nb⟩
    · simp only [setByte_get]
      have len := corr.sized blk mem
      simp only [setByte_length] at inside
      by_cases at_ : i = p + o - blk.base
      · rw [if_pos (by addr_omega), if_pos at_]
      · rw [if_neg (by addr_omega), if_neg at_]
        exact corr.bytes blk mem live i inside
    · have len := corr.sized b mb
      have disjoint : b.base + i ≠ p + o := by
        rcases Nat.lt_or_gt_of_ne nb with less | more
        · have := corr.apart b mb blk mem less
          addr_omega
        · have := corr.apart blk mem b mb more
          addr_omega
      rw [if_neg disjoint]
      exact corr.bytes b mb bl i inside
  · intro a above
    simp only [Heap.write]
    rw [if_neg (by addr_omega)]
    exact corr.zero a above

theorem HeapCorr.dealloc {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) {p s a : Nat}
    {h' : Memory.Heap} (ok : h.deallocate p s a = .ok h') : HeapCorr h' w hp := by
  simp only [Memory.Heap.deallocate] at ok
  split at ok
  · simp only [Except.ok.injEq] at ok
    rw [← ok]
    exact corr
  split at ok
  · simp at ok
  rename_i blk found
  split at ok
  · simp at ok
  split at ok
  · simp at ok
  split at ok
  · simp at ok
  simp only [Except.ok.injEq] at ok
  subst ok
  have mem := List.mem_of_find?_eq_some found
  have cases : ∀ b ∈ Memory.replaceBlock h.blocks { blk with live := false },
      (b = { blk with live := false }) ∨ (b ∈ h.blocks ∧ b.base ≠ blk.base) :=
    fun b m => mem_replaceBlock m
  refine ⟨corr.cursor, corr.pos, by simp [Memory.refundBudget, corr.unbounded], corr.small, ?_, ?_, ?_, ?_, ?_,
    corr.zero, corr.out, corr.err, corr.closed, corr.input⟩
  · intro b m
    rcases cases b m with rfl | ⟨m', -⟩
    · exact corr.sized blk mem
    · exact corr.sized b m'
  · intro b m
    rcases cases b m with rfl | ⟨m', -⟩
    · exact corr.below blk mem
    · exact corr.below b m'
  · intro b m b' m' less
    rcases cases b m with rfl | ⟨mb, -⟩ <;> rcases cases b' m' with rfl | ⟨mb', -⟩
    · exact absurd less (Nat.lt_irrefl _)
    · exact corr.apart blk mem b' mb' less
    · exact corr.apart b mb blk mem less
    · exact corr.apart b mb b' mb' less
  · intro b m b' m' same
    rcases cases b m with rfl | ⟨mb, nb⟩ <;> rcases cases b' m' with rfl | ⟨mb', nb'⟩
    · rfl
    · exact absurd same.symm nb'
    · exact absurd same nb
    · exact corr.unique b mb b' mb' same
  · intro b m bl i inside
    rcases cases b m with rfl | ⟨mb, -⟩
    · simp at bl
    · exact corr.bytes b mb bl i inside

theorem validAlignment_pow (shift : Nat) : Memory.validAlignment (2 ^ shift) = true := by
  simp [Memory.validAlignment, Nat.log2_two_pow]

theorem alignUp_eq (n shift : Nat) : alignUp n shift = Memory.alignUp n (2 ^ shift) := rfl

theorem HeapCorr.allocate {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) {n shift p : Nat}
    {h' : Memory.Heap} (ok : h.allocate n (2 ^ shift) = .allocated p h') :
    p = alignUp hp.cursor shift ∧ h'.nextAddress = alignUp hp.cursor shift + max n 1 ∧
      HeapCorr h' w { hp with cursor := alignUp hp.cursor shift + max n 1 } := by
  simp only [Memory.Heap.allocate, validAlignment_pow, Bool.not_true, Bool.false_eq_true, ite_false,
    corr.unbounded, Memory.consumeBudget, Memory.AllocationResult.allocated.injEq] at ok
  obtain ⟨rfl, rfl⟩ := ok
  have one : max h.nextAddress 1 = hp.cursor := by rw [corr.cursor]; have := corr.pos; addr_omega
  rw [one, ← alignUp_eq]
  have ge : hp.cursor ≤ alignUp hp.cursor shift := by
    rw [alignUp_eq]
    exact memAlignUp_ge _ _ (Nat.two_pow_pos _)
  refine ⟨rfl, rfl, rfl, by addr_omega, rfl, corr.small, ?_, ?_, ?_, ?_, ?_, ?_, corr.out, corr.err, corr.closed, corr.input⟩
  · intro b m
    simp only [List.mem_append, List.mem_singleton] at m
    rcases m with m | rfl
    · exact corr.sized b m
    · simp
  · intro b m
    simp only [List.mem_append, List.mem_singleton] at m
    rcases m with m | rfl
    · have := corr.below b m
      rw [← corr.cursor] at this
      addr_omega
    · exact Nat.le_refl _
  · intro b m b' m' less
    simp only [List.mem_append, List.mem_singleton] at m m'
    rcases m with m | rfl <;> rcases m' with m' | rfl
    · exact corr.apart b m b' m' less
    · have := corr.below b m
      rw [← corr.cursor] at this
      simp only
      addr_omega
    · have := corr.below b' m'
      rw [← corr.cursor] at this
      simp only at less
      addr_omega
    · exact absurd less (Nat.lt_irrefl _)
  · intro b m b' m' same
    simp only [List.mem_append, List.mem_singleton] at m m'
    rcases m with m | rfl <;> rcases m' with m' | rfl
    · exact corr.unique b m b' m' same
    · have := corr.below b m
      rw [← corr.cursor] at this
      simp only at same
      addr_omega
    · have := corr.below b' m'
      rw [← corr.cursor] at this
      simp only at same
      addr_omega
    · rfl
  · intro b m bl i inside
    simp only [List.mem_append, List.mem_singleton] at m
    rcases m with m | rfl
    · exact corr.bytes b m bl i inside
    · simp only [List.getElem_replicate]
      exact corr.zero _ (by rw [← corr.cursor]; addr_omega)
  · intro a above
    exact corr.zero a (by rw [← corr.cursor]; addr_omega)

/-! ## Mini runs keep the limit -/

def Outcome.heap : Outcome → Heap
  | .normal _ heap => heap
  | .returned _ heap => heap
  | .broke _ heap => heap
  | .continued _ heap => heap

theorem Exec.limit {prog : Program} {d : Nat} {env : Env} {heap : Heap} {s : Stmt} {out : Outcome}
    (exec : Exec prog d env heap s out) : out.heap.limit = heap.limit := by
  induction exec with
  | seq _ _ ih1 ih2 => exact ih2.trans ih1
  | loopNext _ _ _ ih1 ih2 => exact ih2.trans ih1
  | call _ _ _ _ _ ih => exact ih
  | seqReturned _ ih => exact ih
  | ifTrue _ _ ih => exact ih
  | ifFalse _ _ ih => exact ih
  | loopReturned _ _ ih => exact ih
  | seqBroke _ ih => exact ih
  | seqContinued _ ih => exact ih
  | loopBroke _ _ ih => exact ih
  | loopContinued _ _ _ ih1 ih2 => exact ih2.trans ih1
  | skip | assign | loopDone | ret | brk | cont | alloc | loadByte | storeByte | loadWord | divide | frame => rfl
  | storeWord => exact (Heap.writeLE_limit _ _ _ _).1
  | sys ran =>
    exact (Syscall.run_frame ran).1

theorem Exec.top {prog : Program} {d : Nat} {env : Env} {heap : Heap} {s : Stmt} {out : Outcome}
    (exec : Exec prog d env heap s out) : out.heap.top = heap.top := by
  induction exec with
  | seq _ _ ih1 ih2 => exact ih2.trans ih1
  | loopNext _ _ _ ih1 ih2 => exact ih2.trans ih1
  | call _ _ _ _ _ ih => exact ih
  | seqReturned _ ih => exact ih
  | ifTrue _ _ ih => exact ih
  | ifFalse _ _ ih => exact ih
  | loopReturned _ _ ih => exact ih
  | seqBroke _ ih => exact ih
  | seqContinued _ ih => exact ih
  | loopBroke _ _ ih => exact ih
  | loopContinued _ _ _ ih1 ih2 => exact ih2.trans ih1
  | skip | assign | loopDone | ret | brk | cont | alloc | loadByte | storeByte | loadWord | divide | frame => rfl
  | storeWord => exact (Heap.writeLE_top _ _ _ _).1
  | sys ran =>
    exact Syscall.run_top ran

/-! ## Lowered heap operations -/

theorem atLeastOne_eval (x : Expr) (env : Env) :
    ((atLeastOne x).eval env).toNat = max (x.eval env).toNat 1 := by
  by_cases zero : x.eval env = 0
  · simp [atLeastOne, Expr.eval, Word.apply, BinOp.apply, Word.holds, CmpOp.holdsU, zero]
  · have pos : 0 < (x.eval env).toNat := by
      rcases Nat.eq_zero_or_pos (x.eval env).toNat with h | h
      · exact absurd (BitVec.eq_of_toNat_eq (by simpa using h)) zero
      · exact h
    have same : (atLeastOne x).eval env = x.eval env := by
      simp [atLeastOne, Expr.eval, Word.apply, BinOp.apply, Word.holds, CmpOp.holdsU]; exact zero
    rw [same]
    omega

theorem eval_value {P : Core.Program} {k : Nat} {st : State} {x v : Value} {st' : State}
    (run : evalExpr k P st (.value x) = .done v st') : v = x := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr, Semantics.Outcome.done.injEq] at run
    exact run.1.symm

theorem evalExprs_cons {P : Core.Program} {fuel : Nat} {st : State} {e : Core.Expr} {es : List Core.Expr}
    {vs : List Value} {st' : State} (run : evalExprs fuel P st (e :: es) = .done vs st') :
    ∃ k v vs' mid, evalExpr k P st e = .done v mid ∧ evalExprs k P mid es = .done vs' st' ∧
      vs = v :: vs' := by
  cases fuel with
  | zero => simp [evalExprs] at run
  | succ k =>
    simp only [evalExprs] at run
    split at run
    · rename_i v mid first
      split at run
      · rename_i vs' completed rest
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        exact ⟨k, v, vs', mid, first, rest, rfl⟩
      all_goals simp at run
    all_goals simp at run

/-! ## Several bytes -/

/-- A block replaced by one with the same place, bytes and liveness. -/
theorem HeapCorr.replace {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) {blk r : Block}
    (mem : blk ∈ h.blocks) (base : r.base = blk.base) (size : r.size = blk.size)
    (bytes : r.bytes = blk.bytes) (live : r.live = blk.live) :
    HeapCorr { h with blocks := Memory.replaceBlock h.blocks r } w hp := by
  obtain ⟨rb, rs, ra, rby, rl, ro⟩ := r
  simp only at base size bytes live
  subst base size bytes live
  have cases : ∀ b ∈ Memory.replaceBlock h.blocks ⟨blk.base, blk.size, ra, blk.bytes, blk.live, ro⟩,
      b = ⟨blk.base, blk.size, ra, blk.bytes, blk.live, ro⟩ ∨ (b ∈ h.blocks ∧ b.base ≠ blk.base) :=
    fun b m => mem_replaceBlock m
  refine ⟨corr.cursor, corr.pos, corr.unbounded, corr.small, ?_, ?_, ?_, ?_, ?_, corr.zero, corr.out, corr.err, corr.closed, corr.input⟩
  · intro b m
    rcases cases b m with rfl | ⟨m', -⟩
    · exact corr.sized blk mem
    · exact corr.sized b m'
  · intro b m
    rcases cases b m with rfl | ⟨m', -⟩
    · exact corr.below blk mem
    · exact corr.below b m'
  · intro b m b' m' less
    rcases cases b m with rfl | ⟨mb, -⟩ <;> rcases cases b' m' with rfl | ⟨mb', -⟩
    · exact absurd less (Nat.lt_irrefl _)
    · exact corr.apart blk mem b' mb' less
    · exact corr.apart b mb blk mem less
    · exact corr.apart b mb b' mb' less
  · intro b m b' m' same
    rcases cases b m with rfl | ⟨mb, nb⟩ <;> rcases cases b' m' with rfl | ⟨mb', nb'⟩
    · rfl
    · exact absurd same.symm nb'
    · exact absurd same nb
    · exact corr.unique b mb b' mb' same
  · intro b m bl i inside
    rcases cases b m with rfl | ⟨mb, -⟩
    · exact corr.bytes blk mem bl i inside
    · exact corr.bytes b mb bl i inside

/-- Core's `count` bytes from `p + o`, little-endian, are the mini heap's,
and lie below the cursor. -/
theorem HeapCorr.loadBytesFrom {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) {p : Nat} :
    ∀ (count o : Nat) {bytes : List UInt8}, Memory.loadBytesFrom h p o count = .ok bytes →
      Semantics.decodeNatLE bytes = hp.readLE (p + o) count ∧ (0 < count → p + o + count ≤ h.nextAddress)
  | 0, o, bytes, ok => by
    simp only [Memory.loadBytesFrom, Except.ok.injEq] at ok
    subst ok
    exact ⟨rfl, fun lt => absurd lt (Nat.lt_irrefl 0)⟩
  | count + 1, o, bytes, ok => by
    simp only [Memory.loadBytesFrom] at ok
    split at ok
    · simp at ok
    · rename_i b loaded
      split at ok
      · simp at ok
      · rename_i rest restOk
        simp only [Except.ok.injEq] at ok
        subst ok
        obtain ⟨at_, below⟩ := corr.load loaded
        obtain ⟨decoded, restBelow⟩ := corr.loadBytesFrom count (o + 1) restOk
        refine ⟨?_, fun _ => ?_⟩
        · simp only [Semantics.decodeNatLE, Heap.readLE, at_, decoded, Nat.add_assoc]
        · rcases Nat.eq_zero_or_pos count with zero | pos
          · subst zero; omega
          · have := restBelow pos; omega

theorem HeapCorr.loadNatLE {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) {a count n : Nat}
    (ok : Semantics.loadNatLE h a count = .ok n) :
    n = hp.readLE a count ∧ (0 < count → a + count ≤ h.nextAddress) := by
  simp only [Semantics.loadNatLE, Memory.Heap.loadBytes] at ok
  obtain ⟨bytes, loaded, wrapped⟩ := except_bind_ok ok
  simp only [pure, Except.pure, Except.ok.injEq] at wrapped
  subst wrapped
  have := corr.loadBytesFrom count 0 loaded
  simpa using this

/-- The mini heap with `bytes` written from `address`. -/
def Heap.writeBytes (hp : Heap) (address : Nat) : List UInt8 → Heap
  | [] => hp
  | b :: rest => (hp.write address b).writeBytes (address + 1) rest

theorem HeapCorr.storeBytesFrom {p : Nat} : ∀ (bytes : List UInt8) {h : Memory.Heap} {hp : Heap} (o : Nat)
    {h' : Memory.Heap}, HeapCorr h w hp → Memory.storeBytesFrom h p o bytes = .ok h' →
      HeapCorr h' w (hp.writeBytes (p + o) bytes) ∧ (bytes ≠ [] → p + o + bytes.length ≤ h.nextAddress)
  | [], h, hp, o, h', corr, ok => by
    simp only [Memory.storeBytesFrom, Except.ok.injEq] at ok
    subst ok
    exact ⟨corr, fun ne => absurd rfl ne⟩
  | b :: rest, h, hp, o, h', corr, ok => by
    simp only [Memory.storeBytesFrom] at ok
    cases stored : h.storeByte p o b with
    | error => simp [stored] at ok
    | ok next =>
      simp only [stored] at ok
      obtain ⟨below, corr'⟩ := corr.store stored
      obtain ⟨corr'', restBelow⟩ := HeapCorr.storeBytesFrom rest (o + 1) corr' ok
      refine ⟨by simpa [Heap.writeBytes, Nat.add_assoc] using corr'', fun _ => ?_⟩
      have same := storeByte_next stored
      cases rest with
      | nil => simp; addr_omega
      | cons c more =>
        have := restBelow (List.cons_ne_nil _ _)
        simp only [List.length_cons] at this ⊢
        addr_omega

theorem encodeNatLE_succ (count value : Nat) :
    Semantics.encodeNatLE (count + 1) value = UInt8.ofNat value :: Semantics.encodeNatLE count (value / 256) := by
  simp only [Semantics.encodeNatLE, List.range_succ_eq_map, List.map_cons, List.map_map]
  congr 1
  · apply UInt8.toNat.inj
    simp
  · apply List.map_congr_left
    intro i _
    simp only [Function.comp, Nat.pow_succ', Nat.div_div_eq_div_mul]

theorem writeLE_eq_writeBytes : ∀ (count : Nat) (hp : Heap) (address value : Nat),
    hp.writeLE address value count = hp.writeBytes address (Semantics.encodeNatLE count value)
  | 0, hp, address, value => by simp [Heap.writeLE, Semantics.encodeNatLE, Heap.writeBytes]
  | count + 1, hp, address, value => by
    rw [encodeNatLE_succ]
    simp only [Heap.writeLE, Heap.writeBytes]
    exact writeLE_eq_writeBytes count _ _ _

theorem i32Bytes_eq (number : Int) :
    Semantics.i32Bytes number = Semantics.encodeNatLE 4 (number % 2 ^ 32).toNat := by
  simp only [Semantics.i32Bytes, Semantics.encodeNatLE]
  apply List.map_congr_left
  intro i _
  rw [Nat.pow_mul]

theorem HeapCorr.allocated {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) (n shift : Nat)
    {h' : Memory.Heap} (ok : h.allocate n (2 ^ shift) = .exhausted h') : False := by
  simp [Memory.Heap.allocate, validAlignment_pow, corr.unbounded, Memory.consumeBudget] at ok

theorem HeapCorr.untrapped {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h w hp) (n shift : Nat)
    {r} {h' : Memory.Heap} (ok : h.allocate n (2 ^ shift) = .trapped r h') : False := by
  simp [Memory.Heap.allocate, validAlignment_pow, corr.unbounded, Memory.consumeBudget] at ok

end Lanius.Mini
