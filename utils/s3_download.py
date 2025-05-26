import argparse
import os

from minio import Minio
from minio.error import S3Error

minioServer = "s3.deltares.nl"
bucketName = "ribasim"

parser = argparse.ArgumentParser(
    description="Download a folder (recursively) from the MinIO server"
)
parser.add_argument("remote", help="The path to download in the MinIO server")
parser.add_argument("local", help="The path to the local file system")
parser.add_argument(
    "--accesskey",
    help="The access key to access the MinIO server",
    default=os.environ.get("MINIO_ACCESS_KEY", "KwKRzscudy3GvRB8BN1Z"),
)
parser.add_argument(
    "--secretkey",
    help="The secret key to access the MinIO server",
    default=os.environ.get("MINIO_SECRET_KEY"),
)
args = parser.parse_args()


client = Minio(minioServer, access_key=args.accesskey, secret_key=args.secretkey)
objects = client.list_objects(bucketName, prefix=args.remote, recursive=True)

for obj in objects:
    try:
        client.fget_object(
            bucketName,
            obj.object_name,
            f"models/{args.local}" + obj.object_name.removeprefix(args.remote),
        )
    except S3Error as e:
        print(f"Error occurred: {e}")
