Make sure you have meta-compose installed (https://github.com/webcrofting/meta-compose) by running:
```pip install meta-compose```

Add all **site names** to the list ```sites.txt``` and execute the script ```./stack_generator.sh [SOURCE_REGISTRY]```
All the generated stack files will be under sites/ directory.

If you need to generate new **tls certificates**, run the script ```./certificates_generator.sh```, and then run ```./stack_generator.sh [SOURCE_REGISTRY]``` again.
If you already have existing certificates, create a directory named **tls** (at docker-compose/swarm/tls) and put them there.
