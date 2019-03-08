#!/bin/bash

if [ -n "${_TOYCA_ENTITY_SH}" ]
then
    return 0
fi
_TOYCA_ENTITY_SH=1

. ./ca.env
. ./common.sh

gen_cert_ca() {
    : <<EOF
ca.cnf の ext_ca セクションを使用して中間CA証明書を生成する(extension に CA:true がついているなど)
EOF
    init_ca_param $*
    if [ `echo $TOP | grep $(pwd)` ]
    then
	rm -rf $TOP
    else
	echo "WARNING $TOP is not subdirectory of $(pwd). rm -f canceled."
    fi
    mkdir -p $TOP
    #$REQ -new -newkey ec:<(openssl ecparam -name prime256v1) 
    key_nopass="${TOP}/key-nopass.pem"
    genpkey "$key" "$key_nopass" "$PASS" aes256 rsa rsa_keygen_bits:2048
    $REQ -new -key "$key" -out "$req" -passin file:$PASS -subj "$DN"
    # $REQ -new -newkey rsa:2048 \
    # 	 -keyout $key -out $req -passout file:$PASS -subj "$DN"
    $CA -batch -out $cert -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -extensions ext_enterprise -startdate $START -enddate $END \
	-infiles $req
    if [ ! -s "$cert" ]
    then
	cat <<EOF 
証明書の生成に失敗
    $REQ -new -newkey rsa:2048 \
	 -keyout $key -out $req -passout file:$PASS -subj "$DN"
    $CA -batch -out $cert -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -extensions ext_enterprise -startdate $START -enddate $END \
	-infiles $req
EOF
	exit 1
    fi
    unset_ca_param
}

gen_cert_client() {
    : <<EOF
クライアント証明書を生成する
EOF
    init_ca_param $*
    if [ `echo $TOP | grep $(pwd)` ]
    then
	rm -rf $TOP
    else
	echo "WARNING $TOP is not subdirectory of $(pwd). rm -f canceled."
    fi
    mkdir -p $TOP
    key_nopass="${TOP}/key-nopass.pem"
    genpkey "$key" "$key_nopass" "$PASS" aes256 ec ec_paramgen_curve:P-256 ec_param_enc:named_curve
    $REQ -new -key "$key" -out "$req" -passin file:$PASS -subj "$DN"
    # $REQ -new -newkey ec:<(openssl ecparam -name prime256v1) \
    # 	 -keyout $key -out $req -passout file:$PASS -subj "$DN"
    $CA -batch -out $cert -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -policy policy_any -extensions ext_client -startdate $START -enddate $END \
	-infiles $req
    if [ ! -s "$cert" ]
    then
	cat <<EOF 
証明書の生成に失敗
    $REQ -new -newkey ec:<(openssl ecparam -name prime256v1) \
	 -keyout $key -out $req -passout file:$PASS -subj "$DN"
    $CA -batch -out $cert -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -policy policy_any -extensions ext_client -startdate $START -enddate $END \
	-infiles $req
EOF
	exit 1
    fi
    pkcs12=${TOP}/pkcs12.pfx
    $PKCS12 -export -in "$cert" -inkey "$key" -out "$pkcs12" -certfile $CACERT -passin file:$PASS -passout file:$PASS
    serial=`openssl x509 -in $cert -noout -serial | sed -e 's/^serial=//'`
    #docker/nginx で使うのでコピーをおいておく
    cp -r $TOP $CATOP/certs/$serial-$CN
    unset_ca_param
}

