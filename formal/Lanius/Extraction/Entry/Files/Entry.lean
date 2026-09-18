import Lanius.Extraction.Entry.Files.Source

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties

/-- Enter the checked argument-cursor scope after the startup prefix. The
original main typing proves the initialized state's runtime type, the actual
file body's typing, and all registered i32 word ranges. No successful file
iteration or separately assumed loop-entry typing is needed. -/
theorem CheckedSource.enter (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {argument countId : VarId} {body continuation : Stmt}
    (source : CheckedSource argument countId body continuation)
    (mainTyped : Typing.StmtHasType program.core returnType context inLoop main)
    (beforeTyped : RuntimeStateHasType program.core context before store)
    (startup : Prefix.Reaches program.core before main ready continuation)
    (registry : Allocation.Registry ready) :
    ∃ loopContext loopStore,
      Prefix.Reaches program.core before main (ready.bindLocal argument (.signed .i32 1))
        (.whileLoop (condition argument countId) body) ∧
      RuntimeStateHasType program.core loopContext (ready.bindLocal argument (.signed .i32 1)) loopStore ∧
      Typing.StmtHasType program.core returnType loopContext true body ∧
      Allocation.Registry (ready.bindLocal argument (.signed .i32 1)) ∧
      Host.RepresentableViews (ready.bindLocal argument (.signed .i32 1)) ∧
      (ready.bindLocal argument (.signed .i32 1)).local? argument = some (.signed .i32 1) := by
  have reached := startup.trans source.reaches
  obtain ⟨loopContext, loopStore, loopTyped, typed⟩ := Host.checked_prefix_type program mainTyped beforeTyped reached
  have registered := registry.bindLocal argument (.signed .i32 1)
  refine ⟨loopContext, loopStore, reached, typed, ?_, registered,
    Host.RepresentableViews.ofRuntime typed registered.roots,
    Lanius.Separation.bindLocal_finds_local _ _ _ registry.wellFormed⟩
  cases loopTyped with
  | whileLoop _ bodyTyped => exact bodyTyped

end Lanius.Extraction.Entry.Files
