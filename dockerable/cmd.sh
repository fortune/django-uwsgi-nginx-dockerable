#!/bin/bash

# 使用する環境変数は以下のとおり。
#
# DJANGO_SETTINGS_MODULE
#   Django で使用する settings モジュール名。必須。
#
# USE_SSL
#   HTTP only ならば未定義 or 空にする。
#   HTTPS 対応かつ HTTP を HTTPS へ転送する場合は何らかの値を入れておく。
#
# NGINX_SERVER_NAME
#   ドメイン名を指定する。必須。
#   Nginx の設定ファイル中の server_name の値として使われる。
#   HTTPS 対応の場合、このドメイン名に対する SSL 証明書を Letsencrypt から取得する。
#
# UWSGI_PROCESSES
#   uWSGI の worker プロセス数。デフォルト値は 2.
#
# EMAIL_ADDRESS
#   Letsencrypt から SSL 証明書を取得するときに使うメールアドレス。
#   HTTPS 対応なら必須。
#
#
# DJANGO_SETTINGS_MODULE で指定した settings モジュールが見つかるように適切なホスト上の
# ディレクトリをボリュームマウントしておかねばならない。
#
# HTTPS 対応の場合、コンテナ上の /etc/letsencrypt/ ディレクトリを、ホスト上の適切なディレクトリに
# ボリュームマウントしておかねばならない。このコンテナが docker run されるときにそこに証明書が
# 取得されていないならば、certbot certonly --standalone で SSL 証明書を取得し、
# そのディレクトリ配下に格納される。その後、必要に応じて webroot で同じ証明書を取得し直して
# Nginx を reload し、自動更新の設定もする。自動更新はホスト上の cron 等で docker exec コマンドを
# 使用して実行する。
  
set -e

# コンテナ起動時に環境変数 DJANGO_SETTINGS_MODULE で使用する settings モジュール名を必ず指定する。
#
if [ "$DJANGO_SETTINGS_MODULE" = "" ]; then
    echo "Environment variabl \"DJANGO_SETTINGS_MODULE\" is required."
    exit 1
fi

if [ "$NGINX_SERVER_NAME" = "" ]; then
    echo "Environment variable \"NGINX_SERVER_NAME\" is required."
    exit 1
fi

# UWSGI の worker プロセス数のデフォルト値をセット
if [ "$UWSGI_PROCESSES" = "" ]; then
    export UWSGI_PROCESSES=2
fi


if [ "$USE_SSL" = "" ]; then
    # テンプレートから Nginx の設定ファイルを生成
    envsubst '$NGINX_SERVER_NAME' < /app/dockerable/nginx-app.conf > /etc/nginx/sites-available/default
else
    if [ "$EMAIL_ADDRESS" = "" ];then
        echo "Environment variable \"EMAIL_ADDRESS\" is required if you want to use ssl."
        exit 1
    fi
    envsubst '$NGINX_SERVER_NAME' < /app/dockerable/nginx-app-ssl.conf > /etc/nginx/sites-available/default

    # Letsencrypt から証明書を取得したことがないなら、standalone で取得する
    if [ ! -e /etc/letsencrypt/renewal/${NGINX_SERVER_NAME}.conf ]; then
        certbot certonly --standalone -d ${NGINX_SERVER_NAME} --agree-tos --email "$EMAIL_ADDRESS" --noninteractive
    fi

fi

exec supervisord -n

