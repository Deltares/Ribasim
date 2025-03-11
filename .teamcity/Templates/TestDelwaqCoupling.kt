package Templates

import Ribasim.vcsRoots.Ribasim
import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.buildFeatures.buildCache

open class TestDelwaqCoupling(platformOs: String) : Template() {
    init {
        name = "TestDelwaqCoupling${platformOs}_Template"

        vcs {
            root(Ribasim, ". => ribasim")
            cleanCheckout = true
        }

        val depot_path = generateJuliaDepotPath(platformOs)
        params {
            password("MiniO_credential_token", "credentialsJSON:86cbf3e5-724c-437d-9962-7a3f429b0aa2")
            param("env.JULIA_DEPOT_PATH", depot_path)
        }

        features {
            buildCache {
                id = "Ribasim${platformOs}Cache"
                name = "Ribasim ${platformOs} Cache"
                publish = false
            }
        }

        steps {
            script {
                name = "Set up pixi"
                id = "Set_up_pixi"
                workingDir = "ribasim"
                scriptContent = """
                pixi --version
                pixi run install-ci
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
            script {
                name = "Upload delwaq model"
                id = "Delwaq_upload"
                workingDir = "ribasim"
                scriptContent = """
                pixi run python utils/upload_benchmark.py --secretkey %MiniO_credential_token% "python/ribasim/ribasim/delwaq/model/delwaq_map.nc" "doc-image/delwaq/delwaq_map.nc"
                """.trimIndent()
            }
        }
    }
}

object TestDelwaqCouplingWindows : TestDelwaqCoupling("Windows")
