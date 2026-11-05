module

public import Lanius.Mini.FrameCorr
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
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap

@[expose] public section

/-! # Homes: blocks of frame memory in native layout (F5)

`Homes` (SEMANTIC_DECISIONS "References: the memory model") and the layout
definitions it reads (`slotAt`, `homeView`, `homeOk`), moved here from
`Refs/Model.lean` with their names so that the simulation (`LentHomes`,
stage 2 S6a-1) can use them: `Refs/Model.lean` imports the lowering's
failure lemmas, which import the simulation. Not trusted.
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

/-- The bytes a home takes: its native words. -/
def Addressed.Within (x : Addressed) (a : Nat) : Prop := x.address ≤ a ∧ a < x.address + 8 * x.ty.words

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

end Lanius.Mini
