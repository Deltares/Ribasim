import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.provideAwsCredentials
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.projectFeatures.activeStorage
import jetbrains.buildServer.configs.kotlin.projectFeatures.githubIssues
import jetbrains.buildServer.configs.kotlin.projectFeatures.s3Storage
import jetbrains.buildServer.configs.kotlin.triggers.finishBuildTrigger
import jetbrains.buildServer.configs.kotlin.triggers.vcs

/*
The settings script is an entry point for defining a TeamCity
project hierarchy. The script should contain a single call to the
project() function with a Project instance or an init function as
an argument.

VcsRoots, BuildTypes, Templates, and subprojects can be
registered inside the project using the vcsRoot(), buildType(),
template(), and subProject() methods respectively.

To debug settings scripts in command-line, run the

    mvnDebug org.jetbrains.teamcity:teamcity-configs-maven-plugin:generate

command and attach your debugger to the port 8000.

To debug in IntelliJ Idea, open the 'Maven Projects' tool window (View
-> Tool Windows -> Maven Projects), find the generate task node
(Plugins -> teamcity-configs -> teamcity-configs:generate), the
'Debug' option is available in the context menu for the task.
*/

version = "2023.11"

project {

    buildType(Ribasim_PushSuccessfulNightlyBuildToS3)
    buildType(Ribasim_BuildPythonWheels)
    buildType(Ribasim_MakeQgisPlugin)
    buildType(Ribasim_MakeGitHubRelease)

    features {
        activeStorage {
            id = "PROJECT_EXT_106"
            activeStorageID = "s3_ribasim"
        }
        githubIssues {
            id = "PROJECT_EXT_107"
            displayName = "Ribasim Github Issues"
            repositoryURL = "https://github.com/Deltares/Ribasim.jl"
        }
        s3Storage {
            id = "s3_ribasim"
            awsEnvironment = default {
                awsRegionName = "eu-west-3"
            }
            credentials = accessKeys()
            accessKeyID = "AKIAQBIN2MPWXSD2IZ5F"
            accessKey = "credentialsJSON:dba90026-9856-4f87-94d9-bab91f3f2d5c"
            storageName = "s3"
            bucketName = "ribasim"
            bucketPrefix = "teamcity"
        }
    }
}

object Ribasim_BuildPythonWheels : BuildType({
    name = "Build Python Wheels"

    artifactRules = "ribasim-*.whl"
    publishArtifacts = PublishMode.SUCCESSFUL

    params {
        param("conda_env_path", "%system.teamcity.build.checkoutDir%/pyEnv")
        param("conda_mm_path", "%system.teamcity.build.checkoutDir%/mmEnv")
    }

    vcs {
        root(DslContext.settingsRoot)
    }

    steps {
        script {
            name = "Build wheel"
            scriptContent = """
                #!/usr/bin/env bash
                set -euxo pipefail
                . /usr/share/Modules/init/bash
                ls /opt/apps/modules/anaconda3
                module load anaconda3/miniconda
                rm --force ribasim-*.whl
                pip wheel python/ribasim --no-deps
            """.trimIndent()
        }
    }

    triggers {
        vcs {
            branchFilter = """
                +:<default>
                +:v*
            """.trimIndent()
        }
    }

    requirements {
        doesNotEqual("env.OS", "Windows_NT")
    }
})

