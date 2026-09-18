import Lanius.Extraction.CompactDecode.RoundTrip

namespace Lanius.Extraction.CompactDecode

/-- Production IDs are indices, so authentication needs one bounds check,
not a repeated lookup of the production's complete grammar record. -/
theorem NodeEncodable.iff_bounds (record : SemanticTokens.RecordVisit) :
    NodeEncodable record ↔
      record.production < laniusGrammar.productions.length ∧
      record.production < 4294967296 ∧ record.start < 4294967296 ∧
      record.finish < 4294967296 ∧ record.children.length < 4294967296 ∧
      ∀ child ∈ record.children,
        (Lanius.Compiler.Parser.childPayload child.reference).toNat < 4294967296 := by
  constructor
  · intro valid
    obtain ⟨production, found⟩ := valid.production
    exact ⟨(List.getElem?_eq_some_iff.mp found).1, valid.productionFit,
      valid.startFit, valid.finishFit, valid.countFit, valid.childrenFit⟩
  · rintro ⟨production, productionFit, startFit, finishFit, countFit, childrenFit⟩
    exact ⟨⟨_, List.getElem?_eq_getElem production⟩, productionFit,
      startFit, finishFit, countFit, childrenFit⟩

/-- A Boolean scan avoids constructing nested logical decision trees for
every record in a large concrete pack. Its all-input equivalence is below. -/
def nodeEncodable (record : SemanticTokens.RecordVisit) : Bool :=
  Nat.blt record.production laniusGrammar.productions.length &&
  Nat.blt record.production 4294967296 && Nat.blt record.start 4294967296 &&
  Nat.blt record.finish 4294967296 && Nat.blt record.children.length 4294967296 &&
    record.children.all (fun child =>
      Nat.blt (Lanius.Compiler.Parser.childPayload child.reference).toNat 4294967296)

theorem nodeEncodable_eq_true : nodeEncodable record = true ↔ NodeEncodable record := by
  rw [NodeEncodable.iff_bounds]
  simp only [nodeEncodable, Bool.and_eq_true, Nat.blt_eq, List.all_eq_true, and_assoc]

instance (record : SemanticTokens.RecordVisit) : Decidable (NodeEncodable record) :=
  decidable_of_iff (nodeEncodable record = true) nodeEncodable_eq_true

theorem UnitData.Encodable.iff_fields (data : UnitData) :
    data.Encodable ↔
      data.path.toUTF8.size < 4294967296 ∧ data.source.size < 4294967296 ∧
      data.raw.length < 4294967296 ∧ data.tokens.length < 4294967296 ∧
      data.nodes.length < 4294967296 ∧
      (∀ t ∈ data.raw, t.kind.gpuCode < 4294967296 ∧ t.start < 4294967296 ∧ t.finish < 4294967296) ∧
      (∀ t ∈ data.tokens, t.kind.gpuCode < 4294967296 ∧ t.start < 4294967296 ∧ t.finish < 4294967296) ∧
      (∀ a ∈ data.assignments, a.first < 4294967296 ∧
        (CompactOutput.Assignments.secondWord a + 1).toNat < 4294967296) ∧
      data.assignments.length = data.tokens.length ∧
      ∀ node ∈ data.nodes, NodeEncodable node :=
  ⟨fun valid => ⟨valid.pathFit, valid.sourceFit, valid.rawFit, valid.tokenFit,
      valid.nodeFit, valid.rawFields, valid.tokenFields, valid.assignments,
      valid.assignmentCount, valid.nodes⟩,
    fun ⟨p, s, r, t, n, rf, tf, a, ac, ns⟩ => ⟨p, s, r, t, n, rf, tf, a, ac, ns⟩⟩

def UnitData.isEncodable (data : UnitData) : Bool :=
  Nat.blt data.path.toUTF8.size 4294967296 && Nat.blt data.source.size 4294967296 &&
  Nat.blt data.raw.length 4294967296 && Nat.blt data.tokens.length 4294967296 &&
  Nat.blt data.nodes.length 4294967296 &&
  data.raw.all (fun t => Nat.blt t.kind.gpuCode 4294967296 && Nat.blt t.start 4294967296 && Nat.blt t.finish 4294967296) &&
  data.tokens.all (fun t => Nat.blt t.kind.gpuCode 4294967296 && Nat.blt t.start 4294967296 && Nat.blt t.finish 4294967296) &&
  data.assignments.all (fun a => Nat.blt a.first 4294967296 &&
    Nat.blt (CompactOutput.Assignments.secondWord a + 1).toNat 4294967296) &&
  decide (data.assignments.length = data.tokens.length) &&
  data.nodes.all nodeEncodable

theorem UnitData.isEncodable_eq_true {data : UnitData} : data.isEncodable = true ↔ data.Encodable := by
  rw [UnitData.Encodable.iff_fields]
  simp only [UnitData.isEncodable, Bool.and_eq_true, Nat.blt_eq, decide_eq_true_eq, List.all_eq_true,
    nodeEncodable_eq_true, and_assoc]

instance (data : UnitData) : Decidable data.Encodable :=
  decidable_of_iff (data.isEncodable = true) UnitData.isEncodable_eq_true

/-- The finite obligations required by the complete public decoder round trip.
The source/parse and Core checkers must still validate the decoded artifact. -/
def PackEncodable (units : List UnitData) : Prop :=
  units ≠ [] ∧ units.length < 4294967296 ∧
    ∀ unit ∈ units, unit.Encodable ∧ unit.nodes ≠ []
deriving Decidable

theorem PackEncodable.decoded (valid : PackEncodable units) :
    decodeCompactArtifactPack? (renderedPack units.length units) =
      some ⟨schemaVersion, units.map UnitData.artifact⟩ :=
  decode_renderedPack units valid.2.2 valid.1 valid.2.1

end Lanius.Extraction.CompactDecode
