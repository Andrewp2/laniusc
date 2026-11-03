module

public import Lanius.Mini.FrameCorr
public import Lanius.Mini.SourceCore
public import Lanius.Mini.Compiler.P.widthOf
public import Lanius.Mini.Compiler.P.UintTy_half
public import Lanius.Mini.Stops
public import Lanius.Mini.Fails
import all Lanius.Mini.Compiler.P.SrcType_same

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
(stage 1, S2). The rest here is not trusted. F5's open statements
(`Lanius/Open/F5`) are about them.
-/

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-! ## Scalars -/

/-- `target` = the slot at `address`, at this width. A 1- or 4-byte load
zero-extends. -/
def Access.load : Access → Nat → Expr → Stmt
  | .byte, target, address => .loadByte target address
  | .word width, target, address => .loadWord width target address

/-- The slot `value` at `address`, at this width (its low bytes). -/
def Access.store : Access → Expr → Expr → Stmt
  | .byte, address, value => .storeByte address value
  | .word width, address, value => .storeWord width address value

/-- Two lists of widths, the first's where both have one, then the longer's
rest. -/
def mergeWidths : List MemWidth → List MemWidth → List MemWidth
  | [], b => b
  | a :: as, [] => a :: as
  | a :: as, _ :: bs => a :: mergeWidths as bs

/-- Whether two lists of widths agree where both have one. -/
def widthsAgree : List MemWidth → List MemWidth → Bool
  | [], _ => true
  | _ :: _, [] => true
  | a :: as, b :: bs => a.bytes == b.bytes && widthsAgree as bs

mutual
/-- The native widths of a value's slots, in order, for the types whose slot
`j` is a word (`SrcType.uniform`): a scalar's `widthOf` (Core's
`writeNativeValue` and the slice-element code `loadType`/`storeType` use it:
4 bytes for `i32`, `bool`, `u8`, `u16` and `u32`), a `str`'s two words, a
struct's fields' in turn, an array's element's for each element, and an
enum's 4-byte tag, then the widths its payloads agree on
(`variantsAgree`). -/
def SrcType.widths : SrcType → List MemWidth
  | .i32 => [widthOf .i32]
  | .bool => [widthOf .bool]
  | .uint kind => [widthOf (.uint kind)]
  | .struct _ fields => fieldsWidths fields
  | .enum _ variants => .m32 :: variantsWidths variants
  | .ptr => [widthOf .ptr]
  -- Never used: `uniform` keeps slices out of enum payloads.
  | .slice _ => [.m64, .m64, .m64]
  | .array element length => (List.replicate length element.widths).flatten
  | .unit => [widthOf .unit]
  | .isize => [widthOf .isize]
  | .char => [widthOf .char]
  | .float ft => [widthOf (.float ft)]
  | .sint kind => [widthOf (.sint kind)]
  | .view n => [widthOf (.view n)]
  | .str => [.m64, .m64]
  | .ref _ => [.m64]

def fieldsWidths : List SrcType → List MemWidth
  | [] => []
  | t :: rest => t.widths ++ fieldsWidths rest

/-- The widths of an enum's payload slots: each variant's where it has the
slot. -/
def variantsWidths : List (List SrcType) → List MemWidth
  | [] => []
  | fields :: rest => mergeWidths (fieldsWidths fields) (variantsWidths rest)
end

/-- Whether an enum's variants give each payload slot one width (a `bool`
and a `u64` at the same payload slot do not), so its slots have one native
access whatever the variant. -/
def variantsAgree : List (List SrcType) → Bool
  | [] => true
  | fields :: rest => widthsAgree (fieldsWidths fields) (variantsWidths rest) && variantsAgree rest