gen_cert_server() {
    :<<EOF
p256v1 は対応しないVAなんかがあったりするので RSA:2048 にしておく
EOF
    init_ca_param $*
    if [ `echo $TOP | grep $(pwd)` ]
    then
	rm -rf $TOP
    else
	echo "WARNING $TOP is not subdirectory of $(pwd). rm -f canceled."
    fi
    mkdir -p $TOP
    key_nopass="${TOP}/key-nopass.pem"
    genpkey "$key" "$key_nopass" "$PASS" aes256 rsa rsa_keygen_bits:2048
    $REQ -new -key "$key" -out "$req" -passin file:$PASS -subj "$DN"
    $CA -batch -out "$cert" -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -policy policy_any -extensions ext_server -startdate $START -enddate $END \
	-infiles "$req"
    if [ ! -s "$cert" ]
    then
	cat <<EOF
証明書の生成に失敗
    $REQ -new -newkey rsa:2048 \
	 -keyout "$key" -out "$req" -passout file:$PASS -subj "$DN"
    $CA -batch -out "$cert" -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -policy policy_any -extensions ext_server -startdate $START -enddate $END \
	-infiles "$req"
EOF
	exit 1
    fi
    cert_im=${TOP}/cert-im.pem
    pkcs12=${TOP}/pkcs12.pfx
    openssl x509 -in $cert    > ${cert_im}
    openssl x509 -in $CACERT >> ${cert_im}
    $PKCS12 -export -in "$cert" -inkey "$key" -out "$pkcs12" -certfile $CACERT -passin file:$PASS -passout file:$PASS

    serial=`openssl x509 -in $cert -noout -serial | sed -e 's/^serial=//'`
    #docker/nginx で使うのでコピーをおいておく
    cp -r $TOP $CATOP/certs/$serial-$CN
    unset_ca_param
}

gen_cert_server_p256v1() {
    :<<EOF
p256v1 での証明書生成。どこからも呼ばれるようになっていない。
サンプルとして関数にしているだけ。
EOF
    init_ca_param $*
    if [ `echo $TOP | grep $(pwd)` ]
    then
	rm -rf $TOP
    else
	echo "WARNING $TOP is not subdirectory of $(pwd). rm -f canceled."
    fi
    mkdir -p $TOP
    key_nopass="${TOP}/key-nopass.pem"
    genpkey "$key" "$key_nopass" "$PASS" aes256 ec ec_paramgen_curve:P-256 ec_param_enc:named_curve
    $REQ -new -key "$key" -out "$req" -passin file:$PASS -subj "$DN"
    # $REQ -new -newkey ec:<(openssl ecparam -name prime256v1) \
    # 	 -keyout "$key" -out "$req" -passout file:$PASS -subj "$DN"
    $CA -batch -out "$cert" -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -policy policy_any -extensions ext_server -startdate $START -enddate $END \
	-infiles "$req"
    
    key_nopass="${TOP}/key-nopass.pem"
    cert_im=${TOP}/cert-im.pem
    pkcs12=${TOP}/pkcs12.pfx
    openssl ec -in $key -out ${key_nopass} -passin file:$PASS
    openssl x509 -in $cert    > ${cert_im}
    openssl x509 -in $CACERT >> ${cert_im}
    $PKCS12 -export -in "$cert" -inkey "$key" -out "$pkcs12" -certfile $CACERT -passin file:$PASS -passout file:$PASS

    serial=`openssl x509 -in $cert -noout -serial | sed -e 's/^serial=//'`
    #docker/nginx で使うのでコピーをおいておく
    cp -r $TOP $CATOP/certs/$serial-$CN
    unset_ca_param
}

gen_cert_client_yubikey() {
    : <<EOF
yubikey ようにクライアント証明書を生成する
EOF
    if [ ! `exist_yubikey` ]
    then
	return 1
    fi
    init_ca_param $*
    mkdir -p $TOP
    
    pub=${TOP}/pub.pem
    yubico-piv-tool -a generate -s 9a -A ECCP256 --key=`yubikey_mgm` -o $pub 
    yubico-piv-tool -a verify-pin -P `yubikey_pin` -a request-certificate -s 9a -S "$DN" -i $pub -o $req
    $CA -batch -out $cert -keyfile $CAKEY -passin file:$PASS \
	-name ca_any -policy policy_any -extensions ext_client -startdate $START -enddate $END \
	-infiles $req
    yubico-piv-tool -a import-certificate -s 9a -i $cert
    yubico-piv-tool -s 9a -a set-chuid
    serial=`openssl x509 -in $cert -noout -serial | sed -e 's/^serial=//'`
    mv $TOP $CATOP/certs/$serial-$CN
    unset_ca_param
}

