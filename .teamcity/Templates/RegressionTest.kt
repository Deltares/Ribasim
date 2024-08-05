package Templates

import Ribasim_Windows.Windows_BuildRibasim
import Ribasim_Linux.Linux_BuildRibasim
import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildFeatures.XmlReport
import jetbrains.buildServer.configs.kotlin.buildFeatures.xmlReport
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.schedule

fun generateRegressionTestHeader(platformOs: String): String {
    if (platformOs == "Linux") {
        return """
                #!/bin/bash
                # black magic
                source /usr/share/Modules/init/bash

                module load pixi
            """.trimIndent() + System.lineSeparator()
    }

    return ""
}

open class RegressionTest (platformOs: String) : Template() {

    init {
        name = "RegressionTest_${platformOs}_Template"

        artifactRules = """


        """.trimIndent()

        vcs {
            root(Ribasim.vcsRoots.Ribasim, ". => ribasim")
            cleanCheckout = true
        }

        val header = generateRegressionTestHeader(platformOs)

        steps {
            script {
                name = "Set up pixi"
                id = "RUNNER_1509"
                workingDir = "ribasim"
                scriptContent = header +
                        """
                pixi --version
                pixi run install-ci
                """.trimIndent()
            }
            script {
                name = "Run integration tests"
                id = "RUNNER_1511"
                workingDir = "ribasim"
                scriptContent = header +
                        """
                pixi run test-ribasim-regression
                """.trimIndent()
            }
        }

        failureConditions {
            executionTimeoutMin = 30
        }

        triggers{
            schedule {
                id = ""
                schedulingPolicy = daily {
                    hour = 0
                }

                branchFilter = "+:<default>"
                triggerBuild = always()
                withPendingChangesOnly = true
            }
        }
    }
}

object RegressionTestWindows : RegressionTest("Windows")
object RegressionTestLinux : RegressionTest("Linux")