object Ribasim_MakeGitHubRelease : BuildType({
    name = "Make GitHub Release"

    params {
        param("env.GITHUB_TOKEN", "%github_teamcity-deltares_public_access_token%")
    }

    vcs {
        root(DslContext.settingsRoot)
    }

    steps {
        script {
            name = "Push release to GitHub"
            scriptContent = """
                #!/usr/bin/env bash
                set -euxo pipefail
                . /usr/share/Modules/init/bash
                
                module load github
                # Get the name of the currently checked out tag
                tag_name=${'$'}(git describe --tags --exact-match 2>/dev/null)
                
                # Check if a tag is checked out
                if [ -n "${'$'}tag_name" ]; then
                    echo "Currently checked out tag: ${'$'}tag_name"
                
                    # Create a release using gh
                    gh release create "${'$'}tag_name" \
                        --generate-notes \
                        ribasim_cli_linux.zip \
                        ribasim_cli_windows.zip \
                        ribasim_qgis.zip
                
                    echo "Release created successfully."
                
                else
                    echo "No tag is currently checked out."
                fi
            """.trimIndent()
        }
    }

    triggers {
        vcs {
            branchFilter = "+:v20*"
        }
    }

    features {
        provideAwsCredentials {
            awsConnectionId = "AmazonWebServicesAws"
        }
    }

    dependencies {
        dependency(RelativeId("Linux_BuildRibasimCli")) {
            snapshot {
            }

            artifacts {
                artifactRules = "ribasim_cli.zip => ribasim_cli_linux.zip"
            }
        }
        dependency(Ribasim_MakeQgisPlugin) {
            snapshot {
                onDependencyFailure = FailureAction.FAIL_TO_START
            }

            artifacts {
                artifactRules = "ribasim_qgis.zip"
            }
        }
        dependency(RelativeId("Windows_BuildRibasimCli")) {
            snapshot {
                onDependencyFailure = FailureAction.FAIL_TO_START
            }

            artifacts {
                artifactRules = "ribasim_cli.zip => ribasim_cli_windows.zip"
            }
        }
    }

    requirements {
        equals("teamcity.agent.jvm.os.name", "Linux")
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

object Ribasim_MakeQgisPlugin : BuildType({
    name = "Make QGIS plugin"

    artifactRules = "ribasim_qgis.zip"

    vcs {
        root(DslContext.settingsRoot)
    }

    steps {
        script {
            scriptContent = """
                rsync --verbose --recursive --delete ribasim_qgis/ ribasim_qgis
                rm --force ribasim_qgis.zip
                zip -r ribasim_qgis.zip ribasim_qgis
            """.trimIndent()
        }
    }

    triggers {
        finishBuildTrigger {
            buildType = "Ribasim_Windows_BuildRibasimCli"
            successfulOnly = true
            branchFilter = """
                +:<default>
                +:v*
            """.trimIndent()
        }
    }

    dependencies {
        snapshot(RelativeId("Windows_BuildRibasimCli")) {
            onDependencyFailure = FailureAction.CANCEL
            onDependencyCancel = FailureAction.CANCEL
        }
    }

    requirements {
        doesNotEqual("env.OS", "Windows_NT")
    }
})

object Ribasim_PushSuccessfulNightlyBuildToS3 : BuildType({
    name = "Push successful nightly build to S3"

    steps {
        script {
            name = "Push to nightly S3"
            scriptContent = """
                #!/usr/bin/env bash
                set -euxo pipefail
                . /usr/share/Modules/init/bash
                module load aws
                aws s3 cp ribasim_cli.zip s3://ribasim/teamcity/Ribasim_Ribasim/BuildRibasimCliWindows/latest/ribasim_cli.zip
                aws s3 cp ribasim_qgis.zip s3://ribasim/teamcity/Ribasim_Ribasim/BuildRibasimCliWindows/latest/ribasim_qgis.zip
                aws s3 cp ribasim*.whl s3://ribasim/teamcity/Ribasim_Ribasim/BuildRibasimCliWindows/latest/
            """.trimIndent()
        }
    }

    triggers {
        finishBuildTrigger {
            buildType = "Ribasim_Windows_BuildRibasimCli"
            successfulOnly = true
        }
    }

    features {
        provideAwsCredentials {
            awsConnectionId = "AmazonWebServicesAws"
        }
    }

    dependencies {
        artifacts(Ribasim_BuildPythonWheels) {
            buildRule = lastSuccessful()
            artifactRules = "ribasim*.whl"
        }
        artifacts(Ribasim_MakeQgisPlugin) {
            buildRule = lastSuccessful()
            artifactRules = "ribasim_qgis.zip"
        }
        artifacts(RelativeId("Windows_BuildRibasimCli")) {
            buildRule = lastSuccessful()
            cleanDestination = true
            artifactRules = "ribasim_cli.zip"
        }
    }

    requirements {
        equals("teamcity.agent.jvm.os.name", "Linux")
    }
})
