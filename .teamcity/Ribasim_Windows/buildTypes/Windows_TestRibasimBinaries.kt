package Ribasim_Windows.buildTypes

import Templates.GithubCommitStatusIntegration
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.buildFeatures.XmlReport
import jetbrains.buildServer.configs.kotlin.buildFeatures.xmlReport
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.schedule
import Ribasim.vcsRoots.Ribasim as RibasimVcs

object Windows_TestRibasimBinaries : BuildType({
    templates(Ribasim.buildTypes.Windows_1, GithubCommitStatusIntegration)
    name = "Test Ribasim Binaries"

    artifactRules = """
        ribasim\python\ribasim_api\tests\temp => test_output_api.zip
        ribasim\build\tests\temp => test_output_cli.zip
    """.trimIndent()

    vcs {
        root(RibasimVcs, ". => ribasim")
    }

    steps {
        script {
            name = "Set up pixi"
            id = "RUNNER_1501"
            workingDir = "ribasim"
            scriptContent = "pixi --version"
        }
        script {
            name = "Run tests"
            id = "RUNNER_1503"
            workingDir = "ribasim"
            scriptContent = """
                pixi run install-ci
                pixi run test-ribasim-api
                pixi run test-ribasim-cli
            """.trimIndent()
        }
    }

    triggers {
        schedule {
            id = "TRIGGER_631"
            schedulingPolicy = daily {
                hour = 3
            }
            branchFilter = "+:<default>"
            triggerBuild = always()
        }
    }

    features {
        xmlReport {
            id = "BUILD_EXT_145"
            reportType = XmlReport.XmlReportType.JUNIT
            rules = "ribasim/report.xml"
            verbose = true
        }
    }

    dependencies {
        dependency(Windows_BuildRibasim) {
            snapshot {
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_570"
                cleanDestination = true
                artifactRules = """
                    ribasim_windows.zip!** => ribasim/build/ribasim
                """.trimIndent()
            }
        }
    }

    requirements {
        equals("env.OS", "Windows_NT", "RQ_315")
    }
})
