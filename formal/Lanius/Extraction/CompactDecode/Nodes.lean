import Lanius.Extraction.CompactDecode.Fields
import Lanius.Extraction.CompactDecode.Bytes
import Lanius.Extraction.CompactOutput.Nodes.HeaderWrite
import Lanius.Extraction.CompactOutput.Nodes.Emit

namespace Lanius.Extraction.CompactDecode

open CompactOutput SemanticTokens Lanius.Compiler.Parser

def decodedChild : ChildVisit → ParseChild
  | .token use => .token use.token
  | .node id _ _ => .node id

theorem readChild_encoding (child : ChildVisit)
    (fit : (childPayload child.reference).toNat < 4294967296)
    (encoded : EncodedAt bytes offset (Nodes.encodeChild child)) :
    readChild.run {bytes, offset} =
      some (decodedChild child, {bytes, offset := offset + 16}) := by
  cases child with
  | token use =>
    simpa [Nodes.encodeChild, Nodes.childEncoding, ChildVisit.reference,
      childTag, childPayload, decodedChild] using
      readChild_fields (tag := 1) (Or.inl rfl) fit encoded
  | node id start finish =>
    simpa [Nodes.encodeChild, Nodes.childEncoding, ChildVisit.reference,
      childTag, childPayload, decodedChild] using
      readChild_fields (tag := 2) (Or.inr rfl) fit encoded

theorem reads_children (children : List ChildVisit)
    (fit : ∀ child ∈ children, (childPayload child.reference).toNat < 4294967296)
    (encoded : EncodedAt bytes offset (Nodes.encodeChildren children)) :
    Reads readChild {bytes, offset} (children.map decodedChild)
      {bytes, offset := offset + children.length * 16} := by
  induction children generalizing offset with
  | nil => exact Reads.nil
  | cons child children ih =>
    have head := readChild_encoding child (fit child List.mem_cons_self) encoded.left
    have rest := encoded.right
    simp only [Nodes.encodeChild_length] at rest
    have tail := ih (fun c h => fit c (List.mem_cons_of_mem child h)) rest
    simpa [List.length_cons, Nat.add_mul, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]
      using Reads.cons head tail

