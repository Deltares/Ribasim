using PkgToSoftwareBOM
using UUIDs
using Pkg

Pkg.activate("core")

ribasimLicense = SpdxLicenseExpressionV2("MIT")
organization = SpdxCreatorV2("Organization", "Deltares", "software@deltares.nl")
packageInstructions = spdxPackageInstructions(;
    spdxfile_toexclude = ["Ribasim.spdx.json"],
    originator = organization,
    declaredLicense = ribasimLicense,
    copyright = "Copyright (c) 2025 Deltares <software@deltares.nl>",
    name = "Ribasim",
)

dependencies = Pkg.project().dependencies;
spdxData = spdxCreationData(;
    Name = "Ribasim.jl",
    Creators = [organization],
    NamespaceURL = "https://github.com/Deltares/Ribasim/Ribasim.spdx.json",
    rootpackages = dependencies,
    find_artifactsource = true,
    packageInstructions = Dict{UUID, spdxPackageInstructions}(
        Pkg.project().uuid => packageInstructions,
    ),
)

sbom = generateSPDX(spdxData)
writespdx(sbom, "Ribasim.spdx.json")
