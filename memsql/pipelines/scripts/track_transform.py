#!/usr/bin/python3.6

import json
import os
import struct
import sys
from google.protobuf.json_format import MessageToJson


binary_stdin = sys.stdin if sys.version_info < (3, 0) else sys.stdin.buffer
binary_stderr = sys.stderr if sys.version_info < (3, 0) else sys.stderr.buffer
binary_stdout = sys.stdout if sys.version_info < (3, 0) else sys.stdout.buffer

# dependencies are stored in a folder called python_deps
# relative to this script. This is setup by the Dockerfile.

SCRIPT_DIR = os.path.join(os.path.dirname(__file__))
sys.path.append(os.path.join(SCRIPT_DIR, "/pipelines/protos/"))

from track_pb2 import Track


def input_stream():
    """
        Consume STDIN and yield each record that is received from MemSQL
    """
    while True:
        byte_len = binary_stdin.read(8)
        if len(byte_len) == 8:
            byte_len = struct.unpack("L", byte_len)[0]
            result = binary_stdin.read(byte_len)
            yield result
        else:
            assert len(byte_len) == 0, byte_len
            return


def log(message):
    """
        Log an informational message to stderr which will show up in MemSQL in
        the event of transform failure.
    """
    binary_stderr.write(message + b"\n")


def emit(message):
    """
        Emit a record back to MemSQL by writing it to STDOUT.  The record
        should be formatted as JSON, Avro, or CSV as it will be parsed by
        LOAD DATA.
    """
    binary_stdout.write(message + b"\n")

log(b"Begin transform")

# We start the transform here by reading from the input_stream() iterator.
for data in input_stream():
    track_proto = Track()
    track_proto.ParseFromString(data)
    track_json = json.loads(MessageToJson(track_proto, preserving_proto_field_name=True))
    track_json['type'] = track_proto.type
    track_json['collate_id'] = track_proto.collate_id
    track_json['gender'] = track_proto.gender
    emit(str.encode(json.dumps(track_json, separators=(',', ':'))))

log(b"End transform")



