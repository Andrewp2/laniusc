module

public import Lanius.Mini.Homes
public import Lanius.Mini.SourceCore
public import Lanius.Mini.Compiler.P.widthOf
public import Lanius.Mini.Compiler.P.SrcType_floatTy
public import Lanius.Mini.Compiler.P.SrcType_isBool
public import Lanius.Mini.Compiler.P.SrcType_isChar
public import Lanius.Mini.Compiler.P.SrcType_isFloat
public import Lanius.Mini.Compiler.P.SrcType_isFloatAny
public import Lanius.Mini.Compiler.P.SrcType_isI32
public import Lanius.Mini.Compiler.P.SrcType_isInteger
public import Lanius.Mini.Compiler.P.SrcType_isIsize
public import Lanius.Mini.Compiler.P.SrcType_isPtr
public import Lanius.Mini.Compiler.P.SrcType_isScalar
public import Lanius.Mini.Compiler.P.SrcType_isSint
public import Lanius.Mini.Compiler.P.SrcType_isSintAny
public import Lanius.Mini.Compiler.P.SrcType_isStr
public import Lanius.Mini.Compiler.P.SrcType_isUint
public import Lanius.Mini.Compiler.P.SrcType_isUnit
public import Lanius.Mini.Compiler.P.SrcType_sintKind
public import Lanius.Mini.Compiler.P.SrcType_uintKind
public import Lanius.Mini.Compiler.P.SrcType_word
public import Lanius.Mini.Compiler.P.UintTy_half
public import Lanius.Mini.Compiler.P.UintTy_leastBits
public import Lanius.Mini.Compiler.P.UintTy_signedWord
public import Lanius.Mini.Compiler.P.UintTy_spare
public import Lanius.Mini.Compiler.P.boolBits
public import Lanius.Mini.Compiler.P.lookup
public import Lanius.Mini.Stops
public import Lanius.Mini.Fails
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap

@[expose] public section

/-! # References: the memory model (F5)

SEMANTIC_DECISIONS "References: the memory model". Every local a program
borrows has a *home*, a block of frame memory where it lives for its whole
scope, in Core's native layout (`NativeLayout`: words descending from the
value's word 0, packed `i32` and `u8` arrays ascending). A reference is one
slot holding the lowest byte of a sub-place of a home (a field or element at a
projection path). Reads and writes through it are loads and stores at fixed
offsets from that address, fixed by the referent's type.

The definitions a reference's representation reaches (`Access`, `words`,
`subStep`, `sub`, `Addressed.sub`, `RefTo`, `RefHeld`) are in
`Mini/Layout.lean`, trusted, since `SrcType.HoldsAt.ref` is `RefHeld`
(stage 1, S2). `Homes` and the layout definitions it reads (`slotAt`,
`homeView`, `homeOk`) are in `Mini/Homes.lean`, which the simulation
imports (S6a-1). The rest here is not trusted. F5's open statements
(`Lanius/Open/F5`) are about them.
-/

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)


/-! ## Code templates -/

/-- The address in slot `r` plus `offset`. -/
def addOff (r offset : Nat) : Expr :=
  .binary .u64 .add (.var r) (.lit (BitVec.ofNat 64 offset))

/-- Loads of `count` slots of `ty`, from slot `s` on, from the block whose
lowest byte is in slot `r` into `target + s` on. -/
def SrcType.loadsFrom (ty : SrcType) (r target : Nat) : Nat → Nat → Stmt
  | _, 0 => .skip
  | s, count + 1 => .seq ((ty.refSlotAt s).2.load (target + s) (addOff r (ty.refSlotAt s).1))
      (ty.loadsFrom r target (s + 1) count)

/-- A read through a reference: the value of `ty` at the address in slot
`r`, loaded into the slots from `target`. -/
def SrcType.loadSlots (ty : SrcType) (r target : Nat) : Stmt := ty.loadsFrom r target 0 ty.size

/-- Stores of `count` slots of `ty`, from slot `s` on, from `slot + s` on
into the block whose lowest byte is in slot `r`. -/
def SrcType.storesFrom (ty : SrcType) (r slot : Nat) : Nat → Nat → Stmt
  | _, 0 => .skip
  | s, count + 1 => .seq ((ty.refSlotAt s).2.store (addOff r (ty.refSlotAt s).1) (.var (slot + s)))
      (ty.storesFrom r slot (s + 1) count)

