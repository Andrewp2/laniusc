import Lanius.X86.ProgramCheck

namespace Lanius.X86.ImageCheck

open Lanius Lanius.X86
open Lanius.X86.ProgramCheck

/- The small part of the backend image ABI that this checker authenticates.
   `entryOffset` and `codeOffset` are offsets in the RX segment, not file
   addresses.  Keeping these parameters makes the checker reusable for the
   same ELF layout while the `lanius` value records image.lani's constants. -/
structure Layout where
  base : Machine.Address
  entryOffset : Nat
  codeOffset : Nat

def Layout.entry (layout : Layout) : Machine.Address :=
  layout.base + BitVec.ofNat 64 layout.entryOffset

def lanius : Layout :=
  { base := BitVec.ofNat 64 4194304, entryOffset := 256, codeOffset := 512 }

def Field := Nat × UInt8

def byteFields (offset value width : Nat) : List Field :=
  (List.range width).map fun index =>
    (offset + index, UInt8.ofNat (value / (256 ^ index)))

def fields (layout : Layout) (length : Nat) : List Field :=
  ([(0, 127), (1, 69), (2, 76), (3, 70), (4, 2), (5, 1), (6, 1)] : List Field) ++
  byteFields 7 0 9 ++
  byteFields 16 2 2 ++ byteFields 18 62 2 ++ byteFields 20 1 4 ++
  byteFields 24 layout.entry.toNat 8 ++ byteFields 32 64 8 ++
  byteFields 40 0 8 ++ byteFields 48 0 4 ++
  byteFields 52 64 2 ++ byteFields 54 56 2 ++ byteFields 56 2 2 ++
  byteFields 58 0 6 ++
  byteFields 64 1 4 ++ byteFields 68 5 4 ++ byteFields 72 0 8 ++
  byteFields 80 layout.base.toNat 8 ++ byteFields 88 layout.base.toNat 8 ++
  byteFields 96 length 8 ++ byteFields 104 length 8 ++
  byteFields 112 4096 8 ++ byteFields 120 1685382481 4 ++
  byteFields 124 6 4 ++ byteFields 128 0 8 ++ byteFields 136 0 8 ++
  byteFields 144 0 8 ++ byteFields 152 0 8 ++ byteFields 160 0 8 ++
  byteFields 168 16 8

def fieldOK (bytes : List UInt8) (field : Field) : Bool :=
  bytes[field.1]? == some field.2

def fieldsOK (bytes : List UInt8) (expected : List Field) : Bool :=
  expected.all (fieldOK bytes)

structure HeaderEvidence (layout : Layout) (bytes : List UInt8) : Type where
  fieldsChecked : fieldsOK bytes (fields layout bytes.length) = true
  lengthBound : bytes.length < 2 ^ 64

def checkHeader (layout : Layout) (bytes : List UInt8) :
    Option (HeaderEvidence layout bytes) :=
  if lengthBound : bytes.length < 2 ^ 64 then
    if fieldsChecked : fieldsOK bytes (fields layout bytes.length) then
      some ⟨fieldsChecked, lengthBound⟩
    else none
  else none

theorem HeaderEvidence.field {layout : Layout} {bytes : List UInt8}
    (checked : HeaderEvidence layout bytes) {field : Field}
    (member : field ∈ fields layout bytes.length) :
    bytes[field.1]? = some field.2 := by
  have all := List.all_eq_true.mp checked.fieldsChecked field member
  simpa [fieldOK] using all

structure SliceEvidence (layout : Layout) (bytes : List UInt8) where
  image : FunctionImage
  offset : Nat
  codeOffsetBound : layout.codeOffset ≤ offset
  offsetBound : offset + image.bytes.length ≤ bytes.length
  addressExact : image.address = layout.base + BitVec.ofNat 64 offset
  bytesExact : (bytes.drop offset).take image.bytes.length = image.bytes

def checkSlice (layout : Layout) (bytes : List UInt8) (image : FunctionImage) :
    Option (SliceEvidence layout bytes) :=
  let offset := image.address.toNat - layout.base.toNat
  if _baseBound : layout.base.toNat ≤ image.address.toNat then
    if codeOffsetBound : layout.codeOffset ≤ offset then
      if offsetBound : offset + image.bytes.length ≤ bytes.length then
        if addressExact : image.address = layout.base + BitVec.ofNat 64 offset then
          if bytesExact : (bytes.drop offset).take image.bytes.length = image.bytes then
            some ⟨image, offset, codeOffsetBound, offsetBound, addressExact, bytesExact⟩
          else none
        else none
      else none
    else none
  else none

theorem checkSlice_image {layout : Layout} {bytes : List UInt8}
    {image : FunctionImage} {checked : SliceEvidence layout bytes}
    (accepted : checkSlice layout bytes image = some checked) :
    checked.image = image := by
  unfold checkSlice at accepted
  split at accepted <;> try contradiction
  dsimp only at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  rfl

def checkSlices (layout : Layout) (bytes : List UInt8) :
    List FunctionImage → Option (List (SliceEvidence layout bytes))
  | [] => some []
  | image :: images => do
      let checked ← checkSlice layout bytes image
      let rest ← checkSlices layout bytes images
      return checked :: rest

