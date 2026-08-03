import { describe, expect, test } from "bun:test"

import { AgySearchPlugin } from "../index.ts"

const AGY_EXECUTABLE_ENV = "AGY_SEARCH_AGY_PATH"

describe("OpenCode plugin hooks", () => {
  test("configures install guidance and one skill path idempotently", async () => {
    const config = {
      instructions: ["existing.md"],
      skills: { paths: ["/existing/skill"], urls: ["https://example.com/skill"] },
    }

    const hooks = await AgySearchPlugin()
    await hooks.config?.(config)
    await hooks.config?.(config)

    expect(config.instructions).toHaveLength(2)
    expect(config.instructions[0]).toBe("existing.md")
    expect(config.instructions[1]).toEndWith("skills/agy-search/rules/install.md")
    expect(config.skills.paths).toHaveLength(2)
    expect(config.skills.paths[0]).toBe("/existing/skill")
    expect(config.skills.paths[1]).toEndWith("skills/agy-search")
    expect(config.skills.urls).toEqual(["https://example.com/skill"])
  })

  test("forwards only the documented executable override", async () => {
    const output: Record<string, string> = {}
    const previousExecutable = process.env[AGY_EXECUTABLE_ENV]
    const previousUnrelated = process.env.UNRELATED_SECRET
    process.env[AGY_EXECUTABLE_ENV] = "/fixture/agy"
    process.env.UNRELATED_SECRET = "private"

    try {
      const hooks = await AgySearchPlugin()
      await hooks["shell.env"]?.(
        { cwd: "/fixture", sessionID: "session", callID: "call" },
        { env: output },
      )
    } finally {
      if (previousExecutable === undefined) delete process.env[AGY_EXECUTABLE_ENV]
      else process.env[AGY_EXECUTABLE_ENV] = previousExecutable
      if (previousUnrelated === undefined) delete process.env.UNRELATED_SECRET
      else process.env.UNRELATED_SECRET = previousUnrelated
    }

    expect(output).toEqual({ [AGY_EXECUTABLE_ENV]: "/fixture/agy" })
  })

  test("does not forward an absent or empty override", async () => {
    const output: Record<string, string> = {}
    const previousExecutable = process.env[AGY_EXECUTABLE_ENV]
    process.env[AGY_EXECUTABLE_ENV] = ""

    try {
      const hooks = await AgySearchPlugin()
      await hooks["shell.env"]?.(
        { cwd: "/fixture", sessionID: "session", callID: "call" },
        { env: output },
      )
    } finally {
      if (previousExecutable === undefined) delete process.env[AGY_EXECUTABLE_ENV]
      else process.env[AGY_EXECUTABLE_ENV] = previousExecutable
    }

    expect(output).toEqual({})
  })
})
