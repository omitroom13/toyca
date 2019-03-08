#!/bin/bash

. ./ca.sh

en_file(){
    :<<EOF
CA $caname で $cn について生成されたファイル $type のパスを返す
EOF
    local caname=$1
    local cn=$2
    local type=$3
    case $caname in
	"server-ca-1" | "server-ca-2" | "client-ca-1" | "client-ca-2")
	    local id=`grep "/CN=${cn}" ca/${caname}/index.txt | cut -f 4 | head -n 1`
	    cn="${id}-${cn}"
	;;
    esac
    echo "$(pwd)/ca/$caname/certs/${cn}/${type}.pem"
}
ca_pem(){
    :<<EOF
CA $caname について生成されたファイル $type を PEM 形式で返す
EOF
    local caname=$1
    local type=$2
    case "$type" in
	"cacert")
	    openssl x509 -outform PEM -in $(pwd)/ca/$caname/$type.pem
	    ;;
	"crl")
	    openssl crl  -outform PEM -in $(pwd)/ca/$caname/$type.pem
	    ;;
	"crossroot")
	    case "$caname" in
		"selfsign-ca-1")
		    openssl x509 -outform PEM -in "$(pwd)/ca/$caname/certs/selfsign-ca-2/cert.pem"
		    ;;
		"selfsign-ca-2")
		    openssl x509 -outform PEM -in "$(pwd)/ca/$caname/certs/selfsign-ca-1/cert.pem"
		    ;;
		*)
		    echo "ca_pem:unknown ca:$caname" >&2
		    return 1
		    ;;
	    esac
	    ;;
	*)
	    echo "ca_pem:unknown type:$type" >&2
	    return 1
	    ;;
    esac
    return 0
}
s_server(){
    :<<EOF
openssl s_server $server_cert をもつサーバを起動する
起動したプロセスのIDを pid にセットする
ポート番号を pid にセットする
EOF
    #call 
    #set variable "port" as server local(127.0.0.1) port for s_client connection
    #set variable "pid" as server proccess id to finish test
    local type=$1
    local server_cert=$2
    local server_key=$3
    local server_trust=$4
    port=`get_port`
    local verify="-verify 4"
    if [ "$type" = "client" ]
    then
       verify="-Verify 4"
    fi
    echo "" | \
	openssl s_server \
		$verify -tls1_2 \
		-accept $port -CAfile $server_trust \
		-cert $server_cert -key $server_key -pass file:pass.txt \
		> /dev/null 2>&1 &
    pid=$!
    sleep 1
}
s_client(){
    local result=$1
    local port=$2
    local cn=$3
    local client_trust=$4
    local client_cert=$5
    local client_key=$6
    local client_auth=""
    if [ -e "${client_cert}" -a -e "${client_key}" ]
    then
	client_auth="-cert ${client_cert} -key ${client_key}"
    fi
    openssl s_client -pass file:pass.txt -tls1_2 -quiet -no_ign_eof \
	    -connect localhost:$port -CAfile $client_trust -servername $cn \
	    $client_auth \
	    </dev/null | tee >(grep err | wc -l > $result)
}
oneTimeSetUp(){
    return 0
}
oneTimeTearDown(){
    return 0
}
setUp(){
    #rm -f /tmp/$$-*.pem
    :
}