/-- A write through a reference: the value of `ty` in the slots from `slot`,
stored at the address in slot `r`. -/
def SrcType.storeSlots (ty : SrcType) (r slot : Nat) : Stmt := ty.storesFrom r slot 0 ty.size

/-- The verified compiler's trap, a division by zero into `slot`
(`trap` of `SrcExpr_guard`). -/
def refTrap (slot : Nat) : Stmt := .divide .u64 .uDiv slot (.lit 1) (.lit 0)

/-! ## Places -/

/-- A place a reference names, as Core's places built from a borrowed local
(`home`), the referent of a reference local (`deref`), fields, and elements
at an index expression that does not change the state (it may trap). In
Core's order: an index is evaluated right after its base resolves, so an
out-of-range base index traps before a later index runs (`a[i][e]`). The
verified compiler's code for the index, `code`, runs right after the
base's code and leaves the index's word in `slot` (`RPlace.code`,
`RPlace.IndexRuns`). -/
inductive RPlace where
  | home (id : Lanius.VarId)
  | deref (id : Lanius.VarId)
  | field (base : RPlace) (field : Nat)
  | index (base : RPlace) (index : Core.Expr) (code : Stmt) (slot : Nat)

/-- Core's place: where `borrow` and `assign` go. -/
def RPlace.toCore : RPlace → Core.Place
  | .home id => .local id
  | .deref id => .deref (.local id)
  | .field base f => .field base.toCore f
  | .index base ie _ _ => .index base.toCore ie

/-- Core's read of the place's value, as the front end writes it: the local,
the `dereference` of a reference local, then value-level fields and
elements. -/
def RPlace.read : RPlace → Core.Expr
  | .home id => .local id
  | .deref id => .dereference (.local id)
  | .field base f => .field base.read f
  | .index base ie _ _ => .index base.read ie

/-- What the verified compiler knows where it lowers a place: the slot that
holds the activation's frame block's address, each home's offset in that
block and type (innermost first, as `lookup` finds them), each other local's
slot, and each reference local's referent type. -/
structure RCtx where
  frame : Nat
  homes : List (Lanius.VarId × Nat × SrcType)
  slotOf : Lanius.VarId → Nat
  refTy : Lanius.VarId → SrcType

/-- The local's value in Core's state. -/
def coreLocal (st : State) (id : Lanius.VarId) : Option Value :=
  match st.cellId? id with
  | none => none
  | some cell =>
      match st.cellEntry? cell with
      | none => none
      | some entry => entry.value

/-- The length, the element type and whether the elements are packed, of an
array type. -/
def SrcType.indexInfo (ty : SrcType) : Option (Nat × SrcType) :=
  match ty with
  | .array element length => some (length, element)
  | .i32 => none
  | .bool => none
  | .uint _ => none
  | .struct _ _ => none
  | .enum _ _ => none
  | .ptr => none
  | .slice _ => none
  | .unit => none
  | .isize => none
  | .char => none
  | .float _ => none
  | .sint _ => none
  | .view _ => none
  | .str => none
  | .ref _ => none

/-- `t` = the address in `t` plus element `slot`'s offset in an array of
`length` `element`s: `slot` widths up when packed, else `length - 1 - slot`
elements' words up. The caller checks `slot < length`. -/
def elementAddr (t slot length : Nat) (element : SrcType) : Stmt :=
  if element.accessKind.narrow then
    .assign t (.binary .u64 .add (.var t)
      (.binary .u64 .mul (.var slot) (.lit (BitVec.ofNat 64 element.accessKind.bytes))))
  else
    .assign t (.binary .u64 .sub
      (.binary .u64 .add (.var t) (.lit (BitVec.ofNat 64 (8 * ((length - 1) * element.words)))))
      (.binary .u64 .mul (.var slot) (.lit (BitVec.ofNat 64 (8 * element.words)))))

