# Dockerable Django Project with uWSGI and Nginx

[Dockerable Django Project](https://github.com/fortune/django_dockerable_sample) の続き。そこでは
コンテナ上で uWSGI を起動して Django アプリケーションを実行したが、ここでは、リバースプロキシとして Nginx を
起動して、uWSGI に接続させる。

ここで作成した Dockerfile は、[Django, uWSGI and Nginx in a container, using Supervisord](https://github.com/dockerfiles/django-uwsgi-nginx) を元にしている。


## 方針

やり方としては、[Dockerable Django Project](https://github.com/fortune/django_dockerable_sample) で
作成したコンテナとは別に Nginx 用のコンテナを動かし、両者を link させることもできる（当然、SSL は Nginx 側で
処理する）。１コンテナ１アプリケーションという Docker の作法に合ってはいるが、Nginx と uWSGI の通信に TCP ソケットを
使うよりは Unix ドメインソケットの方が overhead が小さいというのと、コンテナの数をむやみに増やしたくないので、
全部ひとつの Docker イメージにまとめ、１コンテナで uWSGI と Nginx を実行するようにする。１コンテナで２つの
アプリケーションを動かすために [supervisor](http://supervisord.org/) を利用することにする。

本番、ステージング、開発者個人の環境に共通な Docker イメージを作成する。環境ごとの違いは、コンテナ起動時に指定することにする。


## プロジェクト構成

[Dockerable Django Project](https://github.com/fortune/django_dockerable_sample) と同じように Django プロジェクトを
作成し、 settings の個別化、秘匿化もしている。細部が少々異なるのでいかに説明する。

```shell
$ tree
.
├── README.md
├── dockerable
│   ├── Dockerfile
│   ├── cmd.sh          # コンテナ起動スクリプト
│   ├── docker-compose-build-only.yml   # コンテナイメージビルド用の docker-compose.yml
│   ├── nginx-app.conf          # Nginx の設定ファイルのテンプレート
│   ├── supervisor-app.conf     # supervisor の設定ファイル
│   ├── uwsgi.ini               # uwsgi の設定ファイル
│   └── uwsgi_params
├── manage.py
├── project
│   ├── __init__.py
│   ├── settings
│   │   ├── __init__.py
│   │   ├── base.py             # 共通の Django 設定モジュール
│   │   └── fortune             # 個別環境設定のモジュール（fortune ユーザ用）
│   │       ├── __init__.py
│   │       ├── docker-compose.yml  # fortune 用のコンテナ起動用 docker-compose.yml
│   │       ├── secrets.json        # 秘密設定情報
│   │       └── settings.py
│   ├── urls.py
│   └── wsgi.py
├── requirements.txt
```

Dockerfile で、このツリー全体がコンテナ上の */app/* にコピーしているが、仮想環境や、個別設定 *project/settings/fortune* 等は除くように
`.dockerignore` を定義している。

`dockerable/` 内の `supervisor-app.conf` ファイルは、コンテナ内の Supervisor のための適切な場所にコピーするように Dockerfile に記述している。

`dockerable/` 内の `nginx-app.conf` ファイルをテンプレートとして、コンテナ実行時に Nginx 設定ファイルを生成するように `cmd.sh` に記述してある。


## ビルド方法

プロジェクトのトップディレクトリで次のようにする。

```shell
$ docker-compose -f dockerable/dockerable-compose-build-only.yml build
```

これで全環境で共通の Docker イメージがビルドされる。

Dockerfile のコメントにも書かれているが、プロジェクト全体をコンテナにコピーする前に `requirements.txt` を `pip install` する方が build が
効率的になる。Docker の caching により、`requirements.txt` に変更があった場合のみ `pip install` が実行され、
それ以外のファイルに変更があっても無駄に `pip install` が実行されることがなくなる。

https://vsupalov.com/speed-up-python-docker-image-build/


## 実行方法

*fortune* ユーザ用の環境だけ定義されているので、プロジェクトのトップディレクトリで次のようにする。

```shell
$ docker-compose -f project/settgings/fortune/docker-compose.yml up -d
```

別のホストにもっていって実行する場合、Docker イメージをそのホストにデプロイし、*fortune* ディレクトリをそのホスト上にコピーする。
その上で上と同様に -f オプションで *fortune/docker-compose.yml* を指定して docker-compose すればいい。


## 環境ごとの設定方法

たとえば、staging という環境を作りたい場合、`project/settings/staging/` というディレクトリを作成し、*fortune* と同じように
そこに *settings.py*, *secrets.json*, *docker-compose.yml* を作成する。

*settings.py*, *secrets.json* は、Django アプリケーション用の設定である。

*docker-compose.yml* で、ホスト上にある、環境ごとのディレクトリ、ここだと `staging/` ディレクトリとコンテナ上の `app/project/settings/staging/`
ディレクトリをボリュームマウントさせ、環境変数 *DJANGO_SETTINGS_MODULE* を *project.settings.staging.settings* にセットする。*fortune* 環境も
同様にしている。

コンテナ上で実行される uWSGI の設定は *docker-compose.yml* 内で環境変数をセットすることによりおこなう。いまのところ、worker プロセスの数を
*UWSGI_PROCESSES* という環境変数で指定するようにしている。*uwsgi.ini* 内でこの環境変数を使用している。設定項目を増やしたければ、同じように
*docker-compose.yml* 内で環境変数をセットし、*uwsgi.ini* 内で使用するようにする。

Nginx の設定ファイルは環境変数を内部で参照することはできないので、[envsubst コマンド](http://manpages.ubuntu.com/manpages/bionic/man1/envsubst.1.html)
を使用してコンテナ起動時にテンプレートから設定ファイルを
生成するようにしている。この例では *NGINX_SERVER_NAME* という環境変数を設定値として使っている。

*cmd.sh* で環境変数をチェックし、デフォルト値のセットや、テンプレートからの設定ファイル生成をした後で、*supervisord* プロセスを起動する。
フォアグラウンドで起動するようにしてあるので、Docker コンテナが起動後すぐに終了してしまうということはない。




## ロギング

ログの設定は特にしていない。

Nginx のログファイルはデフォルトの設定のままで、`/var/log/nginx/` ディレクトリに作成されている。

uWSGI は、フォアグラウンドで実行され、*uwsgi.ini* でログの指定もしていないので、標準（エラー）出力にはログメッセージが出力される。

supervisor のログは、`/var/log/supervisor/` ディレクトリに作成されている。管理下にある uwsgi が標準出力に吐いたメッセージを保存した
ログファイルもここに作成されている。



## 課題

ロギングは Docker での運用に合うように集約なり何なりをする必要がある。

SSL 化していない。SSL 化のためには、Nginx の設定ファイルを SSL 化対応してやればいい。少々面倒なのは、SSL 証明書の取得と自動更新だ。
Letsencrypt を利用するとして、証明書自動更新のためには、cron を動かさねばならない。

cron を動かす場合、大きく分けて２つ選択肢がある。

- コンテナ内で実行する
- ホスト側で実行する

コンテナ内で動かすには、Nginx, uWSGI と同じように cron のための設定をコンテナイメージに組み込み、必要ならコンテナ起動時に設定を
変更できるようにして supervisor で Nginx, uWSGI に加えて実行するようにする。ホスト側でやるなら、ホスト上で cron の設定をしてやり、
*docker exec* コマンドで証明書自動更新のコマンドをコンテナ内で起動してやるようにすればいい。

cron までコンテナ内に組み込むと、構成が少々複雑になりすぎる気がする。また、Web サーバを冗長化することを考えると、SSL 証明書は
ロードバランサに置くだろうから、コンテナに組み込むと無駄になる。よって、ホスト側で実行する方がよさげだ。

