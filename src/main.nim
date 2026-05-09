import std/[os, strutils]

import fetcher
import formatter
import parser

const
  ReadmeTemplatePath = "templates/README.md"
  ReadmeOutputPath = "README.md"
  LocalModelsOutputPath = "LOCAL_MODELS.md"
  CategoriesOutputPath = "CATEGORIES.md"
  ModelTablePlaceholder = "{{MODEL_TABLE}}"
  ModelTablesPlaceholder = "{{MODEL_TABLES}}"
  DefaultReadmeTemplate = """# AI Model Price Tracker

{{MODEL_TABLES}}
"""

proc loadReadmeTemplate(): string =
  try:
    if fileExists(ReadmeTemplatePath):
      return readFile(ReadmeTemplatePath)

    if fileExists(ReadmeOutputPath):
      let existingReadme = readFile(ReadmeOutputPath)
      if ModelTablesPlaceholder in existingReadme or ModelTablePlaceholder in existingReadme:
        return existingReadme

    result = DefaultReadmeTemplate
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to load README template: " & exc.msg)

proc writeOutputFile(path, content, label: string) =
  try:
    writeFile(path, content)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write " & label & ": " & exc.msg)

proc writeReadme(tableMarkdown: string) =
  let readmeTemplate = loadReadmeTemplate()

  if ModelTablesPlaceholder in readmeTemplate:
    writeOutputFile(
      ReadmeOutputPath,
      readmeTemplate.replace(ModelTablesPlaceholder, tableMarkdown),
      "README.md"
    )
    return

  if ModelTablePlaceholder in readmeTemplate:
    writeOutputFile(
      ReadmeOutputPath,
      readmeTemplate.replace(ModelTablePlaceholder, tableMarkdown),
      "README.md"
    )
    return

  raise newException(CatchableError, "README template is missing the {{MODEL_TABLES}} or {{MODEL_TABLE}} placeholder")

proc main() =
  try:
    let rawJson = fetchRegistryJson()
    writeRawRegistry(rawJson)

    let rows = parseModels(rawJson)
    writeReadme(generateFreeVsPaidTables(rows))
    writeOutputFile(LocalModelsOutputPath, generateLocalModelsTable(), "LOCAL_MODELS.md")
    writeOutputFile(CategoriesOutputPath, generateCategoryPages(rows), "CATEGORIES.md")

    stdout.writeLine("Generated README.md, LOCAL_MODELS.md, and CATEGORIES.md for " & $rows.len & " models.")
  except CatchableError as exc:
    stderr.writeLine("Error: " & exc.msg)
    quit(QuitFailure)

when isMainModule:
  main()
