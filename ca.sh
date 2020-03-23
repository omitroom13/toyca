#!/bin/bash
# openssl の CS.sh -newca を参照

if [ -n "${_TOYCA_CA_SH}" ]
then
    return 0
fi
. ./ca.env
. ./common.sh
. ./entity.sh

reload(){
    :<<EOF
スクリプトを書き直したときに再読込する
EOF
    unset _TOYCA_COMMON_SH
    unset _TOYCA_CA_SH
    unset _TOYCA_ENTITY_SH
}

init_ca_param(){
    :<<EOF
openssl に使用するパラメータを設定する
ここで定義した名前は続く処理で使用する
バグりやすいので終わったら unset_ca_param を呼ぶこと
EOF
    START=$1
    END=$2
    CN=$3
    DN=$4
    PKEY_ALG=$5
    PKEY_PARAM=$6
    echo init_ca_param $START $END $CN $DN $PKEY_ALG $PKEY_PARAM

    CAKEY=${CATOP}/private/cakey.pem
    CAKEY_NOPASS=${CATOP}/private/cakey-nopass.pem
    CAREQ=${CATOP}/careq.pem
    CACERT=${CATOP}/cacert.pem

    TOP=${CATOP}/certs/$CN
    key=${TOP}/key.pem
    req=${TOP}/req.pem
    cert=${TOP}/cert.pem

    REQ="openssl req -config $OPENSSL_CONFIG"
    CA="openssl ca -config $OPENSSL_CONFIG"
    PKCS12="openssl pkcs12"
}

unset_ca_param(){
    :<<EOF
init_ca_param で定義したパラメータを unset する
EOF
    unset START
    unset END
    unset CN
    unset DN
    unset CERT
    unset KEY
    unset CAKEY
    unset CAREQ
    unset CACERT
    unset TOP
    unset key
    unset req
    unset cert
    unset REQ
    unset CA
    unset PKCS12
    unset PKEY_ALG
    unset PKEY_PARAM
}

publish_crl(){
    :<<EOF
CRL 公開用ウェブサイト用にCRLを並べる
EOF
    local CATOP=$1
    local CN=$2
    CACRL=$(cd $CATOP && pwd)/crl/$(cat ${CATOP}/crlnumber).pem
    $CA -passin file:$PASS -gencrl -out $CACRL
    rm -f $CATOP/crl.pem
    ln -s $CACRL $CATOP/crl.pem
    cp $CACRL $PUBLISH/$CN.crl
}

newcert() {
    :<<EOF
これ obsolete, generate_certificate に移行ずみでよい?
EOF
    echo "newcert: expected to be obsoleted(but executed)!"
    exit 1
    init_ca_param $1 $2 $3 $4 $5 $6
    mkdir -p $TOP
    $REQ -new -keyout $key -out $req -passout file:$PASS -subj "$DN"
    $CA -batch -out $cert -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -extensions ext_ca -startdate $START -enddate $END \
	-infiles $req
    unset_ca_param
}

