# Managment compose file for anyvision better tommorow 

### portainer 
portainer is management docker hosts/containers/voulmes etc.

more details at : 
- [http://portainer.readthedocs.io]
- [https://portainer.io]

##### make your own template dockers

to disable templates you need to add file with "{}" content, named templates.json, and locate it at /storage/templates.json,
    where out nginx run (command was added to compose as: --templates http://localhost/templates.json)

##### add docker endpoints 

in each docker systemd file add the following prameters:

####### ubuntu 16.04

- file location: /lib/systemd/system/docker.service
- parameters at : ExecStart=/usr/bin/dockerd -H fd:// __-H tcp://0.0.0.0:2376 -H unix:///var/run/docker.sock__

you can add automatically endpoints (docker hosts) into portainer:
create file:

[
  {
    "Name": "server1",
    "URL": "tcp://server1:2376"
  },
  {
    "Name": "server2",
    "URL": "tcp://server2:2376",
  }
]

and add into you docker compose at command place: --external-endpoints /endpoints/endpoints.json
and at volumes place add addtional volume: /tmp/endpoints:/endpoints
