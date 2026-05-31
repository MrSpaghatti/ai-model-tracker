import std/[algorithm, json, math, os, sequtils, strformat, strutils, times]
import puppy
import categorizer
import json_mapper
import types

type
  LocalModelEntry = tuple[
    model: string,
    size: string,
    ctxWindow: int,
    ctxWindowSource: string,
    ctxWindowConfidence: string,
    quant: string,
    fp16: string,
    fp8: string,
    q4: string,
    vramSource: string,
    vramConfidence: string,
    bestFor: string,
    notes: string
  ]

# Curated list of local models with their HuggingFace IDs and metadata
# Updated May 2026 — including Gemma 4, Phi-4, and Qwen 2.5 families
# ctxWindow and VRAM values are fetched from HuggingFace or calculated
const LocalModelsMeta: array[21, LocalModelMeta] = [
  # --- Edge / Small GPU (< 8 GB) ---
  LocalModelMeta(hfId: "google/gemma-4-e2b-it", name: "Gemma 4 E2B", size: "2.3B", bestFor: "Edge devices, phones, audio AI", notes: "2.3B active params, native audio + vision, Apache 2.0. Runs on phones."),
  LocalModelMeta(hfId: "google/gemma-4-e4b-it", name: "Gemma 4 E4B", size: "4.5B", bestFor: "Small GPU, multimodal chat", notes: "4.5B active, vision + audio + video. Great for 8 GB GPUs."),
  LocalModelMeta(hfId: "microsoft/Phi-4-mini-instruct", name: "Phi-4 Mini", size: "3.8B", bestFor: "Tiny coding assistants, local apps", notes: "MIT license, 128K context, punches above its weight on coding."),
  LocalModelMeta(hfId: "meta-llama/Llama-3.2-3B-Instruct", name: "Llama 3.2", size: "3B", bestFor: "Light chat, summarization", notes: "Solid small model with 128K context. Great for cheap VPS GPUs."),

  # --- Mid-range GPU (8-16 GB) ---
  LocalModelMeta(hfId: "mistralai/Mistral-7B-Instruct-v0.3", name: "Mistral", size: "7B", bestFor: "General chat, instruction tuning", notes: "Reliable 7B baseline, 32K context, Apache 2.0."),
  LocalModelMeta(hfId: "meta-llama/Llama-3.1-8B-Instruct", name: "Llama 3.1", size: "8B", bestFor: "Balanced general-purpose use", notes: "One of the strongest 8B-class models. 128K context."),
  LocalModelMeta(hfId: "Qwen/Qwen2.5-7B-Instruct", name: "Qwen2.5", size: "7B", bestFor: "Multilingual chat, high-quality output", notes: "Battle-tested 7B with excellent instruction following."),
  LocalModelMeta(hfId: "deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct", name: "DeepSeek Coder V2 Lite", size: "16B", bestFor: "Coding", notes: "Strong coding specialist, fits 12 GB cards with quantization."),
  LocalModelMeta(hfId: "upstage/SOLAR-10.7B-v1.0", name: "SOLAR", size: "10.7B", bestFor: "General chat, summarization", notes: "Great quality-per-VRAM at 10.7B. Fits 8 GB with 4-bit."),
  LocalModelMeta(hfId: "microsoft/Phi-3-medium-4k-instruct", name: "Phi-3 Medium", size: "14B", bestFor: "Reasoning, analysis", notes: "Solid 14B option, squeezes onto 8 GB with aggressive quantization."),

  # --- Single GPU workstation (16-32 GB) ---
  LocalModelMeta(hfId: "google/gemma-4-26b-a4b-it", name: "Gemma 4 26B MoE", size: "26B", bestFor: "Premium efficiency, reasoning", notes: "3.8B active / 26B total MoE. ~97% of 31B quality, 256K context."),
  LocalModelMeta(hfId: "google/gemma-4-31b-it", name: "Gemma 4 31B", size: "31B", bestFor: "Best overall, math, coding, vision", notes: "#3 on LMArena. 89% AIME, 80% LiveCodeBench. Apache 2.0. Needs 24 GB at Q4."),
  LocalModelMeta(hfId: "Qwen/Qwen2.5-14B-Instruct", name: "Qwen2.5", size: "14B", bestFor: "Higher-quality reasoning", notes: "Comfortable on 16 GB cards. Strong multilingual support."),
  LocalModelMeta(hfId: "Qwen/Qwen2.5-32B-Instruct", name: "Qwen2.5", size: "32B", bestFor: "Premium local reasoning", notes: "Great fit for 24 GB cards with 4-bit quantization."),
  LocalModelMeta(hfId: "codellama/CodeLlama-34b-Instruct-hf", name: "CodeLlama", size: "34B", bestFor: "Heavy coding workloads", notes: "Dedicated coding model. Strong option for 24 GB workstations."),

  # --- High-end / Multi-GPU (32+ GB) ---
  LocalModelMeta(hfId: "Qwen/Qwen2.5-72B-Instruct", name: "Qwen2.5", size: "72B", bestFor: "Large-model quality", notes: "Multi-GPU or very large cards recommended. Top-tier output."),
  LocalModelMeta(hfId: "mistralai/Mixtral-8x7B-Instruct-v0.1", name: "Mixtral", size: "8x7B", bestFor: "Reasoning, agent workflows", notes: "MoE with very strong quality but 90 GB+ at FP16. Needs multi-GPU."),
  LocalModelMeta(hfId: "CohereForAI/c4ai-command-r-v01", name: "Command R", size: "35B", bestFor: "RAG, tool use", notes: "Excellent retrieval quality. Optimized for RAG pipelines."),
  LocalModelMeta(hfId: "deepseek-ai/DeepSeek-R1-Distill-Llama-8B", name: "DeepSeek R1 Distill", size: "8B", bestFor: "Reasoning tasks", notes: "Distilled reasoning model. Fits 8 GB GPUs with quantization."),
  LocalModelMeta(hfId: "mistralai/Mistral-Small-3.1-24B-Instruct", name: "Mistral Small 3.1", size: "24B", bestFor: "Fast inference, quality output", notes: "Apache 2.0, 128K context. ~35 tok/s on RTX 4090 at Q4."),
  LocalModelMeta(hfId: "01-ai/Yi-34B", name: "Yi", size: "34B", bestFor: "Long-form writing, analysis", notes: "High-quality 34B open model. Suitable for 24 GB with quantization.")
]

