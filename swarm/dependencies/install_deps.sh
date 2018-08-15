#!/bin/bash

dpkg --install --refuse-downgrade --skip-same-version ./python-pip/*.deb
pip install --no-index --find-links ./meta-compose meta-compose
pip install --no-index --find-links ./j2cli j2cli
