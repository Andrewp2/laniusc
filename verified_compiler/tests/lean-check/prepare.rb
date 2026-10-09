require 'json'
require 'digest'
root, selfcore, out, mode, lean, phase = ARGV
raise 'invalid phase' if phase && !(mode == 'builder' && %w[preflight syntax-header].include?(phase))
Dir.chdir(root)
here = File.dirname(File.realpath(__FILE__))
toolchain = File.dirname(File.dirname(File.realpath(lean)))
raise 'foreign project artifacts in toolchain' unless Dir.glob(toolchain + '/lib/lean/{Lanius,verified_compiler,SelfCore.olean*,GeneratedDirectCore.olean*}').empty?
roots = case mode
when 'builder' then %w[verified_compiler.tests.direct_ir_builder_tests verified_compiler.tests.direct_ir_validator verified_compiler.tests.direct_ir_validator_tests]
when 'catalog-append' then %w[verified_compiler.tests.direct_ir_catalog_append verified_compiler.tests.direct_ir_catalog_append_outer_tests verified_compiler.tests.direct_ir_catalog_append_tests verified_compiler.tests.direct_ir_builder_tests verified_compiler.tests.direct_ir_catalog_build_tests verified_compiler.tests.direct_ir_catalog_store_tests]
else ['verified_compiler.tests.direct_ir_catalog_copy_tests']
end
roots.concat(%w[Lanius.Extraction.CurrentSourceClosure Lanius.TypedIR.Surface.Link]) if mode == 'builder'
roots << 'verified_compiler.tests.direct_ir_catalog_build_tests' if %w[catalog-build catalog-store].include?(mode)
if mode == 'catalog-store'
  roots.concat(%w[verified_compiler.tests.direct_ir_catalog_store_tests verified_compiler.tests.direct_ir_count_store_tests Lanius.Semantics.WritePlaceTests])
end
raise 'unknown check scope' unless %w[builder catalog-copy catalog-build catalog-store catalog-append].include?(mode)
syntax = {
  'SelfCore' => [selfcore, '9fbe69caffaae1d6a8b0a621a042f118149f57d516a0a204d9d3e3264cd11f18', 'fc407d2a93d7a5e36088520115e157f83850c5e87719d65f4b908abf7bbeca6b']
}
imports = lambda do |path|
  text = File.read(path).gsub(%r{(?<block>/- (?:(?!/-|-/).|\g<block>)* -/)}mx, '')
  names = []
  text.each_line do |line|
    line = line.split('--', 2)[0].strip
    next if line.empty? || %w[module prelude].include?(line)
    match = line.match(/\A(?:(?:public|private|meta)\s+)*import\s+(?:all\s+)?(.+)\z/)
    break unless match
    names.concat(match[1].split)
  end
  names
end
if phase == 'syntax-header'
  raise 'fresh SelfCore header is not independently scoped' unless imports.call(selfcore + '/SelfCore.lean') == %w[Lanius.TypedIR.Surface.Link Lanius.Core]
  exit
