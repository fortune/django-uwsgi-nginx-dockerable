FROM ubuntu:18.04

MAINTAINER fortune

# Install required packages and remove the apt packages cache when done.

# この設定により、ビルドされた Docker イメージを起動したときのタイムゾーンが適切に設定される。
# また、Docker ビルド中に tzdata の Configuring のための入力を求められ、途中で停止してしまうことが避けられる。
ENV TZ="Asia/Tokyo"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 新しい apt コマンドはスクリプトでは使いづらいようだ（-y オプションがない）。
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
	certbot \
	git \
	python3 \
	python3-dev \
	python3-setuptools \
	python3-pip \
	nginx \
	supervisor \
	gettext-base && \
	pip3 install -U pip setuptools && \
    rm -rf /var/lib/apt/lists/*

# install uwsgi now because it takes a little while
RUN pip3 install uwsgi

# setup all the config files
#
# nginx をフォアグラウンドで動かすようにする。こうしないと、supervisor の管理下から外れてしまう。
# uwsgi はそのまま起動すればフォアグラウンドなので問題ない。
RUN echo "daemon off;" >> /etc/nginx/nginx.conf
COPY dockerable/supervisor-app.conf /etc/supervisor/conf.d/
# COPY dockerable/nginx-app.conf /etc/nginx/sites-available/default

# COPY requirements.txt and RUN pip install BEFORE adding the rest of your code, this will cause Docker's caching mechanism
# to prevent re-installing (all your) dependencies when you made a change a line or two in your app.

COPY requirements.txt /app/
RUN pip3 install -r /app/requirements.txt

# add (the rest of) our code
COPY . /app/
#RUN chown -R www-data:www-data /app/
RUN chown -R www-data:www-data /app/ && chmod a+x /app/dockerable/cmd.sh


EXPOSE 80

# -n オプションにより、nodaemon、つまり、フォアグラウンドで起動する。
# そうしないと、docker コンテナを run してもすぐに終了してしまう。
#CMD ["supervisord", "-n"]

# 環境変数を渡すためにシェルスクリプトを介する必要はないが、
# デフォルト設定等をするためにシェルスクリプトから supervisord を起動する。
CMD ["/app/dockerable/cmd.sh"]
