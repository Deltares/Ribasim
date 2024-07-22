package Ribasim

import Ribasim.buildTypes.*
import Ribasim.vcsRoots.*
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.projectFeatures.activeStorage
import jetbrains.buildServer.configs.kotlin.projectFeatures.awsConnection
import jetbrains.buildServer.configs.kotlin.projectFeatures.githubIssues
import jetbrains.buildServer.configs.kotlin.projectFeatures.s3Storage

object Project : Project({

    vcsRoot(Ribasim)

    buildType(GenerateTestmodels)
    buildType(Ribasim_MakeQgisPlugin)
    buildType(Ribasim_MakeGitHubRelease)

    template(GitHubIntegrationTemplate)
    template(Linux_1)
    template(Windows_1)

    features {
        awsConnection {
            id = "AmazonWebServicesAws"
            name = "Amazon Web Services (AWS)"
            regionName = "eu-west-3"
            credentialsType = static {
                accessKeyId = "AKIAQBIN2MPWXSD2IZ5F"
                secretAccessKey = "credentialsJSON:dba90026-9856-4f87-94d9-bab91f3f2d5c"
                useSessionCredentials = false
                stsEndpoint = "https://sts.eu-west-3.amazonaws.com"
            }
        }
        activeStorage {
            id = "PROJECT_EXT_106"
            activeStorageID = "s3_ribasim"
        }
        githubIssues {
            id = "PROJECT_EXT_107"
            displayName = "Ribasim GitHub Issues"
            repositoryURL = "https://github.com/Deltares/Ribasim"
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

    subProject(Ribasim_Linux.Project)
    subProject(Ribasim_Windows.Project)
    subProject(Build.Project)
})
