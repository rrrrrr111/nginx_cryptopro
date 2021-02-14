# Сборка Docker Image c NGINX + CryptoPro CSP + плагин c ГОСТ алгоритмами при TLS соединении

1. Поместить дистрибутив CryptoPRO CSP в папку `files/`, поправить имя дистрибутива
   в файле `build.sh` если отличается, рекомендуется версия не менее 5.0.11998-6
2. Запускать сборку скриптом `build.sh`, закомментировать в скрипте ненужное

# Конфигурация Docker Container

### Создание контейнера
Например:

	docker run -d \
        --name nginx \
        --net subnet01 --ip 172.18.0.18 \
        -p 8094:80 -p 8092:443 \
        -v /opt/docker/nginx/conf/nginx.conf:/etc/nginx/nginx.conf \
        -v /opt/docker/nginx/logs:/var/log/nginx \
        -v /opt/docker/nginx/certs:/var/nginx/certs \
        -v /opt/docker/nginx/keys:/var/opt/cprocsp/keys \
        -v /opt/docker/nginx/users:/var/opt/cprocsp/users \
        rrrrrr111/nginx_cryptopro

### Выпуск ключевых пар для TLS соединения

- Поскольку в контейнере установлено CryptoPro CSP, его можно использовать для генерации ключевых пар и 
  выпуска сертификатов, либо использовать CryptoPro установленное в другом месте. Далее для примера 
  используется тестовый удостоверяющий центр (УЦ) доступный по адресу http://testgost2012.cryptopro.ru/certsrv
  
#### Генерация серверного TLS ключа  
  
- Создаем ключевую пару, отсылаем запрос на подпись открытого ключа в УЦ, сохраняем сертификат. Ключ с сертификатом 
  создается в соответствующей папке пользователя `/var/opt/cprocsp/keys/<user>/`. Ключи для сервера и клиентов создаются 
  аналогично. В данном примере указан -certusage 1.3.6.1.5.5.7.3.1 что соответствует серверному сертификату, 
  который будет использоваться самим NGINX. При генерации клиентских ключей указывается -certusage 1.3.6.1.5.5.7.3.2


    /opt/cprocsp/bin/amd64/cryptcp -creatcert -provtype 81 -provname 'Crypto-Pro GOST R 34.10-2012 KC1 Strong CSP' -rdn 'CN=server_01' -cont '\\.\HDIMAGE\server_01' -certusage 1.3.6.1.5.5.7.3.1 -ku -du -both -exprt -ca http://testgost2012.cryptopro.ru/certsrv

  Пароль на ключ не указываем    

- Меняем KC1 на KC2 в имени провайдера ключа, так как nginx работает с провайдером KC2


    /opt/cprocsp/bin/amd64/certmgr -inst -store uMy -cont '\\.\HDIMAGE\server_01' -provtype 81 -provname "Crypto-Pro GOST R 34.10-2012 KC2 Strong CSP"

- Экспортируем в файл сертификат открытого ключа


    /opt/cprocsp/bin/amd64/certmgr -export -cert -dn "CN=server_01" -dest '/var/nginx/certs/server_01.cer'
  
- Преобразуем сертификат к PEM формату. CryptoPro имеет в своем составе кастомизированные библиотеки
  на основе openssl, потому не рекомендуется устанавливать в контейнер стандартный openssl, следует
  установить openssl в другом месте
  

    openssl x509 -inform DER -in "/opt/docker/nginx/certs/server_01.cer" -out "/opt/docker/nginx/certs/server_01.pem"

  Серверный сертификат открытого ключа в формате PEM потребуется для настройки NGINX

##### Генерация клиентского TLS ключа

- При генерации клиентского ключа соответственно указываем -certusage 1.3.6.1.5.5.7.3.2
- Для клиентских ключей необязательно выгружать сертификаты

  
    /opt/cprocsp/bin/amd64/cryptcp -creatcert -provtype 81 -provname 'Crypto-Pro GOST R 34.10-2012 KC1 Strong CSP' -rdn 'CN=client_06' -cont '\\.\HDIMAGE\client_06' -certusage 1.3.6.1.5.5.7.3.2 -ku -du -both -exprt -ca http://testgost2012.cryptopro.ru/certsrv
    ??????? /opt/cprocsp/bin/amd64/certmgr -inst -store uMy -cont '\\.\HDIMAGE\client_06' -provtype 81 -provname "Crypto-Pro GOST R 34.10-2012 KC2 Strong CSP"
    ??????? /opt/cprocsp/bin/amd64/certmgr -export -cert -dn "CN=client_06" -dest '/var/nginx/certs/client_06.cer'
    ??????? openssl x509 -inform DER -in "/opt/docker/nginx/certs/client_06.cer" -out "/opt/docker/nginx/certs/client_06.pem"


#### Конфигурация Mutual-TLS на NGINX

- Папка контейнера `/var/opt/cprocsp/keys` используется для хранения ключей CryptoPRO. Папки ключей
  кладутся в подпапки с именами профилей пользователей. По умолчанию приложение в контейнере запускается под
  пользователем `root`, соответственно ключи должны размещаться в `/var/opt/cprocsp/keys/root/`. При работе
  с ключами CryptoPRO автоматически переназначает права на папки, потому ключи могут стать не видны.

- Папка контейнера `/var/opt/cprocsp/users` используется для хранилищ сертификатов пользователей. Сертификат ключа 
  используемого NGINX для TLS должен находиться в доверенном хранилище у соответствующего пользователя. Можно 
  подложить доверенное хранилище через volume, либо импортировать необходимый сертификат из файла, например:
  
   ?????
  ???????
    /opt/cprocsp/bin/amd64/certmgr -inst -store uMy -file /var/nginx/certs/client_05.cer -provtype 81 -provname "Crypto-Pro GOST R 34.10-2012 KC2 Strong CSP"

- Пример конфига NGINX. 
  В параметре `ssl_client_certificate` указывается путь к файлу PEM формата, с доверенными сертификатами 
  по которым проверяется цепочка для клиентских сертификатов при соединении.


        ...
        user   root;
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
