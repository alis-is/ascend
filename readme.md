# Ascend

Simple, lightweight, portable service manager based on [eli](https://github.com/alis-is/eli).


# Sample run

```sh
cd src
export ASCEND_SERVICES=../tests/assets/services/1
export ASCEND_LOGS=../logs
eli ascend.lua --log-level=trace
```