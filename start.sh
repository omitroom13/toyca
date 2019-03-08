#!/bin/bash

if [ ! -e /etc/ssl/toyca ]
then
    ln -s /opt/toyca/ca /etc/ssl/toyca
fi
if [ ! -e /usr/local/share/ca-certificates/toyca]
then
    ln -s /opt/toyca/www /usr/local/share/ca-certificates/toyca
fi
if [ ! -h /etc/nginx/sites-enabled/ca ]
then
    ln -s /etc/nginx/sites-available/ca /etc/nginx/sites-enabled/ca
fi
if [ -h /etc/nginx/sites-enabled/default ]
then
    rm /etc/nginx/sites-enabled/default
fi
d=/usr/local/lib/python$(python3 --version | cut -c 8-10)/dist-packages/recommonmark
if [ -e /opt/toyca/parser.patch -a -e $d/parser.py -a ! -e $d/parser.py.orig ]
then
    #Sphinx の日本語見出しにデフォルトではリンクできていない件
    #https://qiita.com/leo-mon/items/46c43f0f97f730e64754#%E6%97%A5%E6%9C%AC%E8%AA%9E%E3%82%BB%E3%82%AF%E3%82%B7%E3%83%A7%E3%83%B3%E3%81%AB%E3%82%A2%E3%83%B3%E3%82%AB%E3%83%BC%E3%81%8C%E8%B2%BC%E3%82%89%E3%82%8C%E3%82%8B%E3%82%88%E3%81%86%E3%81%AB%E3%81%99%E3%82%8B
    patch -b $d/parser.py /opt/toyca/parser.patch
fi
update-ca-certificates
/etc/init.d/nginx start
exec /bin/bash
