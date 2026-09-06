import Lean
open Lean

/-! Check source modules in one process, preserving real module boundaries.
Shared import data is loaded once. Program objects are generated in a fresh
directory and may be imported only after this run has checked their source. -/

private structure BatchConfig where
  root : String
  shared : Array String
  modules : Array String
  finalName : String
  output : String
deriving FromJson

unsafe def main (args : List String) : IO UInt32 := do
  let [configPath] := args | throw (IO.userError "expected manifest path")
  let encoded ← IO.FS.readFile configPath
  let config : BatchConfig ← match Json.parse encoded >>= fromJson? with
    | .ok config => pure config
    | .error error => throw (IO.userError error)
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let opts := ({} : Options).setBool `Elab.async false
  let started ← IO.monoMsNow
  let sharedImports := config.shared.map fun name => { module := name.toName : Import }
  let (_, sharedState) ← withImporting <| (importModulesCore sharedImports).run
  enableInitializersExecution
  let mut env ← withImporting <| finalizeImport sharedState sharedImports opts 0 false true
  for name in env.header.moduleNames do
    if (`Lanius.Extraction.VerifiedFrontend).isPrefixOf name then
      throw (IO.userError s!"program-specific import forbidden: {name}")
  let mut available := env.header.moduleNames
  if env.contains config.finalName.toName then
    throw (IO.userError "final theorem was already imported")
  let outputRoot : System.FilePath := config.output
  if ← outputRoot.pathExists then
    throw (IO.userError "output directory must be fresh")
  IO.FS.createDirAll outputRoot
  let mut artifacts : NameMap ImportArtifacts := {}
  let mut states : NameMap ImportState := {}
  let mut closures : NameMap (Array Name) := {}
  -- Keep only pristine import environments. Never cache the environment after
  -- checking a module: doing so would leak declarations and private names.
  -- Exact ordered Import values include all import flags. Bound retention
  -- because each environment owns maps over the shared declaration set.
  let mut importEnvs : List (Array Import × Environment) := []
  for module in config.modules do
    let moduleName := module.toName
    unless (`Lanius.Extraction.VerifiedFrontend).isPrefixOf moduleName do
      throw (IO.userError s!"non-program module in fresh set: {module}")
    if available.contains moduleName then
      throw (IO.userError s!"duplicate or imported program module: {module}")
    if module.contains '/' || module.contains '\\' then
      throw (IO.userError "module names cannot contain path separators")
    let path := config.root ++ "/" ++ module.replace "." "/" ++ ".lean"
    let input ← IO.FS.readFile path
    let inputCtx := Parser.mkInputContext input path
    let (header, parserState, messages) ← Parser.parseHeader inputCtx
    if Elab.HeaderSyntax.isModule header then
      throw (IO.userError "module-system sources require the normal module build")
    let imports := Elab.headerToImports header
    let mut needed : Array Name := #[]
    let mut selectedState := sharedState
    let mut selectedSize := 0
    for imported in imports do
      unless available.contains imported.module do
        throw (IO.userError s!"unavailable dependency {imported.module} in {module}")
      if let some closure := closures.find? imported.module then
        for name in closure do
          unless needed.contains name do needed := needed.push name
        if closure.size > selectedSize then
          selectedState := (states.find? imported.module).getD sharedState
          selectedSize := closure.size
    let before ← IO.monoMsNow
    let (_, importState) ← withImporting <|
      (importModulesCore imports (arts := artifacts)).run selectedState
    -- Rebuild elaboration state at a genuine module boundary. Merely changing
    -- mainModule on the previous environment makes private names collide.
    enableInitializersExecution
    let cached := importEnvs.find? (fun entry => entry.1 == imports)
    let importedEnv ← match cached with
      | some (_, importedEnv) => pure importedEnv
      | none => withImporting <| finalizeImport importState imports opts 0 false true
    importEnvs := ((imports, importedEnv) ::
      importEnvs.filter (fun entry => entry.1 != imports)).take 4
    let importedAt ← IO.monoMsNow
    let state ← Elab.IO.processCommands inputCtx parserState
      (Elab.Command.mkState (importedEnv.setMainModule moduleName) messages opts)
    if state.commandState.messages.hasErrors then
      for message in state.commandState.messages.toList do
        IO.eprint (← message.toString)
      return 1
    unless state.parserState.pos == input.rawEndPos do
      throw (IO.userError s!"source was not fully processed: {module}")
    env := state.commandState.env
    let checkedAt ← IO.monoMsNow
    let output := outputRoot / (module.replace "." "/" ++ ".olean")
    IO.FS.createDirAll output.parent.get!
    writeModule env output
    let exportedAt ← IO.monoMsNow
    artifacts := artifacts.insert moduleName (.ofArrays #[#[output]])
    let (_, completedState) ← withImporting <|
      (importModulesCore #[{ module := moduleName }] (arts := artifacts)).run importState
    states := states.insert moduleName completedState
    closures := closures.insert moduleName (needed.push moduleName)
    available := available.push moduleName
    let finishedAt ← IO.monoMsNow
    IO.println (Json.mkObj [
      ("module", toJson module),
      ("milliseconds", toJson (finishedAt - before)),
      ("import_ms", toJson (importedAt - before)),
      ("import_env_cache_hit", toJson cached.isSome),
      ("check_ms", toJson (checkedAt - importedAt)),
      ("export_ms", toJson (exportedAt - checkedAt)),
      ("cache_ms", toJson (finishedAt - exportedAt)),
      ("elapsed_ms", toJson (finishedAt - started))]).compress
    (← IO.getStdout).flush
  unless (env.find? config.finalName.toName).any (fun info => info matches .thmInfo _) do
    throw (IO.userError "final theorem was not checked")
  let axioms ← (collectAxioms config.finalName.toName : CoreM (Array Name)).toIO'
    { fileName := "<audit>", fileMap := default } { env }
  for name in axioms do
    unless #[`propext, `Classical.choice, `Quot.sound].contains name do
      throw (IO.userError s!"unexpected axiom: {name}")
  IO.println (Json.mkObj [
    ("complete", toJson true),
    ("milliseconds", toJson ((← IO.monoMsNow) - started)),
    ("modules", toJson config.modules.size),
    ("final_theorem", toJson config.finalName),
    ("axioms", toJson (axioms.map (·.toString)))]).compress
  return 0
