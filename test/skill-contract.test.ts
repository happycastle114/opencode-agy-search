import { describe, expect, test } from "bun:test"

const SKILL_PATH = new URL("../skills/agy-search/SKILL.md", import.meta.url)

describe("agent skill contract", () => {
  test("covers preflight, escalation, context saving, and citation safety", async () => {
    const skill = await Bun.file(SKILL_PATH).text()

    for (const command of ["status", "models", "search", "extract", "map", "crawl", "research"]) {
      expect(skill).toContain(`agy-search ${command}`)
    }
    expect(skill).toContain(".agy-search/")
    expect(skill).toContain("http://")
    expect(skill).toContain("https://")
    expect(skill).toContain("sources")
    expect(skill).not.toContain("TODO")
  })
})
