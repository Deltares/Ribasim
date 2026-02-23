import argparse
from pathlib import Path

from minio import Minio
from minio.error import S3Error
from s3_settings import settings

MINIO_SERVER = "s3.deltares.nl"
BUCKET_NAME = "ribasim"


def upload_file(
    source: Path,
    destination: str,
    access_key: str = "",
    secret_key: str = "",
) -> None:
    """Upload a single file to the Ribasim MinIO bucket."""
    access_key = access_key or settings.minio_access_key
    secret_key = secret_key or settings.minio_secret_key

    if not source.is_file():
        raise ValueError(f"The source file does not exist: {source}")
    if not access_key or not secret_key:
        raise ValueError("No MinIO access key or secret key provided")

    client = Minio(MINIO_SERVER, access_key=access_key, secret_key=secret_key)
    try:
        client.fput_object(BUCKET_NAME, destination, str(source))
    except S3Error as e:
        print(f"Error occurred: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upload a file to the MinIO server")
    parser.add_argument("source", type=Path, help="The source file to upload")
    parser.add_argument("destination", help="The destination file in the MinIO server")
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
    upload_file(
        args.source,
        args.destination,
        access_key=args.accesskey,
        secret_key=args.secretkey,
    )
