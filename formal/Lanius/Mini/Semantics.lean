module

public import Lanius.Mini.Compiler.Types
-- import all: Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.pow2
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.copyBinding
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.lowerMatchArms
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.sigs
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.assignAgrees
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.Stmt_kills
import all Lanius.Mini.Compiler.P.optKill
import all Lanius.Mini.Compiler.P.optimizeNeg
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.compileOr
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.larger
import all Lanius.Mini.Compiler.P.Inline_arithOf
import all Lanius.Mini.Compiler.P.Inline_lowerSetScalar
import all Lanius.Mini.Compiler.P.Inline_branchAgrees
-- end import all
-- import parts: Lanius.Mini.Compiler BinOp.bytes DivOp.bytes MemWidth.bytes
public import Lanius.Mini.Compiler.P.Lists_empty
public import Lanius.Mini.Compiler.P.arities
-- end import parts

@[expose] public section

/-! Source semantics over 64-bit words. Arithmetic wraps; an `s32` operation
acts on the low 32 bits and zero-extends its result, and its comparisons are
signed; a `u64` operation uses all 64 bits, unsigned. Statements have a
big-step semantics; the index bounds the call depth of the derivation, which is
what bounds the stack the compiled code uses. A function's non-parameter locals
start at zero. The heap is bytes at offsets below a limit, with a bump
allocator's cursor; a run that would pass the limit has no derivation, and so
has a division by zero or a signed division of the least value by -1. -/

namespace Lanius.Mini

abbrev Env := Nat → BitVec 64

def BinOp.apply {n : Nat} : BinOp → BitVec n → BitVec n → BitVec n
  | .add, a, b => a + b
  | .sub, a, b => a - b
  | .mul, a, b => a * b
  | .and, a, b => a &&& b
  | .or, a, b => a ||| b
  | .xor, a, b => a ^^^ b
  | .shl, a, b => a <<< (b.toNat % n)
  | .shr, a, b => a >>> (b.toNat % n)
  | .sar, a, b => a.sshiftRight (b.toNat % n)

/-- Signed comparisons. -/
def CmpOp.holds : CmpOp → BitVec 32 → BitVec 32 → Bool
  | .eq, a, b => a == b
  | .ne, a, b => a != b
  | .lt, a, b => a.slt b
  | .le, a, b => a.sle b
  | .gt, a, b => b.slt a
  | .ge, a, b => b.sle a

/-- Unsigned comparisons. -/
def CmpOp.holdsU : CmpOp → BitVec 64 → BitVec 64 → Bool
  | .eq, a, b => a == b
  | .ne, a, b => a != b
  | .lt, a, b => a.ult b
  | .le, a, b => a.ule b
  | .gt, a, b => b.ult a
  | .ge, a, b => b.ule a

/-- The low 32 bits of a word. -/
abbrev low (a : BitVec 64) : BitVec 32 := a.setWidth 32

/-- A 32-bit result, zero-extended. -/
abbrev widen (a : BitVec 32) : BitVec 64 := a.setWidth 64

def Word.apply : Word → BinOp → BitVec 64 → BitVec 64 → BitVec 64
  | .s32, operation, a, b => widen (operation.apply (low a) (low b))
  | .u64, operation, a, b => operation.apply a b

def Word.holds : Word → CmpOp → BitVec 64 → BitVec 64 → Bool
  | .s32, operation, a, b => operation.holds (low a) (low b)
  | .u64, operation, a, b => operation.holdsU a b

/-- Division on `n`-bit words: a signed quotient truncates toward zero and a
signed remainder has the dividend's sign. -/
def DivOp.apply {n : Nat} : DivOp → BitVec n → BitVec n → BitVec n
  | .sDiv, a, b => a.sdiv b
  | .sRem, a, b => a.srem b
  | .uDiv, a, b => a / b
  | .uRem, a, b => a % b

/-- The division has a result: the divisor is not zero, and a signed one is
not the least value divided by -1. -/
def DivOp.defined {n : Nat} : DivOp → BitVec n → BitVec n → Bool
  | .sDiv, a, b | .sRem, a, b => b != 0 && !(a == BitVec.intMin n && b == -1)
  | .uDiv, _, b | .uRem, _, b => b != 0

/-- An `s32` division divides the low 32 bits and zero-extends its result; a
`u64` one divides all 64 bits. -/
def Word.divide : Word → DivOp → BitVec 64 → BitVec 64 → BitVec 64
  | .s32, operation, a, b => widen (operation.apply (low a) (low b))
  | .u64, operation, a, b => operation.apply a b

def Word.divides : Word → DivOp → BitVec 64 → BitVec 64 → Bool
  | .s32, operation, a, b => operation.defined (low a) (low b)
  | .u64, operation, a, b => operation.defined a b

