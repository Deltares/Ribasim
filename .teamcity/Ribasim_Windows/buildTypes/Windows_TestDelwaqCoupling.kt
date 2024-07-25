package Ribasim_Windows.buildTypes

import Templates.GithubCommitStatusIntegration
import Templates.WindowsAgent
import Ribasim.vcsRoots.Ribasim as RibasimVcs
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.vcs

object Windows_TestDelwaqCoupling : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration)
    name = "Test Delwaq coupling"

    artifactRules = "ribasim/coupling/delwaq/model"

    vcs {
        root(RibasimVcs, ". => ribasim")
        cleanCheckout = true
    }

    steps {
        script {
            name = "Set up pixi"
            id = "Set_up_pixi"
            workingDir = "ribasim"
            scriptContent = "pixi --version"
        }
        script {
            name = "Run Delwaq"
            id = "Run_Delwaq"
            workingDir = "ribasim"
            scriptContent = """
                pixi install
                pixi run ribasim-core-testmodels basic
                set D3D_HOME=%teamcity.build.checkoutDir%/dimr
                pixi run delwaq
            """.trimIndent()
        }
    }

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
            buildRule = lastPinned()
            artifactRules = "dimrset_x64_signed_*.zip!/x64 => dimr"
        }
    }
})
