print("Importing Packages")

from azure.storage.blob import BlobClient
import argparse
import os

print("Initializing variables")

parser = argparse.ArgumentParser(description='Uploads the Jsons to the FTP.')
parser.add_argument('--customer_name', type=str)
parser.add_argument('--sas_token', type=str)
parser.add_argument('--subscription_id', type=str)
args = parser.parse_args()

customer_name = args.customer_name
sas_token_raw = args.sas_token
sas_token = sas_token_raw.replace('%3D', '=')
subscription_id = args.subscription_id

container_name = "sftp"
storage_account_name = "sftplighthousepoc"
files_to_upload = ["keyvaults.json", "storage_accounts.json", "adf_shir.json"]

# print(sas_token)

print("Listing current working directory")
cwd = os.getcwd()
print(cwd)

print("Pushing to SFTP")

for file in files_to_upload:

    file_name = file
    file_path = os.path.join(cwd, file)
    print(file_path)

    blob_client = BlobClient.from_blob_url(f"https://{storage_account_name}.blob.core.windows.net/{container_name}/{customer_name}/{subscription_id}/{file_name}", credential=sas_token)

    with open(file_path, "rb") as data:
        blob_client.upload_blob(data, overwrite=True)
