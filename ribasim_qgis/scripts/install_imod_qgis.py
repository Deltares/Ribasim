import io
import zipfile

import requests
from enable_plugin import enable_plugin

download_url = requests.get(
    "https://api.github.com/repos/Deltares/imod-qgis/releases/latest"
).json()["assets"][0]["browser_download_url"]

package = requests.get(download_url)
z = zipfile.ZipFile(io.BytesIO(package.content))
z.extractall(".pixi/env/Library/python/plugins")

enable_plugin("imodqgis")
