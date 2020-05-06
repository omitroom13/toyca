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

各 CA のルート証明書をブラウザにインストールする

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

# For cert8 (legacy - DBM, firefox/thunderbird)
for certDB in $(find ~/ -name "cert8.db")
do
 certdir=$(dirname ${certDB});
 install_cacert dbm $certdir
done

# For cert9 (SQL, firefox/thunderbird/chrome)
for certDB in $(find ~/ -name "cert9.db")
do
 certdir=$(dirname ${certDB});
 install_cacert sql $certdir
done
```

- chrome なら chrome://settings/certificates の認証局 org-ToyCA でインストールされたことを確認できる
- 同じ CN の証明書をいくつも追加したときの影響は把握していない。古いものは都度削除したほうが良いかも
- その他アプリケーションの場合は各製品のドキュメント等参照

### IPアドレス・ホスト名

/etc/hosts などで以下のホスト名を参照できるようにしておく。

- ca.example.com
- ca.example.co.jp
- xn--u0h9a3d.xn--eckwd4c7cu47r2wf.jp

## lxd 

### コンテナ設定

lxd の細かい点についてはリポジトリ lxd を参照

### litespeed

コンパイル不要で http/3 対応ということで nginx から変更。

[Install OpenLiteSpeed from LiteSpeed Repositories • OpenLiteSpeed](https://openlitespeed.org/kb/install-ols-from-litespeed-repositories/)

ubuntu 20.4 未対応なので、bionic にする

```
lxc launch images:ubuntu/bionic/amd64 -c lxc.container.conf
```

マウント

```
lxc config device add $container toyca disk source=$(pwd) path=/opt/toyca
lxc config device add $container pki disk source=$(pwd)/www path=/etc/pki
lxc config device remove $container toyca
lxc config device remove $container pki
```

ホストからは

```
sudo ls /var/lib/lxd/containers/$container/rootfs
```

でアクセスできた。にあるみたいだが同期はしていないようだ。

```
lxc exec -- /bin/bash
apt update
apt install lightspeed

lxc image import 
lxc image list images:ubuntu/bionic/amd64
lxc launch images:ubuntu/bionic/amd64

lxc exec $container -- /bin/bash
apt update
wget -O - http://rpms.litespeedtech.com/debian/enable_lst_debian_repo.sh | bash
apt install openlitespeed
```

mysql やら php やら頼んでないパッケージを山盛りでインストールさせられるな。

```
cat ~/.config/lxc/config.yml 

systemctl start lshttpd
/usr/local/lsws/conf/httpd_config.conf