def Expr.eval (env : Env) : Expr → BitVec 64
  | .lit value => value
  | .var index => env index
  | .neg operand => widen (-low (operand.eval env))
  | .binary word operation left right => word.apply operation (left.eval env) (right.eval env)
  | .compare word operation left right =>
      if word.holds operation (left.eval env) (right.eval env) then 1 else 0

def Expr.evalAll (env : Env) : List Expr → List (BitVec 64)
  | [] => []
  | e :: rest => e.eval env :: Expr.evalAll env rest

def Env.set (env : Env) (index : Nat) (value : BitVec 64) : Env :=
  fun other => if other = index then value else env other

/-- `values` stored at `slot`, `slot + 1`, ... -/
def Env.setMany (env : Env) : Nat → List (BitVec 64) → Env
  | _, [] => env
  | slot, value :: rest => Env.setMany (env.set slot value) (slot + 1) rest

/-- Parameters hold the arguments; every other local starts at zero. -/
def Func.entry (args : List (BitVec 64)) : Env := fun index => args.getD index 0

/-- The heap: a byte at each offset, the bump allocator's cursor, and the
limit no allocation passes and every access stays below. -/
structure Heap where
  bytes : Nat → UInt8
  cursor : Nat
  limit : Nat

/-- `n` rounded up to a multiple of `2 ^ shift`. -/
def alignUp (n shift : Nat) : Nat := (n + 2 ^ shift - 1) / 2 ^ shift * 2 ^ shift

/-- The low byte of a word, as x86's byte store takes it. -/
def lowByte (value : BitVec 64) : UInt8 := UInt8.ofNat (value.setWidth 8).toNat

def Heap.write (heap : Heap) (address : Nat) (byte : UInt8) : Heap :=
  { heap with bytes := fun other => if other = address then byte else heap.bytes other }

/-- The `count` bytes from `address`, little-endian. -/
def Heap.readLE (heap : Heap) (address : Nat) : Nat → Nat
  | 0 => 0
  | count + 1 => (heap.bytes address).toNat + 256 * heap.readLE (address + 1) count

/-- The low `count` bytes of `value` written from `address`, little-endian. -/
def Heap.writeLE (heap : Heap) (address value : Nat) : Nat → Heap
  | 0 => heap
  | count + 1 => (heap.write address (UInt8.ofNat value)).writeLE (address + 1) (value / 256) count

theorem Heap.writeLE_limit : ∀ (heap : Heap) (address value count : Nat),
    (heap.writeLE address value count).limit = heap.limit ∧ (heap.writeLE address value count).cursor = heap.cursor
  | _, _, _, 0 => ⟨rfl, rfl⟩
  | heap, address, value, count + 1 => by
    have := Heap.writeLE_limit (heap.write address (UInt8.ofNat value)) (address + 1) (value / 256) count
    exact ⟨this.1, this.2⟩

theorem Heap.readLE_lt (heap : Heap) : ∀ (address count : Nat), heap.readLE address count < 256 ^ count
  | _, 0 => by simp [Heap.readLE]
  | address, count + 1 => by
    have := heap.readLE_lt (address + 1) count
    have := (heap.bytes address).toNat_lt
    simp only [Heap.readLE, Nat.pow_succ]
    omega

inductive Outcome where
  | normal (env : Env) (heap : Heap)
  | returned (values : List (BitVec 64)) (heap : Heap)

