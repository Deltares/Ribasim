import argparse
from pathlib import Path

from ribasim import Model

parser = argparse.ArgumentParser(description="Migrate Ribasim model.")
parser.add_argument("input_toml", help="Path to input TOML file")
parser.add_argument(
    "output_toml",
    nargs="?",
    help="Path to output TOML file (defaults to input_toml if not provided)",
)
args = parser.parse_args()

input_path = Path(args.input_toml)
# If no output path is provided, use the input path (in-place modification)
output_path = Path(args.output_toml) if args.output_toml else input_path

model = Model.read(input_path)
model.write(output_path)