theorem readNode_header (record : RecordVisit) (children : List ParseChild)
    (productionFound : laniusGrammar.production? record.production = some production)
    (productionFit : record.production < 4294967296)
    (startFit : record.start < 4294967296) (finishFit : record.finish < 4294967296)
    (countFit : record.children.length < 4294967296)
    (count : children.length = record.children.length)
    (encoded : EncodedAt bytes offset (Nodes.encodeHeader record))
    (room : children.length * 16 ≤ bytes.size - (offset + 32))
    (childrenRead : Reads readChild {bytes, offset := offset + 32} children after) :
    readNode.run {bytes, offset} =
      some (⟨record.production, production.lhs, record.start, record.finish, children⟩, after) := by
  have p := readU32_hex productionFit encoded.left.left.left
  have s := readU32_hex startFit encoded.left.left.right
  have f := readU32_hex finishFit encoded.left.right
  have c := readU32_hex countFit encoded.right
  simp only [hexDigits_length, List.length_append] at s f c
  have guard := ensureRemaining_ok (state := {bytes, offset := offset + 32}) room
  have childRun := childrenRead.readMany
  rw [count] at childRun guard
  simp only [readNode, StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at p s f c
  rw [p]
  simp only [Option.bind_some, productionFound]
  dsimp only [StateT.bind]
  rw [s]
  dsimp only [bind, Option.bind]
  simp only [Nat.add_assoc]
  rw [f]
  dsimp only [bind, Option.bind]
  simp only [Nat.add_assoc]
  rw [c]
  dsimp only [StateT.run, bind, StateT.bind, pure, StateT.pure] at guard childRun ⊢
  simp only [Nat.add_assoc] at guard childRun ⊢
  rw [guard]
  dsimp only
  rw [childRun]

theorem children_encoding_length (children : List ChildVisit) :
    (Nodes.encodeChildren children).length = children.length * 16 := by
  induction children with
  | nil => rfl
  | cons child children ih =>
    change (Nodes.encodeChild child ++ Nodes.encodeChildren children).length = _
    rw [List.length_append, Nodes.encodeChild_length, ih]
    simp [Nat.add_mul, Nat.add_comm]

theorem readNode_encoding (record : RecordVisit)
    (productionFound : laniusGrammar.production? record.production = some production)
    (productionFit : record.production < 4294967296)
    (startFit : record.start < 4294967296) (finishFit : record.finish < 4294967296)
    (countFit : record.children.length < 4294967296)
    (childrenFit : ∀ child ∈ record.children, (childPayload child.reference).toNat < 4294967296)
    (encoded : EncodedAt bytes offset (Nodes.encodeRecord record)) :
    readNode.run {bytes, offset} =
      some (⟨record.production, production.lhs, record.start, record.finish,
        record.children.map decodedChild⟩,
        {bytes, offset := offset + 32 + record.children.length * 16}) := by
  have rest := encoded.right
  simp only [Nodes.encodeHeader, List.length_append, hexDigits_length] at rest
  have room := rest.remaining
  rw [children_encoding_length] at room
  exact readNode_header record (record.children.map decodedChild) productionFound
    productionFit startFit finishFit countFit (List.length_map ..) encoded.left
    (by simpa only [List.length_map] using room)
    (reads_children record.children childrenFit rest)

def decodedNode (record : RecordVisit) : ParseNode :=
  ⟨record.production, ((laniusGrammar.production? record.production).map (·.lhs)).getD 0,
    record.start, record.finish, record.children.map decodedChild⟩

structure NodeEncodable (record : RecordVisit) : Prop where
  production : ∃ p, laniusGrammar.production? record.production = some p
  productionFit : record.production < 4294967296
  startFit : record.start < 4294967296
  finishFit : record.finish < 4294967296
  countFit : record.children.length < 4294967296
  childrenFit : ∀ child ∈ record.children, (childPayload child.reference).toNat < 4294967296

theorem record_encoding_length (record : RecordVisit) :
    (Nodes.encodeRecord record).length = 32 + record.children.length * 16 := by
  simp only [Nodes.encodeRecord, List.length_append, Nodes.encodeHeader,
    hexDigits_length, children_encoding_length]

theorem reads_nodes (records : List RecordVisit)
    (valid : ∀ record ∈ records, NodeEncodable record)
    (encoded : EncodedAt bytes offset (records.flatMap Nodes.encodeRecord)) :
    Reads readNode {bytes, offset} (records.map decodedNode)
      {bytes, offset := offset + (records.flatMap Nodes.encodeRecord).length} := by
  induction records generalizing offset with
  | nil => exact Reads.nil
  | cons record records ih =>
    have fits := valid record List.mem_cons_self
    obtain ⟨production, found⟩ := fits.production
    have head := readNode_encoding record found fits.productionFit fits.startFit fits.finishFit
      fits.countFit fits.childrenFit encoded.left
    have tail := ih (fun r h => valid r (List.mem_cons_of_mem record h)) encoded.right
    have head' : readNode.run {bytes, offset} =
        some (decodedNode record, {bytes, offset := offset + (Nodes.encodeRecord record).length}) := by
      simpa [decodedNode, found, record_encoding_length, Nat.add_assoc] using head
    simpa only [List.map_cons, List.flatMap_cons, List.length_append, Nat.add_assoc]
      using Reads.cons head' tail

theorem readNodes_encoding (records : List RecordVisit)
    (valid : ∀ record ∈ records, NodeEncodable record)
    (encoded : EncodedAt bytes offset (records.flatMap Nodes.encodeRecord)) :
    (readMany records.length readNode).run {bytes, offset} =
      some (records.map decodedNode,
        {bytes, offset := offset + (records.flatMap Nodes.encodeRecord).length}) := by
  simpa only [List.length_map] using (reads_nodes records valid encoded).readMany

end Lanius.Extraction.CompactDecode