tearDown(){
    #rm -f /tmp/$$-*.pem
    echo "------------------------------------------------------"
}
testCreate() {
    clean
    assertEquals 0 $?
    create_both
    assertEquals 0 $?
}
testVerifyServer(){
    :<<EOF
証明書 $server_cert を $server_trust を信頼するCA証明書のリポジトリとして検証する
CApath では crl も探す。というか、-crlfile というオプションが man にはあるが、コマンドで指定するとエラーになるので CAfile に含めるしかない。順番は問われないようだ
EOF
    local result="/tmp/$$-result.txt"
    local log="/tmp/$$-result.log"
    local server_cert=$(en_file "server-ca-1" "ca.example.com" "cert")
    local server_trust="/tmp/$$-server-trust.pem"
    ca_pem "selfsign-ca-1" "cacert"  > $server_trust
    ca_pem "selfsign-ca-1" "crl"    >> $server_trust
    ca_pem "server-ca-1" "cacert"   >> $server_trust
    ca_pem "server-ca-1" "crl"      >> $server_trust
    openssl verify -CAfile $server_trust -crl_check_all -purpose sslserver -issuer_checks -verbose $server_cert | tee >(grep ^error | wc -l > $result)
    assertEquals 0 $(cat $result)
}
testVerifyCrossRoot(){
    :<<EOF
クロスルート証明書(OldWithNew, NewWithOld)を検証する。
比較のために通常の証明書(NewWithNew, OldWithOld)も検証する
EOF
    local cn="ca.example.com"
    local result="/tmp/$$-result.log"
    local server_trust="/tmp/$$-server-trust.pem"
    local server_cert=$(en_file "server-ca-1" "ca.example.com" "cert")
    #OldWithOld
    ca_pem "selfsign-ca-1" "cacert"  > $server_trust
    ca_pem "selfsign-ca-1" "crl"    >> $server_trust
    ca_pem "server-ca-1" "cacert"   >> $server_trust
    ca_pem "server-ca-1" "crl"      >> $server_trust
    openssl verify -CAfile $server_trust -crl_check_all -purpose sslserver -issuer_checks -verbose $server_cert | tee >(grep ^error | wc -l > $result)
    assertEquals 0 $(cat $result)

    #OldWithNew(cross root:for new client)
    ca_pem "selfsign-ca-2" "cacert"     > $server_trust
    ca_pem "selfsign-ca-2" "crl"       >> $server_trust
    ca_pem "selfsign-ca-2" "crossroot" >> $server_trust
    ca_pem "selfsign-ca-1" "crl"       >> $server_trust
    ca_pem "server-ca-1" "cacert"      >> $server_trust
    ca_pem "server-ca-1" "crl"         >> $server_trust
    openssl verify -CAfile $server_trust -crl_check_all -purpose sslserver -issuer_checks -verbose $server_cert | tee >(grep ^error | wc -l > $result)
    assertEquals 0 $(cat $result)

    local server_cert=$(en_file "server-ca-2" "ca.example.com" "cert")
    #NewWithNew
    ca_pem "selfsign-ca-2" "cacert"  > $server_trust
    ca_pem "selfsign-ca-2" "crl"    >> $server_trust
    ca_pem "server-ca-2" "cacert"   >> $server_trust
    ca_pem "server-ca-2" "crl"      >> $server_trust
    openssl verify -CAfile $server_trust -crl_check_all -purpose sslserver -issuer_checks -verbose $server_cert | tee >(grep ^error | wc -l > $result)
    assertEquals 0 $(cat $result)

    #NewWithOld(cross root:for old client)
    ca_pem "selfsign-ca-1" "cacert"     > $server_trust
    ca_pem "selfsign-ca-1" "crl"       >> $server_trust
    ca_pem "selfsign-ca-1" "crossroot" >> $server_trust
    ca_pem "selfsign-ca-2" "crl"       >> $server_trust
    ca_pem "server-ca-2" "cacert"      >> $server_trust
    ca_pem "server-ca-2" "crl"         >> $server_trust
    openssl verify -CAfile $server_trust -crl_check_all -purpose sslserver -issuer_checks -verbose $server_cert | tee >(grep ^error | wc -l > $result)
    assertEquals 0 $(cat $result)

    rm -f /tmp/$$-*
}
testConnect(){
    #中間認証局証明書をサーバ証明書に入れる
    local cn="ca.example.com"
    local result="/tmp/$$-result.log"
    local server_trust="/tmp/$$-server-trust.pem"
    local client_trust="/tmp/$$-client-trust.pem"
    local server_cert="/tmp/$$-server-cert.pem"
    local server_key=$(en_file "server-ca-1" "$cn" "key")
    openssl x509 -outform PEM -in $(en_file "server-ca-1" "$cn" "cert") > $server_cert
    ca_pem "server-ca-1"   "cacert"  > $server_trust
    ca_pem "selfsign-ca-1" "cacert" >> $server_trust
    ca_pem "selfsign-ca-1" "cacert"  > $client_trust
    local port=0
    local pid=0
    s_server "server" $server_cert $server_key $server_trust
    s_client $result $port $cn $client_trust
    assertEquals 0 $(cat $result)
    # 停止している？
    # kill $pid
}
testConnectCrossroot(){
    local cn="ca.example.com"
    local result="/tmp/$$-result.log"
    local server_trust="/tmp/$$-server.pem"
    local client_trust="/tmp/$$-client.pem"
    local server_cert=$(en_file "server-ca-2" "$cn" "cert")
    local server_key=$(en_file "server-ca-2" "$cn" "key")
    ca_pem "server-ca-2" "cacert"       > $server_trust
    ca_pem "server-ca-1" "cacert"      >> $server_trust
    ca_pem "selfsign-ca-1" "crossroot" >> $server_trust
 
    #クロスルート NewWithOld New サーバ Old クライアント(中間証明書を利用できるか)
    ca_pem "selfsign-ca-1" "cacert" > $client_trust
    local port=0
    local pid=0
    s_server "server" $server_cert $server_key $server_trust
    s_client $result $port $cn $client_trust
    assertEquals 0 $(cat $result)
    # kill $pid
    #クロスルート NewWithOld New サーバ New クライアント(中間証明書を無視できるか)
    ca_pem "selfsign-ca-2" "cacert" > $client_trust
    local port=0
    local pid=0
    s_server "server" $server_cert $server_key $server_trust
    s_client $result $port $cn $client_trust
    assertEquals 0 $(cat $result)
    # kill $pid
}
testConnectClientAuth(){
    #クライアント証明書有無
    local cn="ca.example.com"
    local result="/tmp/$$-result.log"
    local server_trust="/tmp/$$-server.pem"
    local client_trust="/tmp/$$-client.pem"
    local server_cert=$(en_file "server-ca-1" "$cn" "cert")
    local server_key=$(en_file "server-ca-1" "$cn" "key")
    #for server cert auth
    ca_pem "server-ca-1" "cacert"    > $server_trust
    ca_pem "selfsign-ca-1" "cacert"  > $client_trust
    #for client cert auth
    cn="john.doe"
    local client_cert=$(en_file "client-ca-1" "$cn" "cert")
    local client_key=$(en_file "client-ca-1" "$cn" "key")
    ca_pem "selfsign-ca-1" "cacert" >> $server_trust
    ca_pem "client-ca-1" "cacert"   >> $client_trust
    local port=0
    local pid=0
    s_server "server" $server_cert $server_key $server_trust
    s_client $result $port "ca.example.com" $client_trust $client_cert $client_key
    assertEquals 0 $(cat $result)
    #kill $pid
}
testConnectCrossRootClientAuth(){
    #クライアント証明書有無
    local cn="ca.example.com"
    local result="/tmp/$$-result.log"
    local server_trust="/tmp/$$-server.pem"
    local client_trust="/tmp/$$-client.pem"
    #for server cert auth
    local server_cert=$(en_file "server-ca-2" "$cn" "cert")
    local server_key=$(en_file "server-ca-2" "$cn" "key")
    ca_pem "server-ca-2" "cacert"    > $server_trust
    ca_pem "selfsign-ca-2" "cacert"  > $client_trust
    #for client cert auth
    cn="john.doe"
    local client_cert=$(en_file "client-ca-2" "$cn" "cert")
    local client_key=$(en_file "client-ca-2" "$cn" "key")
    ca_pem "selfsign-ca-2" "cacert" >> $server_trust
    ca_pem "client-ca-2" "cacert"   >> $client_trust
    #cross root, send it to old client for server cert auth
    ca_pem "selfsign-ca-1" "crossroot" >> $server_trust

    #cross root, recv client cert from old for client auth
    ca_pem "selfsign-ca-2" "crossroot" >> $server_trust
    #server setup
    local port=0
    local pid=0
    s_server "server" $server_cert $server_key $server_trust
    s_client $result $port "ca.example.com" $client_trust $client_cert $client_key
    assertEquals 0 $(cat $result)
    # kill $pid

    #for server cert auth
    ca_pem "selfsign-ca-1" "cacert"  > $client_trust
    ca_pem "client-ca-1" "cacert"   >> $client_trust
    #クライアントに新中間認証局証明書をインストールしないと相互に認証できない？？それはありえんでしょ
    #ウェブサーバによくある、サーバ証明書に中間認証局証明書を入れた形での認証ができていないので、これは実際のウェブサーバで検証するしかなさそう
    ca_pem "selfsign-ca-1" "crossroot" >> $client_trust
    	
    cn="john.doe"
    client_cert=$(en_file "client-ca-1" "$cn" "cert")
    client_key=$(en_file "client-ca-1" "$cn" "key")
    local port=0
    local pid=0
    s_server "server" $server_cert $server_key $server_trust
    s_client $result $port "ca.example.com" $client_trust $client_cert $client_key
    assertEquals 0 $(cat $result)
    # kill $pid
}
testNginx() {
    local cn="ca.example.com"
    local id=`grep "/CN=${cn}" ca/server-ca-1/index.txt | cut -f 4 | head -n 1`
    local _WWW_="$(pwd)/www"
    local _CERT_="/tmp/$$"
    mkdir -p $_CERT_
    local _SERVER_NAME_1_="ca.example.com"
    local _SERVER_NAME_2_="ca.example.co.jp"
    local _SERVER_NAME_3_="xn--u0h9a3d.xn--eckwd4c7cu47r2wf.jp"
    local _SERVER_NAME_4_="ca.example.com"
    local _SERVER_NAME_5_="ca.example.com"
    local _SERVER_NAME_6_="ca.example.com"
    sed -e "
       s|_WWW_|$_WWW_|;
       s|_CERT_|$_CERT_|; 
       s|_SERVER_NAME_1_|$_SERVER_NAME_1_|; 
       s|_SERVER_NAME_2_|$_SERVER_NAME_2_|; 
       s|_SERVER_NAME_3_|$_SERVER_NAME_3_|; 
       s|_SERVER_NAME_4_|$_SERVER_NAME_4_|; 
       s|_SERVER_NAME_5_|$_SERVER_NAME_5_|; 
       s|_SERVER_NAME_6_|$_SERVER_NAME_6_|; 
    " nginx.conf.template > nginx.conf
    ca_pem "selfsign-ca-2" "cacert"  > $_CERT_/cacert.pem
    #？ここは selfsign-ca-2/selfsign-ca-1 でもいいのだろうか？
    ca_pem "selfsign-ca-1" "cacert" >> $_CERT_/cacert.pem
    cp index.html $_WWW_/
    #
    echo 1
    cp $(en_file "server-ca-2" $_SERVER_NAME_1_ "cert-im") $_CERT_/cert-im.1.pem
    cp $(en_file "server-ca-2" $_SERVER_NAME_1_ "key-nopass") $_CERT_/key-nopass.1.pem
    #ワイルドカードを指定すること
    _SERVER_NAME_2_="wildcard.example.com"
    echo 2
    cp $(en_file "server-ca-2" $_SERVER_NAME_2_ "cert-im") $_CERT_/cert-im.2.pem
    cp $(en_file "server-ca-2" $_SERVER_NAME_2_ "key-nopass") $_CERT_/key-nopass.2.pem
    #400 bad request になる？
    echo 3
    cp $(en_file "server-ca-2" $_SERVER_NAME_3_ "cert-im") $_CERT_/cert-im.3.pem
    cp $(en_file "server-ca-2" $_SERVER_NAME_3_ "key-nopass") $_CERT_/key-nopass.3.pem
    # 400 Bad Request SSL cert error
    echo 4
    cp $(en_file "server-ca-2" $_SERVER_NAME_4_ "cert-im") $_CERT_/cert-im.4.pem
    cp $(en_file "server-ca-2" $_SERVER_NAME_4_ "key-nopass") $_CERT_/key-nopass.4.pem
    #
    #？クロスルートの順番は決まっている？
    echo 5
    cat $(en_file "server-ca-2" $_SERVER_NAME_5_ "cert-im") > $_CERT_/cert-im.5.pem
    ca_pem "selfsign-ca-2" "crossroot" >> $_CERT_/cert-im.5.pem
    cp $(en_file "server-ca-2" $_SERVER_NAME_5_ "key-nopass") $_CERT_/key-nopass.5.pem
    #
    echo 6
    cat $(en_file "server-ca-2" $_SERVER_NAME_6_ "cert-im") > $_CERT_/cert-im.6.pem
    ca_pem "selfsign-ca-2" "crossroot" >> $_CERT_/cert-im.6.pem
    cp $(en_file "server-ca-2" $_SERVER_NAME_6_ "key-nopass") $_CERT_/key-nopass.6.pem
    # echo "setup web server. if ready, press enter"
    # read enter
    # cn="john.doe"
    # id=`grep "/CN=${cn}" ca/client-ca-1/index.txt | cut -f 4`
    # dir="./ca/client-ca-1/certs/${id}-${cn}"
    # openssl s_client -brief -connect www.example.com:443 -pass file:pass.txt -tls1_2 -CApath ./www/ -cert ${dir}/cert.pem -key ${dir}/key.pem < /dev/null
    # #s_client $result $port "www.example.com" $client_trust  $client_cert $client_key
    # assertEquals 0 $?
}

. shunit2

#revocation check

# firefox でクライアントエラーがでるとどこがおかしいか全然わからんぞ？？？？
# s_client のみどころ
# Certificate chain
#  0 s:/CN=www.example.com
#    i:/O=ToyCA/CN=server-ca-2
#  1 s:/O=ToyCA/CN=server-ca-2
#    i:/O=ToyCA/CN=selfsign-ca-2
# -----END CERTIFICATE-----
# subject=/CN=www.example.com
# issuer=/O=ToyCA/CN=server-ca-2
# ---
# Acceptable client certificate CA names
# /O=ToyCA/CN=selfsign-ca-2
# /O=ToyCA/CN=selfsign-ca-1
# /O=ToyCA/CN=client-ca-2
# Start Time: 1478650539
# Timeout   : 7200 (sec)
# Verify return code: 0 (ok)