# Known context windows for gated models (from official documentation)
proc getFallbackCtxWindow(hfId: string): int =
  case hfId
  of "google/gemma-4-e2b-it": result = 131072
  of "google/gemma-4-e4b-it": result = 131072
  of "google/gemma-4-26b-a4b-it": result = 262144
  of "google/gemma-4-31b-it": result = 262144
  of "meta-llama/Llama-3.2-1B": result = 131072
  of "meta-llama/Llama-3.2-3B": result = 131072
  of "meta-llama/Llama-3.2-3B-Instruct": result = 131072
  of "meta-llama/Llama-3.1-8B-Instruct": result = 131072
  of "codellama/CodeLlama-7b-Instruct-hf": result = 16384
  of "codellama/CodeLlama-13b-Instruct-hf": result = 16384
  of "codellama/CodeLlama-34b-Instruct-hf": result = 16384
  of "01-ai/Yi-34B": result = 4096
  of "CohereForAI/c4ai-command-r-v01": result = 131072
  of "mistralai/Mistral-Small-3.1-24B-Instruct": result = 131072
  of "deepseek-ai/DeepSeek-R1-Distill-Llama-8B": result = 131072
  else: result = 4096 # conservative default

# Parse model size string to float (billions of parameters)
proc parseModelSize(size: string): float =
  let s = size.replace("B", "")
  if s.contains("x"):
    # Handle MoE models like "8x7B" -> total params = sum of experts? Actually just track the base
    let parts = s.split("x")
    if parts.len == 2:
      try:
        let n = parseFloat(parts[0])
        let per = parseFloat(parts[1])
        result = n * per
      except: result = 0.0
  else:
    try: result = parseFloat(s)
    except: result = 0.0

# Calculate VRAM requirement based on model size and quantization bits
# Includes overhead for KV cache, activations, and system memory
proc calcVram(paramsB: float; bytesPerParam: float): string =
  let baseGb = paramsB * bytesPerParam
  let kvCacheGb = paramsB * 0.3  # KV cache overhead ~0.3GB per 1B params
  let activationGb = baseGb * 0.15  # Activation memory ~15% of weights
  let overhead = 0.5  # System overhead (CUDA kernels, etc.)
  let total = baseGb + kvCacheGb + activationGb + overhead
  let rounded = ceil(total).int
  result = $rounded & " GB"

