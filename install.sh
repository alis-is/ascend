#!/bin/sh

TMP_NAME="./$(head -n 1 -c 32 /dev/urandom | tr -dc 'a-zA-Z0-9'| fold -w 32)"

if which curl >/dev/null; then
    if curl --help  2>&1 | grep "--progress-bar" >/dev/null 2>&1; then 
        PROGRESS="--progress-bar"
    fi

    set -- curl -L $PROGRESS -o "$TMP_NAME"
    LATEST=$(curl -sL https://api.github.com/repos/alis-is/ascend/releases/latest | grep tag_name | sed 's/  "tag_name": "//g' | sed 's/",//g')
else
    if wget --help  2>&1 | grep "--show-progress" >/dev/null 2>&1; then 
        PROGRESS="--show-progress"
    fi
    set -- wget -q $PROGRESS -O "$TMP_NAME"
    LATEST=$(wget -qO- https://api.github.com/repos/alis-is/ascend/releases/latest | grep tag_name | sed 's/  "tag_name": "//g' | sed 's/",//g')
fi

# install eli
echo "Downloading eli setup script..."
# TODO: remove prerelease after eli 0.32.0 lands
if ! "$@" https://raw.githubusercontent.com/alis-is/eli/master/install.sh; then
    echo "Failed to download eli, please retry ... "
    rm "$TMP_NAME"
    exit 1
fi
if ! sh "$TMP_NAME" --prerelase; then
    echo "Failed to download eli, please retry ... "
    rm "$TMP_NAME"
    exit 1
fi
rm "$TMP_NAME"

if ascend --version | grep "$LATEST"; then
    echo "Latest ascend already available."
    exit 0
fi

# install ascend
echo "Downloading ascend $LATEST..."
if "$@" "https://github.com/alis-is/ascend/releases/download/$LATEST/ascend.lua" &&
    cp "$TMP_NAME" /usr/sbin/ascend &&
    chmod +x /usr/sbin/ascend; then
    rm "$TMP_NAME"
    echo "ascend $LATEST successfuly installed."
else
    rm "$TMP_NAME"
    echo "ascend installation failed!" 1>&2
    exit 1
fi
# install asctl
echo "Downloading asctl $LATEST..."
if "$@" "https://github.com/alis-is/ascend/releases/download/$LATEST/asctl.lua" &&
    cp "$TMP_NAME" /usr/sbin/asctl &&
    chmod +x /usr/sbin/asctl; then
    rm "$TMP_NAME"
    echo "asctl $LATEST successfuly installed."
else
    rm "$TMP_NAME"
    echo "asctl installation failed!" 1>&2
    exit 1
fi
