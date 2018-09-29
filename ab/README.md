Changes to do in:

## a

If you have several A servers, rename docker-compose-local-aXX.yml to docker-compose-local-a01.yml and copy each the corresponding file to each A server...

In each compose file: change the a<XX> to a02,a03,a04... in each line that exist a<XX> in each compose file

For each A server copy the certificate from B.


## b

Replace "<ip of aXX server>" with the IP of the A server(s)
