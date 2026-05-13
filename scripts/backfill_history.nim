import std/[json, os, osproc, options, sequtils, strformat, strutils, times]

import ../src/types

proc isoUtc(epoch: int64): string =
  fromUnix(epoch).utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc parsePrice(node: JsonNode): float =
  case node.kind
  of JString: parseFloat(node.getStr)
  of JInt: node.getInt.float
  of JFloat: node.getFloat
  else: 0.0

proc readRegistryAt(commit: string): JsonNode =
  let output = execProcess("git", args = ["show", &"{commit}:data/registry.json"], options = {poUsePath, poStdErrToStdOut})
  # Check if output is complete (ends with "}}")
  let trimmed = output.strip()
  if trimmed.len > 10000:  # Basic sanity check - should be > 10KB for a real registry
    parseJson(trimmed)
  else:
    raise newException(ValueError, "Incomplete JSON from commit " & commit & " (only " & $trimmed.len & " bytes)")

proc main() =
  # Get commit history (skip HEAD which may have truncated merge data)
  let commitsOutput = execProcess("git", args = ["log", "--first-parent", "--format=%H %ct", "--", "data/registry.json"], options = {poUsePath, poStdErrToStdOut})
  var lines = commitsOutput.splitLines().filterIt(it.len > 0)
  
  # Skip HEAD (first line) since it may have truncated data from merge commit
  if lines.len > 0:
    lines.delete(0)
  
  if lines.len == 0:
    stderr.writeLine("Warning: No commit history found for data/registry.json")
    return

  var snapshots: seq[tuple[ts: int64, models: JsonNode]] = @[]
  var skipped = 0
  
  for line in lines:
    let parts = line.splitWhitespace()
    if parts.len != 2:
      continue
    try:
      let registry = readRegistryAt(parts[0])
      let models = if registry.hasKey("data"): registry["data"] else: registry["models"]
      snapshots.add((ts: parseInt(parts[1]).int64, models: models))
    except ValueError as e:
      stderr.writeLine("Skipping commit " & parts[0] & ": " & e.msg)
      inc(skipped)
  
  if snapshots.len == 0:
    stderr.writeLine("Error: No valid snapshots found")
    quit(QuitFailure)
  
  stdout.writeLine("Found " & $snapshots.len & " snapshots (" & $skipped & " skipped)")
  
  # Build history entries
  var entries: seq[JsonHistoryEntry] = @[]
  for i, snapshot in snapshots:
    let toDate = if i + 1 < snapshots.len: some(isoUtc(snapshots[i + 1].ts)) else: none(string)
    for model in snapshot.models.elems:
      let pricing = model["pricing"]
      entries.add JsonHistoryEntry(
        model_id: model["id"].getStr,
        from_date: isoUtc(snapshot.ts),
        to_date: toDate,
        prompt_price: parsePrice(pricing["prompt"]),
        completion_price: parsePrice(pricing["completion"]),
      )
  
  createDir("docs/data")
  writeFile("docs/data/history.json", pretty(%*{
    "version": 1,
    "generated_at": isoUtc(epochTime().int64),
    "entries": entries,
  }))
  
  echo "Generated docs/data/history.json with " & $entries.len & " entries"

when isMainModule:
  main()