package Ribasim_Linux.buildTypes

import Templates.GithubCommitStatusIntegration
import Templates.LinuxAgent
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.buildSteps.script

object Linux_BuildRibasim : BuildType({
    templates(LinuxAgent, GithubCommitStatusIntegration)
    name = "Build Ribasim"

    artifactRules = """ribasim\build\ribasim => ribasim_linux.zip"""

    vcs {
        root(Ribasim.vcsRoots.Ribasim, ". => ribasim")
        cleanCheckout = true
    }

    val linuxheader = """
                #!/bin/bash
                # black magic
                source /usr/share/Modules/init/bash

                module load pixi
                module load gcc/11.3.0
            """.trimIndent()
    val buildscript = """
                pixi --version
                pixi run install-ci
                pixi run remove-artifacts
                pixi run build
            """.trimIndent()

    val totalscript = linuxheader + "\n" + buildscript

    steps {
        script {
            name = "Build binary"
            id = "RUNNER_2416"
            workingDir = "ribasim"
            scriptContent = totalscript.trimIndent()
        }
    }

    failureConditions {
        executionTimeoutMin = 120
    }
})