newca() {
    :<<EOF
    新規 root CAを作る. 中間の場合は generate_certificate を使う
EOF
    echo "newca"
    # START=$1
    # END=$2
    # CN=$3
    # DN=$4
    # PKEY_ALG=$5
    # PKEY_PARAM=$6
    init_ca_param $START $END $CN $DN $PKEY_ALG $PKEY_PARAM
    CERT=$7
    KEY=$8
    if [ -e ${CATOP} ]; then
	echo "$CN already exists." >&2
	return 1
    fi
    mkdir -p ${CATOP}
    mkdir -p ${CATOP}/certs
    mkdir -p ${CATOP}/crl
    mkdir -p ${CATOP}/newcerts
    mkdir -p ${CATOP}/private
    touch ${CATOP}/index.txt
    cat >${CATOP}/index.txt.attr<<EOF
unique_subject = no
EOF
    printf '%X' `date +%s` > ${CATOP}/serial
    echo '00' > ${CATOP}/crlnumber
    if [ -e "$CERT" -a -e "$KEY" ]
    then
	#CERT および KEY は上位CAで生成済みの公開鍵と秘密鍵なので、指定されていた場合ここで生成するのは下位(中間)CAということになる
	cp $CERT $CACERT
	cp $KEY $CAKEY
    else
	#CERT および KEY が設定されていない場合、ここで生成するのはルートCAということになる
	echo genpkey "$CAKEY" $PKEY_ALG $PKEY_PARAM
	genpkey "$CAKEY" $PKEY_ALG $PKEY_PARAM
	#$REQ -new -keyout $CAKEY -out $CAREQ -passout file:$PASS -subj "$DN"
	echo $REQ -new -key $CAKEY -out $CAREQ -subj "$DN"
	$REQ -new -key $CAKEY -out $CAREQ -subj "$DN"
	$CA -selfsign -batch -out $CACERT -keyfile $CAKEY \
	    -name ca_any -extensions ext_ca -startdate $START -enddate $END \
	    -infiles $CAREQ
	echo "ccccccc"
	#↓テストしていない
	openssl pkey -in "$CAKEY" -out "$CAKEY_NOPASS" -passin file:"$PASS"
    fi
    #cer は CRL と組でWeb公開に使う
    cp $CACERT $PUBLISH/$CN.cer
    #crt は /etc/ca-certificates.conf 用
    cp $CACERT $PUBLISH/$CN.crt
    publish_crl $CATOP $CN
    unset_ca_param
}

create_both(){
    export SAN=""
    mkdir -p $PUBLISH
    N=1
    echo "create_both:gen $N start"
    START_CA=$(lifetime '+%Y/%m/01' "-2 years 1 months")
    END_CA=$(lifetime '+%Y/%m/01' "2 years 1 months")
    START_EE=$(lifetime '+%Y/%m/01' "-2 years 1 months")
    END_EE=$(lifetime '+%Y/%m/01' "0 years 1 months")
    create_ca $N $START_CA $END_CA $START_EE $END_EE
    create_ee $N $START_CA $END_CA $START_EE $END_EE
    echo "create_both:gen $N end"
    N=2
    echo "create_both:gen $N start"
    START_CA=$(lifetime '+%Y/%m/01' "0 years 0 months")
    END_CA=$(lifetime '+%Y/%m/01' "4 years 1 months")
    START_EE=$(lifetime '+%Y/%m/01' "0 years 0 months")
    END_EE=$(lifetime '+%Y/%m/01' "2 years 1 months")
    create_ca $N $START_CA $END_CA $START_EE $END_EE
    create_ee $N $START_CA $END_CA $START_EE $END_EE
    echo "create_both:gen $N end"

    cross_root_ca 1 2 $START_CA $END_CA
    gen_nginx_conf
    return 0
}

create_ca(){
    : <<EOF
一通りの役割を持つCAを生成する
EOF
    local N=$1
    local START_CA=$2
    local END_CA=$3
    local START_EE=$4
    local END_EE=$4
    local cert=""
    local key=""
    for caname in selfsign-ca server-ca client-ca choroi-ca
    do
	echo $caname
	set_ca selfsign-ca $N
	local cn="$caname-$N"
	local dn="/O=ToyCA/CN=$cn"
	if [ "$caname" != "selfsign-ca" ]
	then
	    echo gen_cert_ca $START_CA $END_CA "$cn" "$dn" rsa rsa_keygen_bits:2048
	    gen_cert_ca $START_CA $END_CA "$cn" "$dn" rsa rsa_keygen_bits:2048
	    cert="$CATOP/certs/$cn/cert.pem"
	    key="$CATOP/certs/$cn/key.pem"
	fi
	export CATOP="$(pwd)/ca/$cn"
	echo newca $START_CA $END_CA "$cn" "$dn" rsa rsa_keygen_bits:2048 $cert $key
	newca $START_CA $END_CA "$cn" "$dn" rsa rsa_keygen_bits:2048 $cert $key
    done
    cert=""
    key=""
    cd www
    #cer と crt 同じ証明書があること、で WARNING が出力される
    c_rehash .
    cd ..
}