# Fetch context window length from HuggingFace config.json
proc fetchHfContextWindow(hfId: string): int =
  let configUrl = "https://huggingface.co/" & hfId & "/resolve/main/config.json"
  for attempt in 0..2:
    try:
      let rawConfig = fetch(
        configUrl,
        headers = @[
          Header(key: "Accept", value: "application/json"),
          Header(key: "User-Agent", value: "ai-model-tracker/1.0")
        ]
      )
      let config = parseJson(rawConfig)
      # Try various known field names for context window
      if config.hasKey("max_position_embeddings"):
        return config["max_position_embeddings"].getInt()
      if config.hasKey("n_positions"):
        return config["n_positions"].getInt()
      if config.hasKey("n_ctx"):
        return config["n_ctx"].getInt()
      if config.hasKey("seq_length"):
        return config["seq_length"].getInt()
      if config.hasKey("sliding_window"):
        return config["sliding_window"].getInt()
      if config.hasKey("model_max_length"):
        return config["model_max_length"].getInt()
      return 0
    except:
      if attempt < 2:
        sleep(200 * (attempt + 1))
  0

# Main function to build local models data from HuggingFace sources
proc buildLocalModels*(): seq[LocalModelEntry] =
  for meta in LocalModelsMeta:
    let paramsB = parseModelSize(meta.size)
    
    # Try to fetch context window from HuggingFace
    var ctxWindow = fetchHfContextWindow(meta.hfId)
    var ctxSource = "huggingface-config"
    var ctxConfidence = "high"
    if ctxWindow == 0:
      ctxWindow = getFallbackCtxWindow(meta.hfId)
      ctxSource = "fallback-curated"
      ctxConfidence = "medium"
    
    var entry: LocalModelEntry
    entry.model = meta.name
    entry.size = meta.size
    entry.ctxWindow = ctxWindow
    entry.ctxWindowSource = ctxSource
    entry.ctxWindowConfidence = ctxConfidence
    entry.quant = "FP16, FP8, 4-bit"
    entry.fp16 = calcVram(paramsB, 2.0)
    entry.fp8 = calcVram(paramsB, 1.0)
    entry.q4 = calcVram(paramsB, 0.5)
    entry.vramSource = "heuristic-size-formula"
    entry.vramConfidence = "medium"
    entry.bestFor = meta.bestFor
    entry.notes = meta.notes
    result.add(entry)

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
  let c = classify(value)
  if c == fcNaN or c == fcNegInf:
    return "N/A"
  if c in {fcInf, fcNegInf}:
    return "∞"

  if value >= 1_000_000_000_000.0:
    return formatFloat(value, ffScientific, 2)

  let rounded = value.round.int
  result = formatWholeNumber(rounded)

proc formatUsdPerMillion*(price: float): string =
  if price.classify == fcNaN:
    return "N/A"
  "$" & formatFloat(price * 1_000_000.0, ffDecimal, 4)

proc formatRequestPrice(price: float; hasRequestPrice: bool): string =
  if not hasRequestPrice:
    return "-"

  if price.classify == fcNaN:
    return "N/A"

  "$" & formatFloat(price, ffDecimal, 6)

proc escapeMarkdownCell(value: string): string =
  value.replace("|", "\\|").replace("\n", " ")

proc formatModerationStatus(row: ModelRow): string =
  if row.isModerated:
    "✅"
  else:
    "⚠️"

