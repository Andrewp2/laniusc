require 'set'
out, config, root, here = ARGV
setting = config + '/max-lean.txt'
configured = File.file?(setting) ? File.read(setting) : "2\n"
raise 'max-lean.txt must select 2 or 4 workers' unless configured.match?(/\A(?:2|4)\n?\z/)
max_lean = configured.to_i
rows = File.readlines(config + '/jobs.tsv').map { |line| line.chomp.split("\t") }
names = rows.map(&:first).to_set
dag = File.readlines(config + '/source-dag.tsv').to_h { |line| name, deps=line.chomp.split("\t", 2); [name, deps.to_s.split.select { |dep| names.include?(dep) }] }
weights = Hash.new(0.5)
priority = {}
rows.reverse_each { |name, _, _| priority[name] = weights.fetch(name, 0.5) + rows.map(&:first).select { |child| dag.fetch(child).include?(name) }.map { |child| priority.fetch(child) }.max.to_f }
pending = names.dup; done = Set.new; running = {}; peak = 0; max_rss = 0; min_available = Float::INFINITY; max_running = 0
mem = -> { File.read('/proc/meminfo')[/^MemAvailable:\s+(\d+)/, 1].to_i }
reserve = mem.call / 4
pressure = -> { File.read('/proc/pressure/memory')[/^full.* total=(\d+)/, 1].to_i }
initial_pressure = pressure.call
last_pressure = initial_pressure; sampled_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
limit = max_lean; bad = 0; good = 0; rate = 0.0; peak_rate = 0.0
sid = Process.getsid(0)
begin
  File.open(out + '/schedule.log', 'w') do |log|
    log.puts "memory-policy reserveKiB=#{reserve} fullPSIreduce=2pct/two-1s-windows recover=0.5pct/two-1s-windows memoryRecover=120pct maxLean=#{max_lean} workerSelection=#{File.file?(setting) ? 'explicit' : 'default'}"
    until pending.empty? && running.empty?
      available = mem.call; min_available = [min_available, available].min
      floor = [reserve, peak * max_lean].max
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if now - sampled_at >= 1
        current = pressure.call; rate = (current - last_pressure) / ((now - sampled_at) * 10_000.0)
        peak_rate = [peak_rate, rate].max; last_pressure = current; sampled_at = now
        bad = rate >= 2 ? bad + 1 : 0
        good = rate <= 0.5 && available >= floor * 1.2 ? good + 1 : 0
        limit = 1 if bad >= 2
        limit = max_lean if good >= 2
        rss = IO.popen(['ps', '-o', 'rss=', '--sid', sid.to_s], &:read).split.map(&:to_i).sum
        max_rss = [max_rss, rss].max
        log.puts "memory availableKiB=#{available} workerRSSKiB=#{rss} fullPSIrecentPct=#{rate.round(3)} dispatchLimit=#{limit} running=#{running.size}"; log.flush
      end
      if available < floor
        limit = 1; good = 0
      end
      ready = pending.select { |name| dag.fetch(name).all? { |dep| done.include?(dep) } }.sort_by { |name| -priority.fetch(name) }
      while running.size < limit && !ready.empty?
        name = ready.shift; pending.delete(name)
        pid = Process.spawn('bash', here + '/body.sh', out, config, root, name)
        running[pid] = name; max_running = [max_running, running.size].max
        log.puts "start #{name} pid=#{pid} running=#{running.size} availableKiB=#{available}"; log.flush
      end
      raise 'source DAG stalled' if running.empty? && !pending.empty?
      running.keys.each do |pid|
        result = Process.waitpid2(pid, Process::WNOHANG); next unless result
        _, status=result; name=running.delete(pid)
        time = out + '/logs/' + name + '.time'
        peak = [peak, File.read(time)[/peakRSSKiB=(\d+)/, 1].to_i].max if File.file?(time)
        raise "body failed #{name} status=#{status.exitstatus}" unless status.success? && File.file?(out + '/completed/' + name)
        done.add(name); log.puts "done #{name}"; log.flush
      end
      sleep 0.05 unless running.empty?
    end
  end
ensure
  File.write(out + '/memory.txt', "configuredMaxConcurrentLean=#{max_lean} maxConcurrentLean=#{max_running} peakBodyRSSKiB=#{peak} sampledPeakWorkerRSSKiB=#{max_rss} minimumMemAvailableKiB=#{min_available} pressureFullDelta=#{pressure.call - initial_pressure} peakRecentFullPSIpct=#{peak_rate.round(3)} completed=#{done.size} pending=#{pending.size} runningAtStop=#{running.size}\n")
end
