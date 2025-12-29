package Ribasim_Windows

import Templates.*
import jetbrains.buildServer.configs.kotlin.AbsoluteId
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.FailureAction
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.vcs
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.buildSteps.PowerShellStep
import jetbrains.buildServer.configs.kotlin.buildSteps.powerShell
import Ribasim.vcsRoots.Ribasim as RibasimVcs

object RibasimWindowsProject : Project({
    id("Ribasim_Windows")
    name = "Ribasim_Windows"

    buildType(Windows_Main)
    buildType(Windows_BuildRibasim)
    buildType(Windows_BuildMsix)
    buildType(Windows_TestDelwaqCoupling)
    buildType(Windows_TestRibasimBinaries)

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
                +:pull/*
            """.trimIndent()
            triggerRules = "-:comment=skip ci:**"
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

object Windows_BuildMsix : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration)
    name = "Build MSIX Package"

    // Disable this until signtool is updated so we can sign the MSIX
    paused = true

    vcs {
        root(RibasimVcs, ". => ribasim")
        cleanCheckout = true
    }

    steps {
        powerShell {
            name = "Create MSIX package"
            id = "RUNNER_MSIX"
            workingDir = "ribasim/build"
            scriptMode = script {
                    content = """
                try {
                    # Copy files needed for MSIX into the directory we will pack
                    Copy-Item AppxManifest.xml ribasim/
                    Copy-Item logo-150.png ribasim/
                    Copy-Item logo-44.png ribasim/

                    # Pack the ribasim directory to ribasim_windows.msix, overwriting existing msix files
                    makeappx pack /o /d ribasim /p ribasim_windows.msix
                } Catch {
                    ${'$'}ErrorMessage = ${'$'}_.Exception.Message
                    Write-Output ${'$'}ErrorMessage
                    exit(1)
                }
            """.trimIndent()
            }
        }
    }

    artifactRules = """ribasim\build\ribasim_windows.msix"""

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

object Windows_TestRibasimBinaries : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, TestBinariesWindows)
    name = "Test Ribasim Binaries"

    failureConditions {
        executionTimeoutMin = 30
    }

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
    templates(WindowsAgent, GithubCommitStatusIntegration, TestDelwaqCouplingWindows, GithubPullRequestsIntegration)
    name = "Test Delwaq coupling"

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
                +:pull/*
            """.trimIndent()
            triggerRules = """
                +:ribasim/coupling/delwaq/**
                +:ribasim/core/**
                +:ribasim/python/**
                +:ribasim/ribasim_testmodels/**
                -:comment=skip ci:**
            """.trimIndent()
        }
    }

    dependencies {
        artifacts(AbsoluteId("DWaqDPart_Windows_Build")) {
            id = "ARTIFACT_DEPENDENCY_4206"
            buildRule = lastSuccessful()
            artifactRules = """
                DWAQ_win64_Release_Visual Studio *.zip!** => dimr
            """.trimIndent()
        }
    }
})