end
seen = {}; model = {}; dag = {}; jobs = []; cached = []; sources = []; external = {}; counts = []
visit = lambda do |name|
  raise "invalid module #{name}" unless name.match?(/\A[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*\z/)
  raise "source cycle #{name}" if seen[name] == :visiting
  next model.fetch(name, false) if seen[name] == :done
  # No prior generated artifact is inspected or admitted by this early audit.
  if phase == 'preflight' && name == 'SelfCore'
    seen[name] = :done; model[name] = false; dag[name] = []; next false
  end
  if name.match?(/\A(?:Init|Lean|Std|Lake)(?:\.|\z)/)
    external[name] = true; next false
  end
  dir = case name
  when 'SelfCore' then syntax.fetch(name)[0]
  when /\ALanius(?:\.|\z)/ then root + '/formal'
  when /\Averified_compiler\./ then root
  else raise "undeclared syntax/module #{name}"
  end
  relative = name.tr('.', '/')
  source = dir + '/' + relative + '.lean'
  raise "missing canonical source #{source}" unless File.file?(source)
  seen[name] = :visiting
  deps = imports.call(source); dag[name] = deps
  dependent = deps.map { |dep| visit.call(dep) }.any? || name == 'Lanius.Semantics'
  model[name] = dependent; seen[name] = :done
  fresh = name.start_with?('verified_compiler.') || name == 'Lanius.Semantics.WritePlaceTests'
  if fresh
    jobs << [name, dir, source]
  else
    artifact = name == 'SelfCore' ? dir + '/SelfCore.olean' : root + '/formal/.lake/build/lib/lean/' + relative + '.olean'
    if syntax[name]
      _, source_hash, artifact_hash = syntax.fetch(name)
      raise 'SelfCore imports the changed model' if dependent
      unless mode == 'builder'
        raise 'SelfCore source/artifact is not the designated independent snapshot' unless Digest::SHA256.file(source).hexdigest == source_hash && Digest::SHA256.file(artifact).hexdigest == artifact_hash
      end
      raise 'unlisted SelfCore companion' unless Dir.glob(dir + '/SelfCore.{olean.private,olean.server,ir,ilean}').empty?
    end
    cached << [name, source, artifact]
  end
  sources << source if fresh || dependent
  counts << [fresh ? 'fresh specialized/fixture' : dependent ? 'cached current model' : 'cached independent', name, File.foreach(source).count, source]
  dependent
end
roots.each { |name| visit.call(name) }
write_rows = ->(file, rows) { File.write(out + '/' + file, rows.map { |row| row.join("\t") }.join("\n") + "\n") }
write_rows.call('jobs.tsv', jobs)
write_rows.call('source-dag.tsv', dag.map { |name, deps| [name, deps.join(' ')] })
write_rows.call('source-counts.tsv', counts)
write_rows.call('cached-modules.tsv', cached)
File.write(out + '/proof-sources.txt', sources.uniq.join("\n") + "\n")
File.write(out + '/lean-bin.txt', lean + "\n")
File.write(out + '/toolchain.txt', toolchain + "\n")
generic = cached.map(&:first).grep(/\ALanius(?:\.|\z)/)
targets = generic.reject { |name| generic.any? { |parent| dag.fetch(parent).include?(name) } }
File.write(out + '/foundation-roots.txt', targets.join("\n") + "\n")
audit = IO.popen(['ruby', '-E', 'UTF-8', here + '/audit.rb', lean, *generic], &:read)
unless $?.success?
  warn 'Current shared provenance failed; refresh the normal Lake targets in foundation-roots.txt before checking. No stale cache fallback.'
  exit 1
end
File.write(out + '/foundations.json', audit)
exit if phase == 'preflight'
authenticated = JSON.parse(audit).fetch('verified_files')
aliases = []
cached.each do |name, source, artifact|
  raise "nonregular cache #{artifact}" unless File.file?(artifact) && !File.symlink?(artifact)
  [artifact, artifact + '.private', artifact + '.server', artifact.delete_suffix('.olean') + '.ir'].each do |file|
    next unless File.file?(file)
    raise "unauthenticated cache #{file}" unless name == 'SelfCore' || authenticated.key?(file)
    aliases << [name.tr('.', '/') + file.delete_prefix(artifact.delete_suffix('.olean')), file]
  end
end
write_rows.call('cache-artifacts.tsv', aliases)
tool_seen = {}; tool_files = []
tool_visit = lambda do |name|
  next if tool_seen[name]; tool_seen[name] = true
  raise "non-toolchain import #{name}" unless name.match?(/\A(?:Init|Lean|Std|Lake)(?:\.|\z)/)
  base = toolchain + '/lib/lean/' + name.tr('.', '/')
  source = toolchain + '/src/lean/' + name.tr('.', '/') + '.lean'
  raise "missing installed module #{name}" unless File.file?(base + '.olean') && File.file?(source)
  tool_files << source
  tool_files.concat(Dir.glob(base + '.olean*') + Dir.glob(base + '.ir*') + Dir.glob(base + '.ilean'))
  imports.call(source).each { |dep| tool_visit.call(dep) }
end
tool_visit.call('Init'); external.each_key { |name| tool_visit.call(name) }
hash_lines = ->(paths) { paths.uniq.sort.map { |path| Digest::SHA256.file(path).hexdigest + '  ' + path }.join("\n") + "\n" }
File.write(out + '/toolchain.sha256', hash_lines.call(tool_files))
%w[required-axioms.tsv fixture-markers.tsv].each do |file|
  File.write(out + '/' + file, File.readlines(here + '/' + file).select { |line| jobs.any? { |name, _, _| name == line.split("\t", 2)[0] } }.join)
end
inputs = jobs.map { |_, _, source| source } + cached.flat_map { |_, source, artifact| [source, artifact] }
inputs.concat(authenticated.keys + tool_files + Dir.glob(here + '/*').select { |path| File.file?(path) })
inputs << root + '/verified_compiler/tests/ir_builder_check.sh'
inputs.concat(%w[bash ruby time awk sha256sum ps setsid].map { |name| '/usr/bin/' + name })
File.write(out + '/inputs.sha256', hash_lines.call(inputs))
File.write(out + '/cache-policy.txt', "Fresh canonical specialized proofs/fixtures. Shared caches must match current source, transitive import artifacts and native Lake traces. No old-model namespace fallback; this ordinary CLI is not the separate fresh-all migration acceptance.\n")
metadata = Dir.glob(out + '/*').select { |path| File.file?(path) }
File.write(out + '/snapshot.sha256', hash_lines.call(metadata))
puts "Canonical #{mode} DAG: #{jobs.size} fresh bodies, #{cached.size} authenticated current shared/syntax caches."
