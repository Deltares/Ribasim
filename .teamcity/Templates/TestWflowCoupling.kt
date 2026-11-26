package Templates

import Ribasim.vcsRoots.Ribasim
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildSteps.powerShell
import jetbrains.buildServer.configs.kotlin.buildSteps.script

// Only on Windows, since the Wflow forcing comes from the Deltares P: drive, which these agents can map.
object TestWflowCouplingWindows : Template({
    name = "TestWflowCouplingWindows_Template"

    vcs {
        root(Ribasim, ". => ribasim")
        cleanCheckout = true
    }

    params {
        param("env.JULIA_DEPOT_PATH", generateJuliaDepotPath("Windows"))
        // GitHub token with read access to Deltares-research/hydromt_ribasim
        password("env.HYDROMT_RIBASIM_TOKEN", "credentialsJSON:aca31dba-434e-4a69-b4bc-1e97bce6ebb2")
    }

    dependencies {
        artifacts(AbsoluteId("Ribasim_Windows_GenerateCache")) {
            id = "ARTIFACT_DEPENDENCY_WFLOW_COUPLING_CACHE"
            buildRule = lastSuccessful()
            artifactRules = "cache.zip!** => %teamcity.build.checkoutDir%/.julia"
        }
    }

    steps {
        powerShell {
            name = "Connect to P drive"
            id = "Map_P_drive"
            scriptMode = script {
                content = """
                    if (-not (Test-Path 'P:\')) {
                        net use P: \\directory.intra\PROJECT /persistent:no
                        exit ${'$'}LASTEXITCODE
                    }
                """.trimIndent()
            }
        }
        powerShell {
            name = "Install the pixi environment"
            id = "Install_pixi_environment"
            workingDir = "ribasim"
            scriptMode = script {
                content = """
                    # hydromt_ribasim is an internal repository, so pixi needs a token to fetch it.
                    if (-not ${'$'}env:HYDROMT_RIBASIM_TOKEN) {
                        throw "HYDROMT_RIBASIM_TOKEN is not set, it needs to be a GitHub token with read access to Deltares-research/hydromt_ribasim."
                    }
                    # Git reads this configuration from the environment, so the token is not stored on the agent.
                    ${'$'}env:GIT_CONFIG_COUNT = "1"
                    ${'$'}env:GIT_CONFIG_KEY_0 = "url.https://x-access-token:" + ${'$'}env:HYDROMT_RIBASIM_TOKEN + "@github.com/Deltares-research/hydromt_ribasim.insteadOf"
                    ${'$'}env:GIT_CONFIG_VALUE_0 = "https://github.com/Deltares-research/hydromt_ribasim"
                    pixi --version
                    pixi install --locked --environment wflow-coupled
                    exit ${'$'}LASTEXITCODE
                """.trimIndent()
            }
        }
        script {
            name = "Build Wflow and Ribasim models and the mapping between them"
            id = "Build_models"
            workingDir = "ribasim"
            scriptContent = "pixi run --environment wflow-coupled wflow-coupled-prepare"
        }
        script {
            name = "Run online coupling"
            id = "Run_online_coupling"
            workingDir = "ribasim"
            scriptContent = "pixi run --environment wflow-coupled wflow-coupled-run"
        }
        script {
            name = "Test the coupling"
            id = "Test_coupling"
            workingDir = "ribasim"
            scriptContent = "pixi run --environment wflow-coupled wflow-coupled-test"
        }
    }

    failureConditions {
        executionTimeoutMin = 90
    }
})
