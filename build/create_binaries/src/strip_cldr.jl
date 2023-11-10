"""
The cldr artifact has such long paths that it errors on Windows unless long paths are enabled.
Also the artifact has many files and is over 300 MB, while we only need a single small file.
This modifies the artifact to remove everything except the file we need.
Since the artifact is only used on Windows, only strip do it there.
This needs exactly TimeZones 1.13.0, which is fixed in the Project.toml.
https://github.com/JuliaTime/TimeZones.jl/issues/373
"""
function strip_cldr()
    if Sys.iswindows()
        # Get the artifact directory and the file path we need to keep
        hash = Base.SHA1("40b35727ea0aff9a9f28b7454004b68849caf67b")
        @assert artifact_exists(hash)
        artifact_dir = artifact_path(hash)
        keep_file =
            normpath(artifact_dir, "cldr-release-43-1/common/supplemental/windowsZones.xml")
        @assert isfile(keep_file)

        # Read the file into memory, empty the artifact dir, and write the file back
        keep_file_content = read(keep_file)
        rm(artifact_dir; recursive = true)
        mkpath(dirname(keep_file))
        write(keep_file, keep_file_content)
    end
end