/-- The code that puts the place's lowest byte in slot `t`, with the place's
type: a home's address is the frame block's plus its offset, a reference
local's slot holds the address, a field adds its offset, and an element
runs its index's code after its base's, then adds its offset after
checking the index slot is below the length (else the trap).
None for a place that does not fit the types, a reference local that has a
home, or an array of `2 ^ 31` elements or more. -/
def RPlace.code (c : RCtx) (t : Nat) : RPlace → Option (Stmt × SrcType)
  | .home id =>
      match c.homes.lookup id with
      | none => none
      | some (offset, ty) => some (.assign t (addOff c.frame offset), ty)
  | .deref id =>
      match c.homes.lookup id with
      | some _ => none
      | none => some (.assign t (.var (c.slotOf id)), c.refTy id)
  | .field base f =>
      match base.code c t with
      | none => none
      | some (code, ty) =>
          match ty.subStep (.field f) with
          | none => none
          | some (offset, child) => some (.seq code (.assign t (addOff t offset)), child)
  | .index base _ indexCode slot =>
      match base.code c t with
      | none => none
      | some (code, ty) =>
          match ty.indexInfo with
          | none => none
          | some (length, element) =>
              if 2 ^ 31 ≤ length then none else
              some (.seq code (.seq indexCode
                (.ite (.compare .u64 .lt (.var slot) (.lit (BitVec.ofNat 64 length)))
                  (elementAddr t slot length element) (refTrap t))), element)

