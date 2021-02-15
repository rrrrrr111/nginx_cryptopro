# Сборка Docker Image c NGINX + CryptoPro CSP + плагин c ГОСТ алгоритмами для TLS

1. Поместить дистрибутив CryptoPRO CSP в папку `files/`, поправить имя дистрибутива
   в файле `build.sh` если отличается, рекомендуется версия не менее 5.0.11998-6
2. Запускать сборку скриптом `build.sh`, закомментировать в скрипте ненужное

# Конфигурация Docker Container

## Создание контейнера
Например:

	docker run -d --privileged \
        --name nginx \
        --net subnet01 --ip 172.18.0.18 \
        -p 8094:80 -p 8092:443 \
        -v /opt/docker/nginx/conf/nginx.conf:/etc/nginx/nginx.conf \
        -v /opt/docker/nginx/logs:/var/log/nginx \
        -v /opt/docker/nginx/certs:/var/nginx/certs \
        -v /opt/docker/nginx/keys:/var/opt/cprocsp/keys \
        -v /opt/docker/nginx/users:/var/opt/cprocsp/users \
        rrrrrr111/nginx_cryptopro

## Выпуск ключевых пар для TLS соединения

- Поскольку в контейнере установлено CryptoPro CSP, его можно использовать для генерации ключевых пар и
  выпуска сертификатов. Серверный ключ должен быть создан непосредственно в контейнере, либо можно подложить
  соответствующее содержимое папок `/var/opt/cprocsp/keys` и `/var/opt/cprocsp/users`. Далее для примера
  используется тестовый удостоверяющий центр (УЦ) доступный по адресу http://testgost2012.cryptopro.ru/certsrv
  
### Генерация серверного TLS ключа  
  
- Создаем ключевую пару, отсылаем запрос на подпись открытого ключа в УЦ, сохраняем сертификат. Ключ с сертификатом 
  создается в папке `/var/opt/cprocsp/keys/<user>/`. Ключи для сервера и клиентов создаются аналогично. В данном 
  примере указан `-certusage 1.3.6.1.5.5.7.3.1` что соответствует серверному сертификату, который будет использоваться 
  самим NGINX, например:


    /opt/cprocsp/bin/amd64/cryptcp -creatcert -provtype 81 -provname 'Crypto-Pro GOST R 34.10-2012 KC1 Strong CSP' -rdn 'CN=server_01' -cont '\\.\HDIMAGE\server_01' -certusage 1.3.6.1.5.5.7.3.1 -ku -du -both -exprt -ca http://testgost2012.cryptopro.ru/certsrv

  Пароль на ключ не указываем. 
  При генерации клиентских ключей указывается `-certusage 1.3.6.1.5.5.7.3.2`

- Меняем KC1 на KC2 в имени провайдера ключа, так как nginx работает с провайдером KC2, например:


    /opt/cprocsp/bin/amd64/certmgr -inst -store uMy -cont '\\.\HDIMAGE\server_01' -provtype 81 -provname "Crypto-Pro GOST R 34.10-2012 KC2 Strong CSP"

- Экспортируем в файл сертификат открытого ключа, например:


    /opt/cprocsp/bin/amd64/certmgr -export -cert -dn "CN=server_01" -dest '/var/nginx/certs/server_01.cer'
  
- Преобразуем сертификат к PEM формату. CryptoPro имеет в своем составе кастомизированные библиотеки
  на основе openssl, потому не рекомендуется устанавливать в контейнер стандартный openssl, следует
  использовать openssl в другом месте, например:
  

    openssl x509 -inform DER -in "/opt/docker/nginx/certs/server_01.cer" -out "/opt/docker/nginx/certs/server_01.pem"

  Серверный сертификат открытого ключа в формате PEM потребуется для настройки NGINX

### Генерация клиентского TLS ключа

- Клиентский ключ может быть создан в другом месте, но обязательно должен быть подписан соответствующим УЦ по цепочке. 
  Для клиентских ключей менять имя провайдера, и экспортировать сертификаты необязательно. При генерации клиентского 
  ключа соответственно указываем `-certusage 1.3.6.1.5.5.7.3.2`, например: 
  

    /opt/cprocsp/bin/amd64/cryptcp -creatcert -provtype 81 -provname 'Crypto-Pro GOST R 34.10-2012 KC1 Strong CSP' -rdn 'CN=client_01' -cont '\\.\HDIMAGE\client_01' -certusage 1.3.6.1.5.5.7.3.2 -ku -du -both -exprt -ca http://testgost2012.cryptopro.ru/certsrv


## Конфигурация Mutual-TLS на NGINX

- Папки контейнера `/var/opt/cprocsp/keys/` и `/var/opt/cprocsp/users/` используются CryptoPro для ключей и хранилищ
  пользователей. CryptoPro при работе автоматически переназначает права на папки, потому содержимое может стать недоступно. 
  Нужно сгенерировать серверный ключ в контейнере либо обеспечить соответствующее содержимое этих папок.

- Пример конфига NGINX для Mutual-TLS. 
  В параметрах `ssl_certificate` и `ssl_certificate_key` указывается сертификат и алиас серверного ключа. 
  В параметре `ssl_client_certificate` указывается путь к файлу PEM формата, с доверенными сертификатами по которым 
  проверяется цепочка для клиентских сертификатов при соединении. Данный файл можно получить в соответствующем УЦ.


        ...
        user    root;
        ...
        server {
                listen                          443 ssl;
                ...
                ssl_certificate                 /var/nginx/certs/server_01.pem;
                ssl_certificate_key             engine:gostengy:server_01;
                ssl_protocols                   TLSv1.2;
                ssl_ciphers                     GOST2012-GOST8912-GOST8912:GOST2001-GOST89-GOST89:HIGH;
                ssl_session_cache               shared:SSL:1m;
                ssl_session_timeout             5m;
                ssl_prefer_server_ciphers       on;
                ssl_client_certificate          /var/nginx/certs/cp_ca_pem.cer;
                ssl_verify_client               on;
                ssl_verify_depth                3;
                ...
        }
