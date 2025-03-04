package Templates

import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildFeatures.buildCache
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
            """.trimIndent() + System.lineSeparator()
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

        params {
            password("MiniO_credential_token", "credentialsJSON:86cbf3e5-724c-437d-9962-7a3f429b0aa2")
        }

        features {
            buildCache {
                id = "Ribasim${platformOs}Cache"
                name = "Ribasim ${platformOs} Cache"
                publish = false
            }
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
                pixi run install-ci
                """.trimIndent()
            }
            script {
                name = "Run tests"
                id = "RUNNER_1503"
                workingDir = "ribasim"
                scriptContent = header +
                """
                pixi run test-ribasim-api
                pixi run test-ribasim-cli
                pixi run python utils/get_benchmark.py --secretkey %MiniO_credential_token% "hws_2024_7_0/"
                pixi run model-integration-test
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
