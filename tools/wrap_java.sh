#
# Wrap a java script for execution in the development runtime environment.
# Ultimately should be able to emit warnings about deprecated script
# names to stderr
#

if [ $# -ne 2 ] ; then
    echo "Usage: $0 source dest" 1>&2
    exit 1
fi

src=$1
dst=$2



cat > $dst <<EOF1
#!/bin/sh
export KB_TOP=$KB_TOP
export KB_RUNTIME=$KB_RUNTIME
export PATH=$KB_RUNTIME/bin:$KB_TOP/bin:\$PATH
EOF1
for var in $WRAP_VARIABLES ; do
    val=${!var}
    if [ "$val" != "" ] ; then
        echo "export $var='$val'" >> $dst
    fi
done
cat >> $dst <<EOF
java -Dlogback.configurationFile=$SEED_JARS/logback.xml -Dlogfile.name=$KB_TOP/Data/logs/$src -jar $SEED_JARS/$src.jar %*
EOF

chmod +x $dst
