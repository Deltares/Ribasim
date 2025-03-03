package Ribasim_Linux

import Ribasim.vcsRoots.Ribasim
import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.FailureAction
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.vcs

object RibasimLinuxProject : Project({
    id("Ribasim_Linux")
    name = "Ribasim_Linux"

    buildType(Linux_Main)
    buildType(Linux_BuildRibasim)
    buildType(Linux_TestRibasimBinaries)
    buildType(Linux_GenerateCache)

    template(TestBinariesLinux)
    template(GenerateCacheLinux)
})

object Linux_Main : BuildType({
    name = "RibasimMain"

    templates(GithubPullRequestsIntegration)

    allowExternalStatus = true
    type = Type.COMPOSITE

    vcs {
        root(Ribasim, ". => ribasim")
        cleanCheckout = true
    }

    triggers {
        vcs {
        }
    }

    dependencies {
        snapshot(Linux_TestRibasimBinaries) {
            onDependencyFailure = FailureAction.FAIL_TO_START
        }
    }
})

object Linux_BuildRibasim : BuildType({
    templates(
        LinuxAgent,
        GithubCommitStatusIntegration,
        BuildLinux
    )

    name = "Build Ribasim"

    artifactRules = """ribasim\build\ribasim => ribasim_linux.zip!/ribasim"""
})

object Linux_TestRibasimBinaries : BuildType({
    templates(LinuxAgent, GithubCommitStatusIntegration, TestBinariesLinux)
    name = "Test Ribasim Binaries"

    dependencies {
        dependency(Linux_BuildRibasim) {
            snapshot {
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_570"
                cleanDestination = true
                artifactRules = """
                    ribasim_linux.zip!/ribasim/** => ribasim/build/ribasim
                """.trimIndent()
            }
        }
    }
})

object Linux_GenerateCache : BuildType({
    templates(LinuxAgent, GithubCommitStatusIntegration, GenerateCacheLinux)
    name = "Generate TC cache"

    triggers {
        vcs {
            id = "TRIGGER_RIBA_L1"
            triggerRules = """
                +:Manifest.toml
                +:Project.toml
                +:pixi.lock
                +:pixi.toml
            """.trimIndent()
        }
    }
})
