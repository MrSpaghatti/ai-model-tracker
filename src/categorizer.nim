import std/[algorithm, math, strutils, tables]

import types

proc hasModality(row: ModelRow; target: string): bool =
  for modality in row.modalities:
    if modality.toLowerAscii() == target.toLowerAscii():
      return true

  false

proc sortRows(rows: var seq[ModelRow]) =
  rows.sort(proc (left, right: ModelRow): int =
    if left.contextPerCent > right.contextPerCent:
      return -1
    if left.contextPerCent < right.contextPerCent:
      return 1

    if left.averagePrice < right.averagePrice:
      return -1
    if left.averagePrice > right.averagePrice:
      return 1

    if left.contextLength > right.contextLength:
      return -1
    if left.contextLength < right.contextLength:
      return 1

    cmp(left.id, right.id)
  )

proc parseNumberToken(value: string; startIndex: int): tuple[number: float, nextIndex: int] =
  var index = startIndex

  while index < value.len and (value[index].isDigit or value[index] == '.'):
    inc(index)

  result.number = parseFloat(value[startIndex ..< index])
  result.nextIndex = index

proc inferParameterBillions(row: ModelRow): float =
  let haystack = (row.id & " " & row.name).toLowerAscii()
  var index = 0

  while index < haystack.len:
    if not haystack[index].isDigit:
      inc(index)
      continue

    let firstToken = parseNumberToken(haystack, index)
    var probe = firstToken.nextIndex

    if probe < haystack.len and haystack[probe] == 'x':
      inc(probe)

      if probe < haystack.len and haystack[probe].isDigit:
        let secondToken = parseNumberToken(haystack, probe)

        if secondToken.nextIndex < haystack.len and haystack[secondToken.nextIndex] == 'b':
          result = max(result, firstToken.number * secondToken.number)
          index = secondToken.nextIndex + 1
          continue

    if probe < haystack.len and haystack[probe] == 'b':
      result = max(result, firstToken.number)
      index = probe + 1
      continue

    index = firstToken.nextIndex

proc estimatedFourBitVramGb(row: ModelRow): int =
  let parameterBillions = inferParameterBillions(row)

  if parameterBillions <= 0.0:
    return high(int)

  int(ceil(parameterBillions * 0.75))

proc splitFreeVsPaid*(rows: seq[ModelRow]): tuple[freeRows: seq[ModelRow], paidRows: seq[ModelRow]] =
  for row in rows:
    if row.isFree:
      result.freeRows.add(row)
    else:
      result.paidRows.add(row)

proc getTopModelsByVram*(rows: seq[ModelRow]; vramGb: int): seq[ModelRow] =
  for row in rows:
    if row.isFree:
      continue

    if estimatedFourBitVramGb(row) <= vramGb:
      result.add(row)

  sortRows(result)

proc getBestModelsForTask*(rows: seq[ModelRow]; task: string): seq[ModelRow] =
  let taskName = task.toLowerAscii()

  for row in rows:
    let searchable = (row.id & " " & row.name).toLowerAscii()
    var matchesTask = false

    case taskName
    of "coding":
      matchesTask = searchable.contains("code") or searchable.contains("coder") or
        searchable.contains("codex") or searchable.contains("codestral") or
        searchable.contains("devstral")
    of "vision":
      matchesTask = row.hasModality("image") or searchable.contains("vision") or searchable.contains("vl")
    of "encoding":
      matchesTask = searchable.contains("embed") or searchable.contains("embedding") or
        searchable.contains("encoder") or searchable.contains("encode") or
        searchable.contains("retrieval") or searchable.contains("rerank")
    of "tts":
      matchesTask = row.hasModality("audio") or searchable.contains("tts") or searchable.contains("speech") or
        searchable.contains("voice") or searchable.contains("lyria") or searchable.contains("audio")
    else:
      matchesTask = searchable.contains(taskName)

    if matchesTask:
      result.add(row)

  sortRows(result)

proc categorizeByModality*(rows: seq[ModelRow]): Table[string, seq[ModelRow]] =
  for row in rows:
    if row.modalities.len == 0:
      result.mgetOrPut("text", @[]).add(row)
      continue

    for modality in row.modalities:
      result.mgetOrPut(modality, @[]).add(row)
