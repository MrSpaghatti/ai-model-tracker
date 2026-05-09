import std/[algorithm, math, strformat, strutils]

import categorizer
import types

type
  LocalModelEntry = tuple[
    model: string,
    size: string,
    fp16: string,
    q4: string,
    bestFor: string,
    notes: string
  ]

const LocalModels: array[26, LocalModelEntry] = [
  ("Llama 3.2", "1B", "4 GB", "2 GB", "Light chat, assistants", "Great for edge devices and cheap VPS GPUs."),
  ("Llama 3.2", "3B", "6 GB", "3 GB", "General chat, summarization", "Comfortable on consumer 6 GB cards with 4-bit quantization."),
  ("Llama 3.1", "8B", "16 GB", "8 GB", "Balanced general-purpose use", "One of the easiest strong 8B-class local models to run."),
  ("Qwen2.5", "7B", "14 GB", "8 GB", "General chat, multilingual work", "Strong instruction following for the footprint."),
  ("Qwen2.5", "14B", "28 GB", "16 GB", "Higher-quality reasoning", "Needs a roomier GPU for comfortable generation."),
  ("Qwen2.5", "32B", "64 GB", "24 GB", "Premium local reasoning", "Great fit for 24 GB cards when quantized."),
  ("Qwen2.5", "72B", "144 GB", "48 GB", "Large-model quality", "Multi-GPU or very large cards recommended."),
  ("Mistral", "7B", "14 GB", "8 GB", "General chat, instruction tuning", "Still a solid baseline for local inference."),
  ("Gemma 2", "9B", "18 GB", "8 GB", "Chat, analysis", "Efficient option for consumer GPUs."),
  ("Gemma 2", "27B", "54 GB", "20 GB", "Long-form quality", "Good target for 24 GB-class systems with quantization."),
  ("DeepSeek Coder V2 Lite", "16B", "32 GB", "12 GB", "Coding", "Local coding specialist with good IDE-assistant potential."),
  ("Phi-3 Mini", "3.8B", "8 GB", "4 GB", "Tiny assistants, local apps", "Fits low-end GPUs and laptops with eGPU setups."),
  ("Phi-3 Small", "7B", "14 GB", "6 GB", "Compact reasoning", "Good step-up from mini models."),
  ("Phi-3 Medium", "14B", "28 GB", "8 GB", "Reasoning, analysis", "Can squeeze onto 8 GB only with aggressive quantization/offload."),
  ("Neural Chat", "7B", "14 GB", "8 GB", "Friendly assistant chat", "Optimized for dialogue quality."),
  ("Zephyr", "7B", "14 GB", "8 GB", "Instruction following", "Popular open instruct baseline."),
  ("StarCoder2", "3B", "6 GB", "4 GB", "Lightweight coding", "Good for autocomplete and small coding tasks."),
  ("StarCoder2", "7B", "14 GB", "8 GB", "Coding", "Better completion quality on standard developer GPUs."),
  ("StarCoder2", "15B", "30 GB", "12 GB", "Higher-end coding", "Best on 12 GB+ cards with quantization."),
  ("CodeLlama", "7B", "14 GB", "8 GB", "Coding", "Reliable local coding baseline."),
  ("CodeLlama", "13B", "26 GB", "12 GB", "Coding, refactoring", "Good sweet spot for 12 GB GPUs."),
  ("CodeLlama", "34B", "68 GB", "24 GB", "Heavy coding workloads", "Strong option for 24 GB workstations."),
  ("Mixtral", "8x7B", "90 GB", "48 GB", "Reasoning, agent workflows", "MoE model with very strong quality but big memory needs."),
  ("Command R", "35B", "70 GB", "48 GB", "RAG, tool use", "Excellent for retrieval-heavy local assistants."),
  ("Yi", "34B", "68 GB", "24 GB", "Long-form writing, analysis", "High-quality large open model family."),
  ("SOLAR", "10.7B", "22 GB", "8 GB", "General chat, summarization", "Great performance for modest 4-bit VRAM budgets.")
]

proc formatWholeNumber(value: int): string =
  let digits = $value
  var groups: seq[string]
  var index = digits.len

  while index > 3:
    groups.insert(digits[index - 3 ..< index], 0)
    index -= 3

  groups.insert(digits[0 ..< index], 0)
  result = groups.join(",")