/-- `Exec prog depth env heap stmt outcome`: running `stmt` from `env` and
`heap` ends in `outcome`, with calls nested fewer than `depth` deep. -/
inductive Exec (prog : Program) : Nat → Env → Heap → Stmt → Outcome → Prop where
  | skip {depth : Nat} {env : Env} {heap : Heap} : Exec prog depth env heap .skip (.normal env heap)
  | assign {depth : Nat} {env : Env} {heap : Heap} {index : Nat} {value : Expr} :
      Exec prog depth env heap (.assign index value) (.normal (env.set index (value.eval env)) heap)
  | seq {depth : Nat} {env middle : Env} {heap between : Heap} {first second : Stmt} {outcome : Outcome} :
      Exec prog depth env heap first (.normal middle between) → Exec prog depth middle between second outcome →
      Exec prog depth env heap (.seq first second) outcome
  | seqReturned {depth : Nat} {env : Env} {heap after : Heap} {first second : Stmt} {value : List (BitVec 64)} :
      Exec prog depth env heap first (.returned value after) →
      Exec prog depth env heap (.seq first second) (.returned value after)
  | ifTrue {depth : Nat} {env : Env} {heap : Heap} {condition : Expr} {thenBranch elseBranch : Stmt}
      {outcome : Outcome} :
      condition.eval env ≠ 0 → Exec prog depth env heap thenBranch outcome →
      Exec prog depth env heap (.ite condition thenBranch elseBranch) outcome
  | ifFalse {depth : Nat} {env : Env} {heap : Heap} {condition : Expr} {thenBranch elseBranch : Stmt}
      {outcome : Outcome} :
      condition.eval env = 0 → Exec prog depth env heap elseBranch outcome →
      Exec prog depth env heap (.ite condition thenBranch elseBranch) outcome
  | loopDone {depth : Nat} {env : Env} {heap : Heap} {condition : Expr} {body : Stmt} :
      condition.eval env = 0 → Exec prog depth env heap (.loop condition body) (.normal env heap)
  | loopNext {depth : Nat} {env middle : Env} {heap between : Heap} {condition : Expr} {body : Stmt}
      {outcome : Outcome} :
      condition.eval env ≠ 0 → Exec prog depth env heap body (.normal middle between) →
      Exec prog depth middle between (.loop condition body) outcome →
      Exec prog depth env heap (.loop condition body) outcome
  | loopReturned {depth : Nat} {env : Env} {heap after : Heap} {condition : Expr} {body : Stmt}
      {value : List (BitVec 64)} :
      condition.eval env ≠ 0 → Exec prog depth env heap body (.returned value after) →
      Exec prog depth env heap (.loop condition body) (.returned value after)
  | call {depth inner target count callee : Nat} {env : Env} {heap after : Heap} {args : List Expr}
      {func : Func} {value : List (BitVec 64)} :
      prog.funcs[callee]? = some func → args.length = func.params → value.length = count → inner < depth →
      Exec prog inner (Func.entry (Expr.evalAll env args)) heap func.body (.returned value after) →
      Exec prog depth env heap (.call target count callee args) (.normal (env.setMany target value) after)
  | ret {depth : Nat} {env : Env} {heap : Heap} {values : List Expr} :
      Exec prog depth env heap (.ret values) (.returned (Expr.evalAll env values) heap)
  | alloc {depth : Nat} {env : Env} {heap : Heap} {target shift : Nat} {size : Expr} :
      alignUp heap.cursor shift + (size.eval env).toNat ≤ heap.limit →
      Exec prog depth env heap (.alloc target shift size)
        (.normal (env.set target (BitVec.ofNat 64 (alignUp heap.cursor shift)))
          { heap with cursor := alignUp heap.cursor shift + (size.eval env).toNat })
  | loadByte {depth : Nat} {env : Env} {heap : Heap} {target : Nat} {address : Expr} :
      (address.eval env).toNat < heap.limit →
      Exec prog depth env heap (.loadByte target address)
        (.normal (env.set target (BitVec.ofNat 64 (heap.bytes (address.eval env).toNat).toNat)) heap)
  | storeByte {depth : Nat} {env : Env} {heap : Heap} {address value : Expr} :
      (address.eval env).toNat < heap.limit →
      Exec prog depth env heap (.storeByte address value)
        (.normal env (heap.write (address.eval env).toNat (lowByte (value.eval env))))
  | loadWord {depth : Nat} {env : Env} {heap : Heap} {width : MemWidth} {target : Nat} {address : Expr} :
      (address.eval env).toNat + width.bytes ≤ heap.limit →
      Exec prog depth env heap (.loadWord width target address)
        (.normal (env.set target (BitVec.ofNat 64 (heap.readLE (address.eval env).toNat width.bytes))) heap)
  | storeWord {depth : Nat} {env : Env} {heap : Heap} {width : MemWidth} {address value : Expr} :
      (address.eval env).toNat + width.bytes ≤ heap.limit →
      Exec prog depth env heap (.storeWord width address value)
        (.normal env (heap.writeLE (address.eval env).toNat (value.eval env).toNat width.bytes))
  | divide {depth : Nat} {env : Env} {heap : Heap} {word : Word} {operation : DivOp} {target : Nat}
      {left right : Expr} :
      word.divides operation (left.eval env) (right.eval env) = true →
      Exec prog depth env heap (.divide word operation target left right)
        (.normal (env.set target (word.divide operation (left.eval env) (right.eval env))) heap)

/-- Calling function `callee` with `args` from `heap` returns `value` and
leaves `after`, nesting calls fewer than `depth` deep. -/
def Program.Returns (prog : Program) (depth callee : Nat) (args : List (BitVec 64)) (heap : Heap)
    (value : List (BitVec 64)) (after : Heap) : Prop :=
  ∃ func, prog.funcs[callee]? = some func ∧ args.length = func.params ∧
    Exec prog depth (Func.entry args) heap func.body (.returned value after)

end Lanius.Mini