lxc info $container
```

表示されたIPの8088にアクセス

テストで区別する意味はないので、管理用UIの証明書はコンテンツと共用にしておく。
WebAdmin Settings - Listener adminListener > SSL > SSL Private Key & Certificate


```
$SERVER_ROOT/admin/conf/webadmin.key
$SERVER_ROOT/admin/conf/webadmin.crt
```

証明書チェインでないと正常と認識されない

lsws の設定ファイルは /usr/local/lsws/conf にある。

管理インタフェースが版管理しているように見えたが、普通に編集して再起動で良いみたいだ。

> The best and easiest way to edit the OpenLiteSpeed configuration is through the WebAdmin Console. When using WebAdmin, there is no need for you to remember OLS configuration syntax, and it is much easier for a beginner with no prior knowledge of OpenLiteSpeed. OLS configuration files are plain text. If you are an advanced OLS user and know OLS syntax, then you are certainly encouraged to use vi to edit the configuration file directly. Don't forget to restart OLS after any changes to the configuration.

[OpenLiteSpeed Configuration Examples • OpenLiteSpeed](https://openlitespeed.org/kb/ols-configuration-examples/)

```
/usr/local/lsws/bin/lswsctrl start
```

でサーバと管理インタフェースが起動する。systemctl のユニット lshttpd.service でも制御できる

```
journalctl -f --system --since today -u lshttpd.service
systemctl restart lshttpd
```

### litespeed ssl 設定

- http とは別ポートで受ける必要があるので、listner を追加する
- lisnter と vhost 紐付け
- listner か vhost で証明書設定

証明書の設定は最低限以下をやっておけば良い。マウントした 秘密鍵は nobody.nobody 権限で読めるようにしておく。でないと listener が起動しない。

- Private Key File
  - /opt/toyca/ca/server-ca-1/certs/ca.example.com/key.pem
- Certificate File	
  - /opt/toyca/ca/server-ca-1/certs/ca.example.com/cert-im.pem
- Chained Certificate
  - No
- CA Certificate Path
  - /etc/pki
- CA Certificate File
  - /opt/toyca/ca/server-ca-1/cacert.pem

コンテンツは Virtual Host Example で定義されている。
アクセスログは vhost 毎に分割されている

```
tail ../lsws/Example/logs/access.log 
```

### http/3

```
openssl s_client -connect ca.example.com:8443 -servername ca.example.com < /dev/null
...
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
```

```
sudo echo "バックグラウンドで tdpdump を実行するのでここで認可させる"
sudo tcpdump -s 0 -w /tmp/test.pcap -i lxdbr0 host 10.250.120.21 and port 8443
```

```
netstat -uanp
```

待受はしている

```
chrome --enable-quic
```

で url にアクセスさせたが chrome の最初から tcp で聞いていて、フォールバックにはなっていないな。chrome 側のもんだいなのか?

[litespeed_wiki:config:enable_quic [LiteSpeed Wiki]](https://www.litespeedtech.com/support/wiki/doku.php/litespeed_wiki:config:enable_quic)

### curl

chrome 側のアクセス時点で UDP にならなかったので、他のUAで確認してみる

[curl/HTTP3.md at master · curl/curl](https://github.com/curl/curl/blob/master/docs/HTTP3.md)

curl --http3 https://ca.example.com:8443 -I

bionic のパッケージ版 curl では流石に対応してなかった

```
apt install git cmake g++ golang libunwind-dev curl autoconf libtool
```

[curl/HTTP3.md at master · curl/curl](https://github.com/curl/curl/blob/master/docs/HTTP3.md)
の quiche version で BoringSSL, quiche, curl をビルドする

```
  HTTP3:            enabled (quiche)
