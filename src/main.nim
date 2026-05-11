import std/[os, strutils]

import fetcher
import formatter
import parser

const
  ReadmeTemplatePath = "templates/README.md"
  ReadmeOutputPath = "README.md"
  FreeModelsOutputPath = "FREE_MODELS.md"
  PaidModelsOutputPath = "PAID_MODELS.md"
  LocalModelsOutputPath = "LOCAL_MODELS.md"
  CategoriesOutputPath = "CATEGORIES.md"
  ReadmeContentPlaceholder = "{{README_CONTENT}}"
  DefaultReadmeTemplate = """# AI Model Price & Context Tracker

> Automatically updated every 12 hours via GitHub Actions.

## 📊 Pages

- [🆓 Free Models](FREE_MODELS.md) — All models with zero pricing, sorted by context length
- [💳 Paid Models](PAID_MODELS.md) — All paid models, sorted by context/cent efficiency
- [🏆 Category Picks](CATEGORIES.md) — Top-5 models for coding, vision, value, VRAM tiers, and more
- [💻 Local Models](LOCAL_MODELS.md) — Curated self-hosted model recommendations with VRAM estimates

## 📈 Raw Data

Historical JSON snapshots are stored in the `data/` directory.
"""

proc loadReadmeTemplate(): string =
  try:
    if fileExists(ReadmeTemplatePath):
      return readFile(ReadmeTemplatePath)

    if fileExists(ReadmeOutputPath):
      let existingReadme = readFile(ReadmeOutputPath)
      if ReadmeContentPlaceholder in existingReadme:
        return existingReadme

    result = DefaultReadmeTemplate
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to load README template: " & exc.msg)

proc writeOutputFile(path, content, label: string) =
  try:
    writeFile(path, content)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write " & label & ": " & exc.msg)

proc writeReadme(content: string) =
  let readmeTemplate = loadReadmeTemplate()

  if ReadmeContentPlaceholder in readmeTemplate:
    writeOutputFile(
      ReadmeOutputPath,
      readmeTemplate.replace(ReadmeContentPlaceholder, content),
      "README.md"
    )
    return

  # Template is the complete README (no placeholder needed)
  writeOutputFile(ReadmeOutputPath, readmeTemplate, "README.md")

proc main() =
  try:
    let rawJson = fetchRegistryJson()
    writeRawRegistry(rawJson)

    let rows = parseModels(rawJson)
    writeReadme("")
    writeOutputFile(FreeModelsOutputPath, generateFreeModelsPage(rows), "FREE_MODELS.md")
    writeOutputFile(PaidModelsOutputPath, generatePaidModelsPage(rows), "PAID_MODELS.md")
    writeOutputFile(LocalModelsOutputPath, generateLocalModelsTable(), "LOCAL_MODELS.md")
    writeOutputFile(CategoriesOutputPath, generateCategoryPages(rows), "CATEGORIES.md")

    stdout.writeLine("Generated README.md, FREE_MODELS.md, PAID_MODELS.md, LOCAL_MODELS.md, and CATEGORIES.md for " & $rows.len & " models.")
  except CatchableError as exc:
    stderr.writeLine("Error: " & exc.msg)
    quit(QuitFailure)

when isMainModule:
  main()