cross_root_ca(){
    :<<EOF
クロスルート証明書の生成
今の所適当
EOF
    echo cross_root_ca
    local old_n=$1
    local new_n=$2
    local START_CA=$3
    local END_CA=$4
    local caname="selfsign-ca"
    local new_caname="${caname}-${new_n}"
    local old_caname="${caname}-${old_n}"

    set_ca $caname $old_n
    N=$new_n
    CN=$new_caname
    DN="/O=ToyCA/CN=$CN"
    init_ca_param $START_CA $END_CA $CN $DN
    mkdir -p $TOP
    ln -s "$(pwd)/ca/${new_caname}/careq.pem" $req
    ln -s "$(pwd)/ca/${new_caname}/private/cakey.pem" $key
    #old CA で new CA の req/key に署名する
    $CA -batch -out $cert -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -extensions ext_ca -startdate $START -enddate $END \
	-infiles $req

    #各証明書の -im に cross を加えないといけない
    cross=./ca/server-ca-2/certs/ca.example.com
    cat $cross/cert.pem > $cross/cert-im-cross.pem
    cat $cross/cert-im.pem >> $cross/cert-im-cross.pem
    cat ./ca/selfsign-ca-1/certs/selfsign-ca-2/cert.pem >> $cross/cert-im-cross.pem
    cat ./ca/selfsign-ca-1/certs/selfsign-ca-2/cert.pem > ./ca/selfsign-ca-1/cacert-cross.pem
    cat ./ca/selfsign-ca-2/cacert.pem >> ./ca/selfsign-ca-1/cacert-cross.pem
    unset_ca_param

    set_ca $caname $new_n
    N=$old_n
    CN=$old_caname
    DN="/O=ToyCA/CN=$CN"
    init_ca_param $START_CA $END_CA $CN $DN
    mkdir -p $TOP
    ln -s "$(pwd)/ca/${old_caname}/careq.pem" $req
    ln -s "$(pwd)/ca/${old_caname}/private/cakey.pem" $key 
    #new CA で old CA の req/key に署名する
    $CA -batch -out $cert -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -extensions ext_ca -startdate $START -enddate $END \
	-infiles $req

    #各証明書の -im に cross を加えないといけない
    cross=./ca/server-ca-1/certs/ca.example.com
    cat $cross/cert.pem > $cross/cert-im-cross.pem
    cat $cross/cert-im.pem >> $cross/cert-im-cross.pem
    # cat ./ca/selfsign-ca-2/certs/selfsign-ca-2/cert.pem >> $cross/cert-im-cross.pem
    # cat ./ca/selfsign-ca-2/certs/selfsign-ca-2/cert.pem >> $cross/cert-im-cross.pem
    # cat ./ca/selfsign-ca-2/certs/selfsign-ca-2/cert.pem >> $cross/cert-im-cross.pem
    unset_ca_param
}

gen_nginx_conf(){
    :<<EOF
デモ用 nginx 設定(nginx.conf)の生成
EOF
    path=/etc/ssl/toyca
    sed -e "
    s@_SERVERNAME1_@ca.example.com@g;
    s@_SERVERNAME2_@ca.example.co.jp@g;
    s@_SERVERNAME3_@○△□.ドメイン名例.jp@g;
    s@_SERVERDISP3_@○△□.ドメイン名例.jp@;
    s@_SERVERNAME4_@ca.example.com@g;
    s@_SERVERDISP4_@かいぎょうなんかできるの？@;
    s@_SERVERNAME5_@ca.example.com@g;
    s@_SERVERNAME6_@ca.example.com@g;
" index.html.template > www/index.html
    sed -e "
    s@_WWW_@/usr/share/nginx/html@g;
    s@_SERVERNAME1_@ca.example.com@g;
    s@_CERT1_@$path/server-ca-2/certs/ca.example.com@g;

    s@_SERVERNAME2_@ca.example.co.jp@g;
    s@_CERT2_@$path/server-ca-2/certs/wildcard.example.com@g;

    s@_SERVERNAME3_@xn--u0h9a3d.xn--eckwd4c7cu47r2wf.jp@g;
    s@_CERT3_@$path/server-ca-2/certs/xn--u0h9a3d.xn--eckwd4c7cu47r2wf.jp@g;

    s@_SERVERNAME4_@ca.example.com@g;
    s@_CERT4_@$path/server-ca-2/certs/かいぎょうなんかできるの？@g;

    s@_SERVERNAME5_@ca.example.com@g;
    s@_CERT5_@$path/server-ca-2/certs/ca.example.com@g;

    s@_SERVERNAME6_@ca.example.com@g;
    s@_CERT6_@$path/server-ca-2/certs/ca.example.com@g;
    s@_CERT6CLIENT_@$path/client-ca-1@g;
    s@_CERT6TRUSTED_@$path/selfsign-ca-1@g;
" nginx.conf.template > www/nginx.conf
}

