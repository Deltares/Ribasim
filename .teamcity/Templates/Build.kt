package Templates


import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildSteps.script

fun generateBuildHeader(platformOs: String): String {
    if (platformOs == "Linux") {
        return """
                #!/bin/bash
                # black magic
                source /usr/share/Modules/init/bash

                module load pixi
                module load gcc/12.2.0_gcc12.2.0
            """.trimIndent() + System.lineSeparator()
    }

    return ""
}

open class Build(platformOs: String) : Template() {
    init {
        name = "Build${platformOs}_Template"

        vcs {
            root(Ribasim.vcsRoots.Ribasim, ". => ribasim")
            cleanCheckout = true
        }

        val header = generateBuildHeader(platformOs)
        steps {
            script {
                name = "Set up pixi"
                id = "RUNNER_2415"
                workingDir = "ribasim"
                scriptContent = header +
                """
                pixi --version
                pixi run --environment=dev install-ci
                pixi install --environment=rust
                """.trimIndent()
            }
            script {
                name = "Build binary"
                id = "RUNNER_2416"
                workingDir = "ribasim"
                scriptContent = header +
                """
                pixi run --environment=dev remove-artifacts
                pixi run --environment=dev build
                """.trimIndent()
            }
        }

        failureConditions {
            executionTimeoutMin = 120
        }
    }
}

object BuildWindows : Build("Windows")
object BuildLinux : Build("Linux")
