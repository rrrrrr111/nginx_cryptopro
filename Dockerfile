
ARG BASE_IMAGE

FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG IMAGE_NAME
ARG CRYPTOPRO_DISTRIB
ARG CRYPTOPRO_NGINX_GOST_INSTALLER

LABEL Name=${IMAGE_NAME} \
      Description="$BASE_IMAGE + Nginx-gost (nginx + openssl gostengy + cryptopro $CRYPTOPRO_DISTRIB), see $CRYPTOPRO_NGINX_GOST_INSTALLER"

COPY files/ /
WORKDIR /

RUN set -x \
 && yum update -y \
 && yum install -y wget git lsb-base lsb-core-noarch initscripts alien gcc gcc-c++ g++ \
 && git config --global http.sslVerify false \
 && cd / \
 && git clone $CRYPTOPRO_NGINX_GOST_INSTALLER \
 && cd /nginx-gost/nginx-gost \
 && groupadd --system --gid 101 nginx \
 && useradd --system -g nginx --no-create-home --home-dir /nonexistent --comment "nginx user" --shell /bin/false --uid 101 nginx \
 && chmod +x *.sh \
 && ./install-nginx.sh --csp=/$CRYPTOPRO_DISTRIB --install=gcc --install=zlib --install=pcre \
# && ./install-certs.sh --certname=server_00 --container=server_00 \
 && rm -rf /$CRYPTOPRO_DISTRIB \
 && rm -rf /nginx-gost \
 && yum remove -y git alien gcc gcc-c++ g++ \
 && yum autoremove -y \
 && cd / \
 && chmod +x *.sh \
 && nginx -V \
 && /opt/cprocsp/cp-openssl-1.1.0/bin/amd64/openssl engine \
 && yum list installed | grep csp

EXPOSE 80/tcp 443/tcp
STOPSIGNAL SIGQUIT
CMD [ "/bin/sh", "-c", "/docker-entrypoint.sh" ]
