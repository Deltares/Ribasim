package Ribasim.buildTypes

import Templates.GithubCommitStatusIntegration
import Templates.WindowsAgent
import Templates.LinuxAgent
import Templates.GenerateCacheWindows
import Templates.GenerateCacheLinux
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.vcs

object Windows_GenerateCache : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, GenerateCacheWindows)
    name = "Generate Windows TC cache"

    triggers {
        vcs {
            id = "TRIGGER_RIBA_W1"
            triggerRules = """
                +:root=Ribasim_Ribasim:/Manifest.toml
                +:root=Ribasim_Ribasim:/Project.toml
                +:root=Ribasim_Ribasim:/pixi.lock
                +:root=Ribasim_Ribasim:/pixi.toml
            """.trimIndent()
            branchFilter = "+:<default>"
        }
    }
})

object Linux_GenerateCache : BuildType({
    templates(LinuxAgent, GithubCommitStatusIntegration, GenerateCacheLinux)
    name = "Generate Linux TC cache"

    triggers {
        vcs {
            id = "TRIGGER_RIBA_L1"
            triggerRules = """
                +:root=Ribasim_Ribasim:/Manifest.toml
                +:root=Ribasim_Ribasim:/Project.toml
                +:root=Ribasim_Ribasim:/pixi.lock
                +:root=Ribasim_Ribasim:/pixi.toml
            """.trimIndent()
            branchFilter = "+:<default>"
        }
    }
})
