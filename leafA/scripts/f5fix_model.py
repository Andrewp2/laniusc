import sys
p = sys.argv[1]
s = open(p).read()
def rep(old, new, count=1):
    global s
    n = s.count(old)
    assert n == count, (n, old[:80])
    s = s.replace(old, new)

rep("public import Lanius.Mini.SourceCore\n",
    "public import Lanius.Mini.SourceCore\npublic import Lanius.Mini.Compiler.P.widthOf\npublic import Lanius.Mini.Compiler.P.UintTy_half\n")

rep("""/-- A scalar's access width: 4 bytes for an `i32`, 1 for a `u8`, 8 for the
others. A scalar takes one 8-byte word of native layout; an `i32` or `u8`
has zero upper bytes there (`SrcType.Holds`), so its narrow access reads the
same value, and an `i32` or `u8` array element is packed at this width. -/""",
"""/-- How an element of an array of this type is packed: an `i32` at 4 bytes
and a `u8` at 1 (`narrow`, the packed arrays); the others are not packed and
take whole native words. A scalar outside a packed array is accessed at its
native width instead (`widthOf`, `SrcType.slotAt`). -/""")

rep("""/-- The largest payload's words. -/
def variantWords : List (List SrcType) → Nat
  | [] => 0
  | fields :: rest => max (fieldWords fields) (variantWords rest)
end
""", """/-- The largest payload's words. -/
def variantWords : List (List SrcType) → Nat
  | [] => 0
  | fields :: rest => max (fieldWords fields) (variantWords rest)
end

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
  | .slice _ => [.m64, .m64, .m64]
  | .array element length => (List.replicate length element.widths).flatten
  | .unit => [widthOf .unit]
  | .isize => [widthOf .isize]
  | .char => [widthOf .char]
  | .float ft => [widthOf (.float ft)]
  | .sint kind => [widthOf (.sint kind)]
  | .view n => [widthOf (.view n)]
  | .str => [.m64, .m64]

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
""")

rep("""`i` elements below the top. An enum's tag is word 0 and its payload's slot
`j` word `1 + j` (exact for payloads whose slots are words,
`SrcType.homeOk`). -/""", """`i` elements below the top. A scalar is accessed at its native width
(`widthOf`: 4 bytes for `i32`, `bool`, `u8`, `u16` and `u32`, as Core and
the slice-element code write it). An enum's tag is word 0, 4 bytes, and its
payload's slot `j` word `1 + j`, at the width its variants agree on (exact
for payloads whose slots are words, `SrcType.homeOk`). -/""")

rep("""  | .i32, _ => (0, .word .m32)
  | .bool, _ => (0, .word .m64)
  | .uint kind, _ => (0, (SrcType.uint kind).accessKind)
  | .struct _ fields, s => fieldsSlotAt (max 1 (fieldWords fields)) 0 fields s
  | .enum id variants, s =>
      (8 * ((SrcType.enum id variants).words - 1 - s), .word .m64)
  | .ptr, _ => (0, .word .m64)""", """  | .i32, _ => (0, .word (widthOf .i32))
  | .bool, _ => (0, .word (widthOf .bool))
  | .uint kind, _ => (0, .word (widthOf (.uint kind)))
  | .struct _ fields, s => fieldsSlotAt (max 1 (fieldWords fields)) 0 fields s
  | .enum id variants, 0 => (8 * ((SrcType.enum id variants).words - 1), .word .m32)
  | .enum id variants, s + 1 =>
      (8 * ((SrcType.enum id variants).words - 1 - (s + 1)), .word ((variantsWidths variants).getD s .m64))
  | .ptr, _ => (0, .word (widthOf .ptr))""")

rep("""  | .unit, _ => (0, .word .m64)
  | .isize, _ => (0, .word .m64)
  | .char, _ => (0, .word .m64)
  | .float _, _ => (0, .word .m64)
  | .sint _, _ => (0, .word .m64)
  | .view _, _ => (0, .word .m64)
  | .str, s => (8 * (1 - s), .word .m64)""", """  | .unit, _ => (0, .word (widthOf .unit))
  | .isize, _ => (0, .word (widthOf .isize))
  | .char, _ => (0, .word (widthOf .char))
  | .float ft, _ => (0, .word (widthOf (.float ft)))
  | .sint kind, _ => (0, .word (widthOf (.sint kind)))
  | .view n, _ => (0, .word (widthOf (.view n)))
  | .str, s => (8 * (1 - s), .word .m64)""")

rep("""/-- The bytes a value of this type is read and written in: its packed
elements or its narrow scalar's bytes, else all its words. -/
def SrcType.span (ty : SrcType) : Nat :=
  match ty with
  | .array element length =>
      if element.accessKind.narrow then element.accessKind.bytes * length else 8 * ty.words
  | .i32 => 4
  | .bool => 8 * ty.words
  | .uint _ => ty.accessKind.bytes
""", """/-- How a reference to a `ty` reaches slot `s` of its referent: by `slotAt`,
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
""")
rep("""  | .sint _ => 8 * ty.words
  | .view _ => 8 * ty.words
  | .str => 8 * ty.words

/-- The slots""", """  | .sint kind => (widthOf (.sint kind)).bytes
  | .view _ => 8 * ty.words
  | .str => 8 * ty.words

/-- The slots""")

rep("""/-- Whether native layout is exact for this type's slots: no viewed array,
and every enum's payloads take one word per slot (`uniform`). -/""",
"""/-- Whether native layout is exact for this type's slots: no viewed array,
and every enum's payloads take one word per slot (`uniform`) and agree on
each payload slot's width (`variantsAgree`). -/""")
rep("""  | .enum _ variants => variantsUniform variants
  | .array element _ => element.homeOk""", """  | .enum _ variants => variantsUniform variants && variantsAgree variants
  | .array element _ => element.homeOk""")
rep("""  | .enum _ variants => variantsUniform variants
  | .array element _ => !element.accessKind.narrow && element.uniform""",
"""  | .enum _ variants => variantsUniform variants && variantsAgree variants
  | .array element _ => !element.accessKind.narrow && element.uniform""")

rep("""  | s, count + 1 => .seq ((ty.slotAt s).2.load (target + s) (addOff r (ty.slotAt s).1))""",
    """  | s, count + 1 => .seq ((ty.refSlotAt s).2.load (target + s) (addOff r (ty.refSlotAt s).1))""")
rep("""  | s, count + 1 => .seq ((ty.slotAt s).2.store (addOff r (ty.slotAt s).1) (.var (slot + s)))""",
    """  | s, count + 1 => .seq ((ty.refSlotAt s).2.store (addOff r (ty.refSlotAt s).1) (.var (slot + s)))""")

# Homes: statics
rep("""(`apart`). No view roots at a home's cell (`unviewed`). This replaces
`FrameCorr` (design note point 6). -/""", """(`apart`). No view roots at a home's cell (`unviewed`). The static region
is as the program's statics say (`statics`, which `FrameCorr` held). This
replaces `FrameCorr` (design note point 7). -/""")
rep("""  bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62

/-! ## Code templates -/""", """  bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62
  statics : hp.StaticsAt sx

/-! ## Code templates -/""")
open(p, "w").write(s)
print("ok")
