package Templates

import Ribasim_Windows.Windows_BuildRibasim
import Ribasim_Linux.Linux_BuildRibasim
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildFeatures.buildCache
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

        val depot_path = generateJuliaDepotPath(platformOs)
        params {
            param("env.MINIO_ACCESS_KEY", "KwKRzscudy3GvRB8BN1Z")
            password("env.MINIO_SECRET_KEY", "credentialsJSON:86cbf3e5-724c-437d-9962-7a3f429b0aa2")
            param("env.JULIA_DEPOT_PATH", depot_path)
        }

        features {
            buildCache {
                id = "Ribasim${platformOs}Cache"
                name = "Ribasim${platformOs}Cache"
                publish = false
            }
        }

        val header = generateRegressionTestHeader(platformOs)

        dependencies {
            artifacts(AbsoluteId("Ribasim_${platformOs}_GenerateCache")) {
                buildRule = lastSuccessful()
                artifactRules = "cache.zip => .julia"
            }
        }

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
                name = "Run regression tests"
                id = "RUNNER_1511"
                workingDir = "ribasim"
                scriptContent = header +
                        """
                pixi run test-ribasim-regression
                """.trimIndent()
            }
        }

        failureConditions {
            executionTimeoutMin = 60
        }

    }
}

object RegressionTestWindows : RegressionTest("Windows")
object RegressionTestLinux : RegressionTest("Linux")
