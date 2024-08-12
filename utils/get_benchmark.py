import sys

from minio import Minio
from minio.error import S3Error

"""For access
To access and download a specific folder in MinIO server

minioServer: the access point to MinIO for Deltares
accessKey: the credentials username
secreyKey: input from the terminal, the credentials password
pathToFolder: input from the terminal, the path to the folder to download. E.g. "benchmark/", "hws_2024_7_0/"
"""

minioServer = "s3.deltares.nl"
accessKey = "KwKRzscudy3GvRB8BN1Z"
secretKey = sys.argv[1]
pathToFolder = sys.argv[2]

# The path that will be recursively downloaded
bucketName = "ribasim"
pathName = "hws_2024_7_0"

# Minio client connection
myClient = Minio(minioServer, access_key=accessKey, secret_key=secretKey)

objects = myClient.list_objects(bucketName, prefix=pathToFolder, recursive=True)

for obj in objects:
    try:
        myClient.fget_object(bucketName, obj.object_name, "" + obj.object_name)
    except S3Error as e:
        print(f"Error occurred: {e}")
