import Lanius.Extraction.Parser.Derivation.Runtime

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Execute all three real child-field calls and bind their results. The
    continuation receives the persistent reader frame and exact field values.
    Cell postconditions survive lexical restoration; the returned effect
    separately restores all caller-local bindings. -/
theorem ReaderRuntime.At.initialize_child {reader : ReaderRuntime}
    {post : List Cell → Prop}
    (held : reader.At stateId remaining before)
    (found : reader.workspace.state? stateId = some state)
    (previousFresh : reader.tail.previous ∉ reader.liveLocals)
    (tagFresh : reader.stores.tag ∉ reader.liveLocals)
    (payloadFresh : reader.stores.payload ∉ reader.liveLocals)
    (distinct : reader.tail.previous ≠ reader.stores.tag ∧
      reader.tail.previous ≠ reader.stores.payload ∧ reader.stores.tag ≠ reader.stores.payload)
    (body : Stmt)
    (continuation : ∀ runtime, reader.At stateId remaining runtime →
      runtime.local? reader.tail.previous = some (.signed .i32 (previousValue state.previous)) →
      runtime.local? reader.stores.tag = some (.signed .i32 (childTag state.child)) →
      runtime.local? reader.stores.payload = some (.signed .i32 (childPayload state.child)) →
      ∃ after, Executes verifiedParserCore runtime body completion after ∧
        post after.cells ∧ CellEffect writes runtime after) :
    ∃ after, Executes verifiedParserCore before
      (.letLocal reader.tail.previous parserI32Type
        (.call extractedParserStateValueFunction.id [.local reader.stores.workspace,
          .local reader.stores.base, .local reader.stores.current, .constant 33])
        (.letLocal reader.stores.tag parserI32Type
          (.call extractedParserStateValueFunction.id [.local reader.stores.workspace,
            .local reader.stores.base, .local reader.stores.current, .constant 34])
          (.letLocal reader.stores.payload parserI32Type
            (.call extractedParserStateValueFunction.id [.local reader.stores.workspace,
              .local reader.stores.base, .local reader.stores.current, .constant 35]) body)))
      completion after ∧ post after.cells ∧ CellEffect writes before after := by
  apply held.artifact.let_field (post := fun runtime => post runtime.cells)
    held.wellFormed found (field := 5) (by decide) held.workspaceLocal held.baseLocal
    (Assertion.localPointsTo_local _ _ _ _ held.currentOwned) (by rfl)
  intro first effect1 _ _
  have held1 := (held.after_read effect1).bind previousFresh
    (.signed .i32 (previousValue state.previous))
  have previous1 := bindLocal_finds_local first reader.tail.previous
    (.signed .i32 (previousValue state.previous)) effect1.wellFormed
  apply held1.artifact.let_field (post := fun runtime => post runtime.cells)
    held1.wellFormed found (field := 6) (by decide) held1.workspaceLocal held1.baseLocal
    (Assertion.localPointsTo_local _ _ _ _ held1.currentOwned) (by rfl)
  intro second effect2 _ _
  have held2 := (held1.after_read effect2).bind tagFresh (.signed .i32 (childTag state.child))
  have previous2 := (bindLocal_preserves_other_local (value := .signed .i32 (childTag state.child)) effect2.wellFormed
    (Ne.symm distinct.1)).trans (effect2.empty_preserves_local held1.wellFormed previous1)
  have tag2 := bindLocal_finds_local second reader.stores.tag
    (.signed .i32 (childTag state.child)) effect2.wellFormed
  apply held2.artifact.let_field (post := fun runtime => post runtime.cells)
    held2.wellFormed found (field := 7) (by decide) held2.workspaceLocal held2.baseLocal
    (Assertion.localPointsTo_local _ _ _ _ held2.currentOwned) (by rfl)
  intro third effect3 _ _
  have held3 := (held2.after_read effect3).bind payloadFresh (.signed .i32 (childPayload state.child))
  have previous3 := (bindLocal_preserves_other_local (value := .signed .i32 (childPayload state.child)) effect3.wellFormed
    (Ne.symm distinct.2.1)).trans (effect3.empty_preserves_local held2.wellFormed previous2)
  have tag3 := (bindLocal_preserves_other_local (value := .signed .i32 (childPayload state.child)) effect3.wellFormed
    (Ne.symm distinct.2.2)).trans (effect3.empty_preserves_local held2.wellFormed tag2)
  exact continuation _ held3 previous3 tag3
    (bindLocal_finds_local third reader.stores.payload (.signed .i32 (childPayload state.child))
      effect3.wellFormed)

end Lanius.Extraction.ParserDerivation
