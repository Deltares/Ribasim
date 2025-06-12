import argparse
from os import makedirs

from minio import Minio
from minio.error import S3Error
from s3_settings import settings

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
    default=settings.minio_access_key,
)
parser.add_argument(
    "--secretkey",
    help="The secret key to access the MinIO server",
    default=settings.minio_secret_key,
)
args = parser.parse_args()
if (not args.accesskey) or (not args.secretkey):
    raise ValueError("No MinIO access key or secret key provided")

client = Minio(minioServer, access_key=args.accesskey, secret_key=args.secretkey)
objects = client.list_objects(bucketName, prefix=args.remote, recursive=True)

for obj in objects:
    try:
        if obj.is_dir:
            local_dir = f"models/{args.local}" + obj.object_name.removeprefix(
                args.remote
            )
            makedirs(local_dir, exist_ok=True)
        else:
            client.fget_object(
                bucketName,
                obj.object_name,
                f"models/{args.local}" + obj.object_name.removeprefix(args.remote),
            )
    except S3Error as e:
        print(f"Error occurred: {e}")
