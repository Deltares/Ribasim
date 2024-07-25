package Ribasim.buildTypes

import Templates.LinuxAgent
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.vcs

object Ribasim_MakeGitHubRelease : BuildType({
    templates(LinuxAgent)
    name = "Make GitHub Release"

    params {
        param("env.GITHUB_TOKEN", "%github_deltares-service-account_access_token%")
    }

    vcs {
        root(Ribasim.vcsRoots.Ribasim)
        cleanCheckout = true
    }

    steps {
        script {
            name = "Push release to GitHub"
            id = "RUNNER_2523"
            scriptContent = """
                #!/usr/bin/env bash
                set -euxo pipefail
                . /usr/share/Modules/init/bash

                module load pixi
                pixi run github-release
            """.trimIndent()
        }
    }

    triggers {
        vcs {
            id = "TRIGGER_637"
            branchFilter = """
                +:v20*
                +:release*
            """.trimIndent()
        }
    }

    dependencies {
        dependency(GenerateTestmodels) {
            snapshot {
                onDependencyFailure = FailureAction.FAIL_TO_START
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_685"
                artifactRules = "generated_testmodels.zip"
            }
        }
        dependency(Ribasim_Linux.buildTypes.Linux_BuildRibasim) {
            snapshot {
                onDependencyFailure = FailureAction.FAIL_TO_START
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_684"
                artifactRules = "ribasim_linux.zip"
            }
        }
        snapshot(Ribasim_Linux.buildTypes.Linux_TestRibasimBinaries) {
            onDependencyFailure = FailureAction.FAIL_TO_START
        }
        dependency(Ribasim_MakeQgisPlugin) {
            snapshot {
                onDependencyFailure = FailureAction.FAIL_TO_START
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_603"
                artifactRules = "ribasim_qgis.zip"
            }
        }
        dependency(Ribasim_Windows.buildTypes.Windows_BuildRibasim) {
            snapshot {
                onDependencyFailure = FailureAction.FAIL_TO_START
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_157"
                artifactRules = "ribasim_windows.zip"
            }
        }
        snapshot(Ribasim_Windows.buildTypes.Windows_TestRibasimBinaries) {
            onDependencyFailure = FailureAction.FAIL_TO_START
        }
    }

    cleanup {
        keepRule {
            id = "KEEP_RULE_10"
            keepAtLeast = allBuilds()
            applyToBuilds {
                withStatus = successful()
            }
            dataToKeep = everything()
            applyPerEachBranch = true
            preserveArtifactsDependencies = true
        }
        baseRule {
            option("disableCleanupPolicies", true)
        }
    }
})
