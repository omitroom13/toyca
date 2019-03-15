## インストール

### 動作環境

- ubuntu
  - git
  - openssl
  - shunit2
- Docker

### 諸々生成

```
docker pull library/nginx
git clone https://github.com/omitroom13/toyca
cd toyca
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

sudo chown -R $(id -u):$(id -


PKEY_ALG=
PKEY_PALAM="ec_paramgen_curve:P-256 ec_param_enc:named_curve"


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
docker-compose up -d
```

- ドキュメント
  - http://localhost/
- デモ用ウェブサーバ
  - http://localhost/


### alpine の date ェ

gnu の date と busybox の date は違う。オフセット使うとわかる

[date コマンドつらい - bearmini's blog](https://bearmini.hatenablog.com/entry/2017/06/19/115255)