create_ee(){
    : <<EOF
デモ用の証明書を生成する
EOF
    
    local N=$1
    local START_CA=$2
    local END_CA=$3
    local START_EE=$4
    local END_EE=$5
    local cn=""
    local dn=""
    
    set_ca selfsign-ca $N
    cn="enterprise-ca-$N"
    dn="/O=ToyCA/CN=$cn"
    gen_cert_ca $START_CA $END_CA "$cn" "$dn" "" ""

    cn="proxy-ca-$N"
    dn="/O=ToyCA/CN=$cn"
    gen_cert_ca $START_CA $END_CA "$cn" "$dn" "" ""
    
    set_ca server-ca $N
    cn="ca.example.com"
    dn="/CN=$cn"
    export SAN="DNS:${cn}, DNS:ns.example.com, DNS:ca.example.com, DNS:mail.example.com"
    gen_cert_server $START_EE $END_EE "$cn" "$dn" "" ""

    cn="wildcard.example.com"
    dn="/CN=$cn"
    export SAN="DNS:${cn}, DNS:*.example.org, DNS:*.example.co.jp"
    gen_cert_server $START_EE $END_EE "$cn" "$dn" "" ""

    #punycode 
    #○△□.ドメイン名例.jp
    cn="xn--u0h9a3d.xn--eckwd4c7cu47r2wf.jp"
    dn="/CN=$cn"
    #○△□.ドメイン名例.jp, ●▲■.ドメイン名例.jp
    export SAN="DNS:${cn}, DNS:xn--t0h9a4e.xn--eckwd4c7cu47r2wf.jp"
    #これ START/END_EE でない?
    gen_cert_server $START_EE $END_EE "$cn" "$dn" "" ""
    
    #AA
    #●▲■.ドメイン名例.jp
    cn="かいぎょうなんかできるの？"
    dn="/CN=かいぎょう
なんか
できるの"
    export SAN="DNS:*.example.com"
    gen_cert_server $START_EE $END_EE "$cn" "$dn" "" ""

    #Firefox で日本語ドメインの .com / .net が punycode で表示される理由
    #http://futuremix.org/2010/03/firefox-displays-idn-com-net-domain-with-punycode
    #サブドメインが変換されない原因が自前でもポリシーが確認されないとだめだとすると厳しいな

    set_ca client-ca $N
    cn="john.doe"
    dn="/CN=$cn"
    export SAN="email:${cn}@example.com, otherName:msUPN;UTF8:${cn}@example.com"
    gen_cert_client $START_EE $END_EE $cn "$dn" "" ""
    
    set_ca client-ca $N    
    cn="john.doe"
    #dn="/DC=com/DC=fourthcoffee/CN=Users/CN=moortimo"
    #dn="/CN=omitroom13"
    dn="/CN=$cn"
    export SAN="email:${cn}@example.com, otherName:msUPN;UTF8:${cn}@example.com"
    #export MAIL=mo@fourthcoffee.com
    #export MAIL=moortimo@fourthcoffee.com
    # if [ `exist_yubikey` ]
    # then
    # 	init_yubikey
    # 	gen_cert_client_yubikey $START_EE $END_EE $cn "$dn" "" ""
    # fi
}

if [ "$0" = "-bash" ]
then
    return
fi
if [ ! $(basename $0) = "entity.sh" ]
then
    return 0
fi

# START=`base_date $(date -d "0 years -5 months" '+%Y/06/01')`
# END=`base_date $(date -d "4 years -5 months" '+%Y/06/01')`
# START_CA=`base_date $(date -d "-2 years 1 months" '+%Y/%m/01')`
# END_CA=`base_date $(date -d "2 years 1 months" '+%Y/%m/01')`
# START_EE=$START_CA
# END_EE=`base_date $(date -d "2 months" '+%Y/%m/01')`

# START=$(lifetime '+%Y/06/01' "0 years -5 months")
# END=$(lifetime '+%Y/06/01' "4 years -5 months")
# START_CA=$(lifetime '+%Y/%m/01' "-2 years 1 months")
# END_CA=$(lifetime '+%Y/%m/01' "2 years 1 months")
# START_EE=$START_CA
# END_EE=$(lifetime '+%Y/%m/01' "2 months")

# create_ee $N $START_CA $END_CA $START_EE $END_EE