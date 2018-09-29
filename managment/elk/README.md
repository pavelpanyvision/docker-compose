ELK stack from scratch, with Docker
===================================

The stack include:

- elastic
- redis
- logstash
- filebeat
- kibana

![alt text](https://github.com/AnyVisionltd/devops/blob/master/better_tomorrow/docker/compose/managment/elk/elk%20stask%20(1).jpg)


## Run (stack)
```
  # run (daemon)
  docker-compose up -d
  # show logs
  docker-compose logs -f
```

## Index management with curator
```
  docker run --network dockerelkstack_logging --link elastic:elasticsearch -v "$PWD/curator/config":/config --rm bobrik/curator:4.0.4 --config /config/config.yml /config/actions.yml
```
