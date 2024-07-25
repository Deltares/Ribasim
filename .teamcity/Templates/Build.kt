package Templates


import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildSteps.script

open class Build(platformOs: String) : Template() {
    init {
        name = "Build${platformOs}_Template"

        artifactRules = """ribasim\build\ribasim => ribasim_linux.zip"""

        vcs {
            root(Ribasim.vcsRoots.Ribasim, ". => ribasim")
            cleanCheckout = true
        }

        var header = ""
        if (platformOs == "Linux") {
            header = """
                #!/bin/bash
                # black magic
                source /usr/share/Modules/init/bash

                module load pixi
                module load gcc/11.3.0
            """.trimIndent()
        }
        steps {
            script {
                name = "Build binary"
                id = "RUNNER_2416"
                workingDir = "ribasim"
                scriptContent = header + """
                    pixi --version
                    pixi run install-ci
                    pixi run remove-artifacts
                    pixi run build
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