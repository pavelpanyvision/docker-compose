### install python 2.7

windows: ```https://www.python.org/ftp/python/2.7/python-2.7.amd64.msi```
linux: already built in

install it by next next next

### download mtp drive
```
http://www.mtpdrive.com/download.html
```

install it by next next next

add the license:

```
-----BEGIN MTPDRIVE REGISTRATION KEY----- 
mBB+3DRmGuE00HyipaMLe6Xp6cPNenn0bwFOCa33UDmoPSl0SYCiqIxog600nxFJ
gYCjZhLxQIsoozDZMdvvfCNhxwvOq85qpbjtG5K7U4/L0P+pxI4WoYS/drqcn6Uo
7NuCIUE+N+SAXOVB80SQ0pqK8HPFbOSFIDo4Q+qy+sePxRHnKREy5+vH3KOP5/66
sYnoGhlwf2Wr/+toMOIP13BZ65wevOeZYtt2g5Pxnunq8KQYRrfqQlSgdpCwGawB
J4ikILNPGlnJkixJoSGcpvluN6fRcgBmRmrDZotldsChmroV0fziOJNp3i/RXTy7
J8WkHw2RBTtnubLBklUwS5fvNEBq2K6ZwdmvGtdXaDGs4ZZvCSgrGKN/jz3yjkmw
/cuxrEk7SPxTM5RK1r9rEcfnHGawjUdZwsVV05Ea6rIwA8lu6N8VOKWrIs/l7EbU
vqEpoczSxgdkuK4wQdmlkpmyvMX+srZLoIuXezeWQMP0l+dYZw3p0olkX43rjLWe
Ie344vFLBgMBHVCm1M+9MWfjEUNSXE+osdngmf93pXNEijYInkhf1tjBjtC9d0uV
6MmT0tliUbRoqei8MFuPKMWbWPFbh1zxX2jglsQkhSEV92iqcKRklELkj8FJy8Y3
6CwThPsRN/nlSBQmyWIz6UaZmvR7UOvRfKUkW2i6f50=
-----END MTPDRIVE REGISTRATION KEY----- 
```


### install docker ce
for windows: ```https://download.docker.com/win/stable/Docker%20for%20Windows%20Installer.exe```

for linux: ```https://docs.docker.com/install/linux/docker-ce/ubuntu/```

### download git compose files 
``` 
git clone -b dslr git@github.com:AnyVisionltd/docker-compose.git
```

### download git DSLR windows watcher files
```
git clone https://github.com/AnyVisionltd/IDF_DSLR 
```

### credentials for docker login
option 1: with token

got to ```http://jenkins.anyvision.co/job/gcloud_generate_new_token/``` in order to generate new token

``` 
docker login "https://gcr.io" --username "oauth2accesstoken" --password <token from jenkins>
```

### set configuration

First, verify env/backend.env is up to date from the main docker-compose github repo under development branch

Second, edit env/dslr.env with the relevant API_IP , API_PORT and etc...

Third, Edit the IDF_DSLR/windows_watcher/Settings.json with the relevant Directory path


### docker pull & up -d
```
cd <path of the docker compose files>

#linux:
docker-compose -f docker-compose-dslr.yml pull
docker-compose -f docker-compose-dslr.yml up -d


#windows:
docker-compose -f docker-compose-dslr-windows.yml pull
docker-compose -f docker-compose-dslr-windows.yml up -d
```
