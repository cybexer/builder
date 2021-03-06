# Use Bionic Beaver as base image
FROM phusion/baseimage:0.11

ENV TZ 'Europe/Tallinn'
ENV DEBIAN_FRONTEND noninteractive

ARG DOCKER_VERSION="5:19.03.8~3-0~ubuntu-bionic" 
ARG DOCKER_CHANNEL="stable" 
ARG DIND_COMMIT="3b5fac462d21ca164b3778647420016315289034" 
ARG DOCKER_COMPOSE_VERSION="1.25.4"

ENV NVM_DIR /root/.nvm
ENV NODE_VERSION v12.16.1

ENV NODE_PATH $NVM_DIR/versions/node/$NODE_VERSION/lib/node_modules
ENV PATH      $NVM_DIR/versions/node/$NODE_VERSION/bin:$PATH
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64/
ENV PATH=$JAVA_HOME/bin:$PATH

ARG MAVEN_VERSION=3.6.3
ARG USER_HOME_DIR="/root"
ARG MAVEN_SHA512="c35a1803a6e70a126e80b2b3ae33eed961f83ed74d18fcd16909b2d44d7dada3203f1ffe726c17ef8dcca2dcaa9fca676987befeadc9b9f759967a8cb77181c0"
ARG BASE_URL=https://apache.osuosl.org/maven/maven-3/${MAVEN_VERSION}/binaries

RUN echo $TZ > /etc/timezone && \
    add-apt-repository ppa:openjdk-r/ppa \
    && add-apt-repository ppa:git-core/ppa \
    && apt-get update && apt-get upgrade -y -o Dpkg::Options::="--force-confold" \
    && apt-get install -y --no-install-recommends wget \
    && wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
    && apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    bzip2 \
    ca-certificates \
    curl \
    git \
    gnupg2 \
    gnupg-agent \
    google-chrome-unstable \
    iptables \
    libgconf-2-4 \ 
    lxc \
    openjdk-11-jdk-headless \
    python \
    software-properties-common \
    tzdata && \
    rm /etc/localtime && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# Install Docker CE
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   ${DOCKER_CHANNEL}" \
   && apt-get update \
   && apt-get install -y docker-ce=${DOCKER_VERSION} docker-ce-cli=${DOCKER_VERSION} containerd.io


# Installing Node via NVM
RUN mkdir /root/.nvm

# Install nvm with node and npm
RUN cd /root && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.2/install.sh | bash 
RUN . $NVM_DIR/nvm.sh && nvm install $NODE_VERSION && nvm alias default $NODE_VERSION && nvm use default

# Install Java and Maven
RUN ln -s /etc/java-11-openjdk /usr/lib/jvm/java-11-openjdk-$(dpkg --print-architecture)/conf
RUN mkdir -p /usr/share/maven /usr/share/maven/ref \
  && curl -fsSL -o /tmp/apache-maven.tar.gz ${BASE_URL}/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
  && echo "${MAVEN_SHA512}  /tmp/apache-maven.tar.gz" | sha512sum -c - \
  && tar -xzf /tmp/apache-maven.tar.gz -C /usr/share/maven --strip-components=1 \
  && rm -f /tmp/apache-maven.tar.gz \
  && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn \
  && mvn -v

##### Docker in Docker ##### 
RUN set -ex \
    && docker -v \
# set up subuid/subgid so that "--userns-remap=default" works out-of-the-box
    && addgroup dockremap \
    && useradd -g dockremap dockremap \
    && echo 'dockremap:165536:65536' >> /etc/subuid \
    && echo 'dockremap:165536:65536' >> /etc/subgid \
    && wget "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind" -O /usr/local/bin/dind \
    && curl -L https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-Linux-x86_64 > /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/dind /usr/local/bin/docker-compose
##### Docker in Docker end #####

###### Install AWS CLI #####
RUN set -ex \
    && wget "https://bootstrap.pypa.io/2.6/get-pip.py" -O /tmp/get-pip.py \
    && python /tmp/get-pip.py \
    && pip install awscli==1.* \
    && rm -fr /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /src/*.deb

# Temporary fix for error "java.security.InvalidAlgorithmParameterException: the trustAnchors parameter must be non-empty"
COPY cacerts /etc/ssl/certs/java/cacerts

COPY dockerd-entrypoint.sh /usr/local/bin/