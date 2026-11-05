"""Download the original figures from the GitHub issues / pull requests into source_images/.

Run once; the images are reused by 09_original_pr_figures.py.
"""

import ssl
import urllib.request

from common import SOURCE_IMAGES

IMAGES = {
    # PR #3324: QGIS view of Wflow river cells mapped to Ribasim Basin / FlowBoundary nodes
    "pr3324_qgis_mapping.png": "https://github.com/user-attachments/assets/526c3415-edff-4820-994b-0eb3a88b49a2",
    # PR #3333: test schematization with irrigation cells and UserDemand nodes
    "pr3333_schematization.png": "https://github.com/user-attachments/assets/beeb518d-dd40-4137-92b0-2c6de3295200",
    # PR #3333: demand, allocated and realized irrigation per UserDemand
    "pr3333_userdemand_results.png": "https://github.com/user-attachments/assets/3cf52b13-4401-41e0-9031-f4d1d3853264",
}

SOURCE_IMAGES.mkdir(exist_ok=True)
context = ssl.create_default_context()
for name, url in IMAGES.items():
    path = SOURCE_IMAGES / name
    if path.exists():
        print(f"exists   {path}")
        continue
    with urllib.request.urlopen(url, context=context) as response:
        path.write_bytes(response.read())
    print(f"saved    {path}")