/-- The cell and path a place names in Core's state: a home's local's cell,
a reference local's cell and path, then each field, and each element at its
index's value, the index evaluated (with enough fuel, the state unchanged)
once its base has resolved. Out-of-range indices are allowed here; `Traps`
is the place whose resolution traps. -/
inductive RPlace.Resolves (prog : Core.Program) (st : State) :
    RPlace → Lanius.CellId → List ValueProjection → Prop where
  | home {id : Lanius.VarId} {cell : Lanius.CellId} :
      st.cellId? id = some cell → RPlace.Resolves prog st (.home id) cell []
  | deref {id : Lanius.VarId} {T : Core.Ty} {cell : Lanius.CellId} {path : List ValueProjection} :
      coreLocal st id = some (.reference T cell path) → RPlace.Resolves prog st (.deref id) cell path
  | field {base : RPlace} {f : Nat} {cell : Lanius.CellId} {path : List ValueProjection} :
      RPlace.Resolves prog st base cell path → RPlace.Resolves prog st (.field base f) cell (path ++ [.field f])
  | index {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {cell : Lanius.CellId}
      {path : List ValueProjection} {iv : Value} {i : Nat} :
      RPlace.Resolves prog st base cell path →
      (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st index = .done iv st) →
      Semantics.integerIndex iv = .ok i →
      RPlace.Resolves prog st (.index base index code slot) cell (path ++ [.index i])

/-- A place whose resolution traps, in Core's order, with this reason and
state: some index's base resolves to an array and then the index itself
traps, or its value is below zero or not below the array's length
(`arrayBounds`). Indices after it are not evaluated. -/
inductive RPlace.Traps (prog : Core.Program) (st : State) : RPlace → Lanius.Trap → State → Prop where
  | field {base : RPlace} {f : Nat} {r : Lanius.Trap} {st' : State} :
      RPlace.Traps prog st base r st' → RPlace.Traps prog st (.field base f) r st'
  | index {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {r : Lanius.Trap} {st' : State} :
      RPlace.Traps prog st base r st' → RPlace.Traps prog st (.index base index code slot) r st'
  | indexTraps {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {cell : Lanius.CellId}
      {path : List ValueProjection} {elements : List Value} {r : Lanius.Trap} {st' : State} :
      RPlace.Resolves prog st base cell path →
      Semantics.readCellProjection st cell path = .ok (.array elements) →
      (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st index = .trapped r st') →
      RPlace.Traps prog st (.index base index code slot) r st'
  | negative {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {cell : Lanius.CellId}
      {path : List ValueProjection} {iv : Value} {elements : List Value} :
      RPlace.Resolves prog st base cell path →
      Semantics.readCellProjection st cell path = .ok (.array elements) →
      (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st index = .done iv st) →
      Semantics.integerIndex iv = .error .arrayBounds →
      RPlace.Traps prog st (.index base index code slot) .arrayBounds st
  | beyond {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {cell : Lanius.CellId}
      {path : List ValueProjection} {iv : Value} {i : Nat} {elements : List Value} :
      RPlace.Resolves prog st base cell path →
      Semantics.readCellProjection st cell path = .ok (.array elements) →
      (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st index = .done iv st) →
      Semantics.integerIndex iv = .ok i → elements.length ≤ i →
      RPlace.Traps prog st (.index base index code slot) .arrayBounds st

/-- A word for an index value: the index when Core has one, and at least
`2 ^ 31` (so not below any length) when the value is negative. An `i32`
slot is that (its 32 bits zero-extended), and so are the unsigned. -/
def IndexAt (v : Value) (w : BitVec 64) : Prop :=
  (∀ i, Semantics.integerIndex v = .ok i → w.toNat = i) ∧
    (Semantics.integerIndex v = .error .arrayBounds → 2 ^ 31 ≤ w.toNat)

/-- Each index's code does what Core's index does, run right after its
base's code: from slots that agree with `env` outside `scratch` and `t`
(which holds the base's address then), it ends normally, the heap
unchanged, with the index value's word in the index's slot and the slots
outside `scratch` as they were, when Core's index has a value; and it stops
when Core's index traps with a checked trap (`undefinedTrap r = false`:
not a raw memory error or `typeMismatch`, which compiled code need not
catch, as in `raw[k]`). Index slots are scratch slots. Stage 2 proves this
of the code the verified compiler gives an index (its expression lowering's
induction hypothesis). -/
inductive RPlace.IndexRuns (cprog : Core.Program) (st : State) (prog : Program) (depth : Nat)
    (hp : Heap) (env : Env) (t : Nat) (scratch : List Nat) : RPlace → Prop where
  | home {id : Lanius.VarId} : RPlace.IndexRuns cprog st prog depth hp env t scratch (.home id)
  | deref {id : Lanius.VarId} : RPlace.IndexRuns cprog st prog depth hp env t scratch (.deref id)
  | field {base : RPlace} {f : Nat} :
      RPlace.IndexRuns cprog st prog depth hp env t scratch base →
      RPlace.IndexRuns cprog st prog depth hp env t scratch (.field base f)
  | index {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} :
      RPlace.IndexRuns cprog st prog depth hp env t scratch base → slot ∈ scratch →
      (∀ iv, (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel cprog st index = .done iv st) →
        ∀ env₀ : Env, (∀ k, k ∉ scratch → k ≠ t → env₀ k = env k) →
        ∃ env₁ : Env, Exec prog depth env₀ hp code (.normal env₁ hp) ∧ IndexAt iv (env₁ slot) ∧
          ∀ k, k ∉ scratch → env₁ k = env₀ k) →
      (∀ (r : Lanius.Trap) (st' : State), undefinedTrap r = false →
        (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel cprog st index = .trapped r st') →
        ∀ env₀ : Env, (∀ k, k ∉ scratch → k ≠ t → env₀ k = env k) →
        ∀ n, Stops prog depth env₀ hp code n) →
      RPlace.IndexRuns cprog st prog depth hp env t scratch (.index base index code slot)

/-- The compile context agrees with Core's state and the mini slots: the
home `lookup` finds for a local (the innermost, under shadowing) is a place
whose cell is the local's, at the frame block's address plus the home's
offset. A reference local without a home has its slot hold its reference,
to a sub-place of its referent type (`RefTo`). -/
structure RefsAgree (c : RCtx) (places : List Addressed) (st : State) (env : Env) : Prop where
  homes : ∀ id offset ty, c.homes.lookup id = some (offset, ty) → ∃ x ∈ places, ∃ cell,
    st.cellId? id = some cell ∧ x.cell = cell ∧ x.ty = ty ∧ x.address = (env c.frame).toNat + offset
  refs : ∀ id T cell path, c.homes.lookup id = none → coreLocal st id = some (.reference T cell path) →
    RefTo places (c.refTy id) cell path (env (c.slotOf id))

/-- The slots a place's code reads besides its index codes' scratch slots:
the frame slot and reference locals' slots. -/
def RPlace.slots (c : RCtx) : RPlace → List Nat
  | .home _ => [c.frame]
  | .deref id => [c.slotOf id]
  | .field base _ => base.slots c
  | .index base _ _ _ => base.slots c

end Lanius.Mini
