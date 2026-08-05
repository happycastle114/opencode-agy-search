import { fileURLToPath } from "node:url"
import type { Config, Hooks, Plugin } from "@opencode-ai/plugin"

const EXECUTABLE_ENVIRONMENT = ["AGY_SEARCH_AGY_PATH", "AGY_SEARCH_CURL_PATH"] as const
const INSTALL_RULE_PATH = fileURLToPath(
  new URL("./skills/agy-search/rules/install.md", import.meta.url),
)
const SKILL_DIRECTORY = fileURLToPath(new URL("./skills/agy-search", import.meta.url))

type SkillAwareConfig = Config & {
  skills?: {
    paths?: string[]
    urls?: string[]
  }
}

function appendUnique(values: string[] | undefined, value: string): string[] {
  const existing = values ?? []
  return existing.includes(value) ? existing : [...existing, value]
}

function configureAgySearch(config: Config): void {
  const skillAwareConfig: SkillAwareConfig = config
  skillAwareConfig.instructions = appendUnique(skillAwareConfig.instructions, INSTALL_RULE_PATH)
  skillAwareConfig.skills = {
    ...skillAwareConfig.skills,
    paths: appendUnique(skillAwareConfig.skills?.paths, SKILL_DIRECTORY),
  }
}

const agySearchPluginImplementation = (async (): Promise<Hooks> => ({
  config: async (config) => {
    configureAgySearch(config)
  },
  "shell.env": async (_input, output) => {
    for (const name of EXECUTABLE_ENVIRONMENT) {
      const executable = process.env[name]
      if (executable !== undefined && executable.length > 0) {
        output.env[name] = executable
      }
    }
  },
})) satisfies Plugin

export const AgySearchPlugin = agySearchPluginImplementation
