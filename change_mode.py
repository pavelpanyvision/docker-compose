#!/usr/bin/env python3
import fcntl
import os
import socket
import struct
import ruamel.yaml as yaml
import re as reg
import argparse
import math


def check_root():
    euid = os.geteuid()
    if euid != 0:
        raise EnvironmentError('need to be root')


def get_params():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-m', '--mode', help='set mode', action='store', choices=['unicast', 'multicast'], dest='MODE')
    group.add_argument('--get-mode', help='get current mode', action='store_true', dest='getMode')
    args = parser.parse_args()
    if args.getMode:
        print(getmode())
        exit(0)
    if args.MODE == getmode():
        print('you are already on {}, aborting'.format(args.MODE))
        exit(0)
    return args.MODE


def get_ip_address(dev):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    return socket.inet_ntoa(fcntl.ioctl(
        s.fileno(),
        0x8915,
        struct.pack('256s', bytes(dev[:15].encode('utf-8')))
    )[20:24])


def add_entries(data, key, value, services):
    for k in services:
        if key in data['services'][k]:
            if type(value) is not dict:
                data['services'][k][key].append(value)
        else:
            if type(value) is dict or value == 'host':
                data['services'][k].insert(list(data['services'][k]).index('volumes') - 1, key, value)
            else:
                data['services'][k].insert(list(data['services'][k]).index('volumes') - 1, key, [value])


def remove_entries(data, key, value, services):
    for k in services:
        if key in data['services'][k]:
            try:
                data['services'][k][key].remove(value)
            except ValueError:
                continue


def remove_keys(data, key, services):
    for k in services:
        if key in data['services'][k]:
            del data['services'][k][key]


def getmode():
    mode_file = os.path.join(os.path.dirname(os.path.realpath(__file__)), '.MODE')
    if os.path.exists(mode_file):
        with open(mode_file) as f:
            mode = f.read()
    else:
        mode = 'unicast'
    return mode


def set_mode(mode):
    mode_file = os.path.join(os.path.dirname(os.path.realpath(__file__)), '.MODE')
    with open(mode_file, 'w+') as f:
        f.write(mode)
    print('Mode is now: {}'.format(mode))


def is_contains(pattern, file_path):
    with open(file_path, 'r') as lines:
        for line in list(map(str.strip, lines)):
            if reg.findall(pattern, line):
                return True
        return False


def update_hosts(path, line, present=True):
    if present:
        if not is_contains('^{}$'.format(line), path):
            with open(path, 'r+') as f:
                content = f.read()
                f.seek(0, 0)
                f.write(line.rstrip('\r\n') + '\n' + content)
    else:
        with open(path, 'r') as f:
            content = list(filter(line.__ne__, list(map(str.strip, f.readlines()))))
        with open(path, 'w') as f:
            for item in content:
                f.write("{}\n".format(item))


def multicast(st, ip):
    add_entries(st, 'extra_hosts', 'edge.tls.ai:{}'.format(ip), ['api', 'backend', 'collate'])
    add_entries(st, 'network_mode', 'host', ['edge'])
    add_entries(st, 'dns', '127.0.0.53', ['edge'])
    add_entries(st, 'volumes', '/etc/hosts:/etc/hosts', ['edge'])
    add_entries(st, 'extra_hosts', 'edge.tls.ai:127.0.0.1', ['edge'])
    remove_entries(st, 'volumes', '/tmp/pipe_data:/root/pipe_data', ['backend', 'collate'])
    add_entries(st, 'volumes', '/ssd/pipe_data:/root/pipe_data', ['backend', 'collate'])
    remove_entries(st, 'environment', 'ENABLE_OPENSSH_SERVICE=true', ['edge'])
    add_entries(st, 'environment', 'ENABLE_OPENSSH_SERVICE=false', ['edge'])
    remove_keys(st, 'networks', ['edge'])
    remove_keys(st, 'ports', ['edge'])
    update_hosts('/etc/hosts', '127.0.0.1 edge.tls.ai')


def unicast(st, ip):
    add_entries(st, 'networks', {'prod': {'aliases': ('edge.tls.ai', 'proc-localnode.tls.ai')}}, ['edge'])
    add_entries(st, 'ports', '4005:4005', ['edge'])
    remove_entries(st, 'environment', 'ENABLE_OPENSSH_SERVICE=false', ['edge'])
    add_entries(st, 'environment', 'ENABLE_OPENSSH_SERVICE=true', ['edge'])
    remove_entries(st, 'volumes', '/ssd/pipe_data:/root/pipe_data', ['backend', 'collate'])
    add_entries(st, 'volumes', '/tmp/pipe_data:/root/pipe_data', ['backend', 'collate'])
    remove_entries(st, 'extra_hosts', 'edge.tls.ai:127.0.0.1', ['edge'])
    remove_entries(st, 'volumes', '/etc/hosts:/etc/hosts', ['edge'])
    remove_keys(st, 'dns', ['edge'])
    remove_keys(st, 'network_mode', ['edge'])
    remove_entries(st, 'extra_hosts', 'edge.tls.ai:{}'.format(ip), ['backend', 'collate'])
    remove_keys(st, 'extra_hosts', ['api'])
    update_hosts('/etc/hosts', '127.0.0.1 edge.tls.ai', False)


def is_exist(file):
    yml_file = os.path.join(os.getcwd(), file)
    if not os.path.exists(yml_file):
        raise EnvironmentError('No docker-compose-gpu.yml in here please make sure it exist in the working dir')
    return yml_file


def main():
    check_root()
    mode = get_params()
    yml_file = is_exist('docker-compose-gpu.yml')
    edge_ip = get_ip_address('docker0')

    with open(yml_file, 'r') as f:
        st = yaml.round_trip_load(f, preserve_quotes=True)

    if mode == 'multicast':
        multicast(st, edge_ip)
    else:
        unicast(st, edge_ip)

    with open(yml_file, 'w') as f:
        yaml.round_trip_dump(st, f, width=int(math.pow(2, 64)), indent=2, block_seq_indent=2)
    set_mode(mode)


main()