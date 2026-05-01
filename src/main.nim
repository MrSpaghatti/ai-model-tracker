import std/[os, sequtils, strutils]
import puppy

import parser

const
  OpenRouterModelsUrl = "https://openrouter.ai/api/v1/models"
  RegistryPath = "data/registry.json"

  # Template paths
  ReadmeTemplatePath = "templates/README.md"
  LocalModelsTemplatePath = "templates/local-models.md"
  VisionTemplatePath = "templates/best-models/vision.md"
  AudioTemplatePath = "templates/best-models/audio.md"
  ImageGenTemplatePath = "templates/best-models/image-gen.md"
  VramBaseTemplatePath = "templates/vram-guide/base.md"

  # Output paths
  ReadmeOutputPath = "README.md"
  LocalModelsOutputPath = "local-models.md"
  VisionOutputPath = "best-models/vision.md"
  AudioOutputPath = "best-models/audio.md"
  ImageGenOutputPath = "best-models/image-gen.md"

  VramTiers = [4, 8, 16, 24, 48]

  DefaultReadmeTemplate = """# AI Model Price Tracker

## 💰 Paid Models

{{PAID_MODEL_TABLE}}

## 🆓 Free Models

> ⚠️ Free models on OpenRouter may use your prompts to train AI models.

{{FREE_MODEL_TABLE}}
"""

proc fetchRegistryJson(): string =
  try:
    result = fetch(
      OpenRouterModelsUrl,
      headers = @[
        Header(key: "Accept", value: "application/json"),
        Header(key: "HTTP-Referer", value: "https://github.com/spag/ai-model-tracker"),
        Header(key: "X-Title", value: "ai-model-tracker")
      ]
    )
  except PuppyError as exc:
    raise newException(CatchableError, "Unable to fetch OpenRouter model registry: " & exc.msg)

proc writeRawRegistry(rawJson: string) =
  try:
    createDir(parentDir(RegistryPath))
    writeFile(RegistryPath, rawJson)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write raw registry JSON: " & exc.msg)

proc loadTemplate(path: string): string =
  if fileExists(path):
    try:
      return readFile(path)
    except CatchableError:
      discard
  return ""

proc writePage(templatePath, outputPath: string, replacements: openArray[(string, string)]) =
  var content = loadTemplate(templatePath)
  if content.len == 0:
    return

  for (placeholder, value) in replacements:
    content = content.replace(placeholder, value)

  try:
    let dir = parentDir(outputPath)
    if dir.len > 0 and dir != ".":
      createDir(dir)
    writeFile(outputPath, content)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write " & outputPath & ": " & exc.msg)

proc writeReadme(paidTable, freeTable: string) =
  var content = loadTemplate(ReadmeTemplatePath)
  if content.len == 0:
    content = DefaultReadmeTemplate

  content = content.replace("{{PAID_MODEL_TABLE}}", paidTable)
  content = content.replace("{{FREE_MODEL_TABLE}}", freeTable)

  try:
    writeFile(ReadmeOutputPath, content)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write README.md: " & exc.msg)

proc main() =
  try:
    let rawJson = fetchRegistryJson()
    writeRawRegistry(rawJson)

    let rows = parseModels(rawJson)
    let paidRows = rows.filterIt(not it.isFree)
    let freeRows = rows.filterIt(it.isFree)

    # README: paid + free tables
    writeReadme(generateMarkdownTable(paidRows), generateMarkdownTable(freeRows))

    # Local models page
    writePage(LocalModelsTemplatePath, LocalModelsOutputPath,
      [("{{LOCAL_MODEL_TABLE}}", generateLocalModelsTable(rows))])

    # Best-models pages
    writePage(VisionTemplatePath, VisionOutputPath,
      [("{{VISION_MODEL_TABLE}}", generateModalityTable(rows, "image", "input"))])

    writePage(AudioTemplatePath, AudioOutputPath,
      [("{{AUDIO_MODEL_TABLE}}", generateModalityTable(rows, "audio", "output"))])

    writePage(ImageGenTemplatePath, ImageGenOutputPath,
      [("{{IMAGE_GEN_TABLE}}", generateModalityTable(rows, "image", "output"))])

    # VRAM guide pages
    for vramGb in VramTiers:
      let vramPath = "vram-guide/" & $vramGb & "gb.md"
      writePage(VramBaseTemplatePath, vramPath, [
        ("{{VRAM_SIZE}}", $vramGb & "GB"),
        ("{{VRAM_MODEL_TABLE}}", generateVramTable(rows, vramGb))
      ])

    stdout.writeLine("Generated pages for " & $rows.len & " models.")
  except CatchableError as exc:
    stderr.writeLine("Error: " & exc.msg)
    quit(QuitFailure)

when isMainModule:
  main()