clean(){
    :<<EOF
    生成した証明書を削除
EOF
    rm -rf ca/*
    rm -rf www/*
}

if [ "$0" = "-bash" ]
then
    return
fi
if [ $(basename $0) = "ca.sh" ]
then
    CMD=$1
    shift
    case $CMD in	
	newca)
	    newca  $1 $2 $3 $4 $5 $6
	    ;;
	clean)
	    clean
	    ;;
	reload)
	    reload
	    ;;
	create_both)
	    create_both
	    ;;
	gen_cert_server)
	    #細かい設定抜きでサーバ証明書を生成したいとき
	    #ca : 認証局名(server-ca-1 など)
	    #cn : サーバ名(またはIPアドレス)
	    ca=$1
	    cn=$2
	    san=$3
	    alg=$4
	    param=$5
	    dn="/CN=${cn}"
	    set_ca $ca
	    start=$(lifetime '+%Y/%m/01' "-1 years 0 months")
	    end=$(lifetime '+%Y/%m/01' "1 years 0 months")
	    export SAN=$san
	    generate_certificate server $start $end "$cn" "$dn" "$alg" "$param"
	    ;;
	gen_cert_ocsp)
	    #細かい設定抜きでサーバ証明書を生成したいとき
	    #ca : 認証局名(server-ca-1 など)
	    #cn : サーバ名(またはIPアドレス)
	    ca=$1
	    cn=$2
	    san=$3
	    alg=$4
	    param=$5
	    dn="/CN=${cn}"
	    set_ca $ca
	    start=$(lifetime '+%Y/%m/01' "-1 years 0 months")
	    end=$(lifetime '+%Y/%m/01' "1 years 0 months")
	    export SAN=$san
	    generate_certificate ocsp $start $end "$cn" "$dn" "$alg" "$param"
	    ;;
	gen_cert_ca)
	    #細かい設定抜きで中間認証局を生成したいとき
	    #ca : 認証局名(server-ca-1 など)
	    #cn : CA名
	    ca=$1
	    cn=$2
	    san=$3
	    alg=$4
	    param=$5
	    dn=$6
	    if [[ -z "$dn" ]]; then dn="/CN=${cn}" ; fi
	    set_ca $ca
	    start=$(lifetime '+%Y/%m/01' "-1 years 0 months")
	    end=$(lifetime '+%Y/%m/01' "1 years 0 months")
	    export SAN=$san
	    generate_certificate ca $start $end "$cn" "$dn" "$alg" "$param"
	    ;;
	gen_nginx_conf)
	    gen_nginx_conf
	    ;;
	revoke)
	    ca=$1
	    dn=$2
	    export SAN=""
	    cn=$(echo "$dn" | sed -e 's@.*CN=\(.*\)$@\1@')
	    set_ca $ca
	    init_ca_param "" "" "$cn" "$dn" "" "" ""
	    serial=$(grep "$dn" $CATOP/index.txt | awk '{print $3}')
	    cert="$CATOP/certs/$serial-$cn/cert.pem"
	    if [[ -n $serial && -e $cert ]]
	    then
		$CA -revoke $cert
	    else
		echo "$dn, /CN=$cn or $cert not found in $ca"
	    fi
	    ;;
	*)
	    echo "Unknown arg $i" >&2
	    exit 1
	    ;;
    esac
    exit 0
fi
