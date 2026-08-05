import { describe, expect, test } from "bun:test"

import metadata from "../package.json"

const EXPECTED_RUNTIME_FILES = [
  "LICENSE",
  "README.md",
  "index.ts",
  "package.json",
  "scripts/install.sh",
  "skills/agy-search/SKILL.md",
  "skills/agy-search/rules/install.md",
]

describe("public npm package contract", () => {
  test("uses an explicit runtime allowlist, release version, and exact development pins", () => {
    expect(metadata.name).toBe("@happycastle114/opencode-agy-search")
    expect(metadata.version).toBe("0.3.3")
    expect(metadata.files).toEqual([
      "index.ts",
      "skills",
      "scripts/install.sh",
      "README.md",
      "LICENSE",
    ])
    expect(metadata.publishConfig).toEqual({ registry: "https://npm.pkg.github.com" })
    expect(metadata.agySearch.minimumCliVersion).toBe("0.2.4")
    expect("dependencies" in metadata).toBeFalse()
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