mutual
/-- `ty.slotAt s`: where slot `s` of a value of `ty` lies in native layout,
as a byte offset from the lowest byte of the value's `8 * ty.words` bytes,
and how it is accessed. Word `k` of the value is `8 * (ty.words - 1 - k)`
bytes up (word 0 is the top word, `NativeLayout`). A `str`'s pointer is word
0 and its count word 1; a slice's pointer word 0, its length word 1 and its
stride word 2, which no slot holds. A packed array's element `s` is
`width * s` bytes up. Another array's element `i` is the element's words
`i` elements below the top. A scalar is accessed at its native width
(`widthOf`: 4 bytes for `i32`, `bool`, `u8`, `u16` and `u32`, as Core and
the slice-element code write it). An enum's tag is word 0, 4 bytes, and its
payload's slot `j` word `1 + j`, at the width its variants agree on (exact
for payloads whose slots are words, `SrcType.homeOk`). -/
def SrcType.slotAt : SrcType → Nat → Nat × Access
  | .i32, _ => (0, .word (widthOf .i32))
  | .bool, _ => (0, .word (widthOf .bool))
  | .uint kind, _ => (0, .word (widthOf (.uint kind)))
  | .struct _ fields, s => fieldsSlotAt (max 1 (fieldWords fields)) 0 fields s
  | .enum id variants, 0 => (8 * ((SrcType.enum id variants).words - 1), .word .m32)
  | .enum id variants, s + 1 =>
      (8 * ((SrcType.enum id variants).words - 1 - (s + 1)), .word ((variantsWidths variants).getD s .m64))
  | .ptr, _ => (0, .word (widthOf .ptr))
  | .slice _, s => (8 * (2 - s), .word .m64)
  | .array element length, s =>
      if element.accessKind.narrow then (element.accessKind.bytes * s, element.accessKind)
      else
        ((8 * (length * element.words - (s / element.size + 1) * element.words) +
            (element.slotAt (s % element.size)).1), (element.slotAt (s % element.size)).2)
  | .unit, _ => (0, .word (widthOf .unit))
  | .isize, _ => (0, .word (widthOf .isize))
  | .char, _ => (0, .word (widthOf .char))
  | .float ft, _ => (0, .word (widthOf (.float ft)))
  | .sint kind, _ => (0, .word (widthOf (.sint kind)))
  | .view n, _ => (0, .word (widthOf (.view n)))
  | .str, s => (8 * (1 - s), .word .m64)
  | .ref _, _ => (0, .word .m64)

/-- Slot `s` of fields whose first one starts `above` words below the top of
a `total`-word value. -/
def fieldsSlotAt (total above : Nat) : List SrcType → Nat → Nat × Access
  | [], _ => (0, .word .m64)
  | t :: rest, s =>
      if s < t.size then
        (8 * (total - above - t.words) + (t.slotAt s).1, (t.slotAt s).2)
      else fieldsSlotAt total (above + t.words) rest (s - t.size)
end

/-- How a reference to a `ty` reaches slot `s` of its referent: by `slotAt`,
except that a `u8` referent is one byte. A `u8` reference may point into a
packed `[u8; n]`, where elements are one byte apart, or at a `u8`'s native
4-byte word, whose 4-byte reading in `HoldsAt` makes its upper bytes zero;
one byte reads and writes both. -/
def SrcType.refSlotAt (ty : SrcType) (s : Nat) : Nat × Access :=
  if ty.isUint .uint8 then (0, .byte) else ty.slotAt s

/-- The bytes a reference's read or write of a `ty` touches: its packed
elements or its scalar's bytes (`refSlotAt`), else all its words. -/
def SrcType.span (ty : SrcType) : Nat :=
  match ty with
  | .array element length =>
      if element.accessKind.narrow then element.accessKind.bytes * length else 8 * ty.words
  | .i32 => (widthOf .i32).bytes
  | .bool => (widthOf .bool).bytes
  | .uint kind => ((SrcType.uint kind).refSlotAt 0).2.bytes
  | .struct _ _ => 8 * ty.words
  | .enum _ _ => 8 * ty.words
  | .ptr => 8 * ty.words
  | .slice _ => 8 * ty.words
  | .unit => 8 * ty.words
  | .isize => 8 * ty.words
  | .char => 8 * ty.words
  | .float _ => 8 * ty.words
  | .sint kind => (widthOf (.sint kind)).bytes
  | .view _ => 8 * ty.words
  | .str => 8 * ty.words
  | .ref _ => 8 * ty.words

/-- The slots of a value of `ty` whose block's lowest byte is `address`,
read from memory in native layout. -/
def SrcType.homeView (ty : SrcType) (address : Nat) (hp : Heap) : Env :=
  fun s => BitVec.ofNat 64 (hp.readLE (address + (ty.slotAt s).1) (ty.slotAt s).2.bytes)

mutual
/-- Whether native layout is exact for this type's slots: no viewed array,
and every enum's payloads take one word per slot (`uniform`) and agree on
each payload slot's width (`variantsAgree`). -/
def SrcType.homeOk : SrcType → Bool
  | .struct _ fields => fieldsHomeOk fields
  | .enum _ variants => variantsUniform variants && variantsAgree variants
  | .array element _ => element.homeOk
  | .view _ => false
  | .i32 => true
  | .bool => true
  | .uint _ => true
  | .ptr => true
  | .slice _ => true
  | .unit => true
  | .isize => true
  | .char => true
  | .float _ => true
  | .sint _ => true
  | .str => true
  | .ref _ => true

