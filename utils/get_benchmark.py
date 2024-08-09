import sys

from minio import Minio
from minio.error import S3Error

# For access
myMinioServer = "s3.deltares.nl"
myAccessKey = "KwKRzscudy3GvRB8BN1Z"
mySecretKey = sys.argv[1]

# The path that will be recursively downloaded
myBucketName = "ribasim"
myPathName = "hws_2024_7_0"
myRewind = "2023.05.10T16:00"  # Notation that mc uses

# Minio client connection
myClient = Minio(myMinioServer, access_key=myAccessKey, secret_key=mySecretKey)

objects = myClient.list_objects(myBucketName, prefix="benchmark/", recursive=True)

for obj in objects:
    try:
        myClient.fget_object(myBucketName, obj.object_name, "" + obj.object_name)
    except S3Error as e:
        print(f"Error occurred: {e}")