theorem checkSlices_sound {layout : Layout} {bytes : List UInt8}
    {images : List FunctionImage} {checked : List (SliceEvidence layout bytes)}
    (accepted : checkSlices layout bytes images = some checked) :
    checked.map (fun item => item.image) = images := by
  induction images generalizing checked with
  | nil => simp [checkSlices] at accepted; cases accepted; rfl
  | cons image images ih =>
      simp only [checkSlices] at accepted
      cases h : checkSlice layout bytes image with
      | none => simp [h] at accepted
      | some first =>
          cases h' : checkSlices layout bytes images with
          | none => simp [h, h'] at accepted
          | some rest =>
              simp [h, h'] at accepted
              cases accepted
              have tail := ih h'
              simp only [List.map_cons]
              have imageExact : first.image = image := checkSlice_image h
              simpa only [imageExact] using congrArg (List.cons first.image) tail

theorem SliceEvidence.loaded {layout : Layout} {bytes : List UInt8}
    (slice : SliceEvidence layout bytes)
    (mapped : Machine.CodeAt memory layout.base bytes) :
    Machine.CodeAt memory slice.image.address slice.image.bytes := by
  intro index bound
  have sourceBound : slice.offset + index < bytes.length := by
    have offsetBound := slice.offsetBound
    omega
  have sourceSlice? : bytes[slice.offset + index]? =
      some slice.image.bytes[index] := by
    have equality := congrArg (fun values : List UInt8 => values[index]?)
      slice.bytesExact
    simp only [List.getElem?_take, List.getElem?_drop, if_pos bound] at equality
    simpa only [List.getElem?_eq_getElem sourceBound,
      List.getElem?_eq_getElem bound] using equality
  have sourceSlice : bytes[slice.offset + index] = slice.image.bytes[index] := by
    exact Option.some.inj
      ((List.getElem?_eq_getElem sourceBound).symm.trans sourceSlice?)
  calc
    memory (slice.image.address + BitVec.ofNat 64 index) =
        memory (layout.base + BitVec.ofNat 64 slice.offset +
          BitVec.ofNat 64 index) := by rw [slice.addressExact]
    _ = memory (layout.base + BitVec.ofNat 64 (slice.offset + index)) := by
      congr 1
      rw [BitVec.add_assoc, ← BitVec.ofNat_add]
    _ = bytes[slice.offset + index] := mapped (slice.offset + index) sourceBound
    _ = slice.image.bytes[index] := sourceSlice

theorem checkHeader_sound {layout : Layout} {bytes : List UInt8}
    {checked : HeaderEvidence layout bytes}
    (_accepted : checkHeader layout bytes = some checked) :
    fieldsOK bytes (fields layout bytes.length) = true :=
  checked.fieldsChecked

structure Checked (layout : Layout) (bytes : List UInt8)
    (image : ProgramCheck.Image) where
  header : HeaderEvidence layout bytes
  slices : List (SliceEvidence layout bytes)
  slicesExact : slices.map (fun item => item.image) = image.functions

def check (layout : Layout) (bytes : List UInt8) (image : ProgramCheck.Image) :
    Option (Checked layout bytes image) :=
  match _headerChecked : checkHeader layout bytes with
  | none => none
  | some header =>
      match slicesChecked : checkSlices layout bytes image.functions with
      | none => none
      | some slices =>
          some ⟨header, slices, checkSlices_sound slicesChecked⟩

theorem Checked.slice_loaded {layout : Layout} {bytes : List UInt8}
    {image : ProgramCheck.Image} (checked : Checked layout bytes image)
    (mapped : Machine.CodeAt memory layout.base bytes)
    (function : FunctionImage) (member : function ∈ image.functions) :
    Machine.CodeAt memory function.address function.bytes := by
  have member' : function ∈ checked.slices.map (fun item => item.image) := by
    rw [checked.slicesExact]
    exact member
  rcases List.mem_map.mp member' with ⟨slice, sliceMember, imageEq⟩
  subst function
  exact slice.loaded mapped

theorem Checked.loaded_program {layout : Layout} {bytes : List UInt8}
    {image : ProgramCheck.Image} (checked : Checked layout bytes image)
    {executable : Execution.Executable}
    (programChecked : ProgramCheck.Checked executable image)
    (machine : Machine.State)
    (mapped : Machine.CodeAt machine.memory layout.base bytes) :
    ProgramCheck.Loaded programChecked machine := by
  intro evidence member
  apply checked.slice_loaded mapped evidence.image
  have member' : evidence.image ∈
      programChecked.functions.map (fun item => item.image) :=
    List.mem_map.mpr ⟨evidence, member, rfl⟩
  rw [programChecked.imageExact] at member'
  exact member'

theorem Checked.entrypoint_loaded {layout : Layout} {bytes : List UInt8}
    {image : ProgramCheck.Image} (checked : Checked layout bytes image)
    {executable : Execution.Executable}
    (programChecked : ProgramCheck.Checked executable image)
    (machine : Machine.State)
    (mapped : Machine.CodeAt machine.memory layout.base bytes) :
    Machine.CodeAt machine.memory programChecked.entrypoint.image.address
      programChecked.entrypoint.image.bytes := by
  exact checked.slice_loaded mapped programChecked.entrypoint.image
    (by
      have found : programChecked.entrypoint ∈ programChecked.functions :=
        findEntrypoint_mem programChecked.entrypointFound
      have mappedMember : programChecked.entrypoint.image ∈
          programChecked.functions.map (fun item => item.image) :=
        List.mem_map.mpr ⟨programChecked.entrypoint, found, rfl⟩
      rw [programChecked.imageExact] at mappedMember
      exact mappedMember)

end Lanius.X86.ImageCheck
