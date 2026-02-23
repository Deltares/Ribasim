import argparse
from pathlib import Path

from minio import Minio
from minio.error import S3Error
from s3_settings import settings

MINIO_SERVER = "s3.deltares.nl"
BUCKET_NAME = "ribasim"


def download_folder(
    remote: str,
    local: str,
    access_key: str = "",
    secret_key: str = "",
) -> None:
    """Download a folder (recursively) from the Ribasim MinIO bucket."""
    access_key = access_key or settings.minio_access_key
    secret_key = secret_key or settings.minio_secret_key

    if not access_key or not secret_key:
        raise ValueError("No MinIO access key or secret key provided")

    client = Minio(MINIO_SERVER, access_key=access_key, secret_key=secret_key)
    objects = list(client.list_objects(BUCKET_NAME, prefix=remote, recursive=True))

    if not objects:
        raise ValueError(f"Remote path '{remote}' does not exist or is empty.")

    for obj in objects:
        try:
            if obj.is_dir:
                local_dir = f"models/{local}" + obj.object_name.removeprefix(remote)
                Path(local_dir).mkdir(parents=True, exist_ok=True)
            else:
                client.fget_object(
                    BUCKET_NAME,
                    obj.object_name,
                    f"models/{local}" + obj.object_name.removeprefix(remote),
                )
        except S3Error as e:
            print(f"Error occurred: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Download a folder (recursively) from the MinIO server"
    )
    parser.add_argument("remote", help="The path to download in the MinIO server")
    parser.add_argument("local", help="The path to the local file system")
    parser.add_argument(
        "--accesskey",
        help="The access key to access the MinIO server",
        default="",
    )
    parser.add_argument(
        "--secretkey",
        help="The secret key to access the MinIO server",
        default="",
    )
    args = parser.parse_args()
    download_folder(
        args.remote,
        args.local,
        access_key=args.accesskey,
        secret_key=args.secretkey,
    )
