#!/bin/bash
set -eu
 
# function section 

create_ssl() {
	#Generate a key
	# Generate private/public RSA key pair :
	openssl genrsa -aes256 -passout pass:$password -out $CA_CERTS_DIR/anyvisionCA.key.pem 2048
	 
	# change permissions & secure it
	chmod 400 $CA_CERTS_DIR/anyvisionCA.key.pem
	
	echo " Generate self-signed CA certificate signed by our own CA using the config we editted earlier."
	# -x509 means public key, -subj means cert issuer (SAN), crucial for the validity of the cert.
	openssl req -new -x509 -subj "/CN=anyvisionCA" -extensions v3_ca -days 3650 -key $CA_CERTS_DIR/anyvisionCA.key.pem -sha256 -out $CA_CERTS_DIR/anyvisionCA.pem -config tls/anyvisionCA.cnf -passin pass:$password
	
	echo " Generate private/public RSA key pair"
	# We won't use a passphrase here. (just not necessary)
	openssl genrsa -out $CA_CERTS_DIR/apigateway.anyvision.local.key.pem 2048
	 
	echo " Let the access to read this file."
	chmod 755 /etc/ssl/private
	
	echo " Generate .csr of our domain / hostname."
	openssl req -subj "/CN=apigateway.anyvision.local" -extensions v3_req -sha256 -new -key $CA_CERTS_DIR/apigateway.anyvision.local.key.pem -out $CA_CERTS_DIR/apigateway.anyvision.local.csr
	
	echo "Generate a signed(by our own CA) certificate for our host"
	openssl x509 -req -extensions v3_req -days 3650 -sha256 -passin pass:$password -in $CA_CERTS_DIR/apigateway.anyvision.local.csr -CA $CA_CERTS_DIR/anyvisionCA.pem -CAkey $CA_CERTS_DIR/anyvisionCA.key.pem -CAcreateserial -out $CA_CERTS_DIR/apigateway.anyvision.local.crt -extfile tls/anyvisionCA.cnf
	
	cd $CA_CERTS_DIR
	cat apigateway.anyvision.local.crt  anyvisionCA.pem anyvisionCA.key.pem > apigateway.anyvision.local.full.pem
        cd ..
}

########
# Main #
########
CA_CERTS_DIR=tls
# if [ -d $CA_CERTS_DIR ]; then
#         rm -rf $CA_CERTS_DIR/*
# fi
if [ ! -d $CA_CERTS_DIR ]; then
        mkdir -p $CA_CERTS_DIR
        chmod 755 $CA_CERTS_DIR
fi
password=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
echo "$password" > $CA_CERTS_DIR/passinfo
if [ ! -f "$CA_CERTS_DIR/apigateway.anyvision.local.full.pem" ] ; then
	echo "creating ssl"
	create_ssl
	## ADD ALL THE CA-CERTIFICATES OF THE WORLD TO ENABLE SSL CONNECTIVITY TO THE WWW
	#curl https://mkcert.org/generate/ >> $CA_CERTS_DIR/anyvisionCA.pem
else
	echo "The key $CA_CERTS_DIR/apigateway.anyvision.local.full.pem already exist. skip creating ssl"
fi
