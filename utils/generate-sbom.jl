using PkgToSoftwareBOM
using UUIDs
using Pkg

Pkg.activate("core")

myLicense = SpdxLicenseExpressionV2("MIT")
myOrg = SpdxCreatorV2("Organization", "Deltares", "software@deltares.nl")
myPackage_instr = spdxPackageInstructions(;
    spdxfile_toexclude = ["Ribasim.spdx.json"],
    originator = myOrg,  # Could be myOrg if appropriate
    declaredLicense = myLicense,
    copyright = "Copyright (c) 2025 Deltares <software@deltares.nl>",
    name = "Ribasim",
)

active_pkgs = Pkg.project().dependencies;
spdxData = spdxCreationData(;
    Name = "Ribasim.jl",
    Creators = [myOrg],
    NamespaceURL = "https://github.com/Deltares/Ribasim/Ribasim.spdx.json",
    rootpackages = active_pkgs,
    find_artifactsource = true,
    packageInstructions = Dict{UUID, spdxPackageInstructions}(
        Pkg.project().uuid => myPackage_instr,
    ),
)

sbom = generateSPDX(spdxData)
writespdx(sbom, "Ribasim.spdx.json")
