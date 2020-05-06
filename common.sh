#!/bin/sh

if [ -n "${_TOYCA_COMMON_SH}" ]
then
    return 0
fi
_TOYCA_COMMON_SH=1

base_date(){
    :<<EOF
GMT のタイムスタンプを出すためにTZで修正する
EOF
    local base=$1
    tz=`date "+%:::z" | tr '\-+' '+-'`
    if [ -z "$tz" ]
    then
	date -u '+%Y%m%d%H%M%SZ'
    else
	date -u -d "$base $tz hours" '+%Y%m%d%H%M%SZ'
    fi
}

lifetime(){
    :<<EOF
証明書の有効期間を出力する
lifetime base offset
base : date コマンドのフォーマット 例:'+%Y/%m/01' 
offset : base に対するオフセット 例:'+%Y/%m/01' 
EOF
    local base=$1
    local offset=$2
    base_date $(date -d "${offset}" "${base}")
}

set_ca(){
    : <<EOF
CANAME と CATOP と設定(export)する
set_ca caname n
caname : ca名 例:selfsign-ca
n : ca世代 例:2
n が空の場合、caname に含まれているものとして扱う
EOF
    local caname=$1
    local n=$2
    if [ -z "$n" ]
    then
	export CANAME="${caname}"
    else
	export CANAME="${caname}-${n}"
    fi
    export CATOP="$(pwd)/ca/${CANAME}"
}

test_date(){
    ret=$(lifetime '+%Y/06/01' "0 years -5 months")
    echo $ret
    assertEquals 0 $?

    ret=$(lifetime '+%Y/06/01' "2 years -5 months")
    echo $ret
    assertEquals 0 $?
}

get_port(){
    :<<EOF
netstat で listen 状態になっていない、1024 番以上のポート番号を1つランダムに選ぶ
EOF
    port=1
    listen=1
    while [ $port -lt 1024 -o $listen -ne 0 ]
    do
	port=`od -vAn -N2 -tu2 < /dev/urandom | tr -d ' '`
	listen=`netstat -4tan | awk -v PORT=:$port '$4 ~ PORT { print }' | wc -l`
    done
    echo $port
}

genpkey(){
    :<<EOF
openssl genpkey を呼び出す
genpkey $key $alg $opt
key=./ca/server-ca-1/certs/www.example.com/key.pem
pass=./pass.txt
enc=aes256
alg=rsa
genpkey "$key" rsa rsa_keygen_bits:2048
genpkey "$key" ec ec_paramgen_curve:secp384r1 ec_param_enc:named_curve
? genpkey "$key" ec ec_paramgen_curve:P-256 ec_param_enc:named_curve
? genpkey "$key" ec ec_paramgen_curve:prime256v1 ec_param_enc:named_curve
? genpkey "$key" ED25519

EOF
    local key=$1
    shift
    local alg=$1
    shift
    local pkeyopt=""
    for opt in $*
    do
	pkeyopt=" $pkeyopt -pkeyopt $opt"
    done
    openssl genpkey -out "$key" -algorithm "$alg" $pkeyopt
    if [ ! $? ]
    then
	echo ng openssl genpkey -out "$key" -algorithm "$alg" $pkeyopt
	return 1
    fi
    if [ "$alg" == "rsa" ]
    then
	#[OpenSSL/genpkey - NORK's "HOW TO..." Wiki 略して「のうはうWiki」](https://wiki.ninth-nine.com/OpenSSL/genpkey)
	#> 実運用で必要だと思ったことは無いが、世の中には秘密鍵を暗号化しないといけないユースケースがあるようで、その場合の指定方法について調査した。
	#> 結論から言えば、ＲＳＡでのみ指定できる。ＥＣＤＳＡでは指定できない。未検証だがＥｄＤＳＡも指定できないと思う。
	#rsa のときのみ、enc- と付けて aes256 決め打ちで暗号化しておく。パスワードファイル決め打ち?
	b=$(basename $key)
	echo openssl pkey -in "$key" -out $(echo $key | sed -e "s/$b/enc-$b/") -aes256 -passout file:./pass.txt
	openssl pkey -in "$key" -out $(echo $key | sed -e "s/$b/enc-$b/") -aes256 -passout file:./pass.txt
	if [ ! $? ]
	then
	    # echo ng openssl pkey -in "$key" -out $(echo $f | sed -e "s/$b/enc-$b/") -aes256 -passin file:"./pass.txt"
	    return 1
	fi
    fi
    return 0
}

verify_certificate_and_key(){
    :<<EOF
cert.pem と key.pem が対になっているかどうかを確認する
EOF
    local cert_file=$1
    local key_file=$2
    local key_sha256=$(openssl pkey -in $key_file -pubout -outform pem | sha256sum)
    local cert_sha256=$(openssl x509 -in $cert_file -pubkey -noout -outform pem | sha256sum)
    diff <(echo $cert_sha256) <(echo $key_sha256)
}
is-edwards-enabled-in-client-hello(){
    :<<EOF
    TLS セッションをキャプチャした .pcap ファイル中に、CLIENT HELLO の sig_hash_alg で ed25519 または ed488 を有効にしたパケットが含まれる場合 0 を返す
    is-edwards-enabled-in-client-hello .pcap
EOF
    local CLIENT_HELLO=1
    local ED25515=0x0807
    local ED488=0x0808
    local pcap=$1
    local QUERY="\
        ssl.handshake.type == $CLIENT_HELLO \
        and ssl.handshake.sig_hash_alg == $ED25515 \
        and ssl.handshake.sig_hash_alg == $ED488"
    [ $(tshark -r $pcap "$QUERY" | wc | awk '{print $1}') == 0 ]
    local packets=$?
    echo $packets
    return $packets
}

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

verifyServer(){
    :<<EOF
証明書 $server_cert を $server_trust を信頼するCA証明書のリポジトリとして検証する
CApath では crl も探す。というか、-crlfile というオプションが man にはあるが、コマンドで指定するとエラーになるので CAfile に含めるしかない。順番は問われないようだ
EOF
    local cn=$1
    shift
    local leaf=$1
    local chain=$*
    local result="/tmp/$$-result.txt"
    local log="/tmp/$$-result.log"
    local server_cert=$(en_file "$leaf" "$cn" "cert")
    local server_trust="/tmp/$$-server-trust.pem"
    cat /dev/null > $server_trust
    for ca in $chain
    do
        ca_pem "$ca" "cacert" >> $server_trust
        ca_pem "$ca" "crl"    >> $server_trust
    done
    openssl verify -CAfile $server_trust -crl_check_all -purpose sslserver -issuer_checks -verbose $server_cert | tee >(grep ^error | wc -l > $result)
}

if [ "$0" = "-bash" ]
then
    return
fi
if [ $(basename $0) = "common.sh" ]
then
    . shunit2
fi
