# Dockerable Django Project with uWSGI and Nginx

[Dockerable Django Project](https://github.com/fortune/django_dockerable_sample) の続き。そこでは
コンテナ上で uWSGI を起動して Django アプリケーションを実行したが、ここでは、リバースプロキシとして Nginx を
起動して、uWSGI に接続させる。また、HTTP only にも HTTPS にも対応できるようにする。

ここで作成した Dockerfile は、[Django, uWSGI and Nginx in a container, using Supervisord](https://github.com/dockerfiles/django-uwsgi-nginx) を元にしている。


## 方針

やり方としては、[Dockerable Django Project](https://github.com/fortune/django_dockerable_sample) で
作成したコンテナとは別に Nginx 用のコンテナを動かし、両者を link させることもできる（当然、SSL は Nginx 側で
処理する）。１コンテナ１アプリケーションという Docker の作法に合ってはいるが、Nginx と uWSGI の通信に TCP ソケットを
使うよりは Unix ドメインソケットの方が overhead が小さいというのと、コンテナの数をむやみに増やしたくないので、
全部ひとつの Docker イメージにまとめ、１コンテナで uWSGI と Nginx を実行するようにする。１コンテナで２つの
アプリケーションを動かすために [supervisor](http://supervisord.org/) を利用することにする。

SSL 証明書は `certbot` ツールを使い、Letsencrypt から取得するようにする。

本番、ステージング、開発者個人の環境、また HTTP only か HTTPS 対応の両方に共通な Docker イメージを作成する。
環境ごとの違いは、コンテナ起動時に指定することにする。


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
│   ├── nginx-app-ssl.conf          # HTTPS 対応の Nginx の設定ファイルのテンプレート
│   ├── nginx-app.conf              # HTTP only の Nginx の設定ファイルのテンプレート
│   ├── supervisor-app.conf         # supervisor の設定ファイル
│   ├── uwsgi.ini                   # uwsgi の設定ファイル
│   └── uwsgi_params
├── manage.py
├── project
│   ├── __init__.py
│   ├── settings
│   │   ├── __init__.py
│   │   ├── base.py             # 共通の Django 設定モジュール
│   │   └── fortune             # 個別環境設定のモジュール（fortune ユーザ用）
│   │       ├── __init__.py
│   │       ├── docker-compose-ssl.yml  # fortune 環境で HTTPS 対応コンテナ起動用 docker-compose.yml
│   │       ├── docker-compose.yml      # fortune 環境で HTTP only コンテナ起動用 docker-compose.yml
│   │       ├── letsencrypt             # SSL 証明書取得用ディレクトリ
│   │       │   └── cli.ini
│   │       ├── secrets.json            # 秘密設定情報
│   │       └── settings.py
│   ├── urls.py
│   └── wsgi.py
├── requirements.txt
```

Dockerfile で、このツリー全体をコンテナ上の */app/* にコピーしているが、仮想環境や、個別設定 *project/settings/fortune* 等は除くように
`.dockerignore` を定義している。

`dockerable/` 内の `supervisor-app.conf` ファイルは、コンテナ内の Supervisor のための適切な場所にコピーするように Dockerfile に記述している。

HTTP only でコンテナを起動するときに、`dockerable/` 内の `nginx-app.conf` テンプレートから Nginx 設定ファイルを生成するように `cmd.sh` に記述してある。

HTTPS 対応（HTTP は HTTPS へ転送）でコンテナを起動するとき、`dockerable/` 内の `nginx-app-ssl.conf` テンプレートから Nginx 設定ファイルを
生成するように `cmd.sh` に記述してある。

コンテナイメージには含まれない `project/settings/fortune` 中の `letsencrypt/` ディレクトリは、HTTPS 対応でコンテナが起動されたときにコンテナ上の
`/etc/letsencrypt/` ディレクトリにボリュームマウントされる。これにより、コンテナ内で取得した SSL 証明書や取得時の設定がホスト上に保存され、
コンテナが破棄され、再度起動されたときでもそれを利用できるようになる。


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



## 実行方法（HTTP only の場合）

*fortune* ユーザ用の環境だけ定義されているので、プロジェクトのトップディレクトリで次のようにする。

```shell
$ docker-compose -f project/settgings/fortune/docker-compose.yml up -d
```

別のホストにもっていって実行する場合、Docker イメージをそのホストにデプロイし、*fortune* ディレクトリをそのホスト上にコピーする。
その上で上と同様に -f オプションで *fortune/docker-compose.yml* を指定して docker-compose すればいい。

`docker-compose.yml` ファイル内には、コンテナ起動時に必要な環境変数のセットや、ボリュームマウントの設定が記述してある。起動用スクリプトの
*cmd.sh* により HTTP only でコンテナが起動される。



## 実行方法（HTTPS 対応の場合）

HTTPS 対応（HTTP は HTTPS へ転送）用の環境変数のセットやボリュームマウントの設定は `docker-compose-ssl.yml` に記述してあるので、
これを指定して次のように実行する。

```shell
$ docker-compose -f project/settgings/fortune/docker-compose-ssl.yml up -d
```

コンテナ起動用のスクリプト `cmd.sh` は、HTTPS 用に起動されると `certbot` を `standalone` プラグインで実行して Letsencrypt から SSL 証明書を取得する。
証明書や取得時の設定は `/etc/letsencrypt/` ディレクトリ以下に保存されるのだが、`docker-compose-ssl.yml` でそのディレクトリをホスト上の
`fortune/letsencrypt/` ディレクトリにボリュームマウントしてあるので、そこに保存される。

`cmd.sh` は、`/etc/letsencrypt/` 以下を確認してすでに証明書をとったことがあるなら `certbot` を実行しないようにしてあるので無駄に証明書を
取得することはない。




## 環境ごとの設定方法

たとえば、staging という環境を作りたい場合、`project/settings/staging/` というディレクトリを作成し、*fortune* と同じように
そこに *settings.py*, *secrets.json*, *docker-compose.yml* を作成する。

*settings.py*, *secrets.json* は、Django アプリケーション用の設定である。

*docker-compose.yml* で、ホスト上にある環境ごとのディレクトリ、ここだと `staging/` ディレクトリとコンテナ上の `app/project/settings/staging/`
ディレクトリをボリュームマウントさせ、環境変数 *DJANGO_SETTINGS_MODULE* を *project.settings.staging.settings* にセットする。これにより、
実行時に Django の settings モジュールが見つかるようになる。

コンテナ上で実行される uWSGI の設定は *docker-compose.yml* 内で環境変数をセットすることによりおこなう。いまのところ、worker プロセスの数を
*UWSGI_PROCESSES* という環境変数で指定するようにしている。*uwsgi.ini* 内でこの環境変数を使用している。設定項目を増やしたければ、同じように
*docker-compose.yml* 内で環境変数をセットし、*uwsgi.ini* 内で使用するようにする。

Nginx の設定ファイルは環境変数を内部で参照することはできないので、[envsubst コマンド](http://manpages.ubuntu.com/manpages/bionic/man1/envsubst.1.html)
を使用してコンテナ起動時にテンプレートから設定ファイルを
生成するようにしている。この例では *NGINX_SERVER_NAME* という環境変数を設定値として使っている。

*cmd.sh* で環境変数をチェックし、デフォルト値のセットや、テンプレートからの設定ファイル生成をした後で、*supervisord* プロセスを起動する。
フォアグラウンドで起動するようにしてあるので、Docker コンテナが起動後すぐに終了してしまうということはない。

HTTPS 接続も受け付けるようにしたいなら、`project/settings/staging/` に次のファイルとディレクトリを用意する。

- *docker-compose-ssl.yml* 
- *letsencrypt/cli.ini*

*letsencrypt* はコンテナ内で取得した SSL 証明書と取得時の設定を保持するためのディレクトリであり、コンテナ内の `/etc/letsencrypt/` とボリュームマウントするように
*docker-compose-ssl.yml* に設定する。このファイルには、HTTPS 用にさらにいくつかの環境変数定義もしてある。*cli.ini* は `certbot` インストール時に
自動で生成されるファイルであり、それをコピーしたもの。このファイル内に（たとえコメントでも）Ascii でない文字があると certbot ツールの実行に失敗するので
注意すること。



## ロギング

supervisord, nginx, uwsgi すべて、ファイルにログを出力せずに Docker コンテナの標準出力、エラー出力にログ出力し、最終的なロギングは
Docker エンジンにまかせることにする。そのため、次のようにする。

nginx は `nginx-app.conf`, `nginx-app-ssl.conf` に

```shell
access_log /dev/stdout;
error_log /dev/stderr;
```

を記述してデフォルトの設定を上書きし、標準出力、エラー出力にログするようにした。

uWSGI は、フォアグラウンドで実行され、*uwsgi.ini* でログの指定もしていないので、標準（エラー）出力にはログメッセージが出力される。

supervisor は、`supervisor-app.conf` にあるとおりに設定しした。これにより、
supervisor プロセスは、サブプロセスである nginx, uwsgi からの標準出力、エラー出力を
ログファイルに保存せずにコンテナの標準出力、エラー出力にはきだす。さらに自分自身のログも
ファイルに保存せず、捨てている。フォアグラウンドで稼働しているので、コンテナの標準出力に
出力されるので問題ない。結局、supervisor はログファイルを作成しなくなるので、`/var/log/supervisor/` ディレクトリは空になる。


`docker-compose.yml`, `docker-compose-ssl.yml` に Docker の logging-driver とオプションを指定した。
syslog をドライバにしたので、ホストの Syslog の設定にしたがって、ホスト上でロギングされる。


## SSL 証明書自動更新

この設定をするには、まず、SSL 証明書を *standalone* ではなく *webroot* で取り直さないといけない。
次のようにする。

```shell
$ docker exec -it {コンテナ名} certbot certonly --webroot -w /var/www/html -d {ドメイン名} --force-renewal
```

*{コンテナ名}* は HTTPS 対応で実行したコンテナの名称、*{ドメイン名}* は `docker-compose-ssl.yml` 内で設定した環境変数 *NGINX_SERVER_NAME* と
同じ値。この環境変数の値で指定されたドメイン名用の SSL 証明書がコンテナ起動時に取得されているはずである。`-w` オプションで Nginx のドキュメントルートを
指定しているが、これは `nginx-app-ssl.conf` でそのように設定してある。

これで Nginx を停止せずに証明書を更新する準備が整った。あとは、証明書更新のために *certbot* を実行する *docker exec* コマンドをホスト上の cron や
systemd timer にセットする。

このログは、コンテナ内の `/var/log/letsencrypt/` ディレクトリにつくられる。


[Letsencrypt による SSL 証明書の取得、利用方法](https://gist.github.com/fortune/6c443c617b706d0d0701867cbdf34f15)


## 課題

１つのコンテナで supervisor, nginx, uwsgi を動かしているので、コンテナの標準出力に出力したログが混じり合うことはないが、
混在してしまい、互いに区別しにくいので分析しにくい。いろいろ調べたが、いい方法はなさそうだ。なので、やはり、nginx と uwsgi（+ Django）の
２つは別々の Docker コンテナで動かした方がよさそうだ。そうすれば、ログを分けるのが簡単になる。

