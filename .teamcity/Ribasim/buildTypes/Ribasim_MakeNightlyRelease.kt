package Ribasim.buildTypes

import Ribasim_Linux.Linux_BuildRibasim
import Ribasim_Linux.Linux_TestRibasimBinaries
import Ribasim_Windows.Windows_BuildRibasim
import Ribasim_Windows.Windows_TestRibasimBinaries
import Templates.LinuxAgent
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.provideAwsCredentials
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.vcs

object Ribasim_MakeNightlyRelease : BuildType({
    templates(LinuxAgent)
    name = "Make Nightly Release"

    params {
        param("env.GITHUB_TOKEN", "%github_deltares-service-account_access_token%")
        param("env.AWS_ENDPOINT_URL", "https://s3.deltares.nl")
    }

    features {
        provideAwsCredentials {
            awsConnectionId = "AmazonWebServicesAws"
        }
    }

    vcs {
        root(Ribasim.vcsRoots.Ribasim)
        cleanCheckout = true
    }

    steps {
        script {
            name = "Push release to AWS"
            id = "RibaPushReleaseAWS"
            scriptContent = """
                set -euxo pipefail
                . /usr/share/Modules/init/bash
                module load aws

                aws s3 cp ribasim_windows.zip s3://ribasim/teamcity/Ribasim_Ribasim/BuildRibasimCliWindows/latest/ribasim_windows.zip
                aws s3 cp ribasim_linux.zip s3://ribasim/teamcity/Ribasim_Ribasim/BuildRibasimCliWindows/latest/ribasim_linux.zip
                aws s3 cp ribasim_qgis.zip s3://ribasim/teamcity/Ribasim_Ribasim/BuildRibasimCliWindows/latest/ribasim_qgis.zip
                aws s3 cp generated_testmodels.zip s3://ribasim/teamcity/Ribasim_Ribasim/BuildRibasimCliWindows/latest/generated_testmodels.zip
            """.trimIndent()
        }
    }

    triggers {
        vcs {
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
        dependency(Linux_BuildRibasim) {
            snapshot {
                onDependencyFailure = FailureAction.FAIL_TO_START
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_684"
                artifactRules = "ribasim_linux.zip"
            }
        }
        snapshot(Linux_TestRibasimBinaries) {
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
        dependency(AbsoluteId("SigningAndCertificates_Ribasim_SigningRibasimRelease")) {
            snapshot {
                onDependencyFailure = FailureAction.FAIL_TO_START
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_157"
                artifactRules = "ribasim_windows.zip"
            }
        }
        snapshot(Windows_TestRibasimBinaries) {
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
