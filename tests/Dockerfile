FROM alpine:3.6

LABEL maintainer "Igal Dahan <igald@anyvision.co>"


ARG JMETER_VERSION="4.0"
ENV JMETER_HOME /opt/apache-jmeter-${JMETER_VERSION}
ENV	JMETER_BIN	${JMETER_HOME}/bin
ENV	JMETER_DOWNLOAD_URL  http://mirrors.ocf.berkeley.edu/apache/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz


ARG TZ="Europe/Amsterdam"
RUN    apk update \
	&& apk upgrade \
	&& apk add ca-certificates \
	&& apk add ca-certificates wget \
	&& update-ca-certificates \
	&& apk add --update openjdk8-jre tzdata curl unzip bash \
	&& rm -rf /var/cache/apk/* \
	&& mkdir -p /tmp/dependencies  \
	&& curl -L --silent ${JMETER_DOWNLOAD_URL} >  /tmp/dependencies/apache-jmeter-${JMETER_VERSION}.tgz  \
	&& mkdir -p /opt  \
	&& tar -xzf /tmp/dependencies/apache-jmeter-${JMETER_VERSION}.tgz -C /opt  \
	&& rm -rf /tmp/dependencies

COPY requirements.txt /root/requirements.txt

RUN apk add --update \
    python \
    python-dev \
    py-pip \
    build-base \
  && pip install virtualenv  \ 
  && pip install -r /root/requirements.txt \
  && rm -rf /var/cache/apk/*

# Set global PATH such that "jmeter" command is found
ENV PATH $PATH:$JMETER_BIN

# Entrypoint has same signature as "jmeter" command
RUN mkdir -p /root/backend_trunk/tests/functional && mkdir -p /root/backend_trunk/tests/jmeter/tests && mkdir -p /root/backend_trunk/tests/test_data && mkdir -p /storage/logs && mkdir -p /tmp/results
COPY functional/execute.sh /root/backend_trunk/execute.sh 
RUN  chmod u+x /root/backend_trunk/execute.sh
COPY functional/check_env_setup.py /root/backend_trunk/tests/functional/check_env_setup.py
COPY functional/dash_api_mock_server.py /root/backend_trunk/tests/functional/dash_api_mock_server.py
COPY functional/check_tests_results.py /root/backend_trunk/tests/functional/check_tests_results.py
COPY jmeter/tests/play_video_update_subject_image.jmx  /root/backend_trunk/tests/jmeter/tests/play_video_update_subject_image.jmx
WORKDIR	/root/backend_trunk

CMD ["./execute.sh"]
