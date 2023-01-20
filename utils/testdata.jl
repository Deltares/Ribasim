using Downloads
# ensure test data is present
datadir = normpath(@__DIR__, "..", "data")

"Download a test data file if it does not already exist"
function testdata(source_filename, target_filename = source_filename)
    target_path = joinpath(datadir, target_filename)
    parent_path = dirname(target_path)
    isdir(parent_path) || mkpath(parent_path)
    # TODO update artifact
    base_url = "https://github.com/visr/ribasim-artifacts/releases/download/v0.1.0/"
    url = string(base_url, source_filename)
    isfile(target_path) || Downloads.download(url, target_path)
    return target_path
end