proc formatLargeFloat(value: float): string =
  if classify(value) in {fcInf, fcNegInf}:
    return "∞"

  if value >= 1_000_000_000_000.0:
    return formatFloat(value, ffScientific, 2)

  let rounded = value.round.int
  result = formatWholeNumber(rounded)

proc formatUsdPerMillion*(price: float): string =
  "$" & formatFloat(price * 1_000_000.0, ffDecimal, 4)

proc formatRequestPrice(price: float; hasRequestPrice: bool): string =
  if not hasRequestPrice:
    return "-"

  "$" & formatFloat(price, ffDecimal, 6)

proc escapeMarkdownCell(value: string): string =
  value.replace("|", "\\|").replace("\n", " ")

proc formatModerationStatus(row: ModelRow): string =
  if row.isModerated:
    "✅"
  else:
    "⚠️"

proc generateRowsTable(rows: seq[ModelRow]): string =
  result = "| Model ID | Name | Context | Prompt ($/1M) | Completion ($/1M) | Request ($/req) | Moderated | Context per Cent |\n"
  result.add "| --- | --- | ---: | ---: | ---: | ---: | :---: | ---: |\n"

  for row in rows:
    result.add fmt"| {escapeMarkdownCell(row.id)} | {escapeMarkdownCell(row.name)} | {formatWholeNumber(row.contextLength)} | {formatUsdPerMillion(row.promptPrice)} | {formatUsdPerMillion(row.completionPrice)} | {formatRequestPrice(row.requestPrice, row.hasRequestPrice)} | {formatModerationStatus(row)} | {formatLargeFloat(row.contextPerCent)} |" & "\n"

proc generateModelTable*(rows: seq[ModelRow]; title: string): string =
  result = "## " & title & "\n\n"
  result.add generateRowsTable(rows)
  result.add "\n"

proc sortFreeModels(rows: var seq[ModelRow]) =
  rows.sort(proc (left, right: ModelRow): int =
    if left.contextLength > right.contextLength:
      return -1
    if left.contextLength < right.contextLength:
      return 1
    cmp(left.id, right.id)
  )

proc sortPaidModels(rows: var seq[ModelRow]) =
  rows.sort(proc (left, right: ModelRow): int =
    if left.contextPerCent > right.contextPerCent:
      return -1
    if left.contextPerCent < right.contextPerCent:
      return 1
    if left.averagePrice < right.averagePrice:
      return -1
    if left.averagePrice > right.averagePrice:
      return 1
    cmp(left.id, right.id)
  )

proc generateFreeModelsPage*(allRows: seq[ModelRow]): string =
  let split = splitFreeVsPaid(allRows)
  var freeModels = split.freeRows
  sortFreeModels(freeModels)

  result = "# 🆓 Free Models\n\n"
  result.add "Models are considered free when both prompt and completion prices are zero. Sorted by context length descending.\n\n"
  result.add generateRowsTable(freeModels)
  result.add "\n"
  result.add "> **Moderated**: ✅ means the top provider reports content moderation, which usually lowers the chance that raw prompts/outputs are used for training workflows. ⚠️ means the provider does not report moderation here, so treat the model as higher-risk for sensitive data.\n"

proc generatePaidModelsPage*(allRows: seq[ModelRow]): string =
  let split = splitFreeVsPaid(allRows)
  var paidModels = split.paidRows
  sortPaidModels(paidModels)

  result = "# 💳 Paid Models\n\n"
  result.add "Paid models sorted by **Context/Cent** — how much context you get for $0.01 based on the average of prompt and completion pricing.\n\n"
  result.add generateRowsTable(paidModels)
  result.add "\n"
  result.add "> **Moderated**: ✅ means the top provider reports content moderation, which usually lowers the chance that raw prompts/outputs are used for training workflows. ⚠️ means the provider does not report moderation here, so treat the model as higher-risk for sensitive data.\n"

proc generateLocalModelsTable*(): string =
  result = "# Local Model Recommendations\n\n"
  result.add "> Static reference page for popular self-hosted models. VRAM estimates are approximate and assume standard inference setups; quantization, KV cache, batching, and context length can move these numbers significantly.\n\n"
  result.add "| Model | Size | VRAM (FP16) | VRAM (4-bit) | Best For | Notes |\n"
  result.add "| --- | --- | ---: | ---: | --- | --- |\n"

  for entry in LocalModels:
    result.add fmt"| {escapeMarkdownCell(entry.model)} | {escapeMarkdownCell(entry.size)} | {escapeMarkdownCell(entry.fp16)} | {escapeMarkdownCell(entry.q4)} | {escapeMarkdownCell(entry.bestFor)} | {escapeMarkdownCell(entry.notes)} |" & "\n"