def fieldsHomeOk : List SrcType → Bool
  | [] => true
  | t :: rest => t.homeOk && fieldsHomeOk rest

/-- A type whose slot `j` is its native word `j`: scalars, `str`, nonempty
structs of such fields, unpacked arrays of such elements, and enums of such
payloads. -/
def SrcType.uniform : SrcType → Bool
  | .struct _ fields => !fields.isEmpty && fieldsUniform fields
  | .enum _ variants => variantsUniform variants && variantsAgree variants
  | .array element _ => !element.accessKind.narrow && element.uniform
  | .slice _ => false
  | .view _ => false
  | .i32 => true
  | .bool => true
  | .uint _ => true
  | .ptr => true
  | .unit => true
  | .isize => true
  | .char => true
  | .float _ => true
  | .sint _ => true
  | .str => true
  | .ref _ => true

def fieldsUniform : List SrcType → Bool
  | [] => true
  | t :: rest => t.uniform && fieldsUniform rest

def variantsUniform : List (List SrcType) → Bool
  | [] => true
  | fields :: rest => fieldsUniform fields && variantsUniform rest
end

mutual
/-- Whether every enum in the type has at most `2 ^ 32` variants, so that
each tag fits the 4-byte native tag word (Core's `encodeNatLE 4`, and the
4-byte stores and loads at `slotAt`). A value of an enum with more variants
cannot be stored and read back by its tag word. -/
def SrcType.tagsFit : SrcType → Bool
  | .struct _ fields => fieldsTagsFit fields
  | .enum _ variants => decide (variants.length ≤ 2 ^ 32) && variantsTagsFit variants
  | .array element _ => element.tagsFit
  | .i32 => true
  | .bool => true
  | .uint _ => true
  | .ptr => true
  | .slice _ => true
  | .unit => true
  | .isize => true
  | .char => true
  | .float _ => true
  | .sint _ => true
  | .view _ => true
  | .str => true
  | .ref _ => true

def fieldsTagsFit : List SrcType → Bool
  | [] => true
  | t :: rest => t.tagsFit && fieldsTagsFit rest

def variantsTagsFit : List (List SrcType) → Bool
  | [] => true
  | fields :: rest => fieldsTagsFit fields && variantsTagsFit rest
end

/-! ## Homes -/

/-- The homes of the activations, youngest first, and the frame memory
around them. Each home is a whole local (`roots`) in native layout
(`sliced`, exact by `homeOk`). Its cell's value is what its bytes represent
(`holds`), where the slices and references in it name only older homes
(`places.drop (i + 1)`, the age order). The blocks lie between the frame
pointer and the top (`inside`), are apart, and belong to different cells
(`apart`). No view roots at a home's cell (`unviewed`). The static region
is as the program's statics say (`statics`, which `FrameCorr` held). This
replaces `FrameCorr` (design note point 7). -/
structure Homes (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) : Prop where
  holds : ∀ (i : Nat) (x : Addressed), places[i]? = some x → ∃ v, Semantics.readCellProjection st x.cell [] = .ok v ∧
    x.ty.HoldsAt sx (places.drop (i + 1)) v (x.ty.homeView x.address hp) 0
  roots : ∀ x ∈ places, x.projections = []
  sliced : ∀ x ∈ places, x.sliced = true
  layout : ∀ x ∈ places, x.ty.homeOk = true
  inside : ∀ x ∈ places, hp.fsp ≤ x.address ∧ hp.limit ≤ x.address ∧ x.address + 8 * x.ty.words ≤ hp.top
  small : ∀ x ∈ places, x.address + 8 * x.ty.words < 2 ^ 62
  apart : ∀ (i j : Nat) (x y : Addressed), places[i]? = some x → places[j]? = some y → i ≠ j →
    x.cell ≠ y.cell ∧ (x.address + 8 * x.ty.words ≤ y.address ∨ y.address + 8 * y.ty.words ≤ x.address)
  unviewed : ∀ v ∈ st.i32ArrayViews, ∀ x ∈ places, v.root ≠ x.cell
  room : 0 < bud.room + bud.block → hp.limit + bud.room ≤ hp.fsp
  ceiling : 0 < bud.room + bud.block → hp.fsp + bud.block ≤ hp.top
  bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62
  statics : hp.StaticsAt sx

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
