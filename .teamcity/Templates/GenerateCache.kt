package Templates

import Ribasim.vcsRoots.Ribasim
import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.*

fun generateJuliaDepotPath(platformOs: String): String {
    if (platformOs == "Linux") {
        return "%teamcity.build.checkoutDir%/.julia:"
    } else {
        return "%teamcity.build.checkoutDir%/.julia;"
    }
}

open class GenerateCache(platformOs: String) : Template() {
    init {
        name = "GenerateCache${platformOs}_Template"

        artifactRules = """%teamcity.build.checkoutDir%/.julia => cache.zip"""
        publishArtifacts = PublishMode.SUCCESSFUL

        vcs {
            root(Ribasim, ". => ribasim")
            cleanCheckout = true
        }

        val depot_path = generateJuliaDepotPath(platformOs)
        params {
            param("env.JULIA_DEPOT_PATH", depot_path)
        }

        val header = generateTestBinariesHeader(platformOs)
        steps {
            script {
                name = "Set up pixi"
                id = "Set_up_pixi"
                workingDir = "ribasim"
                scriptContent =  header +
                """
                pixi --version
                pixi run install-ci
                pixi run initialize-julia-test
                """.trimIndent()
            }
        }
    }
}

object GenerateCacheWindows : GenerateCache("Windows")
object GenerateCacheLinux : GenerateCache("Linux")
