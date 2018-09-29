###local docker registry

for insecure need to add the following line (in the server and in the client):

example:
```
{
  "insecure-registries" : ["192.168.59.128:5000"]
}
```
remark: replace 192.168.59.128 with the local docker regsitry server ip or fqdn 
remark: replace 5000 with the port that you choose

now restart the docker service
```
service docker restart
```

##server side:
add image to the local docker registry

example:
```
docker tag gcr.io/anyvision-training/backend-cpu:development 192.168.59.128:5000/backend-cpu:development
docker push 192.168.59.128:5000/backend-cpu:development
```

## client side
change in the docker compose the relevant image

example:
```
image: 192.168.59.128:5000/backend-cpu:development
```

now pull and up and that's it


## support certificate
for now anyvision certificate is not supported and you need to follow those steps:

example:
```
mkdir -p certs
openssl req   -newkey rsa:4096 -nodes -sha256 -keyout certs/domain.key   -x509 -days 365 -out certs/domain.crt
```
now add those certs to the docker compose

on the client side:
copy only the ```domain.crt``` file to ```/etc/docker/certs.d/myregistrydomain.com:5000/ca.crt```
