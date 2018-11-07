# vault init
access the ui on web browser. example: ```https://vault.tls.ai:8200/ui```

now choose:
```
key threshold 3
key share 5
```
download the file and *seal* the vault


export VAULT_ADDR="https://vault.tls.ai:8200"  
export VAULT_TOKEN="Huh0AGo9Q7IpFks5bF84wMQB"


#enable audit log
vault audit enable file file_path=/vault/vault_audit.log


#create user and pass
vault list auth/userpass/users/
vault write auth/userpass/users/dors password=dors policies=admins

#write key value secretes (kv)
```
vault secrets enable -version=2 kv
#write secret
vault kv put secret/my-secret my-value=s3cr3t
#read secret
vault kv get secret/my-secret

#vault write secret/dorsec value=test
#vault read secret/dorsec
```

 
 
 #encrypt data for you (Transit)
 ```
 vault secrets enable transit
 
 #encrypt with base64 for safe Transit
 vault write transit/encrypt/my-key plaintext=$(base64 <<< "my secret data") type=ecdsa-p256
 vault write transit/encrypt/my-key plaintext=Huh0AGo9Q7IpFks5bF84wMQB type=ecdsa-p256
 
 #you will get value example vault:v1:mx/Bo/R3tA/IAgLQ4uQlA3LPnjyZpbsYhCHOoZa1duH8wQ/39shD8SE9lczIOg==
 #decrypt
 vault write transit/keys/my-key ciphertext="vault:v1:jksjdf7ds9fudfjds98fd="
 #more types here
 ```
 
 
 # mongo
 ```
 vault write database/config/my-mongodb-database \
    plugin_name=mongodb-database-plugin \
    allowed_roles="my-role" \
    connection_url="mongodb://mongodb.tls.ai:27017/admin?ssl=false" \
	  username="admin" \
    password="Password!"

vault write database/roles/my-role \
    db_name=my-mongodb-database \
    creation_statements='{ "db": "admin", "roles": [{ "role": "readWrite" }, {"role": "read", "db": "foo"}] }' \
    default_ttl="30s" \
    max_ttl="1m"
	
vault read database/roles/my-role

#get user name and passowrd to access the mongo
vault read database/creds/my-role
```

# app role
```
vault auth enable approle

vault write auth/approle/role/my-role \
    secret_id_ttl=10m \
    token_num_uses=10 \
    token_ttl=20m \
    token_max_ttl=30m \
    secret_id_num_uses=40 \
    policies=default
	
vault read auth/approle/role/my-role/role-id	
#example output:

Key        Value
---        -----
role_id    0b4fb237-c41a-7d4a-e96a-9277da2846df

vault write -f auth/approle/role/my-role/secret-id

#example output:

Key                   Value
---                   -----
secret_id             8b4d27eb-ec0e-620d-3bbe-dc1d6f935e7f
secret_id_accessor    1cba2fbb-9ab6-f462-cf41-2de1097537d9

#get token for use
vault write auth/approle/login role_id=0b4fb237-c41a-7d4a-e96a-9277da2846df secret_id=8b4d27eb-ec0e-620d-3bbe-dc1d6f935e7f
	
#example output:

	
Key                     Value
---                     -----
token                   8bQx5GMsclbggwYh7sWqig23
token_accessor          3jM9uvvyVNuPJiHZgzvs3iZP
token_duration          20m
token_renewable         true
token_policies          ["default"]
identity_policies       []
policies                ["default"]
token_meta_role_name    my-role
```

##example use approle
curl --header "X-Vault-Token: 6o2CdweiG3O8H8kCjYNMvSEB" --request GET https://vault.tls.ai:8200/v1/database/creds/my-role


# delete identeties
example:
```
vault delete secret/database
```    