proc topRows(rows: seq[ModelRow]; limit: int = 5): seq[ModelRow] =
  let capped = min(rows.len, limit)
  if capped == 0:
    return @[]

  rows[0 ..< capped]

proc generateCompactTable(rows: seq[ModelRow]): string =
  if rows.len == 0:
    return "_No matching models found._\n"

  result = "| Model ID | Name | Context | Prompt ($/1M) | Completion ($/1M) | Moderated | Context per Cent |\n"
  result.add "| --- | --- | ---: | ---: | ---: | :---: | ---: |\n"

  for row in rows:
    result.add fmt"| {escapeMarkdownCell(row.id)} | {escapeMarkdownCell(row.name)} | {formatWholeNumber(row.contextLength)} | {formatUsdPerMillion(row.promptPrice)} | {formatUsdPerMillion(row.completionPrice)} | {formatModerationStatus(row)} | {formatLargeFloat(row.contextPerCent)} |" & "\n"

proc generateCategorySection(title: string; rows: seq[ModelRow]): string =
  result = "## " & title & "\n\n"
  result.add generateCompactTable(topRows(rows))
  result.add "\n"

proc generateCategoryPages*(allRows: seq[ModelRow]): string =
  let split = splitFreeVsPaid(allRows)
  var bestValueModels = split.paidRows
  var largestContextModels = allRows
  var cheapestPaidModels = split.paidRows

  largestContextModels.sort(proc (left, right: ModelRow): int =
    if left.contextLength > right.contextLength:
      return -1
    if left.contextLength < right.contextLength:
      return 1
    if left.averagePrice < right.averagePrice:
      return -1
    if left.averagePrice > right.averagePrice:
      return 1
    cmp(left.id, right.id)
  )

  cheapestPaidModels.sort(proc (left, right: ModelRow): int =
    if left.averagePrice < right.averagePrice:
      return -1
    if left.averagePrice > right.averagePrice:
      return 1
    if left.contextPerCent > right.contextPerCent:
      return -1
    if left.contextPerCent < right.contextPerCent:
      return 1
    cmp(left.id, right.id)
  )

  bestValueModels.sort(proc (left, right: ModelRow): int =
    if left.contextPerCent > right.contextPerCent:
      return -1
    if left.contextPerCent < right.contextPerCent:
      return 1
    if left.averagePrice < right.averagePrice:
      return -1
    if left.averagePrice > right.averagePrice:
      return 1
    cmp(left.id, right.id)
  )

  result = "# Model Category Picks\n\n"
  result.add "> Generated from the OpenRouter registry snapshot. VRAM-tier sections are heuristic because the API does not expose exact parameter counts for every model; they are inferred from model names and intended only as rough guidance.\n\n"
  result.add generateCategorySection("Top 5 Models for Coding", getBestModelsForTask(allRows, "coding"))
  result.add generateCategorySection("Top 5 Vision Models", getBestModelsForTask(allRows, "vision"))
  result.add generateCategorySection("Top 5 Best Value Models", bestValueModels)
  result.add generateCategorySection("Top 5 Largest Context Windows", largestContextModels)
  result.add generateCategorySection("Top 5 Cheapest Paid Models", cheapestPaidModels)
  result.add generateCategorySection("Top 5 Models for Encoding", getBestModelsForTask(allRows, "encoding"))
  result.add generateCategorySection("Top 5 Models for TTS / Audio", getBestModelsForTask(allRows, "tts"))
  result.add generateCategorySection("Top 5 Models for ~8 GB VRAM", getTopModelsByVram(allRows, 8))
  result.add generateCategorySection("Top 5 Models for ~16 GB VRAM", getTopModelsByVram(allRows, 16))
  result.add generateCategorySection("Top 5 Models for ~24 GB VRAM", getTopModelsByVram(allRows, 24))
  result.add generateCategorySection("Top 5 Models for ~32 GB VRAM", getTopModelsByVram(allRows, 32))
  result.add generateCategorySection("Top 5 Models for ~48 GB VRAM", getTopModelsByVram(allRows, 48))
