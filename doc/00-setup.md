## インストール

### 動作環境

- ubuntu
  - git
  - openssl
  - shunit2
- Docker

### 諸々生成

```
docker pull library/nginx:alpine
docker pull abiosoft/caddy
docker pull mattbodholdt/openca-ocspd
git clone https://github.com/omitroom13/toyca
cd toyca
```

library/nginx(debian ビルドされている)での openssl バージョンは 1.1.0j だった、 alpine の方は 1.1.1b になっている。 TLS 1.3 や ED25519 のテストのためにこちらを使う。

```
$ docker run abiosoft/caddy -version
Caddy 0.11.5 (unofficial)
$ docker run library/nginx:alpine nginx -V
nginx version: nginx/1.15.10
built by gcc 8.2.0 (Alpine 8.2.0) 
built with OpenSSL 1.1.1b  26 Feb 2019
TLS SNI support enabled
configure arguments: --prefix=/etc/nginx --sbin-path=/usr/sbin/nginx --modules-path=/usr/lib/nginx/modules --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --pid-path=/var/run/nginx.pid --lock-path=/var/run/nginx.lock --http-client-body-temp-path=/var/cache/nginx/client_temp --http-proxy-temp-path=/var/cache/nginx/proxy_temp --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp --http-scgi-temp-path=/var/cache/nginx/scgi_temp --user=nginx --group=nginx --with-http_ssl_module --with-http_realip_module --with-http_addition_module --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_random_index_module --with-http_secure_link_module --with-http_stub_status_module --with-http_auth_request_module --with-http_xslt_module=dynamic --with-http_image_filter_module=dynamic --with-http_geoip_module=dynamic --with-threads --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module --with-stream_geoip_module=dynamic --with-http_slice_module --with-mail --with-mail_ssl_module --with-compat --with-file-aio --with-http_v2_module
$ google-chrome --version
Google Chrome 73.0.3683.103 
```

```
sudo chown -R $(id -u):$(id -g) .
docker build -f Dockerfile/squid -t squid-bump .
docker build -f Dockerfile/openssl -t openssl-tls1_3 .
docker build -f Dockerfile/sphinx -t sphinx .
```

ドキュメント生成。 Sphinx が必要

```
docker run -it -v $(pwd):/opt/toyca sphinx

pushd doc
mkdir _static
make html
popd
```

デモ用CAの生成

```
docker run -it -v $(pwd):/opt/toyca openssl-tls1_3
./ca.sh clean
./ca.sh create_both

sudo chown -R $(id -u):$(id -g) .
ca="server-ca-2"
cn="ec.P-256.example.com"
san="DNS:${cn}"
PKEY_ALG=EC
PKEY_PARAM="ec_paramgen_curve:P-256 ec_param_enc:named_curve"
./ca.sh gen_cert_server "$ca" "$cn" "$san" "$PKEY_ALG" "$PKEY_PARAM"

ca="server-ca-1"
cn="ocsp.example.com"
san="DNS:${cn}"
PKEY_ALG=rsa
PKEY_PARAM="rsa_keygen_bits:2048"
./ca.sh gen_cert_ocsp "$ca" "$cn" "$san" "$PKEY_ALG" "$PKEY_PARAM"

ca="server-ca-2"
cn="ec.ed25519.example.com"
san="DNS:${cn}"
PKEY_ALG=ED25519
PKEY_PARAM=""
./ca.sh gen_cert_server "$ca" "$cn" "$san" "$PKEY_ALG" "$PKEY_PARAM"

ca="server-ca-2"
cn="ec.ed448.example.com"
san="DNS:${cn}"
PKEY_ALG=ED448
PKEY_PARAM=""
./ca.sh gen_cert_server "$ca" "$cn" "$san" "$PKEY_ALG" "$PKEY_PARAM"
```

```
openssl genpkey -algorithm ED25519 -out 秘密鍵ファイル名.pem
```

単体テスト

```
docker-compose -f ./Dockerfile/docker-compose.yml up

./test.sh
```

テスト用 Web サイト(www.example.comなど)の起動

```
./ca.sh gen_nginx_conf
```

```
./Dockerfile.sh run
```

```eval_rst
.. todo::
	エラーチェック
	- v オプションで指定した先にファイルが存在するか
	- p オプションで開放したポートにアクセスできるか
```

### ホストの設定

#### 認証局証明書

コンテナ上のウェブサーバにホストから HTTPS で接続するために、必要に応じて実施する。

**ubuntu の場合**

```
sudo ln -s $(pwd)/www /usr/local/share/ca-certificates/toyca
sudo update-ca-certificates
```

**Firefox/Chrome**

```
sudo apt install libnss3-tools
```

各 CA のルート証明書をインストールする

```
install_cacert(){
 method=$1
 certdir=$2
 for cacert in $(ls ca/selfsign-ca-*/cacert.pem)
 do
  name=$(echo $cacert | sed -e 's@^ca/@@; s@/cacert.pem$@@;')
  certutil -A -n "${name}" -t "TC,C,T" -i ${cacert} -d ${method}:${certdir}
 done
}

# For cert8 (legacy - DBM)
for certDB in $(find ~/ -name "cert8.db")
do
 certdir=$(dirname ${certDB});
 install_cacert dbm $certdir
done

# For cert9 (SQL)
for certDB in $(find ~/ -name "cert9.db")
do
 certdir=$(dirname ${certDB});
 install_cacert sql $certdir
done
```

chrome なら chrome://settings/certificates の認証局 org-ToyCA でインストールされたことを確認できる。

**その他アプリケーションの場合**

各製品のドキュメント等参照

#### /etc/hosts

hosts ファイルに以下を加える

```
127.0.0.1       localhost ca.example.com ca.example.co.jp xn--u0h9a3d.xn--eckwd4c7cu47r2wf.jp
```

### ドキュメント・デモコンテナの生成・起動

```
docker build -t toyca .
docker-compose up -d -f Dockerfile/docker-compose.yml
```

- ドキュメント
  - http://localhost/
- デモ用ウェブサーバ
  - http://localhost/


### alpine の date ェ

gnu の date と busybox の date は違う。オフセット使うとわかる

[date コマンドつらい - bearmini's blog](https://bearmini.hatenablog.com/entry/2017/06/19/115255)
