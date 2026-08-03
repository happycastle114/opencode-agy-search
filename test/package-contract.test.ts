import { describe, expect, test } from "bun:test"

import metadata from "../package.json"

const EXPECTED_RUNTIME_FILES = [
  "LICENSE",
  "README.md",
  "index.ts",
  "package.json",
  "skills/agy-search/SKILL.md",
  "skills/agy-search/rules/install.md",
]

describe("public npm package contract", () => {
  test("uses an explicit runtime allowlist and exact development pins", () => {
    expect(metadata.files).toEqual(["index.ts", "skills", "README.md", "LICENSE"])
    expect(metadata.publishConfig).toEqual({ access: "public", provenance: true })
    expect(
      Object.values(metadata.devDependencies).every((version) => /^\d+\.\d+\.\d+$/.test(version)),
    ).toBeTrue()
  })

  test("dry-run tarball contains each runtime asset and excludes tests", () => {
    const result = Bun.spawnSync(["npm", "pack", "--dry-run"], {
      cwd: new URL("..", import.meta.url).pathname,
    })
    const report = `${result.stdout.toString()}\n${result.stderr.toString()}`

    expect(result.exitCode).toBe(0)
    for (const file of EXPECTED_RUNTIME_FILES) expect(report).toContain(file)
    expect(report).not.toContain("test/plugin-config.test.ts")
  })
})
