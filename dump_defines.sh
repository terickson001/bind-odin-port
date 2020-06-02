CC=
if [ -x "$(which gcc 2>/dev/null)" ]; then
    CC=gcc
elif [ -x "$(which clang 2>/dev/null)" ]; then
    CC=clang
else
    echo "Cannot find GCC or Clang in PATH"
    exit
fi

$CC -dM -E - < /dev/null | grep -E "#define [a-zA-Z0-9_]+ " > DEFINES.h
