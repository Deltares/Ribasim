package Ribasim.buildTypes

import Templates.GithubCommitStatusIntegration
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.vcs

object GenerateTestmodels : BuildType({
    templates(GithubCommitStatusIntegration)
    name = "Generate Testmodels"

    artifactRules = """ribasim\generated_testmodels => generated_testmodels.zip"""
    publishArtifacts = PublishMode.SUCCESSFUL

    vcs {
        cleanCheckout = true
        root(Ribasim.vcsRoots.Ribasim, ". => ribasim")
    }

    steps {
        script {
            name = "Set up pixi"
            id = "RUNNER_2415"
            workingDir = "ribasim"
            scriptContent = """
                #!/bin/bash
                # black magic
                source /usr/share/Modules/init/bash

                module load pixi
                pixi --version
            """.trimIndent()
        }
        script {
            name = "Generate testmodels"
            id = "RUNNER_2416"
            workingDir = "ribasim"
            scriptContent = """
                #!/bin/bash
                # black magic
                source /usr/share/Modules/init/bash

                module load pixi
                pixi run --environment=dev generate-testmodels
            """.trimIndent()
        }
    }

    triggers {
        vcs {
            id = "TRIGGER_646"
        }
    }

    failureConditions {
        executionTimeoutMin = 120
    }

    requirements {
        doesNotEqual("env.OS", "Windows_NT", "RQ_275")
        doesNotEqual("teamcity.agent.name", "Default Agent", "RQ_339")
    }
})
