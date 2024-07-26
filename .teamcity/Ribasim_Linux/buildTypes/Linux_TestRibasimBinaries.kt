package Ribasim_Linux.buildTypes

import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.XmlReport
import jetbrains.buildServer.configs.kotlin.buildFeatures.commitStatusPublisher
import jetbrains.buildServer.configs.kotlin.buildFeatures.xmlReport
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.schedule

object Linux_TestRibasimBinaries : BuildType({
    templates(Ribasim.buildTypes.Linux_1)
    name = "Test Ribasim Binaries"

    artifactRules = """
        ribasim\python\ribasim_api\tests\temp => test_output_api.zip
        ribasim\build\tests\temp => test_output_cli.zip
    """.trimIndent()

    vcs {
        root(Ribasim.vcsRoots.Ribasim, ". => ribasim")
    }

    steps {
        script {
            name = "Set up pixi"
            id = "RUNNER_1501"
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
            name = "Run tests"
            id = "RUNNER_1503"
            workingDir = "ribasim"
            scriptContent = """
                #!/bin/bash
                # black magic
                source /usr/share/Modules/init/bash

                module load pixi
                pixi run install-ci
                pixi run test-ribasim-api
                pixi run test-ribasim-cli
            """.trimIndent()
        }
    }

    triggers {
        schedule {
            id = "TRIGGER_642"
            schedulingPolicy = daily {
                hour = 3
            }
            branchFilter = "+:<default>"
            triggerBuild = always()
        }
    }

    failureConditions {
        executionTimeoutMin = 120
    }

    features {
        xmlReport {
            id = "BUILD_EXT_145"
            reportType = XmlReport.XmlReportType.JUNIT
            rules = "ribasim/report.xml"
            verbose = true
        }
        commitStatusPublisher {
            id = "BUILD_EXT_295"
            publisher = github {
                githubUrl = "https://api.github.com"
                authType = personalToken {
                    token = "credentialsJSON:6b37af71-1f2f-4611-8856-db07965445c0"
                }
            }
        }
    }

    dependencies {
        dependency(Linux_BuildRibasim) {
            snapshot {
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_570"
                cleanDestination = true
                artifactRules = """
                    ribasim_linux.zip!** => ribasim/build/ribasim
                """.trimIndent()
            }
        }
    }

    requirements {
        doesNotEqual("env.OS", "Windows_NT", "RQ_315")
    }
})
