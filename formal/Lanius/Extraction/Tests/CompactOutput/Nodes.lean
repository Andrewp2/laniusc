import Lanius.Extraction.CompactOutput.Nodes.Validate
import Lanius.Extraction.CompactOutput.Nodes.Write
import Lanius.Extraction.CompactOutput.Nodes.Source
import Lanius.Extraction.CompactOutput.Nodes.Scope
import Lanius.Extraction.CompactOutput.Nodes.Fields
import Lanius.Extraction.CompactOutput.Nodes.Entry
import Lanius.Extraction.CompactOutput.Nodes.Failure
import Lanius.Extraction.CompactOutput.Nodes.Success
import Lanius.Extraction.CompactOutput.Nodes.ChildState
import Lanius.Extraction.CompactOutput.Nodes.ChildLoop
import Lanius.Extraction.CompactOutput.Nodes.Header
import Lanius.Extraction.CompactOutput.Nodes.HeaderWrite
import Lanius.Extraction.CompactOutput.Nodes.ChildSetup
import Lanius.Extraction.CompactOutput.Nodes.HeaderControl
import Lanius.Extraction.CompactOutput.Nodes.ChildPhase
import Lanius.Extraction.CompactOutput.Nodes.Emit
import Lanius.Extraction.CompactOutput.Nodes.RecordSetup
import Lanius.Extraction.CompactOutput.Nodes.Step
import Lanius.Extraction.CompactOutput.Nodes.Loop
import Lanius.Extraction.CompactOutput.Nodes.Function
import Lanius.Extraction.CompactOutput.Nodes.Call
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.Nodes

open Lanius.Extraction.CompactOutput

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Nodes.child_slot, ``Nodes.read_child, ``Nodes.validate_token, ``Nodes.validate_node,
      ``Nodes.write_child, ``Nodes.initialize_child, ``Nodes.validate_child,
      ``Nodes.child_fields, ``Nodes.encodeChild_length, ``Nodes.ChildEntry.write,
      ``Nodes.ChildEntry.validate, ``Nodes.ChildEntry.failure, ``Nodes.ChildEntry.success,
      ``Nodes.ChildOwned.entry, ``Nodes.ChildOwned.transition, ``Nodes.ChildOwned.condition,
      ``Nodes.execute_child_loop, ``Nodes.read_header, ``Nodes.record_guard_pass,
      ``Nodes.children_guard_pass, ``Nodes.HeaderOwned.transition,
      ``Nodes.HeaderOwned.write, ``Nodes.write_header, ``Nodes.ReferencesOwned.preserve,
      ``Nodes.HeaderOwned.start_children, ``Nodes.step_header,
      ``Nodes.header_failure, ``Nodes.header_success, ``Nodes.execute_child_phase,
      ``Nodes.emit_record, ``Nodes.read_offset, ``Nodes.initialize_record,
      ``Nodes.prepare_header, ``Nodes.RecordEntry.execute, ``Nodes.Owned.entry,
      ``Nodes.Owned.transition, ``Nodes.Owned.condition, ``Nodes.execute_loop,
      ``Nodes.Function.Entry.invariant, ``Nodes.Function.Entry.guard, ``Nodes.Function.Entry.execute,
      ``Nodes.Checked.write] do
    unless (← Lean.getEnv).contains name do throwError "Missing node serializer theorem {name}"
    for axiomName in ← Lean.collectAxioms name do
      unless standard.contains axiomName do throwError "Node serializer theorem {name} depends on {axiomName}"
  Lean.logInfo "Complete node serializer public-call proof uses standard axioms only on its stated valid-record domain."

end Lanius.Extraction.Tests.CompactOutput.Nodes
