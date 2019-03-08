## インストール

### 動作環境

- ubuntu
  - git
  - openssl
  - shunit2
- Docker

### 諸々生成

```
git clone https://github.com/omitroom13/toyca
cd toyca
```

ドキュメント生成。 Sphinx が必要

```
pushd doc
mkdir _static
make html
popd
```

デモ用CAの生成

```
./ca.sh clean
./ca.sh create_both
```

単体テスト

```
./test.sh
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

# CA file to install (CUSTOMIZE!)
install_cacert(){
 method=$1
 certdir=$2
 for cacert in $(ls ca/selfsign-ca-*/cacert.pem)
 do
  name=$(echo $cacert | sed -e 's@^ca/@@; s@/cacert.pem$@@;')
  certutil -A -n "${name}" -t "TCu,Cu,Tu" -i ${cacert} -d ${method}:${certdir}
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

> Notice: Trust flag u is set automatically if the private key is present.
これなんだっけ?

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
