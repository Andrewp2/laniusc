require 'json'; require 'fiddle'; require 'digest'
root = Dir.pwd; toolchain = File.dirname(File.dirname(ARGV.shift))
native = Fiddle::Function.new(Fiddle.dlopen(toolchain + '/lib/lean/libleanshared.so')['lean_byte_array_hash'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG_LONG)
mask = (1 << 64) - 1; multiplier = 0xc6a4a7935bd1e995
mix = lambda { |h, k| k = k * multiplier & mask; k ^= k >> 47; ((h ^ k ^ multiplier) * multiplier) & mask }
records = {}; lakehash = lambda do |path, text = false|
  bytes = File.binread(path); records[path] = Digest::SHA256.hexdigest(bytes)
  bytes = bytes.gsub("\r\n", "\n") if text
  # Installed lean_byte_array_hash reads size at offset 8 and byte payload at 24.
  object = [0, bytes.bytesize, bytes.bytesize].pack('Q<3') + bytes
  '%016x' % mix.call(1723, native.call(Fiddle::Pointer[object]) & mask)
end
check = lambda { |path, expected, text = false| actual = lakehash.call(path, text); raise "hash drift: #{path}: #{expected} != #{actual}" unless actual == expected }
leaves = lambda { |x| x.is_a?(Array) && x.length == 2 && x[0].is_a?(String) && x[1].is_a?(String) ? [x] : x.is_a?(Array) ? x.flat_map { |y| leaves.call(y) } : [] }
queue = ARGV.dup; seen = {}; shared = root + '/formal/.lake/build/lib/lean/'
until queue.empty?
  name = queue.shift; next if seen[name]; seen[name] = true
  source = root + '/formal/' + name.tr('.', '/') + '.lean'; base = shared + name.tr('.', '/')
  trace = JSON.parse(File.read(base + '.trace')); lakehash.call(base + '.trace')
  inputs = leaves.call(trace.fetch('inputs')); check.call(source, inputs.assoc(source).fetch(1), true)
  File.read(source).scan(/^import\s+(Lanius\.[^\s]+)/).each { |m| queue << m[0] }
  {'o' => base + '.olean', 'i' => base + '.ilean', 'c' => root + '/formal/.lake/build/ir/' + name.tr('.', '/') + '.c'}.each do |key, path|
    value = trace.fetch('outputs').fetch(key); value = value.first if value.is_a?(Array)
    check.call(path, value.split('.').first); check.call(path, File.read(path + '.hash').strip); lakehash.call(path + '.hash')
  end
  inputs.select { |label, _| label.end_with?(':importAllArts') && label.start_with?('Lanius.') }.each do |label, expected|
    imported = label.delete_suffix(':importAllArts'); actual = lakehash.call(shared + imported.tr('.', '/') + '.olean')
    raise "import artifact drift: #{label}" unless '%016x' % mix.call(1723, actual.to_i(16)) == expected
  end
  setup = root + '/formal/.lake/build/ir/' + name.tr('.', '/') + '.setup.json'; lakehash.call(setup)
  JSON.parse(File.read(setup)).fetch('importArts').each { |m, arts| arts.flatten.each { |p| raise "wrong import path: #{p}" if m.start_with?('Lanius.') && p != shared + m.tr('.', '/') + '.olean'; lakehash.call(p) } }
end
queue = [shared + 'lanius_x2dformal_Lanius_TypedIR_Surface_Link.so']; formal_count = seen.length; seen = {}
until queue.empty?
  path = queue.shift; next if seen[path]; seen[path] = true
  trace = JSON.parse(File.read(path + '.trace')); lakehash.call(path + '.trace'); check.call(path, trace.fetch('outputs').split('.').first)
  leaves.call(trace.fetch('inputs')).select { |p, _| p.start_with?('/') }.each { |p, h| check.call(p, h); queue << p if p.end_with?('.so', '.o.export') }
end
check.call(root + '/formal/lakefile.lean', JSON.parse(File.read(root + '/formal/.lake/config/0/lakefile.olean.trace')).fetch('configHash'), true)
%w[lake-manifest.json lean-toolchain .lake/config/0/lakefile.olean .lake/config/0/lakefile.olean.trace].each { |p| lakehash.call(root + '/formal/' + p) }
%w[bin/lean bin/lake bin/clang lib/lean/libInit_shared.so lib/lean/libLake_shared.so lib/lean/libleanshared.so lib/lean/libleanshared_1.so lib/lean/libleanshared_2.so].each { |p| lakehash.call(toolchain + '/' + p) }
puts JSON.pretty_generate({formal_modules: formal_count, verified_files: records, toolchain_external_imports: 'Installed Lean toolchain artifacts are frozen, not rebuilt.'})
