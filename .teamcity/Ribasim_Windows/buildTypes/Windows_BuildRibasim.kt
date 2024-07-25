package Ribasim_Windows.buildTypes

import Templates.GithubCommitStatusIntegration
import Templates.WindowsAgent
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.PublishMode
import jetbrains.buildServer.configs.kotlin.buildSteps.script

object Windows_BuildRibasim : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration)
    name = "Build Ribasim"

    artifactRules = """ribasim\build\ribasim => ribasim_windows.zip"""
    publishArtifacts = PublishMode.SUCCESSFUL

    vcs {
        root(Ribasim.vcsRoots.Ribasim, ". => ribasim")
        cleanCheckout = true
    }

    steps {
        script {
            name = "Set up pixi"
            id = "RUNNER_2415"
            workingDir = "ribasim"
            scriptContent = """
                pixi --version
                pixi run install-ci
            """.trimIndent()
        }
        script {
            name = "Build binary"
            id = "RUNNER_2416"
            workingDir = "ribasim"
            scriptContent = """
                pixi run remove-artifacts
                pixi run build
            """.trimIndent()
        }
    }

    failureConditions {
        executionTimeoutMin = 120
    }
})
