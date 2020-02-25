# make-docker-base-image
script to make docker base image with yum,dnf,zypper

# example
first copy your configuration file and repository files into /tmp/basefs:
```
mkdir /tmp/basefs
cp opensusetumbleweed/*repo /tmp/basefs/etc/zypp/repos.d/
cp opensusetumbleweed/zypp.conf /tmp/basefs/etc/zypp/
```
then:
```
sudo ./make-docker-base-image.sh -t /tmp/basefs -c /tmp/basefs/etc/zypp/zypp.conf -p aaa_base -p cracklib-dict-small -p shadow -p openSUSE-release -p zypper -p kubic-locale-archive -p netcfg -p openssl -p ca-certificates-mozilla opensuse-tumbleweed
```
or
```
sudo ./make-docker-base-image.sh -t /tmp/basefs -c /tmp/basefs/etc/zypp/zypp.conf -p aaa_base -p cracklib-dict-small -p shadow -p openSUSE-release -p zypper -p netcfg -p openssl -p ca-certificates-mozilla opensuse-42.1
```
