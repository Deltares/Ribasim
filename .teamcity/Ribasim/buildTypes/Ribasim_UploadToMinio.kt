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

object Ribasim_UploadToMinio : BuildType({
    templates(LinuxAgent)
    name = "Upload binaries to Minio"

    params {
        param("env.GITHUB_TOKEN", "%github_deltares-service-account_access_token%")
        param("env.AWS_ENDPOINT_URL", "https://s3.deltares.nl")
        param("env.AWS_ACCESS_KEY_ID", "KwKRzscudy3GvRB8BN1Z")
        param("env.AWS_REGION", "eu-west-1")
        password("env.AWS_SECRET_ACCESS_KEY", "credentialsJSON:86cbf3e5-724c-437d-9962-7a3f429b0aa2")
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

                # Disable the multipart upload, as it fails with MinIO
                aws configure set default.s3.multipart_threshold 1024MB

                aws --debug s3 cp --no-progress ribasim_windows.zip s3://ribasim/Ribasim/Ribasim_UploadToMinio/latest/ribasim_windows.zip
                aws --debug s3 cp --no-progress ribasim_linux.zip s3://ribasim/Ribasim/Ribasim_UploadToMinio/latest/ribasim_linux.zip
                aws --debug s3 cp --no-progress ribasim_qgis.zip s3://ribasim/Ribasim/Ribasim_UploadToMinio/latest/ribasim_qgis.zip
                aws --debug s3 cp --no-progress generated_testmodels.zip s3://ribasim/Ribasim/Ribasim_UploadToMinio/latest/generated_testmodels.zip
            """.trimIndent()
        }
    }

    triggers {
        vcs {
            id = "riba_main_minio_trigger"
            branchFilter = """
                +:<default>
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

})
