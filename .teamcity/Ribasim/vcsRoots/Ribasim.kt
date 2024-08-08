package Ribasim.vcsRoots

import jetbrains.buildServer.configs.kotlin.vcs.GitVcsRoot

object Ribasim : GitVcsRoot({
    name = "Ribasim"
    url = "https://github.com/Deltares/Ribasim"
    branch = "bench-large-model"
    branchSpec = "+:refs/heads/*"
    useTagsAsBranches = true
    authMethod = password {
        userName = "teamcity-deltares"
        password = "credentialsJSON:abf605ce-e382-4b10-b5de-8a7640dc58d9"
    }
})
//object Ribasim : GitVcsRoot({
//    name = "Ribasim"
//    url = "https://github.com/Deltares/Ribasim"
//    branch = "main"
//    branchSpec = """
//        +:refs/heads/main
//        +:refs/tags/*
//        +:refs/heads/gh-readonly-queue/*
//    """.trimIndent()
//    useTagsAsBranches = true
//    authMethod = password {
//        userName = "teamcity-deltares"
//        password = "credentialsJSON:abf605ce-e382-4b10-b5de-8a7640dc58d9"
//    }
//})
