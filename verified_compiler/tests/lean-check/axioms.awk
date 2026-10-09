# Inspect every printed list, including Lean's multiline formatting.
function finish(remaining, tokens, amount, position, token) {
  remaining = buffer
  sub(/^.*depends on axioms: \[/, "", remaining)
  sub(/\].*$/, "", remaining)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", remaining)
  if (remaining != "") {
    amount = split(remaining, tokens, ",")
    for (position = 1; position <= amount; position++) {
      token = tokens[position]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", token)
      if (token != "propext" && token != "Classical.choice" && token != "Quot.sound") {
        print "nonstandard axiom list: " buffer > "/dev/stderr"
        bad = 1
      }
    }
  }
  records++
  active = 0
}
/depends on axioms: \[/ {
  if (active) bad = 1
  buffer = $0
  active = 1
  if ($0 ~ /\]/) finish()
  next
}
active {
  buffer = buffer " " $0
  if ($0 ~ /\]/) finish()
}
END {
  print "standard axiom lists checked: " records + 0
  exit (bad || active)
}
