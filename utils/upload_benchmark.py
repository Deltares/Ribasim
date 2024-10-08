import argparse
import os
from pathlib import Path

from minio import Minio
from minio.error import S3Error

minioServer = "s3.deltares.nl"
bucketName = "ribasim"

parser = argparse.ArgumentParser(description="Upload a file to the MinIO server")
parser.add_argument("source", type=Path, help="The source file to upload")
parser.add_argument("destination", help="The destination file in the MinIO server")
parser.add_argument(
    "--accesskey",
    help="The secret key to access the MinIO server",
    default=os.environ.get("MINIO_ACCESS_KEY", "KwKRzscudy3GvRB8BN1Z"),
)
parser.add_argument(
    "--secretkey",
    help="The secret key to access the MinIO server",
    default=os.environ.get("MINIO_SECRET_KEY"),
)
args = parser.parse_args()

if not args.source.is_file():
    raise ValueError("The source file does not exist")

# Minio client connection
client = Minio(minioServer, access_key=args.accesskey, secret_key=args.secretkey)

try:
    client.fput_object(
        bucketName,
        args.destination,
        args.source,
    )
except S3Error as e:
    print(f"Error occurred: {e}")
