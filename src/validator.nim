import std/[algorithm, options, sets, tables]
import types

proc validateCurrentRows*(rows: seq[ModelRow]) =
  var seen = initHashSet[string]()
  for row in rows:
    if row.id.len == 0:
      raise newException(CatchableError, "Validation failed: model with empty id found")
    if row.id in seen:
      raise newException(CatchableError, "Validation failed: duplicate model id '" & row.id & "'")
    seen.incl(row.id)

proc validateHistoryEntries*(entries: seq[JsonHistoryEntry]) =
  var byModel = initTable[string, seq[JsonHistoryEntry]]()
  for entry in entries:
    byModel.mgetOrPut(entry.model_id, @[]).add(entry)

  for modelId, modelEntries in byModel.pairs:
    var sortedEntries = modelEntries
    sortedEntries.sort(proc(a, b: JsonHistoryEntry): int = cmp(a.from_date, b.from_date))
    var openCount = 0
    var lastToDate = ""
    for entry in sortedEntries:
      if entry.to_date.isNone:
        inc(openCount)
      else:
        let toDate = entry.to_date.get()
        if toDate < entry.from_date:
          raise newException(
            CatchableError,
            "Validation failed: history to_date earlier than from_date for '" & modelId & "'"
          )
        if lastToDate.len > 0 and entry.from_date < lastToDate:
          raise newException(
            CatchableError,
            "Validation failed: non-monotonic history timeline for '" & modelId & "'"
          )
        lastToDate = toDate

    if openCount > 1:
      raise newException(
        CatchableError,
        "Validation failed: multiple open history entries for '" & modelId & "'"
      )
