Make sure you have meta-compose installed (https://github.com/webcrofting/meta-compose) by running:
```pip install meta-compose```

Put all the **site names** in ```sites.txt``` and execute the script ```./stack_generator.sh [SOURCE_REGISTRY]```
All the generated stack files will be under sites/ directory.

if you need new **tls certificates**, run the script ```./certificates_generator.sh```
if you already have an existing certificates copy the certificates and put it under **tls** directory.