proc generateRowsTable(rows: seq[ModelRow]): string =
  result = "| Model ID | Name | Context | Prompt ($/1M) | Completion ($/1M) | Request ($/req) | Data Policy | Moderated | Context per Cent |\n"
  result.add "| --- | --- | ---: | ---: | ---: | ---: | --- | :---: | ---: |\n"

  for row in rows:
    result.add fmt"| {escapeMarkdownCell(row.id)} | {escapeMarkdownCell(row.name)} | {formatWholeNumber(row.contextLength)} | {formatUsdPerMillion(row.promptPrice)} | {formatUsdPerMillion(row.completionPrice)} | {formatRequestPrice(row.requestPrice, row.hasRequestPrice)} | {escapeMarkdownCell(row.dataPolicyLevel)} | {formatModerationStatus(row)} | {formatLargeFloat(row.contextPerCent)} |" & "\n"

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
  let localModels = buildLocalModels()
  result = "# Local Model Recommendations\n\n"
  result.add "> Context windows prefer live HuggingFace config values; curated fallbacks are used when unavailable. VRAM is a heuristic estimate including weights, KV cache, and activation overhead.\n\n"
  result.add "| Model | Size | Ctx Window | Ctx Source | Ctx Confidence | Quant | VRAM (FP16) | VRAM (FP8) | VRAM (4-bit) | VRAM Source | VRAM Confidence | Best For | Notes |\n"
  result.add "| --- | --- | ---: | --- | --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |\n"

  for entry in localModels:
    let ctxWin = if entry.ctxWindow > 0: formatWholeNumber(entry.ctxWindow) else: "N/A"
    result.add fmt"| {escapeMarkdownCell(entry.model)} | {escapeMarkdownCell(entry.size)} | {ctxWin} | {escapeMarkdownCell(entry.ctxWindowSource)} | {escapeMarkdownCell(entry.ctxWindowConfidence)} | {escapeMarkdownCell(entry.quant)} | {escapeMarkdownCell(entry.fp16)} | {escapeMarkdownCell(entry.fp8)} | {escapeMarkdownCell(entry.q4)} | {escapeMarkdownCell(entry.vramSource)} | {escapeMarkdownCell(entry.vramConfidence)} | {escapeMarkdownCell(entry.bestFor)} | {escapeMarkdownCell(entry.notes)} |" & "\n"

proc generateLocalModelsJson*(): string =
  let localModels = buildLocalModels()
  var jsonModels: seq[JsonNode] = @[]
  
  for entry in localModels:
    let bestForJson = %entry.bestFor.split(",").mapIt(%it.strip())
    let sizeSlug = entry.size.toLowerAscii().replace(".", "-").replace("x", "x")
    let idSlug = entry.model.toLowerAscii().replace(" ", "-").replace(",", "") & "-" & sizeSlug
    
    let modelJson = %*{
      "id": idSlug,
      "name": entry.model & " " & entry.size,
      "size": entry.size,
      "ctx_window": entry.ctxWindow,
      "quant": entry.quant,
      "vram_fp16": entry.fp16,
      "vram_fp8": entry.fp8,
      "vram_4bit": entry.q4,
      "best_for": bestForJson,
      "notes": entry.notes,
      "metadata": {
        "ctx_window": {
          "source": entry.ctxWindowSource,
          "confidence": entry.ctxWindowConfidence
        },
        "vram": {
          "source": entry.vramSource,
          "confidence": entry.vramConfidence
        }
      }
    }
    jsonModels.add(modelJson)
  
  let root = %*{
    "version": 1,
    "generated_at": getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "models": jsonModels
  }
  result = pretty(root)

proc topRows(rows: seq[ModelRow]; limit: int = 5): seq[ModelRow] =
  let capped = min(rows.len, limit)
  if capped == 0:
    return @[]

  rows[0 ..< capped]

proc generateCompactTable(rows: seq[ModelRow]): string =
  if rows.len == 0:
    return "_No matching models found._\n"

  result = "| Model ID | Name | Context | Prompt ($/1M) | Completion ($/1M) | Data Policy | Moderated | Context per Cent |\n"
  result.add "| --- | --- | ---: | ---: | ---: | --- | :---: | ---: |\n"

  for row in rows:
    result.add fmt"| {escapeMarkdownCell(row.id)} | {escapeMarkdownCell(row.name)} | {formatWholeNumber(row.contextLength)} | {formatUsdPerMillion(row.promptPrice)} | {formatUsdPerMillion(row.completionPrice)} | {escapeMarkdownCell(row.dataPolicyLevel)} | {formatModerationStatus(row)} | {formatLargeFloat(row.contextPerCent)} |" & "\n"

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

proc generateCurrentJson*(rows: seq[ModelRow]): string =
  var models: seq[JsonModel] = @[]
  for row in rows:
    models.add toJsonModel(row)

  let root = JsonCurrentRoot(
    version: 1,
    generated_at: utcIsoTimestamp(),
    models: models
  )

  result = pretty(%root)
