#!/bin/bash

docker run nginx

name=$(basename $(pwd))

cmd=$1
phase=$2

function volume(){
    : <<EOF
証明書を /var/www にマウントする
EOF
    name=$1
    phase=$2
    if [ "$phase" == "dev" ] ;
    then
	echo "-v $(pwd):/opt/$name"
    fi
    #prod 環境は volume を使用せずに copy するので空で良い
    echo ""
}

case $cmd in 
    build)
	docker build -t $name-$phase -f ./Dockerfile.$phase . --build-arg name=$name
	;;
    run)
	popt="
	-p 80:80
	-p 1080:1080 -p 1443:1443
	-p 2080:2080 -p 2443:2443
	-p 3080:3080 -p 3443:3443
	-p 4080:4080 -p 4443:4443
	-p 5080:5080 -p 5443:5443
	"
	vopt="
 	-v $(pwd)/www:/usr/share/nginx/html
	-v $(pwd)/ca:/etc/ssl/toyca
	-v $(pwd)/www/nginx.conf:/etc/nginx/conf.d/toyca.conf
	"
	docker run -it $popt $vopt nginx
	;;
esac
