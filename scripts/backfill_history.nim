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
  parseJson(output)

proc main() =
  let commitsOutput = execProcess("git", args = ["log", "--format=%H %ct", "--", "data/registry.json"], options = {poUsePath, poStdErrToStdOut})
  let commitLines = commitsOutput.splitLines().filterIt(it.len > 0)
  var snapshots: seq[tuple[ts: int64, models: JsonNode]] = @[]

  for line in commitLines:
    let parts = line.splitWhitespace()
    if parts.len != 2:
      continue
    let registry = readRegistryAt(parts[0])
    snapshots.add((ts: parseInt(parts[1]).int64, models: registry["models"]))

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
  writeFile("docs/data/history.json", $(%*{
    "version": 1,
    "generated_at": isoUtc(epochTime().int64),
    "entries": entries,
  }))

when isMainModule:
  main()
