package Ribasim_Windows

import Templates.*
import jetbrains.buildServer.configs.kotlin.AbsoluteId
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.FailureAction
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.vcs
import Ribasim.vcsRoots.Ribasim as RibasimVcs
import jetbrains.buildServer.configs.kotlin.buildSteps.script

object RibasimWindowsProject : Project({
    id("Ribasim_Windows")
    name = "Ribasim_Windows"

    buildType(Windows_Main)
    buildType(Windows_BuildRibasim)
    buildType(Windows_TestDelwaqCoupling)
    buildType(Windows_TestRibasimBinaries)

    template(TestBinariesWindows)
    template(TestDelwaqCouplingWindows)
})

object Windows_Main : BuildType({
    name = "RibasimMain"

    templates(GithubPullRequestsIntegration)

    allowExternalStatus = true
    type = Type.COMPOSITE

    vcs {
        root(RibasimVcs, ". => ribasim")
        cleanCheckout = true
    }

    triggers {
        vcs {
        }
    }

    dependencies {
        snapshot(Windows_TestRibasimBinaries) {
            onDependencyFailure = FailureAction.FAIL_TO_START
        }
        snapshot(Windows_TestDelwaqCoupling) {
            onDependencyFailure = FailureAction.FAIL_TO_START
        }
    }
})

object Windows_BuildRibasim : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, BuildWindows)
    name = "Build Ribasim"

    steps {
        script {
            name = "add Ribasim logo to .exe"
            id = "RUNNER_2417"
            workingDir = "ribasim"
            scriptContent = "pixi run add-ribasim-icon"
        }
    }
    artifactRules = """ribasim\build\ribasim => ribasim_windows.zip!/ribasim"""
})

object Windows_TestRibasimBinaries : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, TestBinariesWindows)
    name = "Test Ribasim Binaries"

    dependencies {
        dependency(Windows_BuildRibasim) {
            snapshot {
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_570"
                cleanDestination = true
                artifactRules = """
                    ribasim_windows.zip!/ribasim/** => ribasim/build/ribasim
                """.trimIndent()
            }
        }
    }
})

object Windows_TestDelwaqCoupling : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, TestDelwaqCouplingWindows)
    name = "Test Delwaq coupling"

    artifactRules = "ribasim/python/ribasim/ribasim/delwaq/model"

    triggers {
        vcs {
            id = "TRIGGER_304"
            triggerRules = """
                +:ribasim/coupling/delwaq/**
                +:ribasim/core/**
                +:ribasim/python/**
                +:ribasim/ribasim_testmodels/**
            """.trimIndent()
        }
    }

    dependencies {
        artifacts(AbsoluteId("Dimr_DimrCollectors_2bDimrCollectorReleaseSigned")) {
            id = "ARTIFACT_DEPENDENCY_4206"
            buildRule = tag("DIMRset_2.27.09")
            artifactRules = "dimrset_x64_signed_*.zip!/x64 => dimr"
        }
    }
})