```

なんで src の下に実行ファイルつくってんだ? まいいか

./src/curl --http3 https://www.facebook.com/  -v -s -o /dev/null

./src/curl --capath /etc/pki https://ca.example.com:8443/  -v -s -o /dev/null

これが ok なら次

./src/curl --capath /etc/pki --http3 https://ca.example.com:8443/  -v -s -o /dev/null

なんで名前引けているんだ?

コンパイルした curl なら使えるようになったな

```
root@main-garfish:/usr/local/curl# ./src/curl --version
curl 7.70.0-DEV (x86_64-pc-linux-gnu) libcurl/7.70.0-DEV BoringSSL quiche/0.3.0
Release-Date: [unreleased]
Protocols: dict file ftp ftps gopher http https imap imaps pop3 pop3s rtsp smb smbs smtp smtps telnet tftp 
Features: alt-svc AsynchDNS HTTP3 HTTPS-proxy IPv6 Largefile NTLM NTLM_WB SSL UnixSockets
```

え curl て http 以外でも使えるの? しらんかった

```
root@main-garfish:/usr/local/curl# ./src/curl --capath /etc/pki --http3 https://ca.example.com:8443/  -v -s -o /dev/null
*   Trying 127.0.0.1:8443...
```

localhost でも応答がない. FB には curl でアクセス出来ているから、これは litespeed にも問題があるということ?

http3 は最初のパケットに応答していないので載らないな

Server Configuration > Tuning > QUIC

にも設定項目があるが、デフォルトで有効になっているので関係ないか。
正直わからん、飛ばす。

## OCSP
 
openssl ocsp-issuer [CA証明書]-serial [失効確認する証明書のシリアル番号（10進数か、「0x」を前につけた16進数)]-url [OCSPレスポンダーのURL（ホスト名：ポート番号（デフォルトでは2560））]-VAfile [OCSP証明書]-CAfile [CA証明書]

Apr 18 08:08:53 main-garfish ocspd[17144]: [crl.c:230] [ERROR] CRL signature is NOT verified [Code: 0, CA Subject: O=ToyCA, CN=selfsign-ca-1]!

www 更新してないからとか?

openssl crl -CAfile /usr/etc/ocspd/certs/cacert.pem -in /usr/etc/ocspd/crls/selfsign-ca-1.crl 
verify OK

openssl crl -CAfile /usr/etc/ocspd/certs/cacert.pem -in /usr/etc/ocspd/crls/server-ca-1.crl 
verify OK

??

cd /opt/toyca/ca/selfsign-ca-1
openssl ocsp -index index.txt -CA cacert.pem -rsigner cacert.pem -rkey private/cakey.pem -port 2560
openssl ocsp -issuer cacert.pem -nonce -CAfile cacert.pem -url http://localhost:2560/ -cert cacert.pem

openssl ocsp では確認できるが、index.txt を使うので一つのCAしか指定できないな。

80 番で vhost を動作させて cert/crl 置き場にアクセスできるようにすると起動した
ローカルの crl を読み込んでくれないってことかなんで? パスの指定は cacert と同じはずなのに。。。
? パス指定でも死ななくなった? working directory 指定が効いた?

設定ファイル
/usr/var/run/ocspd.pid

www-data

うーん OCSP レスポンダまともなやつなくない?
ここまで面倒なら URI で振り分けてポートは集約するとして、 openssl から CA 数分起動してしまうほうがらくかもな。

port=12560
for ca in selfsign-ca-1 server-ca-1 choroi-ca-1
do
port=$(($port+1))
cat <<EOF > /etc/systemd/system/ocsp-$ca.service 
[Unit]
Description=OCSP $ca
After=network.target

[Service]
SyslogIdentifier=ocsp-$ca
Type=simple
WorkingDirectory=/opt/toyca/ca/$ca
ExecStart=/usr/bin/openssl ocsp -index index.txt -CA cacert.pem -rsigner cacert.pem -rkey private/cakey.pem -port $port
PIDFile=/var/run/ocsp-$ca.pid

[Install]
WantedBy=multi-user.target
EOF
done

systemctl daemon-reload
systemctl start ocsp-selfsign-ca-1
systemctl status ocsp-selfsign-ca-1

上記で openssl で起動して openlitespeed で

- virtual host の external app と context で起動プロセスに振り分け
 cat /usr/local/lsws/conf/vhosts/Example/vhconf.conf

extprocessor selfsign-ca-1 {
  type                    proxy
  address                 http://ca.example.com:12561
  maxConns                1
  initTimeout             10
  retryTimeout            10
  respBuffer              0
}

extprocessor server-ca-1 {
  type                    proxy
  address                 http://ca.example.com:12562
  maxConns                1
  initTimeout             10
  retryTimeout            10
  respBuffer              0
}

extprocessor choroi-ca-1 {
  type                    proxy
  address                 http://ca.example.com:12563
  maxConns                1
  initTimeout             10
  retryTimeout            10
  respBuffer              0
}

context /ocsp/selfsign-ca-1 {
  type                    proxy
  handler                 selfsign-ca-1
  addDefaultCharset       off
}

context /ocsp/server-ca-1 {
  type                    proxy
  handler                 server-ca-1
  addDefaultCharset       off
}

context /ocsp/choroi-ca-1 {
  type                    proxy
  handler                 choroi-ca-1
  addDefaultCharset       off
}

でどうにかなるな。

では AIA の url をこれベースに変更しよう。

- http://ca.example.com/ocsp/selfsign-ca-1
- http://ca.example.com/ocsp/server-ca-1
- http://ca.example.com/ocsp/choroi-ca-1

## gh-pages

- 設定方法はリポジトリ project/git を参照
- doc/00-setup.md (このファイル)は公開しない。 .gitignore に入れる
- リリースする契機を決めていないので、このページを更新するのは整形されたHTMLで読みたくなったら、としておく
