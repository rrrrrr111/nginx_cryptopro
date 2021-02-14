set -x

base_image=centos:7
cryptopro_distrib=linux-amd64.tgz
cryptopro_nginx_gost_installer=https://github.com/CryptoPro/nginx-gost.git
image_name=nginx_cryptopro
image_ver=1.5
image=$image_name:$image_ver

echo Building image: $image

#
# Build image
docker build -t "$image" . \
 --build-arg BASE_IMAGE=$base_image \
 --build-arg CRYPTOPRO_DISTRIB=$cryptopro_distrib \
 --build-arg CRYPTOPRO_NGINX_GOST_INSTALLER=$cryptopro_nginx_gost_installer \
 --build-arg IMAGE_NAME=$image_name \
 #> build.log

# Upload to DockerHub
image_fullname=rrrrrr111/$image_name
docker tag $image $image_fullname:$image_ver \
 && docker tag $image $image_fullname:latest \
 && docker push $image_fullname

# Rerun Container
dc=nginx
docker kill $dc
docker rm $dc
docker run -d \
  --name $dc \
  --net subnet01 --ip 172.18.0.18 \
  -p 8094:80 -p 8092:443 \
  -v /opt/docker/nginx/conf/nginx.conf:/etc/nginx/nginx.conf \
  -v /opt/docker/nginx/logs:/var/log/nginx \
  -v /opt/docker/nginx/certs:/var/nginx/certs \
  -v /opt/docker/nginx/keys:/var/opt/cprocsp/keys \
  -v /opt/docker/nginx/users:/var/opt/cprocsp/users \
  $image
