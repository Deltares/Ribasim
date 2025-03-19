package Ribasim

import Ribasim.buildTypes.GenerateTestmodels
import Ribasim.buildTypes.Ribasim_MakeGitHubRelease
import Ribasim.buildTypes.Ribasim_UploadToMinio
import Ribasim.buildTypes.Ribasim_MakeQgisPlugin
import Ribasim.vcsRoots.Ribasim
import Ribasim_Linux.RibasimLinuxProject
import Ribasim_Windows.RibasimWindowsProject
import Templates.*
import Testbench.Testbench
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.projectFeatures.*

object Project : Project({

    vcsRoot(Ribasim)

    buildType(GenerateTestmodels)
    buildType(Ribasim_MakeQgisPlugin)
    buildType(Ribasim_MakeGitHubRelease)
    buildType(Ribasim_UploadToMinio)

    template(GithubCommitStatusIntegration)
    template(GithubPullRequestsIntegration)
    template(WindowsAgent)
    template(BuildWindows)
    template(LinuxAgent)
    template(BuildLinux)

    features {
        awsConnection {
            id = "AmazonWebServicesAws"
            name = "Amazon Web Services (AWS)"
            regionName = "eu-west-3"
            credentialsType = static {
                accessKeyId = "KwKRzscudy3GvRB8BN1Z"
                secretAccessKey = "credentialsJSON:86cbf3e5-724c-437d-9962-7a3f429b0aa2"
                useSessionCredentials = false
                stsEndpoint = "https://s3-console.deltares.nl"
            }
        }
        githubIssues {
            id = "PROJECT_EXT_107"
            displayName = "Ribasim GitHub Issues"
            repositoryURL = "https://github.com/Deltares/Ribasim"
        }
        s3CompatibleStorage {
            id = "PROJECT_EXT_171"
            accessKeyID = "KwKRzscudy3GvRB8BN1Z"
            accessKey = "credentialsJSON:86cbf3e5-724c-437d-9962-7a3f429b0aa2"
            endpoint = "https://s3.deltares.nl"
            bucketName = "ribasim"
        }
        activeStorage {
            id = "PROJECT_EXT_172"
            activeStorageID = "PROJECT_EXT_171"
        }
        s3Storage {
            id = "s3_ribasim"
            storageName = "s3"
            bucketName = "ribasim"
            bucketPrefix = "teamcity"
            awsEnvironment = default {
                awsRegionName = "eu-west-3"
            }
            credentials = accessKeys()
            accessKeyID = "AKIAQBIN2MPWXSD2IZ5F"
            accessKey = "credentialsJSON:dba90026-9856-4f87-94d9-bab91f3f2d5c"
        }
    }

    subProject(RibasimLinuxProject)
    subProject(RibasimWindowsProject)
    subProject(Testbench)
})
