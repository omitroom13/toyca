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
    date -u -d "$base $tz hours" '+%Y%m%d%H%M%SZ'
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
genpkey $key $pass $enc $alg $opt
key=./ca/server-ca-1/certs/www.example.com/key.pem
pass=./pass.txt
enc=aes256
alg=rsa
genpkey "$key" "$key_nopass" "$pass" "$enc" rsa rsa_keygen_bits:2048
genpkey "$key" "$key_nopass" "$pass" "$enc" ec ec_paramgen_curve:secp384r1 ec_param_enc:named_curve
? genpkey "$key" "$key_nopass" "$pass" "$enc" ec ec_paramgen_curve:P-256 ec_param_enc:named_curve
? genpkey "$key" "$key_nopass" "$pass" "$enc" ec ec_paramgen_curve:prime256v1 ec_param_enc:named_curve
EOF
    local key=$1
    shift
    local key_nopass=$1
    shift
    local pass=$1
    shift
    local enc=$1
    shift
    local alg=$1
    shift
    local pkeyopt=""
    for opt in $*
    do
	pkeyopt=" $pkeyopt -pkeyopt $opt"
    done
    openssl genpkey -out "$key" -pass file:"$pass" -"$enc" -algorithm "$alg" $pkeyopt
    openssl pkey -in "$key" -out "$key_nopass" -passin file:"$pass"
}

if [ "$0" = "-bash" ]
then
    return
fi
if [ $(basename $0) = "common.sh" ]
then
    . shunit2
fi
