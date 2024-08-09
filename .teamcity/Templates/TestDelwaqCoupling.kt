package Templates

import Ribasim.vcsRoots.Ribasim
import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildSteps.script

open class TestDelwaqCoupling(platformOs: String) : Template() {
    init {
        name = "TestDelwaqCoupling${platformOs}_Template"

        vcs {
            root(Ribasim, ". => ribasim")
            cleanCheckout = true
        }

        steps {
            script {
                name = "Set up pixi"
                id = "Set_up_pixi"
                workingDir = "ribasim"
                scriptContent = """
                pixi --version
                pixi run install
                """.trimIndent()
            }
            script {
                name = "Run Delwaq"
                id = "Run_Delwaq"
                workingDir = "ribasim"
                scriptContent = """
                pixi run ribasim-core-testmodels basic
                set D3D_HOME=%teamcity.build.checkoutDir%/dimr
                pixi run delwaq
                """.trimIndent()
            }
        }
    }
}

object TestDelwaqCouplingWindows : TestDelwaqCoupling("Windows")