Make sure you have meta-compose installed (https://github.com/webcrofting/meta-compose) by running:

```pip install meta-compose```



Add all **site names** to the list ``sites.txt`` and execute the script ``./stack_generator.sh [SOURCE_REGISTRY]``.

All the generated stack files will be under sites/ directory.



If you need to generate new **TLS Certificates**, run the script ``./certificates_generator.sh``.

If you already have existing certificates, create a directory named **tls** (at docker-compose/swarm/tls) and put them there.

> Note: If you generated new certificates or made changes to the **tls** directory files, you must run ``./stack_generator.sh [SOURCE_REGISTRY]`` again and re-deploy the generated stacks files for the changes to take effect.
