package Templates

import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildFeatures.XmlReport
import jetbrains.buildServer.configs.kotlin.buildFeatures.xmlReport
import jetbrains.buildServer.configs.kotlin.buildSteps.script

fun generateTestBinariesHeader(platformOs: String): String {
    if (platformOs == "Linux") {
        return """
                #!/bin/bash
                # black magic
                source /usr/share/Modules/init/bash

                module load pixi
            """.trimIndent()
    }

    return ""
}

open class TestBinaries (platformOs: String) : Template() {
    init {
        name = "TestBinaries${platformOs}_Template"

        artifactRules = """
        ribasim\python\ribasim_api\tests\temp => test_output_api.zip
        ribasim\build\tests\temp => test_output_cli.zip
    """.trimIndent()

        vcs {
            root(Ribasim.vcsRoots.Ribasim, ". => ribasim")
            cleanCheckout = true
        }

        val header = generateTestBinariesHeader(platformOs)
        steps {
            script {
                name = "Set up pixi"
                id = "RUNNER_1501"
                workingDir = "ribasim"
                scriptContent = header +
                """
                pixi --version
                """.trimIndent()
            }
            script {
                name = "Run tests"
                id = "RUNNER_1503"
                workingDir = "ribasim"
                scriptContent = header +
                """
                pixi run install
                pixi run test-ribasim-api
                pixi run test-ribasim-cli
                """.trimIndent()
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
        }
    }
}

object TestBinariesWindows : TestBinaries("Windows")
object TestBinariesLinux : TestBinaries("Linux")