import subprocess

# Get the name of the currently checked out tag
tag_name = subprocess.check_output(
    ["git", "describe", "--tags", "--exact-match"], text=True
).strip()


print(f"Currently checked out tag: {tag_name}")

# Create a release using gh
subprocess.check_call(
    [
        "gh",
        "release",
        "create",
        tag_name,
        "--generate-notes",
        "ribasim_cli_linux.zip",
        "ribasim_cli_windows.zip",
        "ribasim_qgis.zip",
        "generated_testmodels.zip",
    ]
)
