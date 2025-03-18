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
    buildType(Windows_GenerateCache)

    template(TestBinariesWindows)
    template(TestDelwaqCouplingWindows)
    template(GenerateCacheWindows)
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
            id = "TRIGGER_RIBA_SKIPW1"
            branchFilter = """
                +:<default>
                +:refs/pull/*
            """.trimIndent()
            triggerRules = "-:comment=^[skip ci]:**"
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

    templates(GithubPullRequestsIntegration)

    vcs {
        root(RibasimVcs, ". => ribasim")
        cleanCheckout = true
    }

    artifactRules = "ribasim/python/ribasim/ribasim/delwaq/model"

    triggers {
        vcs {
            id = "TRIGGER_304"
            branchFilter = """
                +:<default>
                +:refs/pull/*
            """.trimIndent()
            triggerRules = """
                +:ribasim/coupling/delwaq/**
                +:ribasim/core/**
                +:ribasim/python/**
                +:ribasim/ribasim_testmodels/**
                -:comment=^[skip ci]:**
            """.trimIndent()
        }
    }

    dependencies {
        artifacts(AbsoluteId("DWaqDPart_Windows_Build")) {
            id = "ARTIFACT_DEPENDENCY_4206"
            buildRule = lastSuccessful()
            artifactRules = """
                DWAQ_win64_Release_Visual Studio 16 2019_ifx_*.zip!** => dimr
            """.trimIndent()
        }
    }
})

object Windows_GenerateCache : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, GenerateCacheWindows)
    name = "Generate TC cache"

    triggers {
        vcs {
            id = "TRIGGER_RIBA_W1"
            triggerRules = """
                +:Manifest.toml
                +:Project.toml
                +:pixi.lock
                +:pixi.toml
            """.trimIndent()
            branchFilter = "+:<default>"
        }
    }
})
