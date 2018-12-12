#!/bin/bash

# 実行時に設定可能な環境変数は予め決めておく。そして、デフォルト設定をここでおこなう。
# uwsgi の場合、ini ファイルで環境変数をとれるからよいが、Nginx の場合はそうはいかない。
# なので、ここで nginx-app.conf 中の変数部分を置換してやる。
  
set -e

# コンテナ起動時に環境変数 DJANGO_SETTINGS_MODULE で使用する settings モジュール名を必ず指定する。
#
if [ "$DJANGO_SETTINGS_MODULE" = "" ]; then
    echo "Environment variabl \"DJANGO_SETTINGS_MODULE\" is required."
    exit 1
fi

# UWSGI の worker プロセス数のデフォルト値をセット
if [ "$UWSGI_PROCESSES" = ""]; then
    export UWSGI_PROCESSES=2
fi

exec supervisord -n
