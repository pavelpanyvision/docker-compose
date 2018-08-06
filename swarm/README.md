Make sure you have meta-compose installed (https://github.com/webcrofting/meta-compose) by running:
```pip install meta-compose```

Put all the **site names** in ```sites.txt``` and execute the script ./docker_swarm_compose_generator.sh
All the generated compose files will be under sites/ folder.

if you need new **tls** files run the script ```./gen_anv_certs.sh```
if you already has existing certificates copy the certificates and pul it under **tls** dir

