package Templates

import jetbrains.buildServer.configs.kotlin.*

object WindowsAgent : Template({
    id("Ribasim_Windows")
    name = "Ribasim_Windows"
    description = "Template for agent that uses Windows OS"

    requirements {
        contains("teamcity.agent.jvm.os.name", "Windows", "RQ_422")
    }
})
