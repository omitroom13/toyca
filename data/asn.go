package main

import (
	"encoding/asn1"
	"encoding/pem"
	"errors"
	"io/ioutil"
	"log"
	"golang.org/x/crypto/ed25519"
)

type pkcs1PrivateKey struct {
	Version int
	OID ObjectIdentifier
	Key []byte
}

type pkcs1PublicKey struct {
	OID ObjectIdentifier
	Key asn1.BitString
}

type ObjectIdentifier struct {
	ID asn1.ObjectIdentifier
}

func main() {
	path := "ed25519.pem"
	pemdata, err := ioutil.ReadFile(path)
	if err != nil {
		log.Print(err)
	}
	pembyte, _ := pem.Decode(pemdata)
	if pembyte == nil {
		log.Print(errors.New("invalid private key data"))
	}
	var pkcs1priv pkcs1PrivateKey
	rest, err := asn1.Unmarshal(pembyte.Bytes, &pkcs1priv)
	if len(rest) > 0 {
		log.Printf("rest length is not zero: %s", rest)	
	}
	ed25519oid := asn1.ObjectIdentifier([]int{1, 3, 101, 112})
	path = "ed25519pub.pem"
	pemdata, err = ioutil.ReadFile(path)
	if err != nil {
		log.Print(err)
	}
	pembyte, _ = pem.Decode(pemdata)
	if pembyte == nil {
		log.Print(errors.New("invalid private key data"))
	}
	log.Print(len(pembyte.Bytes))
	log.Print(pembyte.Bytes)
	var pkcs1pub pkcs1PublicKey
	rest, err = asn1.Unmarshal(pembyte.Bytes, &pkcs1pub)
	log.Print(pkcs1pub.OID.ID)
	log.Printf("len %d bytes %x", len(pkcs1pub.Key.Bytes), pkcs1pub.Key.Bytes)
	if pkcs1priv.OID.ID.Equal(ed25519oid) {
		//pub key を計算する手段が実装されていないということか。
		hBytes := make([]byte, 64)
		copy(hBytes[:], pkcs1priv.Key[2:])
		copy(hBytes[32:], pkcs1pub.Key.Bytes)
		log.Printf("len %d bytes %x", len(hBytes), hBytes)
		privateKey := ed25519.PrivateKey(hBytes)
		publicKey := privateKey.Public().(ed25519.PublicKey)
		message := []byte("Hello World!")
		sig := ed25519.Sign(privateKey, message)
		//log.Print(sig)
		log.Print(ed25519.Verify(publicKey, message, sig))
	}
}
