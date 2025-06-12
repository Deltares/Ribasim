import argparse

from ribasim import Model

parser = argparse.ArgumentParser(description="Migrate Ribasim model.")
parser.add_argument("input_toml", help="Path to input TOML file")
parser.add_argument("output_toml", help="Path to output TOML file")
args = parser.parse_args()

model = Model.read(args.input_toml)
model.write(args.output_toml